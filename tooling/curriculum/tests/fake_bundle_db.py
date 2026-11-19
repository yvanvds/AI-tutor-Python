"""A made-up database for `export_bundle.py`: the content containers with a
couple of docs each, plus student containers and fields that must never
leave. All data is invented.

It also makes the fixture bundle the app's tests read (#266):

    python tooling/curriculum/tests/fake_bundle_db.py

writes `test/fixtures/curriculum_bundle/` by running the exporter against
this database. `test_export_bundle.py` checks that the fixture is current.
"""

from __future__ import annotations

import copy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE_DIR = ROOT / "test" / "fixtures" / "curriculum_bundle"
FIXTURE_NOW = "2026-11-19T00:00:00.000000Z"

_COSMOS_META = {"_rid": "abc==", "_self": "dbs/x/colls/y/docs/z", "_etag": '"0000"', "_attachments": "attachments/", "_ts": 1763510400}


def _q(qid, subgoal, status="active", **extra):
    doc = {
        "id": qid,
        "type": "question",
        "subgoalId": subgoal,
        "rootGoalId": "variabelen",
        "targetLOIds": ["lo_toekennen"],
        "questionType": "multiple_choice",
        "difficulty": "easy",
        "language": "nl",
        "payload": {
            "type": "multiple_choice",
            "question": "Wat is de waarde van x na `x = 3`?",
            "options": ["3", "x", "0"],
            "correct": "3",
        },
        "model": "gpt-test",
        "createdAt": "2026-10-01T08:00:00.000Z",
        "createdByUid": "uid-leerling-1",
        "askedCount": 7,
        "answeredCount": 6,
        "correctCount": 5,
        "lastAskedAt": "2026-10-20T09:00:00.000Z",
        "optionFeedback": [{"option": "x", "text": "x is de naam, niet de waarde.", "quality": "wrong", "version": 1}],
        "keyDisputedCount": 1,
        "keyDisputedAt": "2026-10-21T09:00:00.000Z",
        "status": status,
        **_COSMOS_META,
    }
    doc.update(extra)
    return doc


DOCS: dict[str, list[dict]] = {
    "goals": [
        {"id": "variabelen", "type": "goal", "title": "Variabelen", "description": "Je kan waarden bewaren.",
         "parentId": None, "order": 1000, "optional": False, "teachingTips": [], "allowChains": False,
         "objectives": [], "contentId": None, "moduleId": "python-basics", **_COSMOS_META},
        {"id": "toekennen", "type": "goal", "title": "Toekennen", "description": "Een waarde aan een naam geven.",
         "parentId": "variabelen", "order": 1000, "optional": False, "teachingTips": ["Begin met een getal."],
         "allowChains": True,
         "objectives": [{"id": "lo_toekennen", "statement": "Je kan een waarde toekennen.", "kind": "apply",
                         "weight": 1.0, "optional": False}],
         "contentId": "toekennen", "moduleId": "python-basics", "draftNote": "nog niet af", **_COSMOS_META},
    ],
    "content": [
        {"id": "toekennen", "type": "content", "title": "Toekennen", "body": "<p>Met <code>=</code> geef je een naam een waarde.</p>",
         "updatedAt": "2026-10-01T08:00:00.000Z", **_COSMOS_META},
    ],
    "modules": [
        {"id": "python-basics", "type": "module", "title": "Python", "order": 0, "updatedAt": "2026-09-01T08:00:00.000Z", **_COSMOS_META},
    ],
    "instructions": [
        {"id": "tutor", "type": "instruction",
         "sections": {"role": "Je bent een tutor.", "mcQuestion": "Maak een meerkeuzevraag."},
         "updatedAt": "2026-10-08T08:00:00.000Z", **_COSMOS_META},
    ],
    "translations": [
        {"id": "goal_toekennen", "language": "en", "kind": "goal", "refId": "toekennen", "title": "Assignment",
         "description": "Give a name a value.", "sourceHash": "0" * 64, "updatedAt": "2026-10-02T08:00:00.000Z", **_COSMOS_META},
        {"id": "content_toekennen", "language": "en", "kind": "content", "refId": "toekennen", "title": "Assignment",
         "body": "<p>With <code>=</code> you give a name a value.</p>", "sourceHash": "1" * 64, **_COSMOS_META},
    ],
    "config": [
        {"id": "global", "type": "config", "Model": "gpt-test", "ApiKey": "made-up-not-a-key",
         "MinimumVersion": "2.14.0", "QuestionBankMinimum": 3, "QuestionBankShare": 0.5,
         "TurnContentKeepUntil": "07-01", **_COSMOS_META},
        {"id": "classes", "type": "config", "classes": [{"name": "6XY", "lessons": []}], **_COSMOS_META},
    ],
    "questions": [
        _q("toekennen_aaaa", "toekennen"),
        _q("toekennen_bbbb", "toekennen", difficulty="medium"),
        _q("toekennen_cccc", "toekennen", status="hidden", hiddenBy="auto", hiddenAt="2026-10-22T09:00:00.000Z"),
    ],
    # Student data: never read.
    "accounts": [{"id": "uid-leerling-1", "uid": "uid-leerling-1", "firstName": "Testa", "lastName": "Voorbeeld"}],
    "lo_beliefs": [{"id": "b1", "uid": "uid-leerling-1", "subgoalId": "toekennen", "loId": "lo_toekennen"}],
    "turn_history": [{"id": "t1", "uid": "uid-leerling-1"}],
    "turn_content": [{"id": "t1", "uid": "uid-leerling-1", "answer": "x = 3"}],
    "progress": [{"id": "uid-leerling-1_variabelen", "uid": "uid-leerling-1"}],
    "playground_files": [{"id": "uid-leerling-1_a.py", "uid": "uid-leerling-1"}],
    "grade_proposals": [{"id": "uid-leerling-1_m1", "uid": "uid-leerling-1"}],
}


class FakeDb:
    """`query` and `read` of `tooling/evaluation/cosmos.py` over [docs]. The
    SQL is ignored: every doc of the container comes back, so the exporter's
    own filters are what is tested. Every container touched is recorded."""

    def __init__(self, docs: dict[str, list[dict]] | None = None):
        self.docs = copy.deepcopy(DOCS if docs is None else docs)
        self.touched: list[str] = []

    def query(self, coll, sql, params=None, pk=None, cross=True):
        self.touched.append(coll)
        return copy.deepcopy(self.docs.get(coll, []))

    def read(self, coll, doc_id, pk):
        self.touched.append(coll)
        for d in self.docs.get(coll, []):
            if d.get("id") == doc_id:
                return copy.deepcopy(d)
        return None


def write_fixture(out_dir: Path = FIXTURE_DIR) -> dict:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import export_bundle

    return export_bundle.write_bundle(export_bundle.read_live(FakeDb()), out_dir, now=FIXTURE_NOW)


if __name__ == "__main__":
    m = write_fixture()
    print(f"fixture {m['contentVersion'][:12]} in {FIXTURE_DIR}")
