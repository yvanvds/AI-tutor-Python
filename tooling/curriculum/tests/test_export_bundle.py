"""Tests for `export_bundle.py`: what may leave the database, the manifest
hash, the bundle on disk and the diff. Standard library only; pytest
collects them too:

    python -m unittest discover -s tooling/curriculum/tests

No test touches the live account: `FakeDb` (`fake_bundle_db.py`) takes the
place of `tooling/evaluation/cosmos.py`, which would read `.env` on import.
"""

from __future__ import annotations

import contextlib
import copy
import io
import json
import random
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import export_bundle as eb  # noqa: E402
from fake_bundle_db import DOCS, FIXTURE_DIR, FIXTURE_NOW, FakeDb  # noqa: E402

STUDENT_FIELDS = {"createdByUid", "askedCount", "answeredCount", "correctCount", "lastAskedAt",
                  "keyDisputedCount", "keyDisputedAt", "hiddenBy", "hiddenAt", "keptByTeacher"}


def _all_keys(value) -> set[str]:
    if isinstance(value, dict):
        return set(value) | {k for v in value.values() for k in _all_keys(v)}
    if isinstance(value, list):
        return {k for v in value for k in _all_keys(v)}
    return set()


class AllowList(unittest.TestCase):
    def setUp(self):
        self.db = FakeDb()
        self.bundle = eb.read_live(self.db)

    def test_every_field_is_on_the_list(self):
        for container, docs in self.bundle.items():
            for doc in docs:
                self.assertLessEqual(set(doc), eb.ALLOWED[container], f"{container}/{doc['id']}")

    def test_a_field_not_on_the_list_does_not_leave(self):
        goal = next(d for d in self.bundle["goals"] if d["id"] == "toekennen")
        self.assertNotIn("draftNote", goal)
        for docs in self.bundle.values():
            for doc in docs:
                self.assertFalse(any(k.startswith("_") for k in doc), "Cosmos' own fields stay behind")

    def test_no_student_container_is_read_or_written(self):
        self.assertFalse(set(self.db.touched) & eb.STUDENT_CONTAINERS)
        self.assertLessEqual(set(self.db.touched), set(eb.ALLOWED))
        self.assertFalse(set(self.bundle) & eb.STUDENT_CONTAINERS)
        for name in ("accounts", "lo_beliefs", "turn_history", "turn_content", "progress",
                     "playground_files", "grade_proposals", "reports"):
            self.assertIn(name, eb.STUDENT_CONTAINERS)
            self.assertNotIn(name, eb.ALLOWED)

    def test_questions_only_active_without_uid_and_counters(self):
        ids = [q["id"] for q in self.bundle["questions"]]
        self.assertEqual(ids, ["toekennen_aaaa", "toekennen_bbbb"])
        for q in self.bundle["questions"]:
            self.assertEqual(q["status"], "active")
            self.assertFalse(set(q) & STUDENT_FIELDS, q["id"])
        # What the app needs to use the question is still there.
        q = self.bundle["questions"][0]
        for field in ("subgoalId", "questionType", "payload", "targetLOIds", "optionFeedback"):
            self.assertIn(field, q)

    def test_config_only_global_model_and_bank_settings(self):
        self.assertEqual(self.bundle["config"], [{
            "id": "global", "type": "config", "Model": "gpt-test",
            "QuestionBankMinimum": 3, "QuestionBankShare": 0.5,
        }])

    def test_no_key_like_field_leaves_even_when_on_the_list(self):
        names = ["ApiKey", "apiKey", "api_key", "OPENAI_API_KEY", "CosmosKey", "clientSecret",
                 "Password", "accessToken", "ConnectionString", "SasToken", "credentials"]
        allowed = dict(eb.ALLOWED)
        try:
            eb.ALLOWED["config"] = eb.ALLOWED["config"] | set(names)
            doc = {"id": "global", "type": "config", "Model": "m", **{n: "x" for n in names}}
            self.assertEqual(eb.clean("config", doc), {"id": "global", "type": "config", "Model": "m"})
        finally:
            eb.ALLOWED.clear()
            eb.ALLOWED.update(allowed)
        for n in names:
            self.assertTrue(eb._is_key_like(n), n)
        for n in ("id", "type", "Model", "title", "body", "sourceHash", "teachingTips", "QuestionBankShare",
                  "options", "correct", "objectives", "statement", "optionFeedback"):
            self.assertFalse(eb._is_key_like(n), n)

    def test_a_nested_key_like_field_stops_the_export(self):
        docs = copy.deepcopy(DOCS)
        docs["questions"][0]["payload"]["apiKey"] = "x"
        with self.assertRaises(eb.SecretFound):
            eb.read_live(FakeDb(docs))

    def test_a_key_like_value_stops_the_export(self):
        for value in ("sk-" + "a1B2" * 10, "AccountEndpoint=https://x/;AccountKey=abc;", "Zm9v" * 20 + "=="):
            docs = copy.deepcopy(DOCS)
            docs["instructions"][0]["sections"]["role"] = value
            with self.assertRaises(eb.SecretFound, msg=value):
                eb.read_live(FakeDb(docs))
        # A sha256 in hex is not one.
        self.assertFalse(eb._looks_like_secret("ab" * 32))

    def test_export_command_writes_nothing_when_a_secret_is_found(self):
        docs = copy.deepcopy(DOCS)
        docs["goals"][0]["teachingTips"] = ["sk-" + "x" * 30]
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stderr(io.StringIO()):
            code = eb.main(["export", "--out", tmp], source=FakeDb(docs))
            self.assertEqual(code, 2)
            self.assertEqual(list(Path(tmp).iterdir()), [])


class Manifest(unittest.TestCase):
    def test_hash_stays_the_same_while_the_content_does(self):
        a = eb.read_live(FakeDb())
        docs = copy.deepcopy(DOCS)
        for v in docs.values():
            random.Random(1).shuffle(v)
        b = eb.read_live(FakeDb(docs))
        self.assertEqual(eb.content_version(a), eb.content_version(b))
        with tempfile.TemporaryDirectory() as t1, tempfile.TemporaryDirectory() as t2:
            m1 = eb.write_bundle(a, Path(t1), now="2026-01-01T00:00:00.000000Z")
            m2 = eb.write_bundle(b, Path(t2), now="2026-02-01T00:00:00.000000Z")
            self.assertEqual(m1["contentVersion"], m2["contentVersion"])

    def test_hash_changes_with_the_content(self):
        a = eb.read_live(FakeDb())
        docs = copy.deepcopy(DOCS)
        docs["content"][0]["body"] = "<p>anders</p>"
        self.assertNotEqual(eb.content_version(a), eb.content_version(eb.read_live(FakeDb(docs))))
        # A field that does not leave does not change the version either.
        docs = copy.deepcopy(DOCS)
        docs["questions"][0]["askedCount"] = 99
        self.assertEqual(eb.content_version(a), eb.content_version(eb.read_live(FakeDb(docs))))

    def test_unchanged_export_keeps_the_folder_as_it_is(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            eb.write_bundle(eb.read_live(FakeDb()), out, now="2026-01-01T00:00:00.000000Z")
            before = {p.name: p.read_bytes() for p in out.iterdir()}
            m = eb.write_bundle(eb.read_live(FakeDb()), out, now="2026-03-01T00:00:00.000000Z")
            self.assertEqual(m["exportedAt"], "2026-01-01T00:00:00.000000Z")
            self.assertEqual({p.name: p.read_bytes() for p in out.iterdir()}, before)

    def test_bundle_format(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            m = eb.write_bundle(eb.read_live(FakeDb()), out, now=FIXTURE_NOW)
            self.assertEqual(m["format"], 1)
            self.assertEqual(len(m["contentVersion"]), 64)
            self.assertEqual(set(m["containers"]), set(eb.ALLOWED))
            self.assertEqual(sorted(p.name for p in out.iterdir()),
                             sorted(["manifest.json"] + [f"{c}.json" for c in eb.ALLOWED]))
            goals = json.loads((out / "goals.json").read_text(encoding="utf-8"))
            self.assertEqual(goals["container"], "goals")
            self.assertEqual(goals["partitionKeyField"], "type")
            q = json.loads((out / "questions.json").read_text(encoding="utf-8"))
            self.assertEqual(q["partitionKeyField"], "subgoalId")
            self.assertEqual(m["containers"]["questions"], {"file": "questions.json", "count": 2})
            self.assertEqual(eb.read_bundle(out), eb.read_live(FakeDb()))

    def test_fixture_bundle_is_current(self):
        """`test/fixtures/curriculum_bundle/` is what the exporter makes of
        the fake database; regenerate with `fake_bundle_db.py`."""
        with tempfile.TemporaryDirectory() as tmp:
            eb.write_bundle(eb.read_live(FakeDb()), Path(tmp), now=FIXTURE_NOW)
            fresh = {p.name: p.read_text(encoding="utf-8") for p in Path(tmp).iterdir()}
        on_disk = {p.name: p.read_text(encoding="utf-8") for p in FIXTURE_DIR.iterdir()}
        self.assertEqual(on_disk, fresh)


class Diff(unittest.TestCase):
    def test_no_changes(self):
        live = eb.read_live(FakeDb())
        self.assertEqual(eb.diff(live, copy.deepcopy(live)), [])

    def test_changes_per_goal_lesson_section_and_question(self):
        old = eb.read_live(FakeDb())
        docs = copy.deepcopy(DOCS)
        docs["goals"][1]["teachingTips"].append("Nog een tip.")
        docs["content"][0]["body"] = "<p>nieuw</p>"
        docs["instructions"][0]["sections"]["mcQuestion"] = "Anders."
        docs["instructions"][0]["sections"]["grader"] = "Nieuw."
        del docs["instructions"][0]["sections"]["role"]
        docs["questions"][0]["status"] = "hidden"
        docs["translations"].append({"id": "goal_variabelen", "language": "fr", "kind": "goal",
                                     "refId": "variabelen", "title": "Variables", "description": "d",
                                     "sourceHash": "2" * 64})
        new = eb.read_live(FakeDb(docs))
        self.assertEqual(eb.diff(old, new), [
            "~ goal toekennen (Toekennen): teachingTips",
            "~ lesson toekennen (Toekennen): body",
            "~ instructions tutor: sections: +grader, -role, ~mcQuestion",
            "+ translation fr/goal_variabelen",
            "- question toekennen/toekennen_aaaa",
        ])

    def test_diff_command_between_two_bundles(self):
        docs = copy.deepcopy(DOCS)
        docs["modules"][0]["title"] = "Python 2"
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            eb.write_bundle(eb.read_live(FakeDb()), Path(a))
            eb.write_bundle(eb.read_live(FakeDb(docs)), Path(b))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                self.assertEqual(eb.main(["diff", "--old", a, "--new", b]), 0)
            self.assertIn("~ module python-basics: title", buf.getvalue())

    def test_first_export_shows_everything_as_new(self):
        with tempfile.TemporaryDirectory() as empty:
            lines = eb.diff(eb.read_bundle(Path(empty)), eb.read_live(FakeDb()))
        self.assertTrue(lines and all(line.startswith("+ ") for line in lines))
        self.assertIn("+ config global", lines)

    def test_diff_command_reads_live_through_the_source(self):
        db = FakeDb()
        with tempfile.TemporaryDirectory() as empty:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                eb.main(["diff", "--old", empty], source=db)
            self.assertEqual(list(Path(empty).iterdir()), [], "diff writes nothing")
        self.assertIn("+ goal variabelen (Variabelen)", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
