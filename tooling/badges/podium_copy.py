"""Copies the class podium (#221) from `config` to its own container (#338).

Until #338 the podium was the partition `podium` of the `config` container.
With access through the user's own sign-in (#306) a role reaches a whole
container, not a partition: so that students can write their places but only
read `config`, the podium has a container of its own, `podium`, with the same
docs and the same partition key (`/type`). From that release on the app reads
and writes the podium only there. This script copies the places that are
still in `config`:

- a place that is not in `podium` yet is copied as it is: same id, same
  fields;
- a place that is in `podium` already for the same student stays as it is
  (copied by an earlier run, or claimed there again);
- a place that is in `podium` already for another student is never
  overwritten. It is reported by its id (class, subgoal and place, no
  student), for the teacher to settle: an older build claimed it in
  `config` while a newer build claimed it in `podium`;
- a place of a student who holds another place for that subgoal in `podium`
  already is not copied, and reported: nobody gets two places for one
  subgoal (as in `podium_backfill.py`).

It only ever `create`s, never replaces or deletes, so it can run again
whenever: once before the release, and again after `MinimumVersion` keeps
the older builds out, for the places they wrote in `config` in the
meantime. The old docs stay in `config` until the teacher removes them.

    python tooling/badges/podium_copy.py           # dry run: counts only
    python tooling/badges/podium_copy.py --apply   # backup, then copy

The dry run only reads. It prints counts, and the ids of the places it does
not copy — never a name or a uid. `--apply` writes nothing before it saved a
backup of the podium docs of both containers to `~/ai-tutor-backups`
(outside the public repo). The `podium` container must exist: the teacher
creates it (README, step 3).

Standard library only; the Cosmos client is `tooling/evaluation/cosmos.py`
(`COSMOS_ENDPOINT` / `COSMOS_KEY` from `.env`). Tests:

    python -m unittest discover -s tooling/badges/tests
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

import podium_backfill as pb

SOURCE = "config"
TARGET = pb.CONTAINER
PARTITION = pb.PARTITION


# ---- the rules ---------------------------------------------------------------


def _is_place(doc: dict) -> bool:
    """A podium doc as `PodiumPlace.toDoc` writes it."""
    doc_id = doc.get("id")
    return (
        doc.get("type") == PARTITION
        and isinstance(doc_id, str)
        and doc_id.startswith("podium_")
        and bool(doc.get("uid"))
        and bool(doc.get("subgoalId"))
    )


def _clean(doc: dict) -> dict:
    """[doc] without Cosmos' own fields (`_rid`, `_etag`, `_ts`, ...)."""
    return {k: v for k, v in doc.items() if not k.startswith("_")}


@dataclass
class Plan:
    copy: list[dict] = field(default_factory=list)
    """The places to create in `podium`, as they are in `config`."""
    already: int = 0
    """Places in `podium` already, for the same student."""
    taken: list[str] = field(default_factory=list)
    """Ids of places that another student holds in `podium`."""
    second: list[str] = field(default_factory=list)
    """Ids of places whose student holds another one for that subgoal in
    `podium`."""


def plan(source: list[dict], target: list[dict]) -> Plan:
    """What to do with every place in [source] (`config`), given what
    [target] (`podium`) holds now. Nothing in [target] ever changes."""
    held = {d["id"]: d for d in target if isinstance(d.get("id"), str)}
    holders = {(d.get("uid"), d.get("subgoalId")) for d in target if _is_place(d)}
    out = Plan()
    for doc in sorted((d for d in source if _is_place(d)), key=lambda d: d["id"]):
        there = held.get(doc["id"])
        if there is not None:
            if there.get("uid") == doc["uid"]:
                out.already += 1
            else:
                out.taken.append(doc["id"])
            continue
        if (doc["uid"], doc["subgoalId"]) in holders:
            out.second.append(doc["id"])
            continue
        out.copy.append(_clean(doc))
    return out


# ---- the report --------------------------------------------------------------


def report(planned: Plan, in_source: int, in_target: int) -> str:
    """Counts, and the ids of the places that are not copied."""
    lines = [
        f"plaatsen in {SOURCE}: {in_source}; in {TARGET}: {in_target}",
        f"te kopiëren: {len(planned.copy)}",
        f"al in {TARGET} voor dezelfde leerling: {planned.already}",
        f"in beide bezet door een andere leerling, niet gekopieerd: {len(planned.taken)}",
        *(f"  {i}" for i in planned.taken),
        "niet gekopieerd, de leerling heeft voor dat subdoel al een plaats in "
        f"{TARGET}: {len(planned.second)}",
        *(f"  {i}" for i in planned.second),
    ]
    return "\n".join(lines)


# ---- the run -----------------------------------------------------------------


def backup(source: list[dict], target: list[dict], out_dir: Path, at) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"backup_podium_copy_{at.strftime('%Y%m%dT%H%M%S')}.json"
    path.write_text(
        json.dumps(
            {"takenAt": pb._iso(at), SOURCE: source, TARGET: target},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    return path


def apply(planned: Plan, cosmos) -> tuple[Counter, list[str]]:
    """Creates the places of [planned]. A place claimed in `podium` since the
    read stays as it is; when another student holds it, its id is returned."""
    done: Counter = Counter()
    taken: list[str] = []
    for doc in planned.copy:
        try:
            cosmos.create(TARGET, doc, PARTITION)
            done["gekopieerd"] += 1
        except cosmos.Exists:
            now = cosmos.read(TARGET, doc["id"], PARTITION)
            if now is not None and now.get("uid") == doc["uid"]:
                done["intussen al aanwezig"] += 1
            else:
                done["intussen bezet door een andere leerling"] += 1
                taken.append(doc["id"])
    return done, taken


def _missing(e: Exception) -> bool:
    """A 404 from Cosmos: the container does not exist."""
    return getattr(e, "code", None) == 404


def run(args) -> None:
    cosmos = _cosmos()
    source = cosmos.query(SOURCE, "SELECT * FROM c", pk=PARTITION, cross=False)
    try:
        target = cosmos.query(TARGET, "SELECT * FROM c", pk=PARTITION, cross=False)
    except Exception as e:  # urllib.error.HTTPError, from cosmos.py
        if _missing(e):
            sys.exit(
                f"de container `{TARGET}` bestaat nog niet: maak hem eerst aan "
                "(README, stap 3), partitiesleutel /type"
            )
        raise
    planned = plan(source, target)
    print(report(planned, sum(1 for d in source if _is_place(d)), len(target)))
    if not args.apply:
        print("\nDroge run: er is niets geschreven. Kopiëren met --apply.")
        return
    if not planned.copy:
        print("\nniets te kopiëren")
        return
    out_dir = Path(args.backup_dir).resolve()
    if out_dir == pb.ROOT or pb.ROOT in out_dir.parents:
        sys.exit(f"de back-up hoort buiten de publieke repo, niet in {out_dir}")
    path = backup(source, target, out_dir, pb._now())
    print(f"\nback-up: {path}")
    done, taken = apply(planned, cosmos)
    print(", ".join(f"{k} {n}" for k, n in sorted(done.items())))
    for i in taken:
        print(f"  {i}")


def _cosmos():
    return pb._cosmos()


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--apply", action="store_true", help="na een back-up echt kopiëren")
    p.add_argument("--backup-dir", default=str(pb.BACKUP_DIR), help="waar de back-up komt")
    run(p.parse_args(argv))


if __name__ == "__main__":
    main()
