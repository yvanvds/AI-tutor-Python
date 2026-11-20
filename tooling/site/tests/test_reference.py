"""Tests for the reference (#323): the check that says what a live lesson
uses and the reference lacks, the "Naslag" section of the start pages, and
the reference file itself. Standard library only:

    python -m unittest discover -s tooling/site/tests
"""

from __future__ import annotations

import copy
import json
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[1] / "translations"))

import check_lessons  # noqa: E402
import curriculum  # noqa: E402
import reference  # noqa: E402

REF = reference.load()
LIVE = curriculum.load_goals(list(curriculum.LIVE_GOALS))


def _group(gid: str, kind: str, items: list[dict], setup: str | None = None) -> dict:
    g = {"id": gid, "kind": kind, "title": {"nl": gid, "en": gid}, "items": items}
    if setup:
        g["setup"] = setup
    return g


def _item(name: str, kind: str = "function", lesson: str | None = None, **extra) -> dict:
    item = {
        "name": name,
        "kind": kind,
        "signature": f"{name}()",
        "summary": {"nl": f"{name} nl", "en": f"{name} en"},
        "example": f"{name}()",
        **extra,
    }
    if lesson:
        item["lesson"] = lesson
    return item


def _lesson(subgoal: str, *code: str, prose: str = "") -> dict:
    blocks = "".join(f"<pre><code>{c}</code></pre>" for c in code)
    return {"goal": "g", "number": 1, "subgoal": subgoal, "body": f"<p>{prose}</p>{blocks}"}


# A small reference with the shapes of the real one.
SMALL = {
    "version": 1,
    "groups": [
        _group("builtins", "builtins", [_item("print", lesson="eerste"), _item("sorted")]),
        _group("list", "type", [_item("append", "method", lesson="lijsten"), _item("pop", "method")]),
        _group("dict", "type", [_item("pop", "method")]),
        _group("random", "module", [_item("randint", lesson="toeval")], setup="import random"),
        _group("matplotlib.pyplot", "module", [_item("plot", lesson="grafiek")],
               setup="import matplotlib.pyplot as plt"),
    ],
}
LESSONS = [
    _lesson("eerste", 'print("hallo")'),
    _lesson("lijsten", "a = [1, 2]\na.append(3)\nprint(a)"),
    _lesson("toeval", "import random\nprint(random.randint(1, 6))"),
    _lesson("grafiek", "import matplotlib.pyplot as plt\nplt.plot([1, 2], [3, 4])"),
]


class Uses(unittest.TestCase):
    def uses(self, *code: str, ref: dict = SMALL) -> set[str]:
        return reference.lesson_uses([_lesson("x", *code)], ref)["x"]

    def test_builtins_modules_and_aliases(self):
        self.assertEqual(
            self.uses("import matplotlib.pyplot as plt\nimport math\nplt.plot([1], [math.sqrt(4)])\nprint(math.pi)"),
            {"matplotlib.pyplot.plot", "math.sqrt", "math.pi", "builtins.print"},
        )

    def test_a_from_import_and_a_module_named_in_the_text(self):
        # `turtle.done()` in a sentence of a lesson that does not import turtle.
        self.assertEqual(self.uses("from random import randint\nx = randint(1, 2)", ref=REF) - {"builtins.print"},
                         {"random.randint"})
        self.assertEqual(self.uses("turtle.done()", ref=REF), {"turtle.done"})

    def test_a_method_on_a_value_of_a_known_type(self):
        self.assertEqual(self.uses("a = [3]\na.pop()\nd = {1: 2}\nd.pop(1)\n'x'.upper()", ref=REF),
                         {"list.pop", "dict.pop", "str.upper"})
        # A type the reference has no group for is no type: `.upper` alone.
        self.assertEqual(self.uses("'x'.upper()"), {".upper"})

    def test_a_method_on_a_value_of_unknown_type(self):
        self.assertEqual(self.uses("def f(a):\n    a.append(1)\n    return a"), {".append"})

    def test_a_name_assigned_two_types_is_unknown(self):
        self.assertEqual(self.uses("a = [1]\na = 'x'\na.pop()"), {".pop"})

    def test_a_call_that_gives_a_type_from_the_reference(self):
        self.assertEqual(self.uses("import turtle\nt = turtle.Turtle()\nt.forward(10)", ref=REF),
                         {"turtle.Turtle", "turtle.Turtle.forward"})

    def test_own_functions_output_and_errors_are_not_uses(self):
        self.assertEqual(self.uses("def max(a):\n    return a\nmax(3)", "5\nTraceback (most recent call last):"), set())

    def test_a_module_itself_is_not_an_item(self):
        self.assertEqual(self.uses("import matplotlib.pyplot\nmatplotlib.pyplot.show()"),
                         {"matplotlib.pyplot.show"})


class Check(unittest.TestCase):
    def test_a_complete_reference_has_no_problem_and_notes_what_no_lesson_uses(self):
        problems, notes = reference.check(SMALL, LESSONS)
        self.assertEqual(problems, [])
        self.assertEqual(notes, ["in no live lesson yet, so without a lesson: builtins.sorted, list.pop, dict.pop"])

    def test_what_a_new_live_lesson_uses_and_the_reference_lacks(self):
        lessons = LESSONS + [_lesson("nieuw", "import random\nrandom.shuffle([1])\nprint(abs(-1))\n'a,b'.split(',')")]
        problems, _ = reference.check(SMALL, lessons)
        self.assertEqual(sorted(problems), [
            "abs() (used in nieuw) is not in the reference",
            "random.shuffle (used in nieuw) is not in the reference",
            "the method split (used in nieuw) is in no type group",
        ])

    def test_a_method_no_type_group_has(self):
        problems, _ = reference.check(SMALL, LESSONS + [_lesson("nieuw", "def f(s):\n    return s.strip()")])
        self.assertEqual(problems, ["the method strip (used in nieuw) is in no type group"])

    def test_an_item_a_live_lesson_uses_needs_a_lesson(self):
        ref = copy.deepcopy(SMALL)
        del ref["groups"][0]["items"][1]  # sorted: not the point here
        lessons = LESSONS + [_lesson("later", "a = [2, 1]\nprint(a.pop())\nd = {1: 2}\nd.pop(1)")]
        problems, notes = reference.check(ref, lessons)
        self.assertEqual(problems, [
            "list.pop: no lesson, and live lessons use it (first: later)",
            "dict.pop: no lesson, and live lessons use it (first: later)",
        ])
        self.assertEqual(notes, [])

    def test_a_pop_of_unknown_type_does_not_count_for_the_dict(self):
        # `.pop` may be a list's or a dict's: it makes neither "used".
        lessons = LESSONS + [_lesson("onbekend", "def f(x):\n    return x.pop()")]
        _, notes = reference.check(SMALL, lessons)
        self.assertIn("dict.pop", notes[0])

    def test_texts_examples_and_titles(self):
        ref = copy.deepcopy(SMALL)
        plot = ref["groups"][4]["items"][0]
        del plot["summary"]["en"]
        plot["example"] = " "
        ref["groups"][1]["title"] = {"nl": "Lijsten"}
        problems, _ = reference.check(ref, LESSONS)
        self.assertEqual(sorted(problems), [
            "group list: no en title",
            "matplotlib.pyplot.plot: no en summary",
            "matplotlib.pyplot.plot: no example",
        ])

    def test_a_lesson_link_that_does_not_hold(self):
        ref = copy.deepcopy(SMALL)
        ref["groups"][3]["items"][0]["lesson"] = "eerste"  # randint: not used there
        ref["groups"][4]["items"][0]["lesson"] = "nooit-live"
        problems, _ = reference.check(ref, LESSONS)
        self.assertEqual(problems, [
            "random.randint: its lesson eerste does not use it",
            "matplotlib.pyplot.plot: its lesson nooit-live is not a subgoal of a live goal",
        ])


class TheRealReference(unittest.TestCase):
    """The file the app ships with, against the lessons of the live goals."""

    def test_it_is_complete_for_the_live_goals(self):
        problems, _ = curriculum.check_reference(LIVE, REF)
        self.assertEqual(problems, [])

    def test_every_group_kind_and_item_kind_is_one_the_app_reads(self):
        for group in REF["groups"]:
            self.assertIn(group["kind"], ("builtins", "type", "module"), group["id"])
            for item in group["items"]:
                self.assertIn(item["kind"], ("function", "method", "class", "constant"), item["name"])

    def test_how_an_item_is_written(self):
        groups = {g["id"]: g for g in REF["groups"]}

        def written(gid, name):
            group = groups[gid]
            return reference.written(group, next(i for i in group["items"] if i["name"] == name))

        self.assertEqual(written("matplotlib.pyplot", "plot"), "plt.plot(x, y, label=..., color=...)")
        self.assertEqual(written("numpy", "linspace"), "np.linspace(start, stop, num)")
        self.assertEqual(written("random", "randint"), "random.randint(a, b)")
        self.assertEqual(written("turtle.Turtle", "forward"), ".forward(distance)")
        self.assertEqual(written("builtins", "len"), "len(s)")

    def test_every_example_runs_and_prints_what_its_comments_say(self):
        """Each example runs after its group's setup, on the headless turtle
        and pyplot of check_lessons.py. A comment on a line that prints, or
        on a line of its own, is output: in order, it is what the example
        prints (spaces and line breaks aside). numpy's need numpy."""
        numpy = check_lessons.has_numpy()
        ran = 0
        for group in REF["groups"]:
            for item in group["items"]:
                example = item["example"]
                code = f"{group.get('setup') or ''}\n{example}"
                if "numpy" in code and not numpy:
                    continue
                with self.subTest(item=reference.key(group, item)):
                    stdout = self._run(code)
                    printed = " ".join(stdout.split())
                    at = 0
                    for comment in self._output_comments(example):
                        found = printed.find(comment, at)
                        self.assertGreaterEqual(found, 0, f"{comment!r} not in {printed[at:]!r}")
                        at = found + len(comment)
                    ran += 1
        self.assertGreater(ran, 50)

    @staticmethod
    def _output_comments(example: str) -> list[str]:
        out = []
        for line in example.split("\n"):
            code, sep, comment = line.partition("# ")
            if sep and ("print(" in code or not code.strip()):
                out.append(" ".join(comment.split()))
        return out

    @staticmethod
    def _run(code: str) -> str:
        state: dict = {}
        saved = {name: sys.modules.get(name) for name in ("turtle", "matplotlib", "matplotlib.pyplot")}
        sys.modules["turtle"] = check_lessons._turtle_module(state)
        package = check_lessons.types.ModuleType("matplotlib")
        package.pyplot = check_lessons._pyplot_module(state)
        sys.modules["matplotlib"], sys.modules["matplotlib.pyplot"] = package, package.pyplot
        try:
            stdout, error = check_lessons._run(code, {"__name__": "__main__"}, ["5"])
        finally:
            for name, module in saved.items():
                if module is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = module
        if error:
            raise AssertionError(f"{error}\n{code}")
        return stdout

    def test_examples_define_functions_that_return(self):
        """A function is "iets erin, iets eruit": no print or input inside
        one, as in the lessons (turtle drawing is the one exception)."""
        for group in REF["groups"]:
            for item in group["items"]:
                for fn in re.finditer(r"^def [\s\S]*?(?=^\S|\Z)", item["example"], re.MULTILINE):
                    self.assertNotRegex(fn.group(0), r"\b(print|input)\(", reference.key(group, item))


class Site(unittest.TestCase):
    def test_the_markup_of_a_group(self):
        lines = reference.render(SMALL, "en", {"grafiek": {"title": "A first chart <1>"}})
        text = "\n".join(lines)
        self.assertIn('<summary><span class="reference-title">matplotlib.pyplot</span></summary>', text)
        self.assertIn('<div class="code"><pre><code>import matplotlib.pyplot as plt</code></pre></div>', text)
        self.assertIn("<dt><code>plt.plot()</code></dt>", text)
        # A lesson that is live is a link to its subgoal; one that is not, no link.
        self.assertIn('<p class="reference-lesson">Lesson: <a href="#subgoal-grafiek">A first chart &lt;1&gt;</a></p>',
                      text)
        self.assertNotIn("#subgoal-toeval", text)

    def test_code_keeps_its_lines_on_one_line_of_the_page(self):
        ref = copy.deepcopy(SMALL)
        ref["groups"][0]["items"][0]["example"] = 'for i in range(2):\n    print(i < 1)'
        lines = reference.render(ref, "nl", {})
        self.assertIn('<div class="code"><pre><code>for i in range(2):&#10;    print(i &lt; 1)</code></pre></div>',
                      "\n".join(lines))

    def test_code_spans_in_a_summary(self):
        ref = copy.deepcopy(SMALL)
        ref["groups"][0]["items"][0]["summary"]["nl"] = "Met `sep=` kies je   wat <ertussen> komt."
        self.assertIn("<p>Met <code>sep=</code> kies je wat &lt;ertussen&gt; komt.</p>",
                      "\n".join(reference.render(ref, "nl", {})))

    def test_every_subgoal_of_the_list_has_the_id_a_lesson_link_points_at(self):
        lines = curriculum.render(LIVE, curriculum.texts_for(LIVE, "nl"), "nl")
        for entry in LIVE:
            for sub in entry["subgoals"]:
                self.assertIn(f'<div id="subgoal-{sub["id"]}">', "\n".join(lines))

    def test_the_start_pages_are_up_to_date(self):
        """What curriculum.py would write is what is committed: a change to
        the reference file comes with its site."""
        for lang, page in curriculum.PAGES.items():
            text = page.read_bytes().decode("utf-8")
            texts = curriculum.texts_for(LIVE, lang)
            filled = curriculum.fill_page(text, curriculum.render(LIVE, texts, lang), page.name)
            filled = curriculum.fill_page(filled, reference.render(REF, lang, texts), page.name,
                                          curriculum.REFERENCE_START, curriculum.REFERENCE_END)
            self.assertEqual(filled, text, f"run python tooling/site/curriculum.py ({page.name})")

    def test_no_page_is_written_while_the_reference_lacks_something(self):
        incomplete = copy.deepcopy(REF)
        for group in incomplete["groups"]:
            if group["id"] == "random":
                group["items"] = [i for i in group["items"] if i["name"] != "uniform"]
        with tempfile.TemporaryDirectory() as tmp:
            page = Path(tmp) / "index.html"
            original = curriculum.PAGES["nl"].read_bytes()
            page.write_bytes(original)
            err = StringIO()
            with mock.patch.object(reference, "load", return_value=incomplete), \
                    redirect_stdout(StringIO()), redirect_stderr(err):
                status = curriculum.main(["--lang", "nl", "--page", str(page)])
            self.assertEqual(status, 1)
            self.assertEqual(page.read_bytes(), original)
            self.assertIn("random.uniform (used in oppervlakte-schatten) is not in the reference", err.getvalue())
            self.assertIn("No page was written.", err.getvalue())

    def test_check_reference_reports_and_writes_nothing(self):
        out, err = StringIO(), StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            self.assertEqual(curriculum.main(["--check-reference"]), 0)
        self.assertIn("reference complete for 01-eenvoudige-python-scripts", out.getvalue())
        self.assertIn("note: in no live lesson yet, so without a lesson: builtins.sorted", out.getvalue())
        self.assertEqual(err.getvalue(), "")

    def test_a_new_live_goal_whose_lesson_uses_something_new(self):
        """The goal-live steps (ROADMAP 6 and 7): a goal file and its lesson
        are added; the check names what the reference lacks."""
        with tempfile.TemporaryDirectory() as tmp:
            goals, lessons = Path(tmp) / "goals", Path(tmp) / "lessons"
            goals.mkdir()
            (lessons / "09-tijdstappen").mkdir(parents=True)
            (goals / "09-tijdstappen.json").write_text(json.dumps({
                "goal": {"id": "tijdstappen", "title": "T", "description": "D", "order": 9000},
                "subgoals": [{"id": "groei", "title": "G", "description": "D", "order": 1000}],
            }), encoding="utf-8")
            (lessons / "09-tijdstappen" / "01-groei.html").write_text(
                "<html><body><pre><code>import math\nprint(math.exp(1))\nd = {'a': 1}\n"
                "print(d.get('a'))</code></pre></body></html>", encoding="utf-8")
            new = curriculum.load_goals(["09-tijdstappen"], goals)
            lessons = reference.lesson_files(LIVE) + reference.lesson_files(new, lessons)
            problems, _ = reference.check(REF, lessons)
        self.assertEqual(problems, [
            "math.exp (used in groei) is not in the reference",
            "dict.get: no lesson, and live lessons use it (first: groei)",
        ])


if __name__ == "__main__":
    unittest.main()
