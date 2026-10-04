"""Tests for the oefeningen backfill (#217): which turn records count as an
oefening, what the dry run shows per class, and what `--apply` backs up and
writes. Standard library only:

    python -m unittest discover -s tooling/xp/tests

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

import backfill  # noqa: E402


def _turn(uid: str, *, qtype: str = "mcQuestion", follow_up: bool | None = False, subgoal: str = "s1") -> dict:
    t = {"uid": uid, "questionType": qtype, "subgoalId": subgoal}
    if follow_up is not None:
        t["isFollowUp"] = follow_up
    return t


def _account(uid: str, klas: str = "6TEST", *, first: str = "Voornaam", last: str = "Achternaam", **extra) -> dict:
    return {
        "id": uid,
        "uid": uid,
        "firstName": first,
        "lastName": last,
        "email": f"{uid}@school.example",
        "className": klas,
        "calibration": {"difficulty": "medium"},
        "streakDays": 2,
        "_etag": f'"{uid}"',
        "_rid": "rid",
        **extra,
    }


def _goal(gid: str, parent: str | None = "r1", optional: bool = False) -> dict:
    return {"id": gid, "type": "goal", "parentId": parent, "optional": optional}


def _progress(uid: str, goal: str, value: float) -> dict:
    return {"uid": uid, "goalId": goal, "progress": value}


class _Conflict(Exception):
    pass


def _fake_cosmos(accounts, turns, goals, progress, conflicts=frozenset(), log=None):
    m = types.ModuleType("cosmos")
    m.Conflict = _Conflict
    m.upserts = []
    log = log if log is not None else []

    def query(coll, sql, params=None, pk=None, cross=True):
        return {"accounts": accounts, "turn_history": turns, "progress": progress}[coll]

    def upsert(coll, doc, pk, etag=None):
        if doc["id"] in conflicts:
            raise _Conflict(doc["id"])
        log.append(("upsert", doc["id"]))
        m.upserts.append((coll, doc, pk, etag))
        return doc

    m.query, m.upsert = query, upsert
    m.goals = lambda: {g["id"]: g for g in goals}
    return m


class RulesTest(unittest.TestCase):
    def test_a_graded_first_answer_counts_whatever_the_grade(self):
        turns = [
            {**_turn("u"), "overallQuality": q} for q in ("correct", "partial", "wrong")
        ]
        self.assertEqual(backfill.oefeningen_per_student(turns)["u"], 3)

    def test_a_follow_up_an_audit_stub_and_an_answer_without_subgoal_do_not(self):
        turns = [
            _turn("u"),
            _turn("u", follow_up=True),
            _turn("u", qtype=""),  # appendAudit: no question asked
            {"uid": "u", "subgoalId": "s1"},  # audit from an older build
            _turn("u", subgoal=""),  # no active subgoal: the conductor's early return
            _turn("u", follow_up=None),  # a record from before the field: no follow-up
        ]
        self.assertEqual(backfill.oefeningen_per_student(turns)["u"], 2)

    def test_the_stored_count_reads_like_the_app(self):
        self.assertEqual(backfill.stored_count({}), 0)
        self.assertEqual(backfill.stored_count({"oefeningCount": 12}), 12)
        self.assertEqual(backfill.stored_count({"oefeningCount": 12.0}), 12)
        self.assertEqual(backfill.stored_count({"oefeningCount": "7"}), 0)
        self.assertEqual(backfill.stored_count({"oefeningCount": -3}), 0)
        self.assertEqual(backfill.stored_count({"oefeningCount": True}), 0)

    def test_mastery_xp_counts_non_optional_subgoals_only(self):
        goals = [_goal("r1", parent=None), _goal("s1"), _goal("s2"), _goal("s3", optional=True)]
        progress = [
            _progress("u", "r1", 1.0),  # the root's cache is no subgoal
            _progress("u", "s1", 1.0),
            _progress("u", "s2", 0.5),
            _progress("u", "s3", 1.0),
            _progress("v", "s1", 0.005),  # 0.5 XP rounds up, as Dart's round()
        ]
        xp = backfill.mastery_xp_per_student(progress, backfill.mastery_subgoals(goals))
        self.assertEqual(xp, {"u": 150, "v": 1})

    def test_levels_are_the_apps(self):
        self.assertEqual(backfill.level(0, 0), 1)
        self.assertEqual(backfill.level(24, 0), 1)
        self.assertEqual(backfill.level(25, 0), 2)
        self.assertEqual(backfill.level(140, 300), 7)

    def test_the_count_never_goes_down(self):
        accounts = [_account("ahead", oefeningCount=50), _account("behind", oefeningCount=3)]
        turns = [_turn("ahead")] * 10 + [_turn("behind")] * 10
        planned = {p.doc["id"]: p for p in backfill.plan(accounts, turns, [], [])}
        self.assertEqual((planned["ahead"].after, planned["ahead"].writes), (50, False))
        self.assertEqual((planned["behind"].after, planned["behind"].writes), (10, True))

    def test_only_the_counter_changes_on_the_doc(self):
        doc = _account("u", oefeningCount=1, somethingNewer="kept")
        out = backfill.updated(doc, 9)
        self.assertEqual(out["oefeningCount"], 9)
        self.assertEqual({k: v for k, v in out.items() if k != "oefeningCount"},
                         {k: v for k, v in doc.items() if not k.startswith("_") and k != "oefeningCount"})
        self.assertNotIn("_etag", out)

    def test_the_constants_are_the_apps(self):
        dart = (backfill.ROOT / "lib/features/shell/shell_state.dart").read_text(encoding="utf-8")
        for name, value in (
            ("kXpPerOefening", backfill.XP_PER_OEFENING),
            ("kXpPerSubgoal", backfill.XP_PER_SUBGOAL),
            ("kXpPerLevel", backfill.XP_PER_LEVEL),
        ):
            m = re.search(rf"const int {name} = (\d+);", dart)
            self.assertIsNotNone(m, name)
            self.assertEqual(int(m.group(1)), value, name)


class RunTest(unittest.TestCase):
    ACCOUNTS = [
        _account("u1", "6EWI", first="Ada", last="Lovelace"),
        _account("u2", "6EWI", first="Alan", last="Turing", oefeningCount=2),
        _account("u3", "6WEWI", first="Grace", last="Hopper"),
        _account("raced", "6WEWI", first="Linus", last="Torvalds"),
        _account("teacher", "", first="Juf", last="Leraar"),
    ]
    TURNS = (
        [_turn("u1")] * 30
        + [_turn("u1", follow_up=True)] * 5
        + [_turn("u2")] * 2
        + [_turn("u3")] * 140
        + [_turn("raced")] * 4
    )
    GOALS = [_goal("r1", parent=None), _goal("s1"), _goal("s2")]
    PROGRESS = [_progress("u3", "s1", 1.0), _progress("u3", "s2", 1.0)]

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def run_backfill(self, *argv, conflicts=frozenset(), log=None):
        fake = _fake_cosmos(
            [dict(a) for a in self.ACCOUNTS], self.TURNS, self.GOALS, self.PROGRESS, conflicts, log
        )
        out = io.StringIO()
        with mock.patch.object(backfill, "_cosmos", return_value=fake), contextlib.redirect_stdout(out):
            backfill.main(list(argv))
        return fake, out.getvalue()

    def test_the_dry_run_writes_nothing_and_shows_each_class_without_names(self):
        fake, out = self.run_backfill("--backup-dir", str(self.tmp))
        self.assertEqual(fake.upserts, [])
        self.assertEqual(list(self.tmp.iterdir()), [], "no backup on a dry run")
        self.assertIn("Droge run", out)

        self.assertIn("6EWI: 2 leerlingen, 32 oefeningen", out)
        self.assertIn("6WEWI: 2 leerlingen, 144 oefeningen", out)
        self.assertIn("(geen klas): 1 leerling, 0 oefeningen", out)
        self.assertLess(out.index("6EWI:"), out.index("6WEWI:"))
        self.assertLess(out.index("6WEWI:"), out.index("(geen klas):"))
        # 140 oefeningen and two subgoals: 2800 + 200 = 3000 XP, level 7.
        self.assertRegex(out, r"\n  1\s+140\s+0\s+140\s+1\s+7\n")
        # 30 counted, the 5 follow-ups not: 600 XP, level 2.
        self.assertRegex(out, r"\n  1\s+30\s+0\s+30\s+1\s+2\n")
        self.assertIn("accounts: 5, te schrijven: 3", out)

        for a in self.ACCOUNTS:
            for field in ("firstName", "lastName", "email", "id"):
                if a[field] in ("u1", "u2", "u3"):
                    continue  # the ids of made-up students are digits in a table
                self.assertNotIn(a[field], out, field)

    def test_apply_backs_up_first_then_writes_only_the_counter_with_the_etag(self):
        tmp = self.tmp
        backups_at_write = []

        class _Log(list):
            """Notes, at every write, how many backups are on disk."""

            def append(self, entry):
                backups_at_write.append(len(list(tmp.glob("backup_accounts_*.json"))))
                super().append(entry)

        fake, out = self.run_backfill("--apply", "--backup-dir", str(tmp), conflicts={"raced"}, log=_Log())

        self.assertTrue(backups_at_write)
        self.assertEqual(set(backups_at_write), {1}, "the backup comes before any write")
        backup = json.loads(next(tmp.glob("backup_accounts_*.json")).read_text(encoding="utf-8"))
        self.assertEqual({a["id"] for a in backup["accounts"]}, {a["id"] for a in self.ACCOUNTS})

        written = {doc["id"]: (doc, pk, etag) for _, doc, pk, etag in fake.upserts}
        # u2 already has its 2; the teacher made none.
        self.assertEqual(set(written), {"u1", "u3"})
        self.assertEqual(written["u1"][0]["oefeningCount"], 30)
        self.assertEqual(written["u3"][0]["oefeningCount"], 140)
        self.assertEqual(written["u3"][1:], ("u3", '"u3"'))
        self.assertTrue(all(coll == "accounts" for coll, *_ in fake.upserts))
        # Everything else as it was read.
        self.assertEqual(written["u1"][0]["calibration"], {"difficulty": "medium"})
        self.assertEqual(written["u1"][0]["streakDays"], 2)
        self.assertNotIn("updatedAt", written["u1"][0])
        # The one a student's app wrote in between is named — anonymously.
        self.assertIn("overgeslagen (intussen gewijzigd): 6WEWI leerling 2", out)
        self.assertNotIn("Torvalds", out)
        self.assertIn("geschreven 2", out)

    def test_apply_refuses_a_backup_inside_the_repo(self):
        with self.assertRaises(SystemExit):
            self.run_backfill("--apply", "--backup-dir", str(backfill.ROOT / "tmp-backup"))
        self.assertFalse((backfill.ROOT / "tmp-backup").exists())


if __name__ == "__main__":
    unittest.main()
