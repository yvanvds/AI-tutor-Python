"""Fills in `oefeningCount` on every account from `turn_history` (#217).

Since #217 every oefening is worth XP: the app counts one on the account doc
at the first graded answer to a question, whatever the grade, never for a
follow-up, and XP = oefeningCount x 20 + the XP for mastery. The oefeningen
made before that release are only in `turn_history`. The teacher decided
that every student gets them: this script counts them the way the app does
and writes the count onto the account, so the jump comes at once, at the
first lesson after the release.

Counted, per student, as the app counts (`Conductor.integrateAnswer`):

- a graded turn record — not an audit stub (`questionType` empty, the
  `is_audit` of tooling/evaluation),
- that is not a follow-up (`isFollowUp`),
- that has a subgoal (`subgoalId`): an answer with no active subgoal is
  the conductor's "nothing to update" and counts nowhere.

Right, partial or wrong makes no difference. The count only goes up: an
account that already has more (a student who worked on the new release
before this ran) keeps what it has. Run it again whenever: it sets the
count from `turn_history`, it never adds to it.

    python tooling/xp/backfill.py           # dry run: per class, before/after
    python tooling/xp/backfill.py --apply   # backup, then write

The dry run only reads. It prints, per class, every student as a number —
never a name or an id — with the oefeningen counted and the level before
and after. `--apply` writes nothing before it saved a backup of every
account doc to `~/ai-tutor-backups` (outside the public repo). It then
writes only `oefeningCount` — the doc as it was read, that one field
changed — with `If-Match`, so an account a student's app wrote in between
is skipped and named: run it again. Best outside lesson hours. Whether to
apply is the teacher's call, after the dry run and once the release with
the new formula is out.

Standard library only; the Cosmos client is `tooling/evaluation/cosmos.py`
(`COSMOS_ENDPOINT` / `COSMOS_KEY` from `.env`). Tests:

    python -m unittest discover -s tooling/xp/tests
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKUP_DIR = Path.home() / "ai-tutor-backups"
CONTAINER = "accounts"
FIELD = "oefeningCount"
NO_CLASS = "(geen klas)"

# `kXpPerOefening`, `kXpPerSubgoal`, `kXpPerLevel` in
# lib/features/shell/shell_state.dart; a test keeps them equal.
XP_PER_OEFENING = 20
XP_PER_SUBGOAL = 100
XP_PER_LEVEL = 500


def _cosmos():
    """The REST client. Imported late: it reads `.env` on import."""
    sys.path.insert(0, str(ROOT / "tooling" / "evaluation"))
    import cosmos

    return cosmos


# ---- the rules ---------------------------------------------------------------


def counts_as_oefening(turn: dict) -> bool:
    """Whether the app counted [turn] as an oefening (see the module doc)."""
    if not turn.get("questionType"):
        return False
    if turn.get("isFollowUp") is True:
        return False
    return bool(turn.get("subgoalId"))


def oefeningen_per_student(turns: list[dict]) -> Counter:
    """Per `uid`, how many of [turns] are oefeningen."""
    return Counter(t["uid"] for t in turns if t.get("uid") and counts_as_oefening(t))


def stored_count(doc: dict) -> int:
    """`oefeningCountOf` in account.dart: a whole number of at least 0, 0
    when the field is missing or not a number."""
    raw = doc.get(FIELD)
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        return 0
    if raw != raw or raw in (float("inf"), float("-inf")):
        return 0
    return max(0, int(raw))


def mastery_subgoals(goals: list[dict]) -> set[str]:
    """The subgoals worth mastery XP: every goal with a parent that is not
    optional (`masteryXpProvider`)."""
    return {g["id"] for g in goals if g.get("parentId") and not g.get("optional")}


def mastery_xp_per_student(progress: list[dict], subgoals: set[str]) -> dict[str, int]:
    """Per `uid`, `progress x 100` summed over [subgoals], rounded — the XP
    for mastery as the app derives it."""
    totals: dict[str, float] = {}
    for p in progress:
        uid, goal, value = p.get("uid"), p.get("goalId"), p.get("progress")
        if not uid or goal not in subgoals:
            continue
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        totals[uid] = totals.get(uid, 0.0) + value * XP_PER_SUBGOAL
    # Dart's `round()` rounds half away from zero; Python's rounds to even.
    return {uid: int(xp + 0.5) if xp >= 0 else -int(-xp + 0.5) for uid, xp in totals.items()}


def level(oefeningen: int, mastery_xp: int) -> int:
    """`levelForXp` in shell_state.dart."""
    return 1 + max(0, oefeningen * XP_PER_OEFENING + mastery_xp) // XP_PER_LEVEL


@dataclass(frozen=True)
class Plan:
    doc: dict
    counted: int
    before: int
    after: int
    mastery_xp: int

    @property
    def writes(self) -> bool:
        return self.after != self.before

    @property
    def klas(self) -> str:
        return (self.doc.get("className") or "").strip() or NO_CLASS

    @property
    def level_before(self) -> int:
        return level(self.before, self.mastery_xp)

    @property
    def level_after(self) -> int:
        return level(self.after, self.mastery_xp)


def plan(accounts: list[dict], turns: list[dict], goals: list[dict], progress: list[dict]) -> list[Plan]:
    counted = oefeningen_per_student(turns)
    mastery = mastery_xp_per_student(progress, mastery_subgoals(goals))
    out = []
    for doc in accounts:
        uid = doc["id"]
        before = stored_count(doc)
        n = counted.get(uid, 0)
        out.append(Plan(doc, n, before, max(before, n), mastery.get(uid, 0)))
    return out


def updated(doc: dict, count: int) -> dict:
    """[doc] as read, with only `oefeningCount` set to [count]."""
    out = {k: v for k, v in doc.items() if not k.startswith("_")}
    out[FIELD] = count
    return out


# ---- the report --------------------------------------------------------------


def by_class(planned: list[Plan]) -> list[tuple[str, list[Plan]]]:
    """Classes alphabetically, no class last; inside a class by the count
    after, most first — never by name, so the numbers say nothing about who."""
    classes: dict[str, list[Plan]] = {}
    for p in planned:
        classes.setdefault(p.klas, []).append(p)
    order = sorted(classes, key=lambda k: (k == NO_CLASS, k))
    return [
        (k, sorted(classes[k], key=lambda p: (-p.after, -p.mastery_xp, p.doc["id"])))
        for k in order
    ]


def report(planned: list[Plan]) -> str:
    lines = []
    for klas, rows in by_class(planned):
        jumps = [p.level_after - p.level_before for p in rows]
        lines += [
            "",
            f"{klas}: {len(rows)} {'leerling' if len(rows) == 1 else 'leerlingen'}, "
            f"{sum(p.counted for p in rows)} oefeningen, "
            f"gemiddeld +{sum(jumps) / len(rows):.1f} levels",
            f"  {'leerling':<10}{'oefeningen':>11}{'teller nu':>11}{'teller na':>11}"
            f"{'level nu':>10}{'level na':>10}",
        ]
        for i, p in enumerate(rows, 1):
            lines.append(
                f"  {i:<10}{p.counted:>11}{p.before:>11}{p.after:>11}"
                f"{p.level_before:>10}{p.level_after:>10}"
            )
    writes = sum(1 for p in planned if p.writes)
    kept = sum(1 for p in planned if p.before > p.counted)
    lines += [
        "",
        f"accounts: {len(planned)}, te schrijven: {writes}, "
        f"teller al hoger dan turn_history (blijft): {kept}",
    ]
    return "\n".join(lines)


# ---- the run -----------------------------------------------------------------


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _iso(t: dt.datetime) -> str:
    return t.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def backup(docs: list[dict], out_dir: Path, at: dt.datetime) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"backup_accounts_{at.strftime('%Y%m%dT%H%M%S')}.json"
    path.write_text(
        json.dumps({"takenAt": _iso(at), "accounts": docs}, ensure_ascii=False),
        encoding="utf-8",
    )
    return path


def apply(planned: list[Plan], cosmos) -> Counter:
    done: Counter = Counter()
    labels = {id(p): f"{klas} leerling {i}" for klas, rows in by_class(planned) for i, p in enumerate(rows, 1)}
    for p in planned:
        if not p.writes:
            continue
        try:
            cosmos.upsert(CONTAINER, updated(p.doc, p.after), p.doc["id"], etag=p.doc.get("_etag"))
            done["geschreven"] += 1
        except cosmos.Conflict:
            done["overgeslagen"] += 1
            print(f"  overgeslagen (intussen gewijzigd): {labels[id(p)]}")
    return done


def run(args) -> None:
    cosmos = _cosmos()
    accounts = cosmos.query(CONTAINER, "SELECT * FROM c")
    turns = cosmos.query(
        "turn_history",
        "SELECT c.uid, c.questionType, c.isFollowUp, c.subgoalId FROM c",
    )
    goals = list(cosmos.goals().values())
    progress = cosmos.query("progress", "SELECT c.uid, c.goalId, c.progress FROM c")
    planned = plan(accounts, turns, goals, progress)
    print(f"turn records: {len(turns)}, waarvan oefeningen: {sum(1 for t in turns if counts_as_oefening(t))}")
    print(report(planned))
    if not args.apply:
        print("\nDroge run: er is niets geschreven. Schrijven met --apply.")
        return
    out_dir = Path(args.backup_dir).resolve()
    if out_dir == ROOT or ROOT in out_dir.parents:
        sys.exit(f"de back-up hoort buiten de publieke repo, niet in {out_dir}")
    at = _now()
    path = backup(accounts, out_dir, at)
    print(f"\nback-up: {path}")
    done = apply(planned, cosmos)
    print(", ".join(f"{k} {n}" for k, n in sorted(done.items())) or "niets te schrijven")


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--apply", action="store_true", help="na een back-up echt schrijven")
    p.add_argument("--backup-dir", default=str(BACKUP_DIR), help="waar de back-up komt")
    run(p.parse_args(argv))


if __name__ == "__main__":
    main()
