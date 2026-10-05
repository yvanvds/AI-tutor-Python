"""Tests for `push_goal.py`: the docs it writes, their order, create-only
pushing and the read-back. Standard library only:

    python -m unittest discover -s tooling/curriculum/tests

No test touches the live account: a fake `cosmos` takes the place of
`tooling/evaluation/cosmos.py`, which would read `.env` on import.
"""

from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import push_goal  # noqa: E402

# What `GoalsService._docMap` and `Content.toMap` write.
GOAL_FIELDS = ["id", "type", "title", "description", "parentId", "order", "optional",
               "teachingTips", "allowChains", "objectives", "contentId", "moduleId"]
CONTENT_FIELDS = ["id", "type", "title", "body", "updatedAt"]

ENTRY = {
    "goal": {"id": "functies", "type": "goal", "moduleId": "python-basics", "title": "Functies",
             "description": "Je kan functies schrijven.", "order": 5000, "optional": False, "parentId": None},
    "subgoals": [
        {"id": "tweede", "type": "goal", "parentId": "functies", "title": "Tweede", "description": "d2",
         "order": 2000, "optional": False, "contentId": None, "teachingTips": ["tip"], "allowChains": True,
         "objectives": [{"id": "lo_b", "statement": "Je kan b.", "kind": "reason", "weight": 1.0, "optional": True}]},
        {"id": "eerste", "type": "goal", "parentId": "functies", "title": "Eerste", "description": "d1",
         "order": 1000, "optional": False, "contentId": None, "teachingTips": [], "allowChains": False,
         "objectives": [{"id": "lo_a", "statement": "Je kan a.", "kind": "apply", "weight": 1.0, "optional": False}]},
    ],
}
LESSONS = {
    "eerste": {"title": "Eerste", "body": "<p>een</p>"},
    "tweede": {"title": "Tweede", "body": "<p>twee</p>"},
}


class FakeCosmos:
    class Exists(Exception):
        pass

    def __init__(self, goals=(), content=(), modules=({"id": "python-basics"},)):
        self.store = {"goals": {d["id"]: d for d in goals}, "content": {d["id"]: d for d in content},
                      "modules": {d["id"]: d for d in modules}}
        self.created: list[str] = []

    def query(self, coll, sql, params=None, pk=None, cross=True):
        return list(self.store[coll].values())

    def read(self, coll, doc_id, pk):
        return self.store[coll].get(doc_id)

    def create(self, coll, doc, pk):
        if doc["id"] in self.store[coll]:
            raise self.Exists(doc["id"])
        self.store[coll][doc["id"]] = dict(doc)
        self.created.append(f"{coll}/{doc['id']}")


class GoalFile:
    """`load` reads `goals/<name>.json`; the tests hand the entry over directly."""

    def __init__(self, entry):
        self.entry = entry

    def __enter__(self):
        self._load = push_goal.load
        push_goal.load = lambda name, goals_dir=None: self.entry
        return self

    def __exit__(self, *exc):
        push_goal.load = self._load


class BuildDocs(unittest.TestCase):
    def test_docs_have_exactly_the_fields_the_app_writes(self):
        docs, notes = push_goal.build_docs(ENTRY, LESSONS, now="2026-10-05T18:00:00.000000Z")
        self.assertEqual(notes, [])
        for coll, pk, d in docs:
            self.assertEqual(list(d), CONTENT_FIELDS if coll == "content" else GOAL_FIELDS)
            self.assertEqual(d["type"], pk)

    def test_lessons_first_then_subgoals_in_order_and_the_root_last(self):
        docs, _ = push_goal.build_docs(ENTRY, LESSONS)
        self.assertEqual(
            [(coll, d["id"]) for coll, _, d in docs],
            [("content", "eerste"), ("content", "tweede"), ("goals", "eerste"), ("goals", "tweede"), ("goals", "functies")],
        )

    def test_a_subgoal_points_at_the_lesson_with_its_own_id_and_takes_the_module_of_its_root(self):
        docs, _ = push_goal.build_docs(ENTRY, LESSONS)
        sub = next(d for coll, _, d in docs if coll == "goals" and d["id"] == "tweede")
        self.assertEqual((sub["contentId"], sub["parentId"], sub["moduleId"]), ("tweede", "functies", "python-basics"))
        self.assertEqual(sub["objectives"], [{"id": "lo_b", "statement": "Je kan b.", "kind": "reason", "weight": 1.0, "optional": True}])
        root = docs[-1][2]
        self.assertEqual((root["parentId"], root["contentId"], root["objectives"], root["order"]), (None, None, [], 5000))

    def test_a_subgoal_without_a_lesson_is_written_unlinked_and_reported(self):
        docs, notes = push_goal.build_docs(ENTRY, {"eerste": LESSONS["eerste"]})
        sub = next(d for coll, _, d in docs if coll == "goals" and d["id"] == "tweede")
        self.assertIsNone(sub["contentId"])
        self.assertEqual([coll for coll, _, _ in docs].count("content"), 1)
        self.assertTrue(any("tweede" in n and "no Dutch lesson" in n for n in notes))


class Commands(unittest.TestCase):
    def test_plan_writes_nothing_and_names_a_root_with_the_same_order(self):
        cosmos = FakeCosmos(goals=[{"id": "lijsten", "parentId": None, "order": 5000}])
        out = io.StringIO()
        with GoalFile(ENTRY):
            _, notes = push_goal.plan(cosmos, "05-functies", out, nl_lessons=LESSONS)
        self.assertEqual(cosmos.created, [])
        self.assertTrue(any("lijsten" in n and "5000" in n for n in notes))

    def test_push_creates_everything_and_reads_it_back_equal(self):
        cosmos = FakeCosmos()
        with GoalFile(ENTRY):
            r = push_goal.push(cosmos, "05-functies", io.StringIO(), nl_lessons=LESSONS)
        self.assertEqual(cosmos.created[-1], "goals/functies")
        self.assertEqual((len(r["created"]), r["exists"], r["different"]), (5, [], {}))

    def test_push_keeps_a_doc_that_is_already_there(self):
        mine = {"id": "eerste", "type": "content", "title": "Eerste", "body": "<p>typed in the app</p>"}
        cosmos = FakeCosmos(content=[mine])
        out = io.StringIO()
        with GoalFile(ENTRY):
            r = push_goal.push(cosmos, "05-functies", out, nl_lessons=LESSONS)
        self.assertEqual(cosmos.store["content"]["eerste"]["body"], "<p>typed in the app</p>")
        self.assertEqual(r["exists"], ["content/eerste"])
        self.assertEqual(r["different"], {"content/eerste": ["body"]})
        self.assertIn("409 KEPT  content/eerste", out.getvalue())

    def test_verify_before_a_push_finds_everything_missing(self):
        with GoalFile(ENTRY):
            r = push_goal.verify(FakeCosmos(), "05-functies", io.StringIO(), nl_lessons=LESSONS)
        self.assertEqual(r["same"], [])
        self.assertEqual(len(r["different"]), 5)
        self.assertTrue(all(diff == ["missing"] for diff in r["different"].values()))


if __name__ == "__main__":
    unittest.main()
