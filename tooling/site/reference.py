"""The reference ("Naslag", #323): every function, method and class the
course uses, from the file the app ships with,

    assets/reference/python_reference.json

which the editor's dropdown after a dot (#322) and the app's reference
panel read too. This module checks that file against the lessons of the
live goals, and writes it as the "Naslag" section of the start pages.
`curriculum.py` uses both: it writes nothing while the check finds a
problem, and `curriculum.py --check-reference` only checks.

The check reads the code of every Dutch lesson of a live goal — the code
blocks and the inline `<code>` in the text — and reports, as problems:

- a built-in, a module's function or a method that a lesson uses and that
  the reference does not have;
- an item without a summary in Dutch or English, or without an example;
- an item that a live lesson uses but that has no `lesson`, with the first
  lesson that uses it as a suggestion;
- a `lesson` that is not a subgoal of a live goal, or whose lesson does not
  use the item.

Items no live lesson uses yet (string and dictionary methods, `sorted`) are
listed as a note: they stay in the reference, without a lesson.

Standard library only.
"""

from __future__ import annotations

import ast
import builtins
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "assets" / "reference" / "python_reference.json"
LESSONS = ROOT / "Goal Generator Cowork Project" / "AI Tutor for Python Goals Generator" / "lessons"

LANGUAGES = ("nl", "en")

_BODY = re.compile(r"<body\b[^>]*>([\s\S]*?)</body\s*>", re.IGNORECASE)
_PRE = re.compile(r"<pre\b[^>]*>\s*<code\b[^>]*>([\s\S]*?)</code>\s*</pre>", re.IGNORECASE)
_CODE = re.compile(r"<code\b[^>]*>([\s\S]*?)</code>", re.IGNORECASE)
_TAG = re.compile(r"<[^>]+>")
_BUILTINS = frozenset(dir(builtins))

# The site's own words; the app's are in lib/l10n/app_*.arb.
LABELS = {
    "nl": {"lesson": "Les:"},
    "en": {"lesson": "Lesson:"},
}


# --- The file ----------------------------------------------------------------


def load(path: Path = REFERENCE) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def prefix(group: dict) -> str | None:
    """What a module's items are written after: the name its `setup`
    imports it as (`plt`), else its id. None for the other groups. The same
    rule as `ReferenceGroup.prefix` in python_reference.dart."""
    if group["kind"] != "module":
        return None
    m = re.search(rf"^import {re.escape(group['id'])} as (\w+)$", group.get("setup") or "", re.MULTILINE)
    return m.group(1) if m else group["id"]


def written(group: dict, item: dict) -> str:
    """How the item is written in code, as `ReferenceItem.writtenIn`."""
    if group["kind"] == "module":
        return f"{prefix(group)}.{item['signature']}"
    if group["kind"] == "type":
        return f".{item['signature']}"
    return item["signature"]


def key(group: dict, item: dict) -> str:
    """`builtins.print`, `random.randint`, `list.append`."""
    return f"{group['id']}.{item['name']}"


# --- What the lessons use ----------------------------------------------------


def lesson_files(entries: list[dict], lessons_dir: Path = LESSONS) -> list[dict]:
    """The Dutch lesson of every subgoal of [entries] (curriculum.load_goals,
    which keeps each goal's file name in `file`), in the Leerpad's order:
    `{goal, number, subgoal, body}`. A subgoal without a lesson file has
    none."""
    out = []
    for number, entry in enumerate(entries, start=1):
        folder = lessons_dir / entry["file"]
        files = {re.sub(r"^\d+-", "", p.stem): p for p in sorted(folder.glob("*.html"))}
        for sub in entry["subgoals"]:
            path = files.get(sub["id"])
            if path is None:
                continue
            text = path.read_text(encoding="utf-8")
            m = _BODY.search(text)
            out.append({
                "goal": entry["goal"]["id"],
                "number": number,
                "subgoal": sub["id"],
                "body": m.group(1) if m else text,
            })
    return out


def _snippets(body: str) -> list[str]:
    """The code of a lesson: its code blocks in order, then the inline code
    of its text, unescaped."""
    blocks = [html.unescape(_TAG.sub("", m.group(1))) for m in _PRE.finditer(body)]
    inline = [html.unescape(_TAG.sub("", m.group(1))) for m in _CODE.finditer(_PRE.sub("", body))]
    return blocks + inline


# The built-in calls that make a value of a type the reference describes.
_MAKERS = {"builtins.str": "str", "builtins.list": "list", "builtins.dict": "dict"}


def uses(snippets: list[str], modules: dict[str, str], returns: dict[str, str] | None = None,
         types: frozenset[str] = frozenset()) -> set[str]:
    """What [snippets] use, as reference keys: `builtins.<name>` for a call
    of a built-in, `<module>.<name>` for a module's function or constant,
    `<type>.<name>` for a method on a value whose type the code shows, and
    `.<name>` for a method on a value of unknown type.

    [modules] maps the names a module is reachable by before any import
    (its id, and the alias its group's `setup` gives it) to the module; the
    imports in the snippets add to it, as in one Python namespace. [types]
    are the type groups (`str`, `list`, `dict`, `turtle.Turtle`), and
    [returns] the type each reference key gives (`turtle.Turtle` for
    `turtle.Turtle`, `str` for `builtins.input`). A name assigned a value of
    one of [types] — a literal, or a call that gives one — has that type in
    the whole lesson, unless it is assigned values of different types. A
    snippet that is not Python (output, an error message, a fragment) is
    skipped."""
    returns = {**_MAKERS, **(returns or {})}
    names = dict(modules)
    defined: set[str] = set()
    trees = []
    for code in snippets:
        try:
            trees.append(ast.parse(code))
        except SyntaxError:
            continue
    for tree in trees:
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for a in node.names:
                    if a.asname:
                        names[a.asname] = a.name
                    else:
                        root = a.name.split(".")[0]
                        names[root] = root
            elif isinstance(node, ast.ImportFrom) and node.module:
                for a in node.names:
                    names[a.asname or a.name] = f"{node.module}.{a.name}"
            elif isinstance(node, (ast.FunctionDef, ast.ClassDef)):
                defined.add(node.name)
    module_paths = set(names.values())

    def dotted(node: ast.AST) -> str | None:
        """`plt.plot` -> `matplotlib.pyplot.plot` when the root is a module."""
        if isinstance(node, ast.Name):
            return names.get(node.id)
        if isinstance(node, ast.Attribute):
            inner = dotted(node.value)
            return f"{inner}.{node.attr}" if inner else None
        return None

    def callee(node: ast.Call) -> str | None:
        if isinstance(node.func, ast.Name):
            name = node.func.id
            if name in names:
                return names[name]
            if name in _BUILTINS and name not in defined:
                return f"builtins.{name}"
            return None
        return dotted(node.func)

    def value_type(node: ast.AST) -> str | None:
        if isinstance(node, (ast.List, ast.ListComp)):
            return "list"
        if isinstance(node, (ast.Dict, ast.DictComp)):
            return "dict"
        if isinstance(node, ast.JoinedStr) or (isinstance(node, ast.Constant) and isinstance(node.value, str)):
            return "str"
        if isinstance(node, ast.Call):
            return returns.get(callee(node) or "")
        return None

    # The type of every name the code assigns one kind of value to.
    seen: dict[str, str | None] = {}
    for tree in trees:
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                name, t = node.targets[0].id, value_type(node.value)
                seen[name] = t if seen.get(name, t) == t else None
    known = {name: t for name, t in seen.items() if t in types}

    found: set[str] = set()
    for tree in trees:
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                k = callee(node)
                if k is not None:
                    found.add(k)
            if not isinstance(node, ast.Attribute):
                continue
            path = dotted(node)
            if path is not None:
                # `matplotlib.pyplot` itself is a module, not an item of one.
                if path not in module_paths and not any(p.startswith(path + ".") for p in module_paths):
                    found.add(path)
            elif dotted(node.value) is None:
                receiver = node.value
                t = known.get(receiver.id) if isinstance(receiver, ast.Name) else value_type(receiver)
                found.add(f"{t}.{node.attr}" if t in types else f".{node.attr}")
    return found


def module_names(reference: dict) -> dict[str, str]:
    """The names each module of the reference is reachable by without an
    import in the lesson itself: its root (`turtle`, `matplotlib`) and the
    alias its `setup` gives it (`plt`, `np`)."""
    out = {}
    for group in reference["groups"]:
        if group["kind"] != "module":
            continue
        root = group["id"].split(".")[0]
        out.setdefault(root, root)
        alias = prefix(group)
        if alias != group["id"]:
            out[alias] = group["id"]
    return out


def lesson_uses(lessons: list[dict], reference: dict) -> dict[str, set[str]]:
    """What each lesson uses, by subgoal id."""
    modules = module_names(reference)
    returns = {key(g, i): i["returns"] for g in reference["groups"] for i in g["items"] if i.get("returns")}
    types = frozenset(g["id"] for g in reference["groups"] if g["kind"] == "type")
    return {
        lesson["subgoal"]: uses(_snippets(lesson["body"]), modules, returns, types)
        for lesson in lessons
    }


# --- The check ---------------------------------------------------------------


def _used_by(item_key: str, group: dict, item: dict, used: set[str], owners: dict[str, int]) -> bool:
    """Whether a lesson's [used] keys include the item. A method on a value
    of unknown type (`.name`) counts only when one type group alone has a
    method of that name ([owners]): `.pop` may be a list's or a dict's."""
    if item_key in used:
        return True
    name = item["name"]
    return group["kind"] == "type" and f".{name}" in used and owners.get(name) == 1


def check(reference: dict, lessons: list[dict]) -> tuple[list[str], list[str]]:
    """The problems and the notes of the reference against [lessons], the
    Dutch lessons of the live goals in the Leerpad's order (lesson_files)."""
    problems: list[str] = []
    per_lesson = lesson_uses(lessons, reference)
    order = [lesson["subgoal"] for lesson in lessons]

    items: dict[str, tuple[dict, dict]] = {}
    owners: dict[str, int] = {}
    group_ids = set()
    for group in reference["groups"]:
        group_ids.add(group["id"])
        for lang in LANGUAGES:
            if not (group.get("title") or {}).get(lang):
                problems.append(f"group {group['id']}: no {lang} title")
        for item in group["items"]:
            items[key(group, item)] = (group, item)
            if group["kind"] == "type":
                owners[item["name"]] = owners.get(item["name"], 0) + 1

    # Used in a lesson, missing from the reference.
    first: dict[str, list[str]] = {}
    for sub in order:
        for used in sorted(per_lesson[sub]):
            first.setdefault(used, []).append(sub)
    for used, subs in first.items():
        where = ", ".join(subs[:3]) + (", …" if len(subs) > 3 else "")
        if used.startswith("."):
            if used[1:] not in owners:
                problems.append(f"the method {used[1:]} (used in {where}) is in no type group")
        elif used not in items and used not in group_ids:
            module = used.rsplit(".", 1)[0]
            what = f"{used[len('builtins.'):]}()" if module == "builtins" else used
            problems.append(f"{what} (used in {where}) is not in the reference")

    # Every item: its texts, its example and its lesson.
    unused = []
    for item_key, (group, item) in items.items():
        for lang in LANGUAGES:
            if not (item.get("summary") or {}).get(lang, "").strip():
                problems.append(f"{item_key}: no {lang} summary")
        if not (item.get("example") or "").strip():
            problems.append(f"{item_key}: no example")
        users = [sub for sub in order if _used_by(item_key, group, item, per_lesson[sub], owners)]
        lesson = item.get("lesson")
        if lesson:
            if lesson not in per_lesson:
                problems.append(f"{item_key}: its lesson {lesson} is not a subgoal of a live goal")
            elif not _used_by(item_key, group, item, per_lesson[lesson], owners):
                problems.append(f"{item_key}: its lesson {lesson} does not use it")
        elif users:
            problems.append(f"{item_key}: no lesson, and live lessons use it (first: {users[0]})")
        if not users:
            unused.append(item_key)

    notes = [f"in no live lesson yet, so without a lesson: {', '.join(unused)}"] if unused else []
    return problems, notes


# --- The markup --------------------------------------------------------------


def _text(s: str) -> str:
    """Plain text with `code` spans, as the panel shows a summary."""
    parts = s.split("`")
    out = []
    for i, part in enumerate(parts):
        escaped = html.escape(re.sub(r"\s+", " ", part) if i % 2 == 0 else part, quote=False)
        out.append(f"<code>{escaped}</code>" if i % 2 else escaped)
    return "".join(out)


def _code(code: str) -> str:
    """A `.code` block on one line of the page: its line breaks are written
    as `&#10;`, so the indentation of the page never enters the <pre>."""
    body = html.escape(code, quote=False).replace("\n", "&#10;")
    return f'<div class="code"><pre><code>{body}</code></pre></div>'


def subgoal_anchor(subgoal_id: str) -> str:
    """The id of a subgoal in the "Wat leer je?" list, which a lesson link
    points at."""
    return f"subgoal-{subgoal_id}"


def render(reference: dict, lang: str, titles: dict[str, dict]) -> list[str]:
    """The lines between the reference markers, without indentation: one
    closed <details> per group, its items in a <dl>. [titles] are the live
    goals' and subgoals' texts in [lang] (curriculum.texts_for); a lesson
    that is not among them gets no link."""
    lines = ['<div class="reference">']
    for group in reference["groups"]:
        lines += [
            '  <details class="reference-group">',
            f'    <summary><span class="reference-title">{_text(group["title"].get(lang) or group["title"]["nl"])}</span></summary>',
            '    <div class="reference-body">',
        ]
        if group.get("setup"):
            lines.append(f"      {_code(group['setup'])}")
        lines.append('      <dl class="reference-items">')
        for item in group["items"]:
            summary = (item.get("summary") or {}).get(lang) or (item.get("summary") or {}).get("nl") or ""
            lines += [
                "        <div>",
                f"          <dt><code>{html.escape(written(group, item), quote=False)}</code></dt>",
                "          <dd>",
                f"            <p>{_text(summary)}</p>",
            ]
            if item.get("example"):
                lines.append(f"            {_code(item['example'])}")
            lesson = item.get("lesson")
            if lesson and lesson in titles:
                lines.append(
                    f'            <p class="reference-lesson">{LABELS[lang]["lesson"]} '
                    f'<a href="#{subgoal_anchor(lesson)}">{_text(titles[lesson]["title"])}</a></p>'
                )
            lines += ["          </dd>", "        </div>"]
        lines += ["      </dl>", "    </div>", "  </details>"]
    lines.append("</div>")
    return lines
