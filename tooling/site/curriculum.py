"""Writes the course into the "Wat leer je?" section of the start page (#292):
every live goal with its title and one sentence, and under it its subgoals,
each with a title and one sentence. No learning objectives.

The texts come from the goal files, the same ones push_goal.py writes to the
live curriculum:

    Goal Generator Cowork Project/AI Tutor for Python Goals Generator/goals/NN-<goal-id>.json

Only the goals in LIVE_GOALS (or --goals) are listed, in the order of the
Leerpad (the root goal's `order`). When a goal goes live, add its file name
to LIVE_GOALS and run this script: that is the step "site bijwerken" in the
per-goal steps of ROADMAP.md. `--check-live` compares LIVE_GOALS with the
`goals` container in Cosmos, read-only.

A page opts in with two markers; everything between them is replaced and the
markers stay, so a second run with the same files changes nothing:

    <!-- curriculum:start -->
    <!-- curriculum:end -->

The same pages carry the reference ("Naslag", #323): every function,
method and class the course uses, from assets/reference/python_reference.json
(the file the app's reference panel and editor read), between its own
markers:

    <!-- reference:start -->
    <!-- reference:end -->

Before it writes, the script checks that file against the lessons of the
live goals (reference.py): something a live lesson uses that the reference
lacks, an item without a Dutch or English summary or an example, or a
lesson link that does not hold is an error, and no page is written. So when
a goal goes live and its lessons use a new function, this step says what to
add. `--check-reference` runs only the check.

By default it writes both start pages (#294): the Dutch list into
public/index.html and the English one into public/en/index.html. The English
titles and descriptions come from goals/en/goal-texts.json; a goal whose
English text is missing, or was translated from another Dutch text than the
file's, is an error. All or nothing: every page is filled in memory before
any is written, so a missing translation leaves both pages as they were.
`--lang nl` or `--lang en` writes only that page.

Run from the repo root:

    python tooling/site/curriculum.py                # both pages
    python tooling/site/curriculum.py --lang nl      # only public/index.html
    python tooling/site/curriculum.py --check-live   # LIVE_GOALS against Cosmos
    python tooling/site/curriculum.py --check-reference  # the reference against the live lessons

Standard library only; --check-live uses tooling/evaluation/cosmos.py and
never writes.
"""

from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reference  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "Goal Generator Cowork Project" / "AI Tutor for Python Goals Generator"
GOALS = GENERATOR / "goals"
EN_TEXTS = GOALS / "en" / "goal-texts.json"

# The goal files whose goal is live, by file name without ".json". Read from
# the `goals` container on 2026-11-09: all six root goals are live, each with
# as many subgoals as its file.
LIVE_GOALS = (
    "01-eenvoudige-python-scripts",
    "02-condities",
    "03-herhaling",
    "04-lijsten-tuples",
    "05-functies",
    "06-toeval-simulatie",
    "07-grafieken",
    "08-vergelijkingen-oplossen",
)

PAGES = {
    "nl": ROOT / "public" / "index.html",
    "en": ROOT / "public" / "en" / "index.html",
}

START = "<!-- curriculum:start -->"
END = "<!-- curriculum:end -->"
REFERENCE_START = "<!-- reference:start -->"
REFERENCE_END = "<!-- reference:end -->"

# The app's own words (lib/l10n/app_nl.arb, app_en.arb).
LABELS = {
    "nl": {"one": "1 subdoel", "many": "{n} subdoelen", "optional": "optioneel"},
    "en": {"one": "1 subgoal", "many": "{n} subgoals", "optional": "optional"},
}

GOAL_PK = "goal"


class CurriculumError(Exception):
    pass


# --- The goals ---------------------------------------------------------------


def load_goals(names: list[str], goals_dir: Path = GOALS) -> list[dict]:
    """The `{goal, subgoals, file}` entries of the named goal files, in the
    order of the Leerpad: by the root goal's `order`, subgoals by theirs.
    `file` is the name the entry was read from, which is also the folder of
    its lessons."""
    entries = []
    for name in names:
        path = goals_dir / f"{name}.json"
        if not path.is_file():
            raise CurriculumError(f"no goal file {path.name} in {goals_dir}")
        entry = json.loads(path.read_text(encoding="utf-8"))
        for node in [entry["goal"], *entry["subgoals"]]:
            for field in ("id", "title", "description"):
                if not (node.get(field) or "").strip():
                    raise CurriculumError(f"{name}: {node.get('id', '?')} has no {field}")
        entry["subgoals"] = sorted(entry["subgoals"], key=lambda s: int(s.get("order") or 0))
        entry["file"] = name
        entries.append(entry)
    return sorted(entries, key=lambda e: int(e["goal"].get("order") or 0))


def texts_for(entries: list[dict], lang: str, en_texts: Path = EN_TEXTS) -> dict[str, dict]:
    """Title and description per goal and subgoal id, in [lang]."""
    nodes = [n for e in entries for n in [e["goal"], *e["subgoals"]]]
    if lang == "nl":
        return {n["id"]: {"title": n["title"], "description": n["description"]} for n in nodes}

    translated = {g["id"]: g for g in json.loads(en_texts.read_text(encoding="utf-8"))["goals"]}
    out, problems = {}, []
    for n in nodes:
        t = translated.get(n["id"])
        if t is None or not (t.get(lang) or {}).get("title") or not (t.get(lang) or {}).get("description"):
            problems.append(f"{n['id']}: no {lang} title and description in {en_texts.name}")
            continue
        source = t.get("nl") or {}
        if source.get("title") != n["title"] or source.get("description") != n["description"]:
            problems.append(f"{n['id']}: the {lang} text was translated from another Dutch text than the goal file's")
            continue
        out[n["id"]] = {"title": t[lang]["title"], "description": t[lang]["description"]}
    if problems:
        raise CurriculumError("; ".join(problems))
    return out


# --- The markup --------------------------------------------------------------


def _text(s: str) -> str:
    return html.escape(" ".join(s.split()), quote=False)


def render(entries: list[dict], texts: dict[str, dict], lang: str) -> list[str]:
    """The lines between the markers, without indentation: one <details> per
    goal, closed, its subgoals in a <dl>. Each subgoal has an id, which the
    reference's lesson links point at."""
    labels = LABELS[lang]
    optional = f' <span class="pill">{labels["optional"]}</span>'
    lines = ['<ol class="curriculum">']
    for number, entry in enumerate(entries, start=1):
        goal, subgoals = entry["goal"], entry["subgoals"]
        count = labels["one"] if len(subgoals) == 1 else labels["many"].format(n=len(subgoals))
        lines += [
            "  <li>",
            '    <details class="curriculum-goal">',
            "      <summary>",
            f'        <span class="curriculum-number">{number}</span>',
            '        <span class="curriculum-heading">',
            f'          <span class="curriculum-title">{_text(texts[goal["id"]]["title"])}'
            + (optional if goal.get("optional") else "") + "</span>",
            f'          <span class="curriculum-count">{count}</span>',
            "        </span>",
            "      </summary>",
            '      <div class="curriculum-body">',
            f'        <p>{_text(texts[goal["id"]]["description"])}</p>',
            '        <dl class="curriculum-subgoals">',
        ]
        for sub in subgoals:
            lines += [
                f'          <div id="{reference.subgoal_anchor(sub["id"])}">',
                f'            <dt>{_text(texts[sub["id"]]["title"])}'
                + (optional if sub.get("optional") else "") + "</dt>",
                f'            <dd>{_text(texts[sub["id"]]["description"])}</dd>',
                "          </div>",
            ]
        lines += [
            "        </dl>",
            "      </div>",
            "    </details>",
            "  </li>",
        ]
    lines.append("</ol>")
    return lines


def fill_page(text: str, lines: list[str], name: str, start_marker: str = START,
              end_marker: str = END) -> str:
    """[text] with [lines] between the markers, indented to the start
    marker's column, in the page's own line endings."""
    start, end = text.find(start_marker), text.find(end_marker)
    if start < 0 or end < start or text.find(start_marker, start + 1) >= 0:
        raise CurriculumError(f"{name}: needs one {start_marker} followed by one {end_marker}")
    newline = "\r\n" if "\r\n" in text else "\n"
    line_start = text.rfind("\n", 0, start) + 1
    indent = text[line_start:start]
    if indent.strip():
        raise CurriculumError(f"{name}: {start_marker} must be on a line of its own")
    body = "".join(newline + indent + line if line else newline for line in lines)
    return text[: start + len(start_marker)] + body + newline + indent + text[end:]


def check_reference(entries: list[dict], ref: dict | None = None,
                    lessons_dir: Path = reference.LESSONS) -> tuple[list[str], list[str]]:
    """The reference's problems and notes against the lessons of [entries]."""
    ref = reference.load() if ref is None else ref
    return reference.check(ref, reference.lesson_files(entries, lessons_dir))


# --- Cosmos (read-only) ------------------------------------------------------


def check_live(names: list[str], goals_dir: Path = GOALS, cosmos=None) -> list[str]:
    """What differs between [names] and the live `goals` container: a live
    root goal with a file that is not listed, a listed goal that is not live,
    and subgoals that are not the same. Only queries; [cosmos] defaults to
    tooling/evaluation/cosmos.py."""
    if cosmos is None:
        sys.path.insert(0, str(ROOT / "tooling" / "evaluation"))
        import cosmos  # reads .env on import

    rows = cosmos.query("goals", "SELECT c.id, c.parentId FROM c", pk=GOAL_PK)
    live = {
        r["id"]: {k["id"] for k in rows if k.get("parentId") == r["id"]}
        for r in rows
        if not r.get("parentId")
    }

    listed = set(names)
    files = sorted(goals_dir.glob("*.json"))
    problems = [f"{n} is listed but has no goal file" for n in sorted(listed - {p.stem for p in files})]
    for path in files:
        entry = json.loads(path.read_text(encoding="utf-8"))
        root = entry["goal"]["id"]
        if path.stem in listed and root not in live:
            problems.append(f"{path.stem} is listed but {root} is not live")
        elif path.stem not in listed and root in live:
            problems.append(f"{root} is live but {path.stem} is not listed")
        elif root in live:
            in_file = {s["id"] for s in entry["subgoals"]}
            if in_file != live[root]:
                problems.append(
                    f"{root}: subgoals differ (only in the file: {sorted(in_file - live[root])}, "
                    f"only live: {sorted(live[root] - in_file)})"
                )
    return problems


# --- Main --------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--lang", choices=sorted(PAGES),
                        help="write only this language's page (default: both)")
    parser.add_argument("--page", type=Path,
                        help="with --lang: the page to write instead of the default "
                             "(public/index.html, public/en/index.html for en)")
    parser.add_argument("--goals", nargs="+", metavar="NN-<goal-id>",
                        help="the live goal files, instead of LIVE_GOALS")
    parser.add_argument("--check-live", action="store_true",
                        help="compare the live goals with Cosmos (read-only) and write nothing")
    parser.add_argument("--check-reference", action="store_true",
                        help="check the reference against the lessons of the live goals and "
                             "write nothing")
    args = parser.parse_args(argv)
    if args.page and not args.lang:
        parser.error("--page needs --lang")
    names = list(args.goals or LIVE_GOALS)

    try:
        if args.check_live:
            problems = check_live(names)
            for p in problems:
                print(f"differs: {p}", file=sys.stderr)
            if not problems:
                print(f"live goals match: {', '.join(names)}")
            return 1 if problems else 0

        entries = load_goals(names)
        ref = reference.load()
        problems, notes = check_reference(entries, ref)
        for n in notes:
            print(f"note: {n}")
        if args.check_reference:
            for p in problems:
                print(f"missing: {p}", file=sys.stderr)
            if not problems:
                items = sum(len(g["items"]) for g in ref["groups"])
                print(f"reference complete for {', '.join(names)} ({items} items)")
            return 1 if problems else 0
        if problems:
            raise CurriculumError(
                "the reference (assets/reference/python_reference.json) is not complete: "
                + "; ".join(problems)
            )

        # Every page filled in memory first; nothing is written on an error.
        pages = []
        for lang in [args.lang] if args.lang else list(PAGES):
            page = args.page or PAGES[lang]
            texts = texts_for(entries, lang)
            text = page.read_bytes().decode("utf-8")
            filled = fill_page(text, render(entries, texts, lang), page.name)
            filled = fill_page(filled, reference.render(ref, lang, texts), page.name,
                               REFERENCE_START, REFERENCE_END)
            pages.append((page, text, filled))
    except (CurriculumError, OSError, KeyError, ValueError) as e:
        print(f"error: {e}. No page was written.", file=sys.stderr)
        return 1

    goals = len(entries)
    subgoals = sum(len(e["subgoals"]) for e in entries)
    for page, text, filled in pages:
        where = page.resolve()
        where = where.relative_to(ROOT) if where.is_relative_to(ROOT) else where
        if filled == text:
            print(f"{where}: unchanged ({goals} goals, {subgoals} subgoals)")
            continue
        page.write_bytes(filled.encode("utf-8"))
        print(f"{where}: written ({goals} goals, {subgoals} subgoals)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
