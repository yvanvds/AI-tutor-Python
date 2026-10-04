"""Tests for the class podium backfill (#221): who finished a subgoal first,
how the places are handed out per class, what the dry run shows, and what
`--apply` backs up and creates. Standard library only:

    python -m unittest discover -s tooling/badges/tests

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

import podium_backfill as pb  # noqa: E402


def _advance(uid: str, at: str, subgoal: str = "s1", *, active: str | None = None, rid: str | None = None, advanced: bool = True) -> dict:
    t = {
        "id": rid or f"{at}_{uid}",
        "uid": uid,
        "turnAt": at,
        "subgoalId": subgoal,
        "subgoalAdvanced": advanced,
    }
    if active is not None:
        t["activeSubgoalId"] = active
    return t


def _account(uid: str, klas: str = "6TEST", first: str = "Voornaam", last: str = "Achternaam") -> dict:
    return {"id": uid, "uid": uid, "className": klas, "firstName": first, "lastName": last}


def _place(klas: str, subgoal: str, place: int, uid: str) -> dict:
    return pb.Place(klas, subgoal, place, uid, "2026-09-01T10:00:00.000Z").doc()


class _Exists(Exception):
    pass


def _fake_cosmos(accounts, turns, podium, taken=frozenset(), log=None):
    m = types.ModuleType("cosmos")
    m.Exists = _Exists
    m.creates = []
    log = log if log is not None else []
    config = [{"id": "global", "type": "config"}, *podium]

    def query(coll, sql, params=None, pk=None, cross=True):
        if coll == "config":
            return [d for d in config if pk is None or d.get("type") == pk]
        return {"accounts": accounts, "turn_history": turns}[coll]

    def create(coll, doc, pk):
        if doc["id"] in taken:
            raise _Exists(doc["id"])
        log.append(("create", doc["id"]))
        m.creates.append((coll, doc, pk))
        return doc

    m.query, m.create = query, create
    return m


class RulesTest(unittest.TestCase):
    def test_the_doc_id_is_the_apps(self):
        # The same examples as test/core/cosmos_doc_id_podium_test.dart.
        self.assertEqual(pb.doc_id("6EWI", "s1", 1), "podium_6EWI_s1_1")
        self.assertEqual(pb.doc_id(" 6 EWI ", "a/b?c#d\\e", 3), "podium_6-EWI_a-b-c-d-e_3")

    def test_three_places_like_the_app(self):
        dart = (pb.ROOT / "lib/services/badges/class_podium.dart").read_text(encoding="utf-8")
        m = re.search(r"const int kPodiumPlaces = (\d+);", dart)
        self.assertIsNotNone(m)
        self.assertEqual(int(m.group(1)), pb.PLACES)

    def test_the_first_advance_counts_and_finishing_again_does_not(self):
        turns = [
            _advance("u", "2026-09-10T10:00:00.000Z"),
            _advance("u", "2026-09-02T10:00:00.000Z"),
            _advance("u", "2026-09-20T10:00:00.000Z"),  # worked through again
            _advance("u", "2026-09-01T10:00:00.000Z", advanced=False),
            _advance("u", "2026-09-05T10:00:00Z", subgoal="s2"),
        ]
        self.assertEqual(
            pb.first_advances(turns),
            {
                ("u", "s1"): ("2026-09-02T10:00:00.000Z", "2026-09-02T10:00:00.000Z_u"),
                ("u", "s2"): ("2026-09-05T10:00:00Z", "2026-09-05T10:00:00Z_u"),
            },
        )

    def test_the_subgoal_is_the_one_the_student_was_on(self):
        turns = [_advance("u", "2026-09-02T10:00:00.000Z", subgoal="old", active="s1")]
        self.assertEqual(set(pb.first_advances(turns)), {("u", "s1")})

    def test_the_first_three_per_class_and_subgoal_even_in_a_small_class(self):
        accounts = [_account(f"a{i}", "6EWI") for i in range(6)] + [
            _account("b0", "6WEWI"),
            _account("loose", ""),
        ]
        turns = [_advance(f"a{i}", f"2026-09-0{9 - i}T10:00:00.000Z") for i in range(6)]
        turns += [
            _advance("b0", "2026-09-30T10:00:00.000Z"),
            _advance("loose", "2026-08-01T10:00:00.000Z"),  # no class: no podium
        ]
        planned, already = pb.plan(accounts, turns, [])
        self.assertEqual(already, 0)
        self.assertEqual(
            [(p.klas, p.place, p.uid) for p in planned],
            [("6EWI", 1, "a5"), ("6EWI", 2, "a4"), ("6EWI", 3, "a3"), ("6WEWI", 1, "b0")],
        )
        self.assertEqual(planned[0].doc(), {
            "id": "podium_6EWI_s1_1",
            "type": "podium",
            "className": "6EWI",
            "subgoalId": "s1",
            "place": 1,
            "uid": "a5",
            "awardedAt": "2026-09-04T10:00:00.000Z",
        })

    def test_places_already_taken_stay_and_their_holders_get_no_second(self):
        accounts = [_account(u, "6EWI") for u in ("first", "second", "third", "fourth")]
        turns = [
            _advance("first", "2026-09-01T10:00:00.000Z"),
            _advance("second", "2026-09-02T10:00:00.000Z"),
            _advance("third", "2026-09-03T10:00:00.000Z"),
            _advance("fourth", "2026-09-04T10:00:00.000Z"),
        ]
        # The app gave "third" gold before the backfill ran.
        existing = [_place("6EWI", "s1", 1, "third")]
        planned, already = pb.plan(accounts, turns, existing)
        self.assertEqual(already, 1)
        self.assertEqual([(p.place, p.uid) for p in planned], [(2, "first"), (3, "second")])

    def test_a_full_podium_hands_out_nothing(self):
        accounts = [_account(u, "6EWI") for u in ("a", "b", "c", "d")]
        turns = [_advance(u, f"2026-09-0{i + 1}T10:00:00.000Z") for i, u in enumerate("abcd")]
        existing = [_place("6EWI", "s1", p, u) for p, u in ((1, "a"), (2, "b"), (3, "c"))]
        self.assertEqual(pb.plan(accounts, turns, existing), ([], 3))


class RunTest(unittest.TestCase):
    ACCOUNTS = [
        _account("u1", "6EWI", "Ada", "Lovelace"),
        _account("u2", "6EWI", "Alan", "Turing"),
        _account("u3", "6WEWI", "Grace", "Hopper"),
        _account("teacher", "", "Juf", "Leraar"),
    ]
    TURNS = [
        _advance("u1", "2026-09-01T10:00:00.000Z"),
        _advance("u2", "2026-09-02T10:00:00.000Z"),
        _advance("u2", "2026-09-03T10:00:00.000Z", subgoal="s2"),
        _advance("u3", "2026-09-04T10:00:00.000Z"),
        _advance("teacher", "2026-08-01T10:00:00.000Z"),
    ]

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def run_backfill(self, *argv, podium=(), taken=frozenset(), log=None):
        fake = _fake_cosmos(self.ACCOUNTS, self.TURNS, list(podium), taken, log)
        out = io.StringIO()
        with mock.patch.object(pb, "_cosmos", return_value=fake), contextlib.redirect_stdout(out):
            pb.main(list(argv))
        return fake, out.getvalue()

    def test_the_dry_run_writes_nothing_and_shows_counts_without_names(self):
        fake, out = self.run_backfill("--backup-dir", str(self.tmp))
        self.assertEqual(fake.creates, [])
        self.assertEqual(list(self.tmp.iterdir()), [], "no backup on a dry run")
        self.assertIn("Droge run", out)
        self.assertIn("6EWI: 2 subdoelen, 2 goud, 1 zilver, 0 brons, 2 leerlingen met een medaille", out)
        self.assertIn("6WEWI: 1 subdoel, 1 goud, 0 zilver, 0 brons, 1 leerling met een medaille", out)
        self.assertIn("te maken: 4 plaatsen voor 3 leerlingen; al aanwezig: 0", out)
        for a in self.ACCOUNTS:
            for field in ("id", "firstName", "lastName"):
                self.assertNotIn(a[field], out, field)

    def test_apply_backs_up_first_then_only_creates(self):
        tmp = self.tmp
        backups_at_write = []

        class _Log(list):
            """Notes, at every write, how many backups are on disk."""

            def append(self, entry):
                backups_at_write.append(len(list(tmp.glob("backup_config_*.json"))))
                super().append(entry)

        held = _place("6WEWI", "s1", 1, "someone-else")
        fake, out = self.run_backfill(
            "--apply",
            "--backup-dir",
            str(tmp),
            podium=[held],
            taken={"podium_6EWI_s2_1"},
            log=_Log(),
        )
        self.assertTrue(backups_at_write)
        self.assertEqual(set(backups_at_write), {1}, "the backup comes before any write")
        backup = json.loads(next(tmp.glob("backup_config_*.json")).read_text(encoding="utf-8"))
        self.assertEqual({d["id"] for d in backup["config"]}, {"global", held["id"]})

        created = {doc["id"]: (coll, doc, pk) for coll, doc, pk in fake.creates}
        self.assertEqual(
            set(created),
            {"podium_6EWI_s1_1", "podium_6EWI_s1_2", "podium_6WEWI_s1_2"},
        )
        self.assertTrue(all(coll == "config" and pk == "podium" for coll, _, pk in created.values()))
        self.assertEqual(created["podium_6EWI_s1_1"][1]["uid"], "u1")
        self.assertEqual(created["podium_6WEWI_s1_2"][1]["uid"], "u3")
        # Claimed by an app between the read and the write: it stays theirs.
        self.assertIn("gemaakt 3, intussen bezet 1", out)

    def test_apply_refuses_a_backup_inside_the_repo(self):
        with self.assertRaises(SystemExit):
            self.run_backfill("--apply", "--backup-dir", str(pb.ROOT / "tmp-backup"))
        self.assertFalse((pb.ROOT / "tmp-backup").exists())


if __name__ == "__main__":
    unittest.main()
