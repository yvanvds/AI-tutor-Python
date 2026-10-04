"""Fills in the class podium (#221) from `turn_history`.

Since #221 the first three students of a class to finish a subgoal get gold,
silver and bronze for it: the app claims a place the moment a graded turn
moves a student past a subgoal for the first time (`subgoalAdvanced`). The
subgoals finished before that release are only in `turn_history`. This
script hands out those places the way the app would have:

- per student and subgoal, the earliest turn record with `subgoalAdvanced`
  — the subgoal is the one the student was on, `activeSubgoalId` when the
  record has one, else `subgoalId` (`podiumSubgoalOf` in
  lib/services/badges/class_podium.dart). Finishing it again later does not
  count again;
- per class (the student's `className` now, trimmed; a student without a
  class does not take part) and subgoal, the first three of those in time;
- three places, also in a small class.

The places are docs in the `podium` partition of the `config` container,
`podium_{class}_{subgoal}_{1|2|3}` (`CosmosDocId.podium`), each with the
student's uid and nothing else about them. The script only ever `create`s:
a place already there — claimed live by the app, or by an earlier run — is
never overwritten. A student who holds a place for a subgoal gets no second
one; the others move up into the free places in the order they finished.
So it can run again whenever: before the release reaches the students is
best (then nobody's app claimed a place yet and the order is exactly the
history's), but a later run only fills what is still free.

The students' apps pick their medals up at their next start: they read every
podium doc with their uid and put the medal on their account doc, with a
notice. This script never touches an account.

    python tooling/badges/podium_backfill.py           # dry run: counts only
    python tooling/badges/podium_backfill.py --apply   # backup, then create

The dry run only reads. It prints counts — per class the subgoals and the
gold, silver and bronze medals to hand out, and in total how many students
would get one — never a name or an id. `--apply` writes nothing before it
saved a backup of the whole `config` container to `~/ai-tutor-backups`
(outside the public repo). Whether to apply is the teacher's call, after the
dry run.

Standard library only; the Cosmos client is `tooling/evaluation/cosmos.py`
(`COSMOS_ENDPOINT` / `COSMOS_KEY` from `.env`). Tests:

    python -m unittest discover -s tooling/badges/tests
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKUP_DIR = Path.home() / "ai-tutor-backups"
CONTAINER = "config"
PARTITION = "podium"

# `kPodiumPlaces` in lib/services/badges/class_podium.dart; a test keeps them
# equal.
PLACES = 3
MEDALS = {1: "goud", 2: "zilver", 3: "brons"}

_UNSAFE = re.compile(r"[/\\?#\s]")


def _cosmos():
    """The REST client. Imported late: it reads `.env` on import."""
    sys.path.insert(0, str(ROOT / "tooling" / "evaluation"))
    import cosmos

    return cosmos


# ---- the rules ---------------------------------------------------------------


def doc_id(klas: str, subgoal: str, place: int) -> str:
    """`CosmosDocId.podium`: the class trimmed, and a character Cosmos refuses
    in an id or white space turned into `-`."""
    return f"podium_{_UNSAFE.sub('-', klas.strip())}_{_UNSAFE.sub('-', subgoal)}_{place}"


def subgoal_of(turn: dict) -> str:
    """The subgoal a record with `subgoalAdvanced` moved the student past."""
    return turn.get("activeSubgoalId") or turn.get("subgoalId") or ""


def first_advances(turns: list[dict]) -> dict[tuple[str, str], tuple[str, str]]:
    """Per (uid, subgoal), the (turnAt as stored, record id) of the first
    advance; the earlier id first when two share a moment."""
    out: dict[tuple[str, str], tuple[dt.datetime, str, str]] = {}
    for t in turns:
        if t.get("subgoalAdvanced") is not True:
            continue
        uid, subgoal, at = t.get("uid"), subgoal_of(t), t.get("turnAt")
        if not uid or not subgoal or not isinstance(at, str):
            continue
        key = (uid, subgoal)
        moment = (_instant(at), t.get("id") or "", at)
        if key not in out or moment[:2] < out[key][:2]:
            out[key] = moment
    return {k: (v[2], v[1]) for k, v in out.items()}


def _instant(at: str) -> dt.datetime:
    """A stored ISO time, comparable whatever its precision."""
    t = dt.datetime.fromisoformat(at.replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def classes_of(accounts: list[dict]) -> dict[str, str]:
    """Per uid, the class now; students without one are left out."""
    out = {}
    for a in accounts:
        uid = a.get("id") or a.get("uid")
        klas = (a.get("className") or "").strip()
        if uid and klas:
            out[uid] = klas
    return out


@dataclass(frozen=True)
class Place:
    klas: str
    subgoal: str
    place: int
    uid: str
    awarded_at: str

    @property
    def id(self) -> str:
        return doc_id(self.klas, self.subgoal, self.place)

    def doc(self) -> dict:
        """As `PodiumPlace.toDoc` writes it."""
        return {
            "id": self.id,
            "type": PARTITION,
            "className": self.klas,
            "subgoalId": self.subgoal,
            "place": self.place,
            "uid": self.uid,
            "awardedAt": self.awarded_at,
        }


def plan(accounts: list[dict], turns: list[dict], existing: list[dict]) -> tuple[list[Place], int]:
    """The places to create, and how many places are there already.

    Per class and subgoal, the students in the order they first finished it;
    one who holds a place for that subgoal already (any class) is passed
    over, the rest go into the free places, lowest first.
    """
    klas_of = classes_of(accounts)
    held_ids = set()
    holders: set[tuple[str, str]] = set()  # (uid, subgoal)
    for d in existing:
        if d.get("type") != PARTITION:
            continue
        held_ids.add(d.get("id"))
        if d.get("uid") and d.get("subgoalId"):
            holders.add((d["uid"], d["subgoalId"]))

    finished: dict[tuple[str, str], list[tuple[str, str, str]]] = {}
    for (uid, subgoal), (at, rid) in first_advances(turns).items():
        klas = klas_of.get(uid)
        if not klas:
            continue
        finished.setdefault((klas, subgoal), []).append((at, rid, uid))

    out: list[Place] = []
    for (klas, subgoal), rows in sorted(finished.items()):
        free = [p for p in range(1, PLACES + 1) if doc_id(klas, subgoal, p) not in held_ids]
        waiting = [(at, uid) for at, _, uid in sorted(rows, key=lambda r: (_instant(r[0]), r[1])) if (uid, subgoal) not in holders]
        for place, (at, uid) in zip(free, waiting):
            out.append(Place(klas, subgoal, place, uid, at))
    return out, len(held_ids)


# ---- the report --------------------------------------------------------------


def _n(count: int, one: str, more: str) -> str:
    return f"{count} {one if count == 1 else more}"


def report(planned: list[Place], already: int) -> str:
    """Counts only: per class the subgoals and medals, then the totals."""
    lines = []
    by_class: dict[str, list[Place]] = {}
    for p in planned:
        by_class.setdefault(p.klas, []).append(p)
    for klas in sorted(by_class):
        rows = by_class[klas]
        medals = Counter(p.place for p in rows)
        subgoals = len({p.subgoal for p in rows})
        students = len({p.uid for p in rows})
        lines.append(
            f"{klas}: {_n(subgoals, 'subdoel', 'subdoelen')}, "
            + ", ".join(f"{medals[n]} {MEDALS[n]}" for n in range(1, PLACES + 1))
            + f", {_n(students, 'leerling', 'leerlingen')} met een medaille"
        )
    students = len({p.uid for p in planned})
    lines += [
        "",
        f"te maken: {_n(len(planned), 'plaats', 'plaatsen')} voor "
        f"{_n(students, 'leerling', 'leerlingen')}; al aanwezig: {already}",
    ]
    return "\n".join(lines)


# ---- the run -----------------------------------------------------------------


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _iso(t: dt.datetime) -> str:
    return t.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def backup(docs: list[dict], out_dir: Path, at: dt.datetime) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"backup_config_{at.strftime('%Y%m%dT%H%M%S')}.json"
    path.write_text(
        json.dumps({"takenAt": _iso(at), "config": docs}, ensure_ascii=False),
        encoding="utf-8",
    )
    return path


def apply(planned: list[Place], cosmos) -> Counter:
    done: Counter = Counter()
    for p in planned:
        try:
            cosmos.create(CONTAINER, p.doc(), PARTITION)
            done["gemaakt"] += 1
        except cosmos.Exists:
            # Claimed by a student's app since the read: it stays theirs.
            done["intussen bezet"] += 1
    return done


def run(args) -> None:
    cosmos = _cosmos()
    accounts = cosmos.query("accounts", "SELECT c.id, c.className FROM c")
    turns = cosmos.query(
        "turn_history",
        "SELECT c.id, c.uid, c.turnAt, c.subgoalId, c.activeSubgoalId, c.subgoalAdvanced "
        "FROM c WHERE c.subgoalAdvanced = true",
    )
    existing = cosmos.query(CONTAINER, "SELECT * FROM c", pk=PARTITION, cross=False)
    planned, already = plan(accounts, turns, existing)
    print(f"turn records met een afgerond subdoel: {len(turns)}")
    print(report(planned, already))
    if not args.apply:
        print("\nDroge run: er is niets geschreven. Schrijven met --apply.")
        return
    out_dir = Path(args.backup_dir).resolve()
    if out_dir == ROOT or ROOT in out_dir.parents:
        sys.exit(f"de back-up hoort buiten de publieke repo, niet in {out_dir}")
    at = _now()
    path = backup(cosmos.query(CONTAINER, "SELECT * FROM c"), out_dir, at)
    print(f"\nback-up: {path}")
    done = apply(planned, cosmos)
    print(", ".join(f"{k} {n}" for k, n in sorted(done.items())) or "niets te maken")


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--apply", action="store_true", help="na een back-up echt schrijven")
    p.add_argument("--backup-dir", default=str(BACKUP_DIR), help="waar de back-up komt")
    run(p.parse_args(argv))


if __name__ == "__main__":
    main()
