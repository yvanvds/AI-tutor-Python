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
        _turn("2026-09-22T09:00:00.000Z", "sg-b", "predict_b1", questionType="", loSignals=[]),
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

    def section(self, md: str, name: str) -> str:
        start = md.index(f"## {name}")
        end = md.find("\n## ", start + 1)
        return md[start:] if end == -1 else md[start:end]

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


class ValidateTest(_CommandTest):
    def test_the_replay_reproduces_what_the_app_stored_after_a_recheck(self):
        self.cosmos.beliefs = lambda uid: CAS_STORED if uid == "u-cas" else {}

        stdout = self.run_cli("validate", "--klas", KLAS_OFF)

        row = next(line for line in stdout.splitlines() if line.startswith("Cas Voorbeeld"))
        # docs · compared · |d mean| > 0.01 · hoogste niveau anders
        self.assertEqual(row.split()[-4:], ["3", "3", "0", "0"])


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
