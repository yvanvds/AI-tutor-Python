"""Writes one authored goal to the live curriculum: the Dutch lesson of every
subgoal (container `content`), the subgoals and the root goal (`goals`).

The goal lives in the repo as `goals/NN-<goal-id>.json`, its lessons in
`lessons/NN-<goal-id>/`. The result is what importing the goal file in the
app (Add) and uploading each lesson in Lesinhoud gives, without the clicking.

    python tooling/curriculum/push_goal.py plan 05-functies     # dry run
    python tooling/curriculum/push_goal.py push 05-functies     # create only, then verify
    python tooling/curriculum/push_goal.py verify 05-functies   # read back, compare

`push` uses create, never upsert: a doc that is already there is kept and
listed. It is for a *new* goal. Changing a live goal goes through the app's
import (Replace) — student belief is keyed on the subgoal and LO ids, so an
edit there is a decision, not a sync.

Lessons are written first, then the subgoals, the root goal last: a root
without subgoals is never visible, so students get the goal in one piece.

The English texts follow with `tooling/translations/translations.py push`,
which only accepts a translation once the live Dutch text equals the files.

Standard library only; the Cosmos client is `tooling/evaluation/cosmos.py`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tooling" / "translations"))
from translations import GENERATOR, lessons  # noqa: E402

GOALS = GENERATOR / "goals"

GOAL_PK = "goal"
CONTENT_PK = "content"


def _cosmos():
    """The REST client. Imported late: it reads `.env` on import."""
    sys.path.insert(0, str(ROOT / "tooling" / "evaluation"))
    import cosmos

    return cosmos


def _now() -> str:
    """As Dart's `DateTime.now().toUtc().toIso8601String()`."""
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def load(name: str, goals_dir: Path | None = None) -> dict:
    """The `{goal, subgoals}` entry of `goals/<name>.json`."""
    return json.loads(((goals_dir or GOALS) / f"{name}.json").read_text(encoding="utf-8"))


# ---- the docs ------------------------------------------------------------------


def _goal_doc(node: dict, parent_id: str | None, module_id: str, content_id: str | None) -> dict:
    """Field for field `GoalsService._docMap`. Subgoals carry the module of
    their root, as the live ones do."""
    return {
        "id": node["id"],
        "type": GOAL_PK,
        "title": node.get("title") or "",
        "description": node.get("description"),
        "parentId": parent_id,
        "order": int(node.get("order") or 0),
        "optional": bool(node.get("optional", False)),
        "teachingTips": list(node.get("teachingTips") or []),
        "allowChains": bool(node.get("allowChains", False)),
        "objectives": [
            {
                "id": o["id"],
                "statement": o["statement"],
                "kind": o["kind"],
                "weight": float(o.get("weight", 1.0)),
                "optional": bool(o.get("optional", False)),
            }
            for o in node.get("objectives") or []
        ],
        "contentId": content_id,
        "moduleId": module_id,
    }


def build_docs(entry: dict, nl_lessons: dict[str, dict], now: str | None = None) -> tuple[list[tuple[str, str, dict]], list[str]]:
    """The docs to write as `(container, partition key, doc)`, in writing
    order, and what the teacher should know before writing them.

    A lesson is `Content.toMap`: its id mirrors the subgoal id, and the
    subgoal's `contentId` points at it. A subgoal without a lesson file is
    written unlinked.
    """
    now = now or _now()
    root = entry["goal"]
    module_id = root.get("moduleId") or ""
    subgoals = sorted(entry.get("subgoals") or [], key=lambda s: s.get("order") or 0)
    notes: list[str] = []
    content_docs, subgoal_docs = [], []
    for sg in subgoals:
        if sg.get("parentId") != root["id"]:
            notes.append(f"subgoal {sg['id']}: parentId {sg.get('parentId')!r} is not the goal {root['id']!r}; written under the goal")
        if not sg.get("objectives"):
            notes.append(f"subgoal {sg['id']}: no learning objectives — the conductor blocks it")
        lesson = nl_lessons.get(sg["id"])
        if lesson is None:
            notes.append(f"subgoal {sg['id']}: no Dutch lesson file — written without a lesson")
        else:
            if lesson["title"] != sg.get("title"):
                notes.append(f"subgoal {sg['id']}: the lesson is titled {lesson['title']!r}, the subgoal {sg.get('title')!r}")
            content_docs.append(
                (
                    "content",
                    CONTENT_PK,
                    {"id": sg["id"], "type": CONTENT_PK, "title": lesson["title"], "body": lesson["body"], "updatedAt": now},
                )
            )
        subgoal_docs.append(("goals", GOAL_PK, _goal_doc(sg, root["id"], module_id, sg["id"] if lesson else None)))
    root_doc = ("goals", GOAL_PK, _goal_doc({**root, "teachingTips": [], "objectives": [], "allowChains": False}, None, module_id, None))
    return content_docs + subgoal_docs + [root_doc], notes


def _same(stored: dict | None, doc: dict) -> list[str]:
    """The fields in which [stored] differs from [doc]; `updatedAt` is the
    moment of writing and is not compared."""
    if stored is None:
        return ["missing"]
    return [k for k, v in doc.items() if k != "updatedAt" and stored.get(k) != v]


# ---- the commands ------------------------------------------------------------------


def plan(cosmos, name: str, out=sys.stdout, goals_dir: Path | None = None, nl_lessons: dict | None = None):
    entry = load(name, goals_dir)
    docs, notes = build_docs(entry, nl_lessons if nl_lessons is not None else lessons("nl"))
    live_goals = {g["id"]: g for g in cosmos.query("goals", "SELECT * FROM c", pk=GOAL_PK)}
    live_content = {c["id"] for c in cosmos.query("content", "SELECT c.id FROM c", pk=CONTENT_PK)}
    root = entry["goal"]
    for g in live_goals.values():
        if g.get("parentId") is None and g["id"] != root["id"] and g.get("order") == root.get("order"):
            notes.append(f"goal {g['id']} already has order {root.get('order')}: the two would sort arbitrarily")
    if root.get("moduleId") and root["moduleId"] not in {m["id"] for m in cosmos.query("modules", "SELECT c.id FROM c")}:
        notes.append(f"module {root['moduleId']!r} does not exist")
    for coll, _, d in docs:
        there = d["id"] in (live_content if coll == "content" else live_goals)
        what = "lesson " if coll == "content" else ("goal   " if d["parentId"] is None else "subgoal")
        extra = f"{len(d['body'])} chars" if coll == "content" else (f"{len(d['objectives'])} LOs, lesson: {d['contentId'] or 'none'}" if d["parentId"] else f"order {d['order']}, module {d['moduleId']}")
        print(f"{'EXISTS' if there else 'create'}  {coll:8} {what} {d['id']:28} {extra}", file=out)
    print(f"\n{len(docs)} docs for goal `{root['id']}` ({root.get('title')})", file=out)
    for n in notes:
        print(f"NOTE  {n}", file=out)
    return docs, notes


def push(cosmos, name: str, out=sys.stdout, goals_dir: Path | None = None, nl_lessons: dict | None = None) -> dict:
    """Creates every doc of [plan], in order; one that exists is kept and listed."""
    docs, notes = plan(cosmos, name, out, goals_dir, nl_lessons)
    created, exists = [], []
    for coll, pk, d in docs:
        try:
            cosmos.create(coll, d, pk=pk)
            created.append(f"{coll}/{d['id']}")
        except cosmos.Exists:
            exists.append(f"{coll}/{d['id']}")
    print(f"\ncreated {len(created)}/{len(docs)}", file=out)
    for i in exists:
        print(f"409 KEPT  {i}: already there; not overwritten", file=out)
    return {"created": created, "exists": exists, "notes": notes, **verify(cosmos, name, out, goals_dir, nl_lessons)}


def verify(cosmos, name: str, out=sys.stdout, goals_dir: Path | None = None, nl_lessons: dict | None = None) -> dict:
    """Reads every doc back and compares it with the files."""
    docs, _ = build_docs(load(name, goals_dir), nl_lessons if nl_lessons is not None else lessons("nl"))
    same, different = [], {}
    for coll, pk, d in docs:
        diff = _same(cosmos.read(coll, d["id"], pk), d)
        if diff:
            different[f"{coll}/{d['id']}"] = diff
        else:
            same.append(f"{coll}/{d['id']}")
    print(f"\nread back: {len(same)}/{len(docs)} docs equal to the files", file=out)
    for i, diff in different.items():
        print(f"DIFFERS   {i}: {', '.join(diff)}", file=out)
    return {"same": same, "different": different}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["plan", "push", "verify"])
    ap.add_argument("goal", help="the goal file's name without .json, e.g. 05-functies")
    args = ap.parse_args(argv)
    cosmos = _cosmos()
    if args.command == "plan":
        plan(cosmos, args.goal)
        return 0
    r = push(cosmos, args.goal) if args.command == "push" else verify(cosmos, args.goal)
    return 1 if r["different"] else 0


if __name__ == "__main__":
    sys.exit(main())
