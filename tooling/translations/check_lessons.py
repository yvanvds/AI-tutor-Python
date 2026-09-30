"""Checks a translated lesson against its Dutch original (#209).

For every lesson with a file in `lessons/<module>/<lang>/`:

1. **Structure**: the translation has exactly the same HTML tags, in the
   same order, as the Dutch body (headings, `callout info|warn|tip`, code
   blocks, tables), and says `<html lang="<lang>">`.
2. **Code**: every code block runs, in both languages, and prints what the
   lesson says it prints. A block followed by an "Output:" / "Uitvoer:" block
   must print exactly that; an error in such a block counts as its last line
   (`IndexError: list index out of range`). Blocks that read `input()` get
   the stdin in [CASES]; claims the text makes in prose ("the script shows
   `The average is 8.5`") are in [CASES] too. The blocks of one lesson run
   in one namespace, in order, because later blocks use earlier variables.
   `turtle` is a headless stub that follows the turtle, so a drawing that
   should close (a square) is checked to end where it started.
3. **Inline claims** in [INLINE]: short inline snippets whose result the
   text states (`"5" == 5` gives `False`, `int("3.5")` fails, ...).

    python tooling/translations/check_lessons.py            # en against nl
    python tooling/translations/check_lessons.py --lang en --verbose

Exit status 0 when everything passes.
"""

from __future__ import annotations

import argparse
import ast
import builtins
import contextlib
import html
import io
import math
import re
import sys
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from translations import lessons  # noqa: E402

_PRE = re.compile(r"<pre><code>([\s\S]*?)</code></pre>")
_TAG = re.compile(r"<[^>]+>")
_OUTPUT_LABEL = re.compile(r"(Output|output|Uitvoer|uitvoer):\s*</p>\s*$")

# Per lesson, per code block (index among the code blocks, output blocks not
# counted): stdin, expected output from the prose, an expected error, or a
# check. Language-specific values are {"nl": ..., "en": ...}.
CASES: dict[str, dict[int, dict]] = {
    "variabelen": {5: {"expect": ""}},
    "invoer-input": {
        0: {"stdin": {"nl": ["Mira"], "en": ["Mira"]}, "expect": {"nl": "Hallo Mira", "en": "Hello Mira"}},
        1: {"stdin": ["16"], "error": "TypeError"},
        2: {"stdin": ["5", "3"], "expect": "53"},
        3: {"stdin": ["16"], "expect": {"nl": "Volgend jaar word je 17", "en": "Next year you will be 17"}},
        4: {"stdin": ["3.5"], "expect": {"nl": "In gram: 3500.0", "en": "In grams: 3500.0"}},
    },
    "klein-script": {
        0: {"stdin": ["7", "10"], "expect": {"nl": "Het gemiddelde is 8.5", "en": "The average is 8.5"}},
        1: {"stdin": ["2.5", "4"], "expect": {"nl": "Totaal: 10.0 euro", "en": "Total: 10.0 euro"}},
        2: {"stdin": ["5", "3"], "expect": "53"},
    },
    "elif-samengestelde-voorwaarden": {
        # "With score = 95 both conditions are true, but only excellent is shown."
        0: {"variant": ("score = 65", "score = 95"), "variant_expect": {"nl": "uitstekend", "en": "excellent"}},
    },
    "tekenen-turtle": {
        0: {"turtle": {"segments": 1}},
        1: {"turtle": {"segments": 4, "closed": True}},
        2: {"stdin": {"nl": ["rood"], "en": ["red"]}, "turtle": {"colors": ["red"]}},
    },
    "herhalen-for": {2: {"turtle": {"segments": 4, "closed": True}}},
    "herhalen-while": {
        1: {"infinite": True},
        2: {"stdin": ["12", "5"], "expect": {"nl": "Gekozen: 5", "en": "Chosen: 5"}},
    },
    "testen-debuggen": {0: {"stdin": ["4", "6"]}},  # its output block: "Average: 7.0"
    "probleem-naar-programma": {
        0: {"stdin": ["3", "5", "0"], "expect": {"nl": "Som: 8", "en": "Sum: 8"}},
    },
    "lijsten-doorlopen": {
        6: {"turtle": {"segments": 4, "colors": ["red", "orange", "green", "blue"], "lengths": [50, 100, 150, 200]}},
    },
    "geneste-lussen": {1: {"lines": 9}},
}

# Inline code whose result the prose states, run in the lesson's namespace
# after its blocks: (language, code, expected repr or exception name).
INLINE: dict[str, list[tuple[str, str, str]]] = {
    "uitvoer-print": [
        ("nl", "print(hallo)", "NameError"),
        ("en", "print(hello)", "NameError"),
        ("*", 'print("score: " + 5)', "TypeError"),
    ],
    "variabelen": [("*", "pi = 3,14; pi", "(3, 14)")],
    "rekenen-getallen": [("*", "8 / 2", "4.0"), ("*", "8 // 2", "4"), ("*", "2 ^ 3", "1")],
    "invoer-input": [
        ("*", 'int("16")', "16"),
        ("nl", 'int("zestien")', "ValueError"),
        ("en", 'int("sixteen")', "ValueError"),
        ("*", 'int("3.5")', "ValueError"),
        ("*", 'float("3,14")', "ValueError"),
    ],
    "vergelijkingen-booleans": [("*", '"5" == 5', "False")],
    "beslissingen-if-else": [
        ("nl", "if getal = 5:\n    pass", "SyntaxError"),
        ("en", "if number = 5:\n    pass", "SyntaxError"),
    ],
    "elif-samengestelde-voorwaarden": [("*", "x = 7; bool(x == 5 or 6)", "True")],
    "lijsten-indexeren": [
        ("nl", "punten[len(punten)]", "IndexError"),
        ("en", "scores[len(scores)]", "IndexError"),
        ("nl", "punten[len(punten) - 1] == punten[-1]", "True"),
        ("en", "scores[len(scores) - 1] == scores[-1]", "True"),
    ],
    "lijsten-aanpassen": [
        ("*", "l = [3, 0, 1]; l.remove(0); l", "[3, 1]"),
        ("*", "l = [3, 0, 1]; l.pop(0); l", "[0, 1]"),
        ("nl", "temperaturen = temperaturen.sort(); temperaturen", "None"),
        ("en", "temperatures = temperatures.sort(); temperatures", "None"),
        ("nl", 'boodschappen.remove("vis")', "ValueError"),
        ("en", 'groceries.remove("fish")', "ValueError"),
    ],
    "lijstpatronen": [
        ("nl", "getallen = [-4, -11, -2]\ngrootste = 0\nfor getal in getallen:\n    if getal > grootste:\n        grootste = getal\ngrootste", "0"),
        ("en", "numbers = [-4, -11, -2]\nlargest = 0\nfor number in numbers:\n    if number > largest:\n        largest = number\nlargest", "0"),
    ],
    "tuples": [
        ("*", "(5)", "5"),
        ("*", "(5,)", "(5,)"),
        ("nl", 'woord = "python"; woord[0] = "m"', "TypeError"),
        ("en", 'word = "python"; word[0] = "m"', "TypeError"),
        ("nl", 'kleuren = ["rood", "groen", "blauw"]; kleuren[0], kleuren[2] = kleuren[2], kleuren[0]; kleuren', "['blauw', 'groen', 'rood']"),
        ("en", 'colors = ["red", "green", "blue"]; colors[0], colors[2] = colors[2], colors[0]; colors', "['blue', 'green', 'red']"),
        ("*", "a = [1, 2, 3]; b = a[:]; b.append(4); a", "[1, 2, 3]"),
    ],
    "geneste-lussen": [
        ("nl", "rooster = [[1, 2, 3], [4, 5, 6]]; rooster[2][1]", "IndexError"),
        ("en", "grid = [[1, 2, 3], [4, 5, 6]]; grid[2][1]", "IndexError"),
    ],
}


def _pick(value, lang: str):
    return value[lang] if isinstance(value, dict) else value


# ---- turtle ------------------------------------------------------------------


class _Pen:
    """Headless turtle: follows position and heading, records the segments
    drawn with the pen down and their colors."""

    def __init__(self, log: list):
        self.x = self.y = 0.0
        self.heading = 0.0
        self.down = True
        self.color = "black"
        self.log = log

    def _move(self, d):
        nx = self.x + d * math.cos(math.radians(self.heading))
        ny = self.y + d * math.sin(math.radians(self.heading))
        if self.down:
            self.log.append({"length": d, "color": self.color})
        self.x, self.y = nx, ny

    def forward(self, d):
        self._move(d)

    def backward(self, d):
        self._move(-d)

    def left(self, a):
        self.heading += a

    def right(self, a):
        self.heading -= a

    def penup(self):
        self.down = False

    def pendown(self):
        self.down = True

    def pencolor(self, c):
        self.color = c


def _turtle_module(state: dict) -> types.ModuleType:
    m = types.ModuleType("turtle")

    def make():
        pen = _Pen(state.setdefault("segments", []))
        state["pen"] = pen
        return pen

    m.Turtle = make
    m.done = lambda: state.__setitem__("done", True)
    return m


# ---- running -----------------------------------------------------------------


class _TooMuchOutput(Exception):
    pass


def _run(code: str, ns: dict, stdin: list[str], max_lines: int = 2000) -> tuple[str, str | None]:
    """Runs [code] in [ns]. Returns (stdout, error line or None)."""
    feed = list(stdin)
    buf = io.StringIO()
    count = [0]

    def fake_input(prompt=""):
        if not feed:
            raise EOFError("no stdin left for input()")
        return feed.pop(0)

    def fake_print(*args, **kw):
        count[0] += 1
        if count[0] > max_lines:
            raise _TooMuchOutput()
        builtins.print(*args, **kw, file=buf)

    ns["input"] = fake_input
    ns["print"] = fake_print
    err = None
    try:
        exec(compile(code, "<lesson>", "exec"), ns)
    except _TooMuchOutput:
        err = "_TooMuchOutput"
    except SyntaxError as e:
        err = f"SyntaxError: {e.msg}"
    except Exception as e:  # noqa: BLE001 — a lesson may show any error
        err = f"{type(e).__name__}: {e}"
    return buf.getvalue(), err


def _eval_inline(code: str, ns: dict) -> str:
    """The repr of [code]'s last expression (`None` when it ends in a
    statement), or the name of the error it raises, a SyntaxError included."""
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return "SyntaxError"
    try:
        if tree.body and isinstance(tree.body[-1], ast.Expr):
            last = ast.Expression(tree.body.pop().value)
            exec(compile(tree, "<inline>", "exec"), ns)
            return repr(eval(compile(last, "<inline>", "eval"), ns))
        exec(compile(tree, "<inline>", "exec"), ns)
        return "None"
    except Exception as e:  # noqa: BLE001 — the claim may be any error
        return type(e).__name__


def split_blocks(body: str) -> list[dict]:
    """The code blocks of [body], each with the output block after it."""
    blocks: list[dict] = []
    last_end = 0
    for m in _PRE.finditer(body):
        text = html.unescape(m.group(1))
        between = body[last_end : m.start()]
        if blocks and _OUTPUT_LABEL.search(between) and blocks[-1]["output"] is None:
            blocks[-1]["output"] = text
        else:
            blocks.append({"code": text, "output": None})
        last_end = m.end()
    return blocks


def check_lesson(lid: str, body: str, lang: str, verbose: bool = False) -> tuple[int, list[str]]:
    """Runs the blocks of one lesson. Returns (blocks run, failures)."""
    failures: list[str] = []
    ns: dict = {"__name__": "__lesson__"}
    state: dict = {}
    sys.modules["turtle"] = _turtle_module(state)
    blocks = split_blocks(body)
    cases = CASES.get(lid, {})
    for i, b in enumerate(blocks):
        case = cases.get(i, {})
        where = f"{lang}/{lid} block {i}"
        state.clear()
        stdin = _pick(case.get("stdin", []), lang)
        code = b["code"]
        out, err = _run(code, ns, stdin)
        shown = out + (err + "\n" if err and err != "_TooMuchOutput" else "")
        if case.get("infinite"):
            if err != "_TooMuchOutput":
                failures.append(f"{where}: meant to loop forever, but stopped ({err or 'no error'})")
            continue
        if err == "_TooMuchOutput":
            failures.append(f"{where}: does not stop")
            continue
        expected_error = case.get("error")
        if expected_error:
            if not err or not err.startswith(expected_error):
                failures.append(f"{where}: expected {expected_error}, got {err or 'no error'}")
        elif err and b["output"] is None:
            failures.append(f"{where}: {err}")
        if b["output"] is not None and shown.rstrip("\n") != b["output"].rstrip("\n"):
            failures.append(f"{where}: prints\n{shown.rstrip()}\n  but the lesson shows\n{b['output'].rstrip()}")
        if "expect" in case and out.rstrip("\n") != _pick(case["expect"], lang):
            failures.append(f"{where}: prints {out.rstrip()!r}, the text says {_pick(case['expect'], lang)!r}")
        if "lines" in case and len(out.splitlines()) != case["lines"]:
            failures.append(f"{where}: prints {len(out.splitlines())} lines, the text says {case['lines']}")
        if "turtle" in case:
            t = case["turtle"]
            segs = state.get("segments", [])
            pen = state.get("pen")
            if not state.get("done"):
                failures.append(f"{where}: turtle script without turtle.done()")
            if "segments" in t and len(segs) != t["segments"]:
                failures.append(f"{where}: draws {len(segs)} lines, expected {t['segments']}")
            if t.get("closed") and pen and (abs(pen.x) > 1e-6 or abs(pen.y) > 1e-6):
                failures.append(f"{where}: the figure does not close ({pen.x:.1f}, {pen.y:.1f})")
            if "colors" in t and [s["color"] for s in segs][: len(t["colors"])] != t["colors"]:
                failures.append(f"{where}: colors {[s['color'] for s in segs]}, expected {t['colors']}")
            if "lengths" in t and [s["length"] for s in segs] != t["lengths"]:
                failures.append(f"{where}: lengths {[s['length'] for s in segs]}, expected {t['lengths']}")
        if "variant" in case:
            old, new = case["variant"]
            if old not in code:
                failures.append(f"{where}: variant needs {old!r} in the block")
            else:
                vout, verr = _run(code.replace(old, new), dict(ns), stdin)
                want = _pick(case["variant_expect"], lang)
                if verr or vout.rstrip("\n") != want:
                    failures.append(f"{where}: with {new!r} prints {vout.rstrip()!r}, the text says {want!r}")
        if verbose:
            print(f"  {where}: ok" if not any(f.startswith(where + ":") for f in failures) else f"  {where}: FAIL")
    for claim_lang, code, want in INLINE.get(lid, []):
        if claim_lang not in ("*", lang):
            continue
        got = _eval_inline(code, dict(ns))
        if got != want:
            failures.append(f"{lang}/{lid} inline {code!r}: gives {got}, the text says {want}")
    sys.modules.pop("turtle", None)
    return len(blocks), failures


def tags(body: str) -> list[str]:
    return _TAG.findall(body)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lang", default="en")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args(argv)

    nl = lessons("nl")
    tr = lessons(args.lang)
    failures: list[str] = []
    runs = {"nl": 0, args.lang: 0}
    inline = {"nl": 0, args.lang: 0}
    for lid in sorted(set(nl) | set(tr)):
        if lid not in tr:
            failures.append(f"{lid}: no {args.lang} file")
            continue
        if lid not in nl:
            failures.append(f"{lid}: {args.lang} file without a Dutch lesson")
            continue
        if tr[lid]["lang"] != args.lang:
            failures.append(f"{lid}: <html lang={tr[lid]['lang']!r}>")
        if tags(nl[lid]["body"]) != tags(tr[lid]["body"]):
            a, b = tags(nl[lid]["body"]), tags(tr[lid]["body"])
            at = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
            failures.append(f"{lid}: HTML structure differs at tag {at}: nl {a[at:at+3]} vs {args.lang} {b[at:at+3]}")
        for lang, body in (("nl", nl[lid]["body"]), (args.lang, tr[lid]["body"])):
            n, f = check_lesson(lid, body, lang, args.verbose)
            runs[lang] += n
            inline[lang] += sum(1 for c, _, _ in INLINE.get(lid, []) if c in ("*", lang))
            failures.extend(f)
    print(
        f"{len(tr)} {args.lang} lessons: structure checked against nl; code blocks run: "
        f"{runs[args.lang]} {args.lang} + {runs['nl']} nl; inline claims: "
        f"{inline[args.lang]} {args.lang} + {inline['nl']} nl"
    )
    for f in failures:
        print("FAIL", f)
    print("all pass" if not failures else f"{len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
