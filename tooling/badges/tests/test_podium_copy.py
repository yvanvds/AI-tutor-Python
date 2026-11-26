"""Tests for copying the class podium from `config` to its own container
(#338): what the dry run shows, that `--apply` backs up first and copies the
places as they are, that a second `--apply` copies nothing twice, that a
place already in `podium` stays as it is, and that a place another student
holds in both is reported, never overwritten. Standard library only:

    python -m unittest discover -s tooling/badges/tests

No test touches the live account: a fake `cosmos` module takes the place of
`tooling/evaluation/cosmos.py`, which would read `.env` on import. The data
is made up.
"""

from __future__ import annotations

import contextlib
import copy
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

import podium_backfill as pb  # noqa: E402
import podium_copy as pc  # noqa: E402


class _Exists(Exception):
    pass


class _NotFound(Exception):
    code = 404


def _place(klas: str, subgoal: str, place: int, uid: str, **extra) -> dict:
    return {**pb.Place(klas, subgoal, place, uid, "2026-09-01T10:00:00.000Z").doc(), **extra}


class _FakeCosmos:
    """`config` and `podium` in memory. A create in `podium` lands there, so
    a second run sees what the first one copied. [claimed_meanwhile] are
    docs that land in `podium` between the read and the write."""

    def __init__(self, config, podium, *, podium_exists=True, claimed_meanwhile=()):
        self.config = [{"id": "global", "type": "config"}, {"id": "classes", "type": "config"}, *config]
        self.podium = list(podium)
        self.podium_exists = podium_exists
        self.claimed_meanwhile = {d["id"]: d for d in claimed_meanwhile}
        self.creates: list[tuple[str, dict, str]] = []
        self.log: list[str] = []
        self.module = types.ModuleType("cosmos")
        self.module.Exists = _Exists
        self.module.query = self.query
        self.module.create = self.create
        self.module.read = self.read

    def query(self, coll, sql, params=None, pk=None, cross=True):
        if coll == "config":
            return copy.deepcopy([d for d in self.config if pk is None or d.get("type") == pk])
        if coll == "podium":
            if not self.podium_exists:
                raise _NotFound("podium")
            return copy.deepcopy([d for d in self.podium if pk is None or d.get("type") == pk])
        raise AssertionError(f"reads {coll}")

    def read(self, coll, doc_id, pk):
        assert coll == "podium" and pk == "podium"
        return next((copy.deepcopy(d) for d in self.podium if d["id"] == doc_id), None)

    def create(self, coll, doc, pk):
        if coll != "podium":
            raise AssertionError(f"writes {coll}")
        late = self.claimed_meanwhile.pop(doc["id"], None)
        if late is not None:
            self.podium.append(late)
        if any(d["id"] == doc["id"] for d in self.podium):
            raise _Exists(doc["id"])
        self.log.append(doc["id"])
        self.creates.append((coll, doc, pk))
        self.podium.append(copy.deepcopy(doc))
        return doc


class RulesTest(unittest.TestCase):
    def test_the_containers(self):
        self.assertEqual((pc.SOURCE, pc.TARGET, pc.PARTITION), ("config", "podium", "podium"))
        self.assertEqual(pb.CONTAINER, "podium", "the backfill writes in the new container too")

    def test_a_free_place_is_copied_as_it_is_without_cosmos_fields(self):
        doc = _place("6EWI", "s1", 1, "a", _rid="x", _etag='"1"', _ts=1)
        planned = pc.plan([doc], [])
        self.assertEqual(planned.copy, [_place("6EWI", "s1", 1, "a")])

    def test_only_podium_docs_are_copied(self):
        planned = pc.plan([{"id": "global", "type": "config"}, {"id": "podium_x", "type": "podium"}], [])
        self.assertEqual(planned.copy, [])

    def test_a_place_in_podium_for_the_same_student_stays(self):
        planned = pc.plan([_place("6EWI", "s1", 1, "a")], [_place("6EWI", "s1", 1, "a")])
        self.assertEqual((planned.copy, planned.already, planned.taken), ([], 1, []))

    def test_a_place_another_student_holds_in_both_is_reported_not_copied(self):
        planned = pc.plan([_place("6EWI", "s1", 1, "a")], [_place("6EWI", "s1", 1, "b")])
        self.assertEqual((planned.copy, planned.taken), ([], ["podium_6EWI_s1_1"]))

    def test_no_second_place_for_one_subgoal(self):
        # "a" claimed silver in `podium` with a newer build, gold in `config`
        # with an older one, on another laptop.
        planned = pc.plan(
            [_place("6EWI", "s1", 1, "a"), _place("6EWI", "s2", 1, "a")],
            [_place("6EWI", "s1", 2, "a")],
        )
        self.assertEqual([d["id"] for d in planned.copy], ["podium_6EWI_s2_1"])
        self.assertEqual(planned.second, ["podium_6EWI_s1_1"])


class RunTest(unittest.TestCase):
    CONFIG = [
        _place("6EWI", "s1", 1, "u1", _etag='"e1"'),
        _place("6EWI", "s1", 2, "u2"),
        _place("6WEWI", "s1", 1, "u3"),
        _place("6WEWI", "s2", 1, "u4"),
    ]

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def run_copy(self, fake: _FakeCosmos, *argv) -> str:
        out = io.StringIO()
        with mock.patch.object(pc, "_cosmos", return_value=fake.module), contextlib.redirect_stdout(out):
            pc.main([*argv, "--backup-dir", str(self.tmp)])
        return out.getvalue()

    def test_the_dry_run_shows_what_is_copied_and_writes_nothing(self):
        # "u3" got gold on 6WEWI/s1 with a newer build as well: the same.
        # Someone else got gold on 6WEWI/s2 there: held by another student.
        podium = [_place("6WEWI", "s1", 1, "u3"), _place("6WEWI", "s2", 1, "u9")]
        fake = _FakeCosmos(self.CONFIG, podium)
        out = self.run_copy(fake)
        self.assertEqual(fake.creates, [])
        self.assertEqual(list(self.tmp.iterdir()), [], "no backup on a dry run")
        self.assertIn("plaatsen in config: 4; in podium: 2", out)
        self.assertIn("te kopiëren: 2", out)
        self.assertIn("al in podium voor dezelfde leerling: 1", out)
        self.assertIn("in beide bezet door een andere leerling, niet gekopieerd: 1\n  podium_6WEWI_s2_1", out)
        self.assertIn("Droge run", out)
        for uid in ("u1", "u2", "u3", "u4", "u9"):
            self.assertNotIn(uid, out)

    def test_apply_backs_up_first_copies_as_is_and_a_second_apply_copies_nothing(self):
        fake = _FakeCosmos(self.CONFIG, [])
        backups_at_write = []
        real_create = fake.create

        def create(coll, doc, pk):
            backups_at_write.append(len(list(self.tmp.glob("backup_podium_copy_*.json"))))
            return real_create(coll, doc, pk)

        fake.module.create = create
        out = self.run_copy(fake, "--apply")
        self.assertEqual(set(backups_at_write), {1}, "the backup comes before any write")
        backup = json.loads(next(self.tmp.glob("backup_podium_copy_*.json")).read_text(encoding="utf-8"))
        # The podium's docs in `config` as they were read, and `podium`.
        self.assertEqual(backup["config"], self.CONFIG)
        self.assertEqual(backup["podium"], [])
        self.assertIn("gekopieerd 4", out)

        created = {doc["id"]: doc for _, doc, _ in fake.creates}
        self.assertEqual(set(created), {d["id"] for d in self.CONFIG})
        self.assertTrue(all(coll == "podium" and pk == "podium" for coll, _, pk in fake.creates))
        # The same doc, without Cosmos' own fields.
        self.assertEqual(created["podium_6EWI_s1_1"], _place("6EWI", "s1", 1, "u1"))
        self.assertEqual(created["podium_6WEWI_s2_1"]["uid"], "u4")

        # Again: nothing twice, and no second backup.
        fake.creates.clear()
        out = self.run_copy(fake, "--apply")
        self.assertEqual(fake.creates, [])
        self.assertIn("te kopiëren: 0", out)
        self.assertIn("al in podium voor dezelfde leerling: 4", out)
        self.assertIn("niets te kopiëren", out)
        self.assertEqual(len(list(self.tmp.glob("backup_podium_copy_*.json"))), 1)

    def test_a_place_already_in_podium_stays_as_it_is(self):
        theirs = _place("6EWI", "s1", 1, "u9", awardedAt="2026-11-30T10:00:00.000Z")
        fake = _FakeCosmos(self.CONFIG, [copy.deepcopy(theirs)])
        out = self.run_copy(fake, "--apply")
        self.assertNotIn("podium_6EWI_s1_1", [doc["id"] for _, doc, _ in fake.creates])
        self.assertEqual([d for d in fake.podium if d["id"] == "podium_6EWI_s1_1"], [theirs])
        self.assertIn("in beide bezet door een andere leerling, niet gekopieerd: 1\n  podium_6EWI_s1_1", out)
        self.assertIn("gekopieerd 3", out)

    def test_a_place_claimed_in_podium_meanwhile_is_not_overwritten(self):
        mine = _place("6EWI", "s1", 2, "u2")
        theirs = _place("6WEWI", "s1", 1, "u9")
        fake = _FakeCosmos(self.CONFIG, [], claimed_meanwhile=[mine, theirs])
        out = self.run_copy(fake, "--apply")
        self.assertIn(
            "gekopieerd 2, intussen al aanwezig 1, intussen bezet door een andere leerling 1\n  podium_6WEWI_s1_1",
            out,
        )
        self.assertEqual([d for d in fake.podium if d["id"] == "podium_6WEWI_s1_1"], [theirs])

    def test_without_the_podium_container_it_says_so_and_writes_nothing(self):
        fake = _FakeCosmos(self.CONFIG, [], podium_exists=False)
        with self.assertRaises(SystemExit) as stop:
            self.run_copy(fake, "--apply")
        self.assertIn("bestaat nog niet", str(stop.exception.code))
        self.assertEqual(fake.creates, [])
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_apply_refuses_a_backup_inside_the_repo(self):
        fake = _FakeCosmos(self.CONFIG, [])
        out = io.StringIO()
        with (
            mock.patch.object(pc, "_cosmos", return_value=fake.module),
            contextlib.redirect_stdout(out),
            self.assertRaises(SystemExit),
        ):
            pc.main(["--apply", "--backup-dir", str(pb.ROOT / "tmp-backup")])
        self.assertFalse((pb.ROOT / "tmp-backup").exists())
        self.assertEqual(fake.creates, [])


if __name__ == "__main__":
    unittest.main()
