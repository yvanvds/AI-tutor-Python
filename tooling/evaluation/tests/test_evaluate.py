"""Tests for the evaluation tooling, at the level the teacher uses it: the
`evaluate.py` commands, their files and what they would write to Cosmos.

Standard library only, like the tooling:

    python -m unittest discover -s tooling/evaluation/tests

No test touches the live account. `evaluate` imports `cosmos`, which reads
the repo's `.env` and talks to Cosmos; a fake takes its place before the
import and on every test. The data is made up: no real student is in here.
"""

from __future__ import annotations

import contextlib
import datetime as dt
import io
import json
import shutil
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


class _Conflict(Exception):
    pass


def _fake_cosmos() -> types.ModuleType:
    m = types.ModuleType("cosmos")
    m.Conflict = _Conflict
    m.upserts = []
    m.milestones = lambda: [MILESTONE]
    m.goals = lambda: GOALS
    m.accounts = lambda klas: [a for a in ACCOUNTS if a["className"] == klas]
    m.turns = lambda uid: sorted(TURNS.get(uid, []), key=lambda t: t["turnAt"])
    m.beliefs = lambda uid: {}
    m.read = lambda coll, doc_id, pk: None
    m.query = lambda *a, **k: []

    def upsert(coll, doc, pk, etag=None):
        m.upserts.append((coll, doc, pk, etag))
        return doc

    m.upsert = upsert
    return m


sys.modules.setdefault("cosmos", _fake_cosmos())

import evaluate  # noqa: E402
import rules  # noqa: E402

NOW = dt.datetime(2026, 9, 24, 12, 0, tzinfo=dt.timezone.utc)
KLAS = "6TEST"

GOALS = {
    "g-root": {"id": "g-root", "title": "Hoofddoel", "order": 1},
    "sg-a": {
        "id": "sg-a",
        "parentId": "g-root",
        "order": 1,
        "title": "Deel A",
        "objectives": [
            {"id": "recall_a1", "statement": "Je kan A1 benoemen."},
            {"id": "write_a2", "statement": "Je kan A2 schrijven."},
            {"id": "fix_a3", "statement": "Je kan A3 verbeteren."},
        ],
    },
    "sg-b": {
        "id": "sg-b",
        "parentId": "g-root",
        "order": 2,
        "title": "Deel B",
        "objectives": [{"id": "predict_b1", "statement": "Je kan B1 voorspellen."}],
    },
}

MILESTONE = {
    "id": "ms-1",
    "title": "Mijlpaal een",
    "periodStart": "2026-09-01T00:00:00.000Z",
    "expectedDifficulty": "medium",
    "subgoalIds": ["sg-a", "sg-b"],
    "coreLoKeys": ["sg-a/recall_a1", "sg-b/predict_b1"],
}

ACCOUNTS = [
    {"uid": "u-anna", "firstName": "Anna", "lastName": "Peeters", "className": KLAS,
     "updatedAt": "2026-09-22T10:00:00Z", "calibration": {"difficulty": "medium"}},
    {"uid": "u-bram", "firstName": "Bram", "lastName": "Janssens", "className": KLAS,
     "updatedAt": "2026-09-01T10:00:00Z"},
]


def _turn(at: str, subgoal: str, lo: str, **extra) -> dict:
    t = {
        "id": f"t-{at}",
        "type": "turn_history",
        "uid": "u-anna",
        "turnAt": at,
        "subgoalId": subgoal,
        "targetLOIds": [lo],
        "questionType": "mcQuestion",
        "difficulty": "medium",
        "isFollowUp": False,
        "chainDepth": 0,
        "overallQuality": "correct",
        "loSignals": [{"subgoalId": subgoal, "loId": lo, "signal": "positive", "strength": "strong"}],
        "appliedSignals": [],
        "provenance": "home",
        "calibrationBefore": "medium",
        "calibrationAfter": "medium",
        "subgoalProgressAfter": 0.5,
        "loStatusAfter": [],
        "subgoalAdvanced": False,
    }
    t.update(extra)
    return t


def _audit(at: str, subgoal: str, uid: str, kind: str = "emptyObjectivesBlock") -> dict:
    """The stub `TurnHistoryService.appendAudit` writes for an audit event
    (CONDUCTOR_POLICY §8.1): no question, and `wrong` and `medium` as
    placeholders. Not an oefening."""
    return {
        "id": f"t-{at}",
        "type": "turn_history",
        "uid": uid,
        "turnAt": at,
        "subgoalId": subgoal,
        "targetLOIds": [],
        "questionType": "",
        "isFollowUp": False,
        "chainDepth": 0,
        "overallQuality": "wrong",
        "loSignals": [],
        "hadFallback": False,
        "appliedSignals": [],
        "provenance": "home",
        "calibrationBefore": "medium",
        "calibrationAfter": "medium",
        "subgoalProgressAfter": 0.0,
        "loStatusAfter": [],
        "subgoalAdvanced": False,
        "signalEvents": [{"kind": kind, "severity": "audit", "details": {"subgoalId": subgoal}}],
    }


_no_provenance = _turn("2026-09-20T09:40:00.000Z", "sg-b", "predict_b1")
del _no_provenance["provenance"]  # a doc from before the field: reads as home

TURNS = {
    "u-anna": [
        # Before the period, and 45 days before the draft: recall_a1 gets no
        # evidence after this, so it is stale. Not in the period's tally.
        *[_turn(f"2026-08-10T09:0{i}:00.000Z", "sg-a", "recall_a1") for i in range(4)],
        # In the period: 3 supervised, 3 home (one explicit, one without the
        # field, one warm-up-style recheck), plus an audit record that is no
        # oefening. The fields the app added in this batch ride along.
        _turn("2026-09-20T09:00:00.000Z", "sg-b", "predict_b1", provenance="supervised",
              usage={"inputTokens": 1200, "outputTokens": 300, "totalTokens": 1500}, clientVersion="2.6.0"),
        _turn("2026-09-20T09:10:00.000Z", "sg-b", "predict_b1", provenance="supervised",
              questionId="q-sg-b-1", fromBank=True, gradedByKey=True),
        _turn("2026-09-20T09:20:00.000Z", "sg-b", "predict_b1", provenance="supervised"),
        _turn("2026-09-20T09:30:00.000Z", "sg-b", "predict_b1", provenance="home"),
        _no_provenance,
        _turn("2026-09-21T09:00:00.000Z", "sg-a", "fix_a3", isRecheck=True, activeSubgoalId="sg-b",
              questionId="q-sg-a-7", fromBank=True),
        _audit("2026-09-22T09:00:00.000Z", "sg-b", "u-anna"),
    ],
}


# #195: a class of two made-up students with the same oefeningen. recall_a1
# was left at μ 0.75 in Deel A; fix_a3 got over the bar from the side while
# the student worked in Deel B, without a direct right answer, so without a
# stamp. Then, still on Deel B and now at `hard`, one question about
# recall_a1 whose grader also names fix_a3 and the active predict_b1.
# Cas has it as the app writes a recheck since #187; Dirk as an older build
# wrote a warm-up, without `activeSubgoalId`.
KLAS_OFF = "6OPFRIS"
ACCOUNTS += [
    {"uid": "u-cas", "firstName": "Cas", "lastName": "Voorbeeld", "className": KLAS_OFF,
     "updatedAt": "2026-09-22T10:00:00Z", "calibration": {"difficulty": "hard"}},
    {"uid": "u-dirk", "firstName": "Dirk", "lastName": "Proef", "className": KLAS_OFF,
     "updatedAt": "2026-09-22T10:00:00Z", "calibration": {"difficulty": "hard"}},
]
OFF_AT = dt.datetime(2026, 9, 22, 9, 0, tzinfo=dt.timezone.utc)


def _sig(subgoal: str, lo: str, strength: str = "strong", signal: str = "positive") -> dict:
    return {"subgoalId": subgoal, "loId": lo, "signal": signal, "strength": strength}


def _off_subgoal_log(uid: str, **marker) -> list[dict]:
    side = _sig("sg-a", "fix_a3")  # a signal from Deel B on an earlier LO (§2.4)
    return [
        _turn("2026-09-10T09:00:00.000Z", "sg-a", "recall_a1", uid=uid, loSignals=[_sig("sg-a", "recall_a1", "moderate")]),
        _turn("2026-09-10T09:05:00.000Z", "sg-a", "recall_a1", uid=uid, loSignals=[_sig("sg-a", "recall_a1", "moderate")]),
        _turn("2026-09-15T09:00:00.000Z", "sg-b", "predict_b1", uid=uid, loSignals=[_sig("sg-b", "predict_b1", "moderate"), side]),
        _turn("2026-09-15T09:05:00.000Z", "sg-b", "predict_b1", uid=uid, loSignals=[_sig("sg-b", "predict_b1", "moderate"), side]),
        _turn(
            "2026-09-22T09:00:00.000Z", "sg-a", "recall_a1", uid=uid,
            difficulty="hard", calibrationBefore="hard", calibrationAfter="hard",
            loSignals=[_sig("sg-a", "recall_a1"), _sig("sg-a", "fix_a3"), _sig("sg-b", "predict_b1")],
            # The conductor reports the active subgoal's LOs on every turn;
            # predict_b1 made the stamp, so Deel B advanced on this turn.
            loStatusAfter=[{"loId": "predict_b1", "mean": 0.85, "evidence": 6.6, "mastered": True, "stuck": False}],
            subgoalProgressAfter=1.0,
            subgoalAdvanced=True,
            **marker,
        ),
    ]


TURNS["u-cas"] = _off_subgoal_log("u-cas", isRecheck=True, activeSubgoalId="sg-b")
TURNS["u-dirk"] = _off_subgoal_log("u-dirk", isWarmUp=True)

# What the conductor stored for Cas (CONDUCTOR_POLICY §3): decay toward the
# prior over the time since the last write, then the weight — the recheck's
# target and the active LO at `hard` (×1.4), fix_a3 from the side at `medium`.
CAS_STORED = {
    ("sg-a", "recall_a1"): {"alpha": 5.5411, "beta": 1.0, "highestPositiveDifficulty": "hard"},
    ("sg-a", "fix_a3"): {"alpha": 6.6893, "beta": 1.0},
    ("sg-b", "predict_b1"): {"alpha": 5.6447, "beta": 1.0, "highestPositiveDifficulty": "hard"},
}

# #201: a class of three made-up students whose logs carry audit records
# (an empty-objectives block, a redirect after a deleted subgoal). Each is
# a `wrong` at `medium` on its day in the raw log; none is an oefening.
# Eva: two oefeningen on write_a2 (one right, one wrong), then ten right on
# recall_a1, and four audit records — one on a lesson day, three on 09-17.
# Fien: works at `hard`, but her first record on the milestone is an
# empty-objectives block on Deel B from before it had objectives; she also
# opened the app on 09-17. Gust: on 09-15, while Eva and Fien worked, he
# only got a redirect. So 09-17 is no class day and 09-15 is one he missed.
KLAS_AUDIT = "6AUDIT"
ACCOUNTS += [
    {"uid": "u-eva", "firstName": "Eva", "lastName": "Monster", "className": KLAS_AUDIT,
     "updatedAt": "2026-09-17T11:00:00Z", "calibration": {"difficulty": "medium"}},
    {"uid": "u-fien", "firstName": "Fien", "lastName": "Staal", "className": KLAS_AUDIT,
     "updatedAt": "2026-09-17T09:00:00Z", "calibration": {"difficulty": "hard"}},
    {"uid": "u-gust", "firstName": "Gust", "lastName": "Model", "className": KLAS_AUDIT,
     "updatedAt": "2026-09-15T09:00:00Z", "calibration": {"difficulty": "medium"}},
]
_HARD = {"difficulty": "hard", "calibrationBefore": "hard", "calibrationAfter": "hard"}
TURNS["u-eva"] = [
    _turn("2026-09-10T09:00:00.000Z", "sg-a", "write_a2", uid="u-eva", loSignals=[_sig("sg-a", "write_a2", "moderate")]),
    _turn("2026-09-10T09:05:00.000Z", "sg-a", "write_a2", uid="u-eva", overallQuality="wrong",
          loSignals=[_sig("sg-a", "write_a2", "moderate", "negative")]),
    *[_turn(f"2026-09-15T09:{i:02d}:00.000Z", "sg-a", "recall_a1", uid="u-eva") for i in range(10)],
    _audit("2026-09-15T09:30:00.000Z", "sg-weg", "u-eva", "subgoalDeletedRedirect"),
    *[_audit(f"2026-09-17T{h}:00:00.000Z", "sg-leeg", "u-eva") for h in ("09", "10", "11")],
]
TURNS["u-fien"] = [
    _audit("2026-09-08T09:00:00.000Z", "sg-b", "u-fien"),
    *[_turn(f"2026-09-{d}T09:0{m}:00.000Z", "sg-a", "recall_a1", uid="u-fien", **_HARD) for d in ("10", "15") for m in (0, 5)],
    _audit("2026-09-17T09:00:00.000Z", "sg-leeg", "u-fien"),
]
TURNS["u-gust"] = [
    _turn("2026-09-10T09:00:00.000Z", "sg-a", "recall_a1", uid="u-gust"),
    _turn("2026-09-10T09:05:00.000Z", "sg-a", "recall_a1", uid="u-gust"),
    _audit("2026-09-15T09:00:00.000Z", "sg-weg", "u-gust", "subgoalDeletedRedirect"),
]

# #203: a class of two made-up students with the same two wrong answers:
# recall_a1 at `easy` (strong), then, in Deel B at `hard`, predict_b1
# (strong) with the grader naming recall_a1 as well (moderate, from the
# side). Hans's client stamps its build on every turn (#165) and computes
# as the app does since #167 and #169: a negative weighs ×1.4 at easy and
# ×0.6 at hard, and the incidental one is no evidence. Ivo's client has no
# `clientVersion`, and still computes the old way: ×0.6 at easy, ×1.4 at
# hard, and the incidental negative at medium after a week of decay.
KLAS_BUILD = "6BUILD"
ACCOUNTS += [
    {"uid": "u-hans", "firstName": "Hans", "lastName": "Nieuw", "className": KLAS_BUILD,
     "updatedAt": "2026-09-22T10:00:00Z", "calibration": {"difficulty": "hard"}},
    {"uid": "u-ivo", "firstName": "Ivo", "lastName": "Vroeger", "className": KLAS_BUILD,
     "updatedAt": "2026-09-22T10:00:00Z", "calibration": {"difficulty": "hard"}},
]


def _wrong_on_easy_and_hard(uid: str, **build) -> list[dict]:
    return [
        _turn("2026-09-15T09:00:00.000Z", "sg-a", "recall_a1", uid=uid, overallQuality="wrong",
              difficulty="easy", calibrationBefore="easy", calibrationAfter="medium",
              loSignals=[_sig("sg-a", "recall_a1", signal="negative")], **build),
        _turn("2026-09-22T09:00:00.000Z", "sg-b", "predict_b1", uid=uid, overallQuality="wrong", **_HARD,
              loSignals=[_sig("sg-b", "predict_b1", signal="negative"),
                         _sig("sg-a", "recall_a1", "moderate", "negative")], **build),
    ]


TURNS["u-hans"] = _wrong_on_easy_and_hard("u-hans", clientVersion="2.6.0+23")
TURNS["u-ivo"] = _wrong_on_easy_and_hard("u-ivo")
BUILD_STORED = {
    "u-hans": {  # β = 1 + 2.0 × 1.4; β = 1 + 2.0 × 0.6, and nothing for the incidental
        ("sg-a", "recall_a1"): {"alpha": 1.0, "beta": 3.8},
        ("sg-b", "predict_b1"): {"alpha": 1.0, "beta": 2.2},
    },
    "u-ivo": {  # β = 1 + 2.0 × 0.6, decayed 7 days, + 1.0 × 1.0; β = 1 + 2.0 × 1.4
        ("sg-a", "recall_a1"): {"alpha": 1.0, "beta": 3.1068},
        ("sg-b", "predict_b1"): {"alpha": 1.0, "beta": 3.8},
    },
}

# #202: a class of one made-up student whose grader answered `neutral` —
# the answer touched the LO but showed nothing either way. Jens gets
# recall_a1 right four times on 08-10 (stamped at medium), then, on 09-20,
# a partial answer on write_a2: the grader names write_a2 and recall_a1,
# both neutral. On 09-22, in Deel B, predict_b1 right, and a neutral from
# the side on fix_a3. The app writes every one of those neutrals: no
# weight, but the doc (at the prior if new) and its clock (§3.1).
KLAS_NEUTRAL = "6NEUTRAAL"
ACCOUNTS += [
    {"uid": "u-jens", "firstName": "Jens", "lastName": "Grijs", "className": KLAS_NEUTRAL,
     "updatedAt": "2026-09-22T10:00:00Z", "calibration": {"difficulty": "medium"}},
]
NEUTRAL_AT = dt.datetime(2026, 9, 20, 9, 0, tzinfo=dt.timezone.utc)
_NOW_BUILD = {"clientVersion": "2.6.0+23"}
TURNS["u-jens"] = [
    *[_turn(f"2026-08-10T09:0{i}:00.000Z", "sg-a", "recall_a1", uid="u-jens", **_NOW_BUILD) for i in range(4)],
    _turn("2026-09-20T09:00:00.000Z", "sg-a", "write_a2", uid="u-jens", overallQuality="partial",
          loSignals=[_sig("sg-a", "write_a2", "weak", "neutral"), _sig("sg-a", "recall_a1", "moderate", "neutral")],
          **_NOW_BUILD),
    _turn("2026-09-22T09:00:00.000Z", "sg-b", "predict_b1", uid="u-jens",
          loSignals=[_sig("sg-b", "predict_b1"), _sig("sg-a", "fix_a3", "weak", "neutral")], **_NOW_BUILD),
]
# What the app stored: recall_a1's (9, 1) of 08-10 decayed over 41 days to
# the neutral's write; write_a2 and fix_a3 at the prior; predict_b1 (3, 1).
JENS_STORED = {
    ("sg-a", "recall_a1"): {"alpha": 5.9819, "beta": 1.0, "highestPositiveDifficulty": "medium"},
    ("sg-a", "write_a2"): {"alpha": 1.0, "beta": 1.0},
    ("sg-a", "fix_a3"): {"alpha": 1.0, "beta": 1.0},
    ("sg-b", "predict_b1"): {"alpha": 3.0, "beta": 1.0, "highestPositiveDifficulty": "medium"},
}

JUSTIFICATION = "Verantwoording van je score\n\nJe kan B1 voorspellen.\n\nFeedback\n\nGa zo door."
COUNTED = ("staleLoCount", "supervisedTurns", "homeTurns")


class _CommandTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.cosmos = _fake_cosmos()
        for p in (
            mock.patch.object(evaluate, "cosmos", self.cosmos),
            mock.patch.object(evaluate, "_now", lambda: NOW),
            mock.patch.object(evaluate, "BACKUP_DIR", self.tmp / "backups"),
            mock.patch.object(evaluate, "DEFAULT_OUT", self.tmp / "out"),
        ):
            p.start()
            self.addCleanup(p.stop)

    def run_cli(self, *argv: str) -> str:
        out = io.StringIO()
        with mock.patch.object(sys, "argv", ["evaluate.py", *argv]), contextlib.redirect_stdout(out):
            evaluate.main()
        return out.getvalue()

    def draft(self, klas: str = KLAS) -> tuple[Path, Path, str]:
        stdout = self.run_cli("draft", "--klas", klas, "--out", str(self.tmp / "out"))
        md = next((self.tmp / "out").glob("*.md"))
        return md, md.with_suffix(".json"), stdout

    def student(self, sidecar: dict, uid: str) -> dict:
        return next(s for s in sidecar["students"] if s["uid"] == uid)

    def section(self, md: str, name: str) -> str:
        start = md.index(f"## {name}")
        end = md.find("\n## ", start + 1)
        return md[start:] if end == -1 else md[start:end]


class DraftTest(_CommandTest):
    def test_sidecar_carries_the_counted_reliability_signals(self):
        _, json_path, _ = self.draft()
        sidecar = json.loads(json_path.read_text(encoding="utf-8"))

        self.assertEqual(sidecar["periodStart"], MILESTONE["periodStart"])
        c = self.student(sidecar, "u-anna")["computed"]
        # recall_a1 last got evidence 45 days ago; write_a2 never did.
        self.assertEqual(c["staleLoCount"], 2)
        self.assertEqual(c["neverProbedCount"], 1)
        self.assertEqual(c["supervisedTurns"], 3)
        self.assertEqual(c["homeTurns"], 3)

    def test_concept_shows_them_before_the_go(self):
        md_path, _, _ = self.draft()
        md = md_path.read_text(encoding="utf-8")

        self.assertIn(
            "**Mee op het voorstel:** verouderd 2 leerdoel(en) (nooit bevraagd: 1) · "
            "oefeningen deze periode: 3 onder toezicht, 3 thuis.",
            md,
        )
        self.assertIn("beoordeelde oefeningen sinds 2026-09-01", md)


class ApplyTest(_CommandTest):
    def sign(self, json_path: Path, drop: tuple[str, ...] = ()) -> None:
        sidecar = json.loads(json_path.read_text(encoding="utf-8"))
        anna = self.student(sidecar, "u-anna")
        anna["justification"] = JUSTIFICATION
        for f in drop:
            anna["computed"].pop(f)
        json_path.write_text(json.dumps(sidecar, ensure_ascii=False), encoding="utf-8")

    def written(self) -> list[dict]:
        return [doc for coll, doc, _, _ in self.cosmos.upserts if coll == "grade_proposals"]

    def test_writes_the_counts_from_the_sidecar_not_zeros(self):
        _, json_path, _ = self.draft()
        self.sign(json_path)

        stdout = self.run_cli("apply", str(json_path))

        docs = self.written()
        self.assertEqual([d["id"] for d in docs], ["u-anna_ms-1"])  # Bram has no data: skipped
        doc = docs[0]
        self.assertEqual(doc["staleLoCount"], 2)
        self.assertEqual(doc["neverProbedCount"], 1)
        self.assertEqual(doc["supervisedTurns"], 3)
        self.assertEqual(doc["homeTurns"], 3)
        self.assertIn("geschreven 1, conflicten 0, overgeslagen 1", stdout)
        self.assertNotIn("blijven weg", stdout)

    def test_an_older_sidecar_leaves_the_fields_out_instead_of_zero(self):
        _, json_path, _ = self.draft()
        self.sign(json_path, drop=COUNTED)

        stdout = self.run_cli("apply", str(json_path))

        doc = self.written()[0]
        for f in COUNTED:
            self.assertNotIn(f, doc)
        self.assertEqual(doc["neverProbedCount"], 1)
        self.assertIn("die velden blijven weg in plaats van 0", stdout)
        self.assertIn("Anna Peeters", stdout)


class OffSubgoalDraftTest(_CommandTest):
    """#195: a warm-up or recheck asks about an LO of another subgoal; the
    rest of its signals count against the subgoal the student was on."""

    COUNTS = ("coreCounted", "extensionMastered", "masteredTotal", "hardCount", "neverProbedCount", "proposal")

    def test_a_recheck_counts_the_active_subgoal_and_not_the_old_one(self):
        md_path, json_path, _ = self.draft(KLAS_OFF)
        cas = self.student(json.loads(json_path.read_text(encoding="utf-8")), "u-cas")["computed"]

        # recall_a1 (the question) and predict_b1 (the active LO) make the
        # stamp at hard; fix_a3, named from the side, does not.
        self.assertEqual(
            {f: cas[f] for f in self.COUNTS},
            {"coreCounted": 2, "extensionMastered": 0, "masteredTotal": 2, "hardCount": 2,
             "neverProbedCount": 1, "proposal": 70},
        )
        md = md_path.read_text(encoding="utf-8")
        self.assertIn("| Cas Voorbeeld | 2/2 | 0/2 | 2/2 | **70** |", md)
        mine = self.section(md, "Cas Voorbeeld")
        self.assertIn("`fix_a3` (uitbreiding) — μ 0.87, 0 vragen", mine)
        self.assertIn("**Onderdelen afgerond:** Deel B op 09-22 (1 van 2)", mine)
        self.assertNotIn("door de app weggegooid", mine)

    def test_an_older_warm_up_reads_the_active_subgoal_from_its_status(self):
        md_path, json_path, _ = self.draft(KLAS_OFF)
        sidecar = json.loads(json_path.read_text(encoding="utf-8"))
        dirk = self.student(sidecar, "u-dirk")["computed"]

        self.assertEqual(dirk["proposal"], 70)
        self.assertEqual(dirk, self.student(sidecar, "u-cas")["computed"])
        dirks = self.section(md_path.read_text(encoding="utf-8"), "Dirk Proef")
        self.assertIn("**Onderdelen afgerond:** Deel B op 09-22 (1 van 2)", dirks)


class AuditRecordDraftTest(_CommandTest):
    """#201: an audit record has no question. The app counts it nowhere
    (`listTurnsBetween`), and neither does any part of the concept."""

    def setUp(self):
        super().setUp()
        md_path, json_path, self.stdout = self.draft(KLAS_AUDIT)
        self.md = md_path.read_text(encoding="utf-8")
        self.sidecar = json.loads(json_path.read_text(encoding="utf-8"))

    def test_the_timeline_and_profile_count_only_oefeningen(self):
        eva = self.section(self.md, "Eva Monster")

        self.assertIn("- 2026-09-10: 2 · 50% · medium · 0 · sg-a:2\n", eva)
        self.assertIn("- 2026-09-15: 10 · 100% · medium · 0 · sg-a:10\n", eva)
        self.assertNotIn("2026-09-17", eva)  # only audit records that day
        self.assertIn("**Profiel:** 12 oefeningen · denktijd 60 s · juist 92% / deels 0% / fout 8%", eva)
        self.assertIn("- per moeilijkheid: gewoon 92% (12)\n", eva)
        self.assertIn("- per vraagtype: meerkeuze 92% (12)\n", eva)

    def test_recent_work_for_the_fossils_is_oefeningen(self):
        # 11 of the last 12 oefeningen right: write_a2, two weeks without a
        # question, is a fossil. Four audit "wrongs" in the window hid it.
        eva = self.section(self.md, "Eva Monster")

        self.assertIn("**Fossielen**", eva)
        self.assertIn("Je kan A2 schrijven. `write_a2` (uitbreiding) — μ 0.50, 14 dagen oud", eva)
        row = next(line for line in self.md.splitlines() if line.startswith("| Eva Monster |"))
        self.assertIn("| 1 fossiel,", row)

    def test_a_day_with_only_audit_records_is_no_class_day_and_no_presence(self):
        # 09-17 (Eva and Fien only opened the app) is no class day; on 09-15
        # the class worked and Gust only got a redirect.
        gust_row = next(line for line in self.stdout.splitlines() if line.lstrip().startswith("Gust Model"))
        self.assertTrue(gust_row.endswith("afwezig: 2026-09-15"), gust_row)
        self.assertIn("- **Afwezig** terwijl de klas werkte: 2026-09-15\n", self.section(self.md, "Gust Model"))
        self.assertNotIn("09-17", self.stdout)
        for name in ("Eva Monster", "Fien Staal"):
            self.assertNotIn("**Afwezig**", self.section(self.md, name))

    def test_the_level_path_starts_at_the_first_oefening(self):
        fien = self.section(self.md, "Fien Staal")

        self.assertIn("- **Niveau binnen dit onderdeel:** begon met moeilijke oefeningen, eindigde met moeilijke\n", fien)

    def test_the_tally_on_the_proposal_is_unchanged(self):
        # `rules.reliability` left them out already (#171); the same test now.
        counts = {
            uid: {f: self.student(self.sidecar, uid)["computed"][f] for f in ("supervisedTurns", "homeTurns")}
            for uid in ("u-eva", "u-fien", "u-gust")
        }
        self.assertEqual(
            counts,
            {
                "u-eva": {"supervisedTurns": 0, "homeTurns": 12},
                "u-fien": {"supervisedTurns": 0, "homeTurns": 4},
                "u-gust": {"supervisedTurns": 0, "homeTurns": 2},
            },
        )


class NeutralSignalDraftTest(_CommandTest):
    """#202: the app writes a neutral signal — the doc and its clock — so
    the counts on the proposal read it as the app does."""

    def setUp(self):
        super().setUp()
        md_path, json_path, _ = self.draft(KLAS_NEUTRAL)
        self.md = md_path.read_text(encoding="utf-8")
        self.jens = self.student(json.loads(json_path.read_text(encoding="utf-8")), "u-jens")["computed"]

    def test_the_counts_on_the_proposal_are_the_apps(self):
        # recall_a1 was written on 09-20, four days ago; write_a2 and fix_a3
        # have a doc. `eval3` had 3 stale and 2 never probed.
        self.assertEqual(
            {f: self.jens[f] for f in ("staleLoCount", "neverProbedCount", "supervisedTurns", "homeTurns")},
            {"staleLoCount": 0, "neverProbedCount": 0, "supervisedTurns": 0, "homeTurns": 2},
        )
        self.assertIn(
            "**Mee op het voorstel:** verouderd 0 leerdoel(en) (nooit bevraagd: 0) · "
            "oefeningen deze periode: 0 onder toezicht, 2 thuis.",
            self.section(self.md, "Jens Grijs"),
        )

    def test_the_number_does_not_move(self):
        # No weight: recall_a1 the one core stamp, nothing else.
        self.assertEqual((self.jens["coreCounted"], self.jens["masteredTotal"], self.jens["proposal"]), (1, 1, 25))

    def test_a_question_answered_neutral_was_asked(self):
        jens = self.section(self.md, "Jens Grijs")

        self.assertIn("Je kan A2 schrijven. `write_a2` (uitbreiding) — μ 0.50, 1 vragen — te weinig vragen om aan te tonen", jens)
        self.assertIn("Je kan A3 verbeteren. `fix_a3` (uitbreiding) — μ 0.50, 0 vragen — te weinig vragen om aan te tonen", jens)
        self.assertNotIn("— nooit bevraagd", jens)
        self.assertIn(f"regels `{rules.RULES_VERSION}`", self.md)


class ValidateTest(_CommandTest):
    def row(self, stdout: str, name: str) -> list[str]:
        """docs · compared · |d mean| > 0.01 · hoogste niveau anders · laatste build"""
        line = next(line for line in stdout.splitlines() if line.startswith(name))
        return line.split()[-5:]

    def test_the_replay_reproduces_what_the_app_stored_after_a_recheck(self):
        self.cosmos.beliefs = lambda uid: CAS_STORED if uid == "u-cas" else {}

        stdout = self.run_cli("validate", "--klas", KLAS_OFF)

        self.assertEqual(self.row(stdout, "Cas Voorbeeld"), ["3", "3", "0", "0", "oud"])

    def test_negatives_as_the_current_app_stores_them_match(self):
        # #203: a wrong answer at easy and at hard, and an incidental one,
        # as the app has stored them since #167 and #169. The replay with
        # the arithmetic from before read both docs as an old build.
        self.cosmos.beliefs = lambda uid: BUILD_STORED.get(uid, {})

        stdout = self.run_cli("validate", "--klas", KLAS_BUILD)

        self.assertEqual(self.row(stdout, "Hans Nieuw"), ["2", "2", "0", "0", "2.6.0+23"])

    def test_an_old_build_still_shows(self):
        # The same oefeningen from a client without `clientVersion`, which
        # still computes the old way: both docs deviate, and the build says why.
        self.cosmos.beliefs = lambda uid: BUILD_STORED.get(uid, {})

        stdout = self.run_cli("validate", "--klas", KLAS_BUILD)

        self.assertEqual(self.row(stdout, "Ivo Vroeger"), ["2", "2", "2", "0", "oud"])
        self.assertIn(f"sinds #167 en #169 ({rules.RULES_VERSION})", stdout)
        self.assertIn("laatste build 'oud'", stdout)
        self.assertNotIn("transfer-krediet", stdout)  # replayed since eval2

    def test_docs_the_app_wrote_on_a_neutral_signal_match(self):
        # #202: `eval3` compared 2 of the 4 docs, and read recall_a1, whose
        # last write was a neutral 41 days on, as a deviation.
        self.cosmos.beliefs = lambda uid: JENS_STORED if uid == "u-jens" else {}

        stdout = self.run_cli("validate", "--klas", KLAS_NEUTRAL)

        self.assertEqual(self.row(stdout, "Jens Grijs"), ["4", "4", "0", "0", "2.6.0+23"])

    def test_the_old_arithmetic_is_what_the_old_build_stored(self):
        # The fixture's old-build docs are that arithmetic, not a guess.
        old = rules.replay(TURNS["u-ivo"], GOALS, asymmetric=False, drop_incidental_negatives=False)
        for key, b in BUILD_STORED["u-ivo"].items():
            self.assertAlmostEqual(old[key].beta, b["beta"], places=4)
        now = rules.replay(TURNS["u-hans"], GOALS)
        for key, b in BUILD_STORED["u-hans"].items():
            self.assertAlmostEqual(now[key].beta, b["beta"], places=9)


class TurnScopeTest(unittest.TestCase):
    """The conductor's reading of a warm-up or recheck, at its edges."""

    def test_the_probe_clock_is_what_the_app_stores_as_lastProbedAt(self):
        st = rules.replay(TURNS["u-cas"], GOALS)

        self.assertEqual(st[("sg-a", "recall_a1")].last_direct_at, OFF_AT)
        self.assertEqual(st[("sg-b", "predict_b1")].last_direct_at, OFF_AT)
        fix = st[("sg-a", "fix_a3")]
        self.assertEqual(fix.last_at, OFF_AT)  # its evidence moved,
        self.assertIsNone(fix.last_direct_at)  # but nobody asked it
        self.assertEqual((fix.n_direct, fix.ratchet), (0, None))

    def test_an_incidental_negative_on_the_old_subgoal_is_not_evidence(self):
        t = _turn("2026-09-22T09:00:00.000Z", "sg-a", "recall_a1", isRecheck=True, activeSubgoalId="sg-b",
                  difficulty="hard", loSignals=[_sig("sg-a", "write_a2", signal="negative")])

        self.assertNotIn(("sg-a", "write_a2"), rules.replay([t], GOALS))  # #167
        # Counted anyway, it lands at `medium` and not as a question.
        s = rules.replay([t], GOALS, drop_incidental_negatives=False)[("sg-a", "write_a2")]
        self.assertEqual((s.beta, s.n_direct), (3.0, 0))

    def test_without_a_status_that_names_it_the_old_subgoal_stands_in(self):
        warm = dict(TURNS["u-dirk"][-1])
        self.assertEqual(rules.turn_scope(warm, GOALS).active, "sg-b")
        for status in ([], [{"loId": "an_lo_since_removed"}]):
            warm["loStatusAfter"] = status
            self.assertEqual(rules.turn_scope(warm, GOALS).active, "sg-a")
        # An ordinary turn is about the active subgoal, whatever it reports.
        plain = _turn("2026-09-22T09:00:00.000Z", "sg-a", "recall_a1", loStatusAfter=[{"loId": "predict_b1"}])
        self.assertEqual(rules.turn_scope(plain, GOALS).active, "sg-a")

    def test_a_warm_up_target_in_a_later_subgoal_is_still_a_direct_probe(self):
        # Back in Deel A, a review of Deel B: §1.5 takes any other subgoal of
        # the root, and the conductor checks the target before the order.
        t = _turn("2026-09-22T09:00:00.000Z", "sg-b", "predict_b1", isWarmUp=True, activeSubgoalId="sg-a",
                  difficulty="hard", calibrationBefore="hard")
        s = rules.replay([t], GOALS)[("sg-b", "predict_b1")]
        self.assertEqual((s.n_direct, s.ratchet), (1, "hard"))


class NeutralSignalTest(unittest.TestCase):
    """#202: a neutral signal down the conductor's write path, at its edges."""

    def test_it_moves_the_clocks_and_not_the_belief(self):
        st = rules.replay(TURNS["u-jens"], GOALS)

        recall = st[("sg-a", "recall_a1")]
        self.assertEqual((recall.last_at, recall.last_direct_at), (NEUTRAL_AT, NEUTRAL_AT))
        before = rules.replay(TURNS["u-jens"][:4], GOALS)[("sg-a", "recall_a1")]
        a, b = rules._decay(before.alpha, before.beta, before.last_at, NEUTRAL_AT)
        self.assertEqual((recall.alpha, recall.beta), (a, b))  # decayed to its moment, nothing added
        self.assertEqual((recall.n_direct, recall.ratchet), (5, "medium"))
        self.assertEqual(recall.direct_signals[-1], (NEUTRAL_AT, "neutral", "moderate", "medium"))
        # A new LO starts at the prior: asked, with nothing to show for it.
        write = st[("sg-a", "write_a2")]
        self.assertEqual((write.alpha, write.beta, write.last_at, write.last_direct_at), (1.0, 1.0, NEUTRAL_AT, NEUTRAL_AT))
        self.assertEqual((write.n_direct, write.ratchet, write.demonstrated), (1, None, False))
        # From the side: the doc and its clock, but nobody asked it.
        fix = st[("sg-a", "fix_a3")]
        self.assertEqual((fix.alpha, fix.beta, fix.last_at), (1.0, 1.0, dt.datetime(2026, 9, 22, 9, 0, tzinfo=dt.timezone.utc)))
        self.assertEqual((fix.last_direct_at, fix.n_direct), (None, 0))

    def test_the_next_evidence_lands_as_if_it_were_not_there(self):
        # Decay composes: the belief a later answer lands on is the same
        # with or without the neutral write in between.
        later = _turn("2026-10-01T09:00:00.000Z", "sg-a", "recall_a1", uid="u-jens")
        with_neutral = rules.replay([*TURNS["u-jens"][:5], later], GOALS)[("sg-a", "recall_a1")]
        without = rules.replay([*TURNS["u-jens"][:4], later], GOALS)[("sg-a", "recall_a1")]
        self.assertAlmostEqual(with_neutral.alpha, without.alpha, places=12)
        self.assertAlmostEqual(with_neutral.beta, without.beta, places=12)

    def test_a_follow_up_or_a_forward_neutral_is_no_probe(self):
        follow = _turn("2026-09-21T09:00:00.000Z", "sg-a", "write_a2", uid="u-jens", isFollowUp=True,
                       loSignals=[_sig("sg-a", "write_a2", "weak", "neutral"), _sig("sg-b", "predict_b1", "weak", "neutral")])
        st = rules.replay([*TURNS["u-jens"][:5], follow], GOALS)

        write = st[("sg-a", "write_a2")]
        self.assertEqual(write.last_at, dt.datetime(2026, 9, 21, 9, 0, tzinfo=dt.timezone.utc))
        self.assertEqual((write.last_direct_at, write.n_direct), (NEUTRAL_AT, 1))  # §6.2: not a probe
        self.assertNotIn(("sg-b", "predict_b1"), st)  # a later subgoal: dropped, no doc

    def test_the_review_flag_clears_on_a_neutral_review(self):
        # recall_a1 is stamped; in Deel B the grader blames it twice from the
        # side, then names it neutral from the side: the oldest flag stands.
        # write_a2, never asked, is blamed too. A warm-up review answered
        # neutral is the direct measurement.
        side = [
            _turn(f"2026-09-2{d}T09:00:00.000Z", "sg-b", "predict_b1", uid="u-jens",
                  loSignals=[_sig("sg-b", "predict_b1"), _sig("sg-a", "recall_a1", "moderate", signal),
                             _sig("sg-a", "write_a2", "moderate", "negative")])
            for d, signal in ((1, "negative"), (2, "negative"), (3, "neutral"))
        ]
        flagged_at = dt.datetime(2026, 9, 21, 9, 0, tzinfo=dt.timezone.utc)
        st = rules.replay([*TURNS["u-jens"][:4], *side], GOALS)
        self.assertEqual(st[("sg-a", "recall_a1")].regressed_at, flagged_at)
        self.assertNotIn(("sg-a", "write_a2"), st)  # never demonstrated: no flag, and no doc

        review = _turn("2026-09-24T09:00:00.000Z", "sg-a", "recall_a1", uid="u-jens", isWarmUp=True,
                       activeSubgoalId="sg-b", overallQuality="partial",
                       loSignals=[_sig("sg-a", "recall_a1", "weak", "neutral")])
        recall = rules.replay([*TURNS["u-jens"][:4], *side, review], GOALS)[("sg-a", "recall_a1")]
        self.assertIsNone(recall.regressed_at)
        self.assertEqual(recall.last_direct_at, dt.datetime(2026, 9, 24, 9, 0, tzinfo=dt.timezone.utc))


class ReliabilityTest(unittest.TestCase):
    """The window and the threshold at their edges, as the app draws them."""

    LOS = [rules.MilestoneLo("sg", "lo_fresh", True), rules.MilestoneLo("sg", "lo_old", True)]
    START = dt.datetime(2026, 9, 1, tzinfo=dt.timezone.utc)

    def state(self, age: dt.timedelta) -> dict:
        return {
            ("sg", "lo_fresh"): rules.LoState(last_at=NOW - dt.timedelta(days=30)),
            ("sg", "lo_old"): rules.LoState(last_at=NOW - age),
        }

    def test_stale_is_strictly_more_than_thirty_days(self):
        exactly = rules.reliability(self.LOS, self.state(dt.timedelta(days=30)), [], self.START, NOW)
        past = rules.reliability(self.LOS, self.state(dt.timedelta(days=30, seconds=1)), [], self.START, NOW)
        self.assertEqual(exactly.stale_lo_count, 0)
        self.assertEqual(past.stale_lo_count, 1)

    def test_never_probed_is_stale(self):
        r = rules.reliability(self.LOS, {("sg", "lo_fresh"): rules.LoState(last_at=NOW)}, [], self.START, NOW)
        self.assertEqual(r.stale_lo_count, 1)

    def test_the_tally_counts_graded_oefeningen_inside_the_window(self):
        turns = [
            {"turnAt": "2026-08-31T23:59:59Z", "questionType": "mcQuestion", "provenance": "supervised"},
            {"turnAt": "2026-09-01T00:00:00Z", "questionType": "mcQuestion", "provenance": "supervised"},
            {"turnAt": "2026-09-10T00:00:00Z", "questionType": "writeCodeQuestion"},
            {"turnAt": "2026-09-11T00:00:00Z", "questionType": "", "provenance": "supervised"},
            {"turnAt": "2026-09-11T00:00:00Z", "provenance": "home"},
            {"turnAt": "2026-09-24T12:00:00Z", "questionType": "mcQuestion", "provenance": "home"},
            {"turnAt": "2026-09-24T12:00:01Z", "questionType": "mcQuestion", "provenance": "home"},
        ]
        r = rules.reliability([], {}, turns, self.START, NOW)
        self.assertEqual((r.supervised_turns, r.home_turns), (1, 2))

        everything = rules.reliability([], {}, turns, None, NOW)
        self.assertEqual((everything.supervised_turns, everything.home_turns), (2, 2))


if __name__ == "__main__":
    unittest.main()
