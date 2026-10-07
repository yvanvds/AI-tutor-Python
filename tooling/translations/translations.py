"""Writes the English lessons, goal texts and learning-objective statements
in the repo to the Cosmos container `translations` (#206, #209, #250).

The translations live in the repo so the teacher can review them and a diff
exists:

- a lesson: `lessons/<module>/en/<NN-id>.html`, next to the Dutch file, as a
  full document like the Dutch one (the app's upload takes the `<body>`);
- every goal and subgoal: one file, `goals/en/goal-texts.json`, each entry
  with the Dutch title and description it was translated from;
- every learning objective (LO): in the same file, the `objectives` list of
  its subgoal's entry, each `{id, nl, en}` with the live Dutch "Je kan ..."
  statement it was translated from. The app reads it from a doc of its own,
  `objective_<subgoalId>.<loId>` (an LO id is unique only within its
  subgoal), with the English `statement` and no title (#243).

Every doc gets the `sourceHash` of the live Dutch text, computed exactly as
`translationSourceHash` in `lib/services/translation/translation.dart`; an
LO's is `source_hash("", statement)`, as `objectiveSourceHash`. A
translation is only written when the Dutch text it was made from (the Dutch
lesson file, the `nl` block of a goal entry, the `nl` of an LO) still equals
the live Dutch text; otherwise it would carry the hash of a text it does not
translate.

    python tooling/translations/translations.py plan     # dry run: ids, partition, fields
    python tooling/translations/translations.py push     # create only, then verify
    python tooling/translations/translations.py verify   # read back, compare hashes

`push` uses create, never upsert: a translation that is already there — for
instance one the teacher typed in the goal editor — is kept and listed.
`content` and `goals` are only read: an English LO statement never goes on
the `goals` doc, which the goal editor writes whole.

Standard library only; the Cosmos client is `tooling/evaluation/cosmos.py`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "Goal Generator Cowork Project" / "AI Tutor for Python Goals Generator"
LESSONS = GENERATOR / "lessons"
GOAL_TEXTS = GENERATOR / "goals" / "en" / "goal-texts.json"

LANGUAGE = "en"
CONTAINER = "translations"

_BODY = re.compile(r"<body\b[^>]*>([\s\S]*?)</body\s*>", re.IGNORECASE)
_TITLE = re.compile(r"<title>([\s\S]*?)</title>", re.IGNORECASE)
_LANG = re.compile(r"<html\b[^>]*\blang=\"([^\"]+)\"", re.IGNORECASE)


def _cosmos():
    """The REST client. Imported late: it reads `.env` on import."""
    sys.path.insert(0, str(ROOT / "tooling" / "evaluation"))
    import cosmos

    return cosmos


# ---- the hash and the files --------------------------------------------------


def norm(s: str) -> str:
    """`\\r\\n` and `\\r` to `\\n`, as `_lf` in translation.dart."""
    return s.replace("\r\n", "\n").replace("\r", "\n")


def source_hash(title: str, text: str) -> str:
    """`translationSourceHash`: SHA-256 of `title + "\\0" + text` (both with
    normalised line endings), as 64 lowercase hex digits."""
    return hashlib.sha256((norm(title) + "\0" + norm(text)).encode("utf-8")).hexdigest()


def body_fragment(html: str) -> str:
    """The `<body>`'s inner HTML, trimmed, as the Lesinhoud upload stores it
    (`_extractBodyFragment`), with `\\n` line endings."""
    m = _BODY.search(html)
    return norm(m.group(1) if m else html).strip()


def lesson_id(path: Path) -> str:
    """`01-uitvoer-print.html` -> `uitvoer-print`: the `content` id."""
    return re.sub(r"^\d+-", "", path.stem)


def lessons(language: str, root: Path | None = None) -> dict[str, dict]:
    """The lesson files in [language] (`nl`: `<module>/<file>`, otherwise
    `<module>/<language>/<file>`), by content id."""
    pattern = "*/*.html" if language == "nl" else f"*/{language}/*.html"
    out = {}
    for path in sorted((root or LESSONS).glob(pattern)):
        html = path.read_text(encoding="utf-8")
        title = _TITLE.search(html)
        lang = _LANG.search(html)
        out[lesson_id(path)] = {
            "path": path,
            "lang": lang.group(1) if lang else None,
            "title": norm(title.group(1)).strip() if title else "",
            "body": body_fragment(html),
        }
    return out


def goal_texts(path: Path | None = None) -> list[dict]:
    return json.loads((path or GOAL_TEXTS).read_text(encoding="utf-8"))["goals"]


def objective_ref(subgoal_id: str, lo_id: str) -> str:
    """`Translation.objectiveRefId`: an LO id is unique only within its
    subgoal, so the subgoal id goes in front."""
    return f"{subgoal_id}.{lo_id}"


def objective_hash(statement: str) -> str:
    """`objectiveSourceHash`: the statement hashed with an empty title."""
    return source_hash("", statement)


# ---- the docs ------------------------------------------------------------------


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def build_docs(
    live_content: list[dict],
    live_goals: list[dict],
    nl_lessons: dict[str, dict],
    en_lessons: dict[str, dict],
    texts: list[dict],
    now: str | None = None,
) -> tuple[list[dict], list[str]]:
    """The `translations` docs to write, and why any translation is left out.

    Field for field what `Translation.toMap` writes (`TranslationService.
    upsert` stamps `updatedAt`): `id`, `language`, `kind`, `refId`, `title`,
    `body` or `description`, `sourceHash`, `updatedAt`; an LO's doc has
    `statement` and no `title`.
    """
    now = now or _now()
    docs: list[dict] = []
    problems: list[str] = []

    for c in live_content:
        cid = c["id"]
        en = en_lessons.get(cid)
        nl = nl_lessons.get(cid)
        if en is None:
            problems.append(f"content {cid}: no English lesson file")
            continue
        if en["lang"] != LANGUAGE:
            problems.append(f"content {cid}: {en['path'].name} says lang={en['lang']!r}, not {LANGUAGE!r}")
            continue
        live_title, live_body = c.get("title") or "", c.get("body") or ""
        if nl is None or nl["title"] != norm(live_title).strip() or nl["body"] != norm(live_body).strip():
            problems.append(
                f"content {cid}: the Dutch lesson file differs from the live lesson — "
                "the translation was made from another text; sync and re-translate first"
            )
            continue
        docs.append(
            {
                "id": f"content_{cid}",
                "language": LANGUAGE,
                "kind": "content",
                "refId": cid,
                "title": en["title"],
                "body": en["body"],
                "sourceHash": source_hash(live_title, live_body),
                "updatedAt": now,
            }
        )
    for cid in sorted(set(en_lessons) - {c["id"] for c in live_content}):
        problems.append(f"content {cid}: English file without a live lesson")

    live = {g["id"]: g for g in live_goals}
    for entry in texts:
        gid = entry["id"]
        g = live.get(gid)
        if g is None:
            problems.append(f"goal {gid}: not in the live goals")
            continue
        live_title, live_desc = g.get("title") or "", g.get("description") or ""
        if (
            norm(entry["nl"]["title"]) != norm(live_title)
            or norm(entry["nl"]["description"]) != norm(live_desc)
        ):
            problems.append(f"goal {gid}: the Dutch text in goal-texts.json differs from the live goal")
            continue
        docs.append(
            {
                "id": f"goal_{gid}",
                "language": LANGUAGE,
                "kind": "goal",
                "refId": gid,
                "title": entry["en"]["title"],
                "description": entry["en"]["description"],
                "sourceHash": source_hash(live_title, live_desc),
                "updatedAt": now,
            }
        )
    for gid in sorted(set(live) - {e["id"] for e in texts}):
        problems.append(f"goal {gid}: live goal without an English text")

    # Learning objectives (#250): each against its own live statement, apart
    # from its subgoal's title and description.
    for entry in texts:
        gid = entry["id"]
        live_los = {lo.get("id"): lo for lo in (live.get(gid) or {}).get("objectives") or []}
        for obj in entry.get("objectives") or []:
            ref = objective_ref(gid, obj["id"])
            lo = live_los.get(obj["id"])
            if lo is None:
                problems.append(f"objective {ref}: not in the live goals")
                continue
            live_statement = lo.get("statement") or ""
            if norm(obj.get("nl") or "") != norm(live_statement):
                problems.append(f"objective {ref}: the Dutch statement in goal-texts.json differs from the live one")
                continue
            if not (obj.get("en") or "").strip():
                problems.append(f"objective {ref}: no English statement")
                continue
            docs.append(
                {
                    "id": f"objective_{ref}",
                    "language": LANGUAGE,
                    "kind": "objective",
                    "refId": ref,
                    "statement": obj["en"],
                    "sourceHash": objective_hash(live_statement),
                    "updatedAt": now,
                }
            )
    in_texts = {objective_ref(e["id"], o["id"]) for e in texts for o in e.get("objectives") or []}
    for g in live_goals:
        for lo in g.get("objectives") or []:
            ref = objective_ref(g["id"], lo.get("id"))
            if ref not in in_texts:
                problems.append(f"objective {ref}: live learning objective without an English statement")
    return docs, problems


def current_hashes(live_content: list[dict], live_goals: list[dict]) -> dict[str, str]:
    """Doc id -> the hash of the live Dutch text it should carry: of every
    lesson, goal and learning objective."""
    out = {f"content_{c['id']}": source_hash(c.get("title") or "", c.get("body") or "") for c in live_content}
    out.update(
        {f"goal_{g['id']}": source_hash(g.get("title") or "", g.get("description") or "") for g in live_goals}
    )
    out.update(
        {
            f"objective_{objective_ref(g['id'], lo['id'])}": objective_hash(lo.get("statement") or "")
            for g in live_goals
            for lo in g.get("objectives") or []
            if lo.get("id")
        }
    )
    return out


# ---- the commands ------------------------------------------------------------------


def _live(cosmos):
    content = cosmos.query("content", "SELECT * FROM c")
    goals = cosmos.query("goals", "SELECT * FROM c")
    return content, goals


def plan(cosmos, out=sys.stdout) -> tuple[list[dict], list[str]]:
    content, goals = _live(cosmos)
    docs, problems = build_docs(content, goals, lessons("nl"), lessons(LANGUAGE), goal_texts())
    width = max((len(d["id"]) for d in docs), default=0)
    for d in docs:
        fields = [k for k in d if k not in ("id", "language")]
        print(f"{d['id']:{width}} partition={d['language']}  fields: {', '.join(fields)}", file=out)
    per_kind = ", ".join(f"{n} {k}" for k, n in Counter(d["kind"] for d in docs).items())
    print(f"\n{len(docs)} docs for `{CONTAINER}`, partition `{LANGUAGE}` ({per_kind})", file=out)
    for p in problems:
        print(f"LEFT OUT  {p}", file=out)
    return docs, problems


def push(cosmos, out=sys.stdout) -> dict:
    """Creates every doc of [plan]; one that exists is kept and listed."""
    docs, problems = plan(cosmos, out)
    created, exists = [], []
    for d in docs:
        try:
            cosmos.create(CONTAINER, d, pk=d["language"])
            created.append(d["id"])
        except cosmos.Exists:
            exists.append(d["id"])
    print(f"\ncreated {len(created)}/{len(docs)}", file=out)
    for i in exists:
        print(f"409 KEPT  {i}: a translation is already there; not overwritten", file=out)
    result = verify(cosmos, out)
    return {"created": created, "exists": exists, "problems": problems, **result}


def verify(cosmos, out=sys.stdout) -> dict:
    """Reads partition `en` back: how many docs, and whether each carries the
    hash of the live Dutch text (else it is stale)."""
    content, goals = _live(cosmos)
    expected = current_hashes(content, goals)
    stored = cosmos.query(CONTAINER, "SELECT * FROM c", pk=LANGUAGE, cross=False)
    current, stale, unknown = [], [], []
    for d in stored:
        want = expected.get(d.get("id"))
        if want is None:
            unknown.append(d.get("id"))
        elif d.get("sourceHash") == want:
            current.append(d["id"])
        else:
            stale.append(d["id"])
    missing = sorted(set(expected) - {d.get("id") for d in stored})
    print(
        f"\nread back: {len(stored)} docs in `{CONTAINER}`/{LANGUAGE}; "
        f"{len(current)} current, {len(stale)} stale, {len(unknown)} without a live source; "
        f"{len(missing)} live lessons/goals/learning objectives without a translation",
        file=out,
    )
    for i in stale:
        print(f"STALE     {i}", file=out)
    for i in unknown:
        print(f"NO SOURCE {i}", file=out)
    for i in missing:
        print(f"MISSING   {i}", file=out)
    return {"stored": len(stored), "current": current, "stale": stale, "unknown": unknown, "missing": missing}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["plan", "push", "verify"])
    args = ap.parse_args(argv)
    cosmos = _cosmos()
    if args.command == "plan":
        _, problems = plan(cosmos)
        return 1 if problems else 0
    if args.command == "push":
        r = push(cosmos)
        return 1 if r["stale"] or r["problems"] else 0
    r = verify(cosmos)
    return 1 if r["stale"] else 0


if __name__ == "__main__":
    sys.exit(main())
