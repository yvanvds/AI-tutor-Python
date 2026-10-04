"""Tests for the question bank cleanup (#215): which existing question is
kept, deleted or hidden and why, and what a run reads, backs up and writes.
Standard library only:

    python -m unittest discover -s tooling/question_bank/tests

No test touches the live account: a fake `cosmos` module takes the place of
`tooling/evaluation/cosmos.py`, which would read `.env` on import. The data
is made up.
"""

from __future__ import annotations

import contextlib
import io
import json
import re
import shutil
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cleanup  # noqa: E402

CREATED = "2026-09-24T10:00:00.000Z"


def _q(qid: str, *, qtype: str = "mcQuestion", answered: int = 1, correct: int = 1, **extra) -> dict:
    return {
        "id": qid,
        "type": "question",
        "subgoalId": "sg-a",
        "questionType": qtype,
        "createdAt": CREATED,
        "askedCount": max(answered, 1),
        "answeredCount": answered,
        "correctCount": correct,
        "status": "active",
        "_etag": f'"{qid}"',
        **extra,
    }


def _turn(qid: str, quality: str, at: str) -> dict:
    return {"questionId": qid, "overallQuality": quality, "turnAt": at}


class _Conflict(Exception):
    pass


def _fake_cosmos(docs: list[dict], turns: list[dict], conflicts: set[str] = frozenset(), log=None):
    m = types.ModuleType("cosmos")
    m.Conflict = _Conflict
    m.deletes, m.upserts = [], []
    log = log if log is not None else []

    def query(coll, sql, params=None, pk=None, cross=True):
        return {"questions": docs, "turn_history": turns}[coll]

    def delete(coll, doc_id, pk, etag=None):
        if doc_id in conflicts:
            raise _Conflict(doc_id)
        log.append(("delete", doc_id))
        m.deletes.append((coll, doc_id, pk, etag))
        return True

    def upsert(coll, doc, pk, etag=None):
        if doc["id"] in conflicts:
            raise _Conflict(doc["id"])
        log.append(("upsert", doc["id"]))
        m.upserts.append((coll, doc, pk, etag))
        return doc

    m.query, m.delete, m.upsert = query, delete, upsert
    return m


class DecideTest(unittest.TestCase):
    def decide(self, doc: dict, turns: list[dict] = ()) -> cleanup.Decision:
        return cleanup.decide(doc, cleanup.first_quality(doc, cleanup.first_answers(list(turns))))

    def test_a_socratic_question_is_deleted_whatever_its_answers(self):
        d = self.decide(_q("s", qtype="socraticQuestion", answered=3, correct=3),
                        [_turn("s", "correct", "2026-09-24T10:01:00Z")])
        self.assertEqual((d.action, d.reason), (cleanup.DELETE, cleanup.SOCRATIC_Q))

    def test_the_first_turn_record_decides_wrong_and_partial_are_not_correct(self):
        turns = [
            _turn("q", "correct", "2026-09-24T10:09:00Z"),
            _turn("q", "wrong", "2026-09-24T10:02:00Z"),
        ]
        self.assertEqual(self.decide(_q("q", answered=2, correct=1), turns).reason, cleanup.FIRST_NOT_CORRECT)
        partial = [_turn("p", "partial", "2026-09-24T10:02:00Z")]
        self.assertEqual(self.decide(_q("p"), partial).action, cleanup.DELETE)
        right = [_turn("r", "correct", "2026-09-24T10:02:00Z"), _turn("r", "wrong", "2026-09-24T10:05:00Z")]
        d = self.decide(_q("r", answered=2, correct=1), right)
        self.assertEqual((d.action, d.reason), (cleanup.KEEP, cleanup.FIRST_CORRECT))

    def test_a_turn_record_from_before_the_doc_was_created_does_not_count(self):
        # Deleted once on a wrong first answer, stored again later by a
        # correct one: the earlier wrong answer is not this doc's first.
        turns = [
            _turn("q", "wrong", "2026-09-20T09:00:00Z"),
            _turn("q", "correct", "2026-09-24T10:00:30Z"),
        ]
        self.assertEqual(self.decide(_q("q"), turns).reason, cleanup.FIRST_CORRECT)

    def test_records_without_a_quality_or_for_another_question_are_ignored(self):
        turns = [
            {"questionId": "q", "turnAt": "2026-09-24T10:01:00Z"},
            _turn("other", "wrong", "2026-09-24T10:01:00Z"),
        ]
        self.assertEqual(self.decide(_q("q", answered=0, correct=0), turns).reason, cleanup.NEVER_ANSWERED)

    def test_without_a_turn_record_the_counters_decide(self):
        self.assertEqual(self.decide(_q("a", answered=0, correct=0)).reason, cleanup.NEVER_ANSWERED)
        self.assertEqual(self.decide(_q("b", answered=3, correct=3)).reason, cleanup.FIRST_CORRECT_BY_COUNTS)
        self.assertEqual(self.decide(_q("c", answered=3, correct=0)).reason, cleanup.FIRST_WRONG_BY_COUNTS)
        mixed = self.decide(_q("d", answered=3, correct=1))
        self.assertEqual((mixed.action, mixed.reason), (cleanup.KEEP, cleanup.MIXED_COUNTS))

    def test_what_stays_hides_below_half_on_ten_answers_and_exactly_half_stays(self):
        first = lambda qid: [_turn(qid, "correct", "2026-09-24T10:01:00Z")]  # noqa: E731
        low = self.decide(_q("low", answered=10, correct=4), first("low"))
        self.assertEqual((low.action, low.reason), (cleanup.HIDE, cleanup.AUTO_HIDDEN))
        self.assertEqual(self.decide(_q("half", answered=10, correct=5), first("half")).action, cleanup.KEEP)
        self.assertEqual(self.decide(_q("nine", answered=9, correct=1), first("nine")).action, cleanup.KEEP)
        # A mixed count without a turn record stays — and the hide rule
        # still applies to it.
        self.assertEqual(self.decide(_q("mixed", answered=12, correct=3)).action, cleanup.HIDE)

    def test_hidden_by_the_teacher_stays_as_it_is_and_kept_by_the_teacher_stays_shown(self):
        by_hand = self.decide(_q("h", answered=10, correct=2, status="hidden"))
        self.assertEqual(by_hand.action, cleanup.KEEP)
        self.assertFalse(by_hand.writes)
        kept = self.decide(_q("k", answered=10, correct=2, keptByTeacher=True))
        self.assertEqual(kept.action, cleanup.KEEP)
        # Deleting still wins over a teacher's hide.
        self.assertEqual(self.decide(_q("w", answered=2, correct=0, status="hidden")).action, cleanup.DELETE)

    def test_review_stamp_and_note_go_from_what_stays(self):
        d = self.decide(_q("q", reviewedAt="2026-09-25T08:00:00Z", teacherNote="x"))
        self.assertEqual((d.action, d.strip), (cleanup.KEEP, ("reviewedAt", "teacherNote")))
        self.assertTrue(d.writes)
        doc = cleanup.rewritten(_q("q", reviewedAt="t", teacherNote="x"), d, "now")
        self.assertNotIn("reviewedAt", doc)
        self.assertNotIn("teacherNote", doc)
        self.assertNotIn("_etag", doc)
        self.assertFalse(self.decide(_q("plain")).writes)

    def test_a_hide_writes_who_and_when(self):
        doc = _q("low", answered=10, correct=4, reviewedAt="t")
        d = cleanup.decide(doc, "correct")
        out = cleanup.rewritten(doc, d, "2026-10-04T12:00:00.000Z")
        self.assertEqual(
            (out["status"], out["hiddenBy"], out["hiddenAt"]),
            ("hidden", "auto", "2026-10-04T12:00:00.000Z"),
        )
        self.assertNotIn("reviewedAt", out)
        self.assertEqual(out["answeredCount"], 10)

    def test_the_thresholds_are_the_apps(self):
        dart = (cleanup.ROOT / "lib/services/tutor/policy_constants.dart").read_text(encoding="utf-8")
        n = re.search(r"bankAutoHideMinAnswers\s*=\s*(\d+)", dart)
        share = re.search(r"bankAutoHideMaxShare\s*=\s*([\d.]+)", dart)
        self.assertEqual(int(n.group(1)), cleanup.AUTO_HIDE_MIN_ANSWERS)
        self.assertEqual(float(share.group(1)), cleanup.AUTO_HIDE_MAX_SHARE)


class RunTest(unittest.TestCase):
    DOCS = [
        _q("keep"),
        _q("strip", reviewedAt="2026-09-25T08:00:00Z"),
        _q("socratic", qtype="socraticQuestion"),
        _q("wrong-first", answered=2, correct=1),
        _q("never", answered=0, correct=0),
        _q("low", answered=11, correct=3),
        _q("raced", answered=0, correct=0),
    ]
    TURNS = [
        _turn("wrong-first", "wrong", "2026-09-24T10:01:00Z"),
        _turn("low", "correct", "2026-09-24T10:01:00Z"),
    ]

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def run_cleanup(self, *argv, conflicts=frozenset(), log=None):
        fake = _fake_cosmos([dict(d) for d in self.DOCS], self.TURNS, conflicts, log)
        out = io.StringIO()
        with mock.patch.object(cleanup, "_cosmos", return_value=fake), contextlib.redirect_stdout(out):
            cleanup.main(list(argv))
        return fake, out.getvalue()

    def test_the_dry_run_writes_nothing_and_counts_per_reason(self):
        fake, out = self.run_cleanup("--backup-dir", str(self.tmp))
        self.assertEqual((fake.deletes, fake.upserts), ([], []))
        self.assertEqual(list(self.tmp.iterdir()), [], "no backup on a dry run")
        self.assertIn("vragen in de bank: 7", out)
        self.assertRegex(out, r"behouden\s+2\n")
        self.assertRegex(out, r"verwijderd\s+4\n")
        self.assertRegex(out, r"automatisch verborgen\s+1\n")
        self.assertRegex(out, r"nooit beantwoord\s+2\n")
        self.assertIn("Droge run", out)

    def test_apply_backs_up_first_then_deletes_and_writes_with_the_etag(self):
        tmp = self.tmp
        backups_at_write = []

        class _Log(list):
            """Notes, at every write, how many backups are on disk."""

            def append(self, entry):
                backups_at_write.append(len(list(tmp.glob("backup_questions_*.json"))))
                super().append(entry)

        fake, out = self.run_cleanup(
            "--apply", "--backup-dir", str(tmp), conflicts={"raced"}, log=_Log()
        )

        self.assertTrue(backups_at_write)
        self.assertEqual(set(backups_at_write), {1}, "the backup comes before any write")
        backup = json.loads(next(self.tmp.glob("backup_questions_*.json")).read_text(encoding="utf-8"))
        self.assertEqual({d["id"] for d in backup["questions"]}, {d["id"] for d in self.DOCS})

        self.assertEqual(
            sorted(d[1] for d in fake.deletes),
            ["never", "socratic", "wrong-first"],
        )
        self.assertTrue(all(etag == f'"{qid}"' for _, qid, _, etag in fake.deletes))
        written = {doc["id"]: (doc, pk, etag) for _, doc, pk, etag in fake.upserts}
        self.assertEqual(set(written), {"strip", "low"})
        self.assertNotIn("reviewedAt", written["strip"][0])
        self.assertEqual(written["low"][0]["hiddenBy"], "auto")
        self.assertEqual(written["low"][1:], ("sg-a", '"low"'))
        self.assertIn("overgeslagen (intussen gewijzigd): raced", out)

    def test_apply_refuses_a_backup_inside_the_repo(self):
        with self.assertRaises(SystemExit):
            self.run_cleanup("--apply", "--backup-dir", str(cleanup.ROOT / "tmp-backup"))
        self.assertFalse((cleanup.ROOT / "tmp-backup").exists())


if __name__ == "__main__":
    unittest.main()
