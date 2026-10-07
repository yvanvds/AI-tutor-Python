"""Tests for the translation tooling (#209): the `sourceHash` against the
app's own test vectors, the docs it would write (lessons, goals and, since
#250, learning-objective statements), create-only pushing, and the lesson
checker. Standard library only:

    python -m unittest discover -s tooling/translations/tests

No test touches the live account: a fake `cosmos` module takes the place of
`tooling/evaluation/cosmos.py`, which would read `.env` on import.
"""

from __future__ import annotations

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

import check_lessons  # noqa: E402
import translations  # noqa: E402

SHELL = """<!doctype html>\r
<html lang="{lang}">\r
<head>\r
<meta charset="utf-8">\r
<title>{title}</title>\r
</head>\r
<body class="lesson">\r
{body}\r
</body>\r
</html>\r
"""

NL_BODY = "<p>Een lijst.</p>\r\n<pre><code>x = [1, 2]\r\nprint(x)</code></pre>\r\n<p>Uitvoer:</p>\r\n<pre><code>[1, 2]</code></pre>"
EN_BODY = "<p>A list.</p>\r\n<pre><code>x = [1, 2]\r\nprint(x)</code></pre>\r\n<p>Output:</p>\r\n<pre><code>[1, 2]</code></pre>"

LIVE_CONTENT = [
    {"id": "lijsten", "type": "content", "title": "Lijsten", "body": NL_BODY, "updatedAt": "2026-09-23T20:04:51Z"},
]
FOR_LOOP_NL = "Je kan een for-lus schrijven die een bewerking een vast aantal keer herhaalt."
LIVE_GOALS = [
    {"id": "root", "title": "Hoofddoel", "description": None, "parentId": None},
    {
        "id": "lijsten",
        "title": "Lijsten",
        "description": "Je kan een lijst maken.",
        "parentId": "root",
        "objectives": [
            {"id": "predict_index_value", "statement": "Je kan voorspellen welk element lijst[i] oplevert.",
             "kind": "predict", "weight": 1.0, "optional": False},
            {"id": "write_for_loop", "statement": FOR_LOOP_NL, "kind": "apply", "weight": 1.0, "optional": False},
        ],
    },
]
TEXTS = [
    {"id": "root", "nl": {"title": "Hoofddoel", "description": ""}, "en": {"title": "Main goal", "description": ""}},
    {
        "id": "lijsten",
        "nl": {"title": "Lijsten", "description": "Je kan een lijst maken."},
        "en": {"title": "Lists", "description": "You can make a list."},
        "objectives": [
            {"id": "predict_index_value", "nl": "Je kan voorspellen welk element lijst[i] oplevert.",
             "en": "You can predict which element my_list[i] gives."},
            {"id": "write_for_loop", "nl": FOR_LOOP_NL,
             "en": "You can write a for loop that repeats an operation a fixed number of times."},
        ],
    },
]
OBJECTIVE_IDS = ["objective_lijsten.predict_index_value", "objective_lijsten.write_for_loop"]


class _Exists(Exception):
    pass


def _fake_cosmos(store: dict | None = None) -> types.ModuleType:
    """Reads from LIVE_*; `translations` is [store], keyed `language/id`."""
    m = types.ModuleType("cosmos")
    m.Exists = _Exists
    m.store = {} if store is None else store
    m.creates = []

    def query(coll, sql, params=None, pk=None, cross=True):
        if coll == "content":
            return [dict(c) for c in LIVE_CONTENT]
        if coll == "goals":
            return [dict(g) for g in LIVE_GOALS]
        if coll == "translations":
            return [dict(d) for k, d in m.store.items() if pk is None or k.startswith(f"{pk}/")]
        raise AssertionError(coll)

    def create(coll, doc, pk):
        assert coll == "translations"
        m.creates.append(doc["id"])
        key = f"{pk}/{doc['id']}"
        if key in m.store:
            raise _Exists(doc["id"])
        m.store[key] = dict(doc)
        return doc

    def upsert(*a, **k):
        raise AssertionError("the translation tooling must never upsert")

    m.query, m.create, m.upsert = query, create, upsert
    return m


class SourceHashTest(unittest.TestCase):
    """The vectors pinned in test/services/translation/translation_test.dart."""

    def test_matches_the_dart_vector_line_endings_normalised(self):
        body = "<p>Een variabele is een doos.</p>\r\n<p>Één ding.</p>"
        want = "220e6ffa097b1396a5982f8baf0566150210b353685950bdf105f95a87f13973"
        self.assertEqual(translations.source_hash("Variabelen", body), want)
        self.assertEqual(translations.source_hash("Variabelen", body.replace("\r\n", "\n")), want)

    def test_a_goal_without_description_hashes_as_empty(self):
        want = "941ad07a66ce42e57501dd67f2b0aaf3472c1009fdbbadcf13080f215f2403c4"
        self.assertEqual(translations.source_hash("Lussen", ""), want)

    def test_the_separator_keeps_title_and_text_apart(self):
        self.assertNotEqual(
            translations.source_hash("Lussen H", "erhalen met for."),
            translations.source_hash("Lussen", "Herhalen met for."),
        )

    def test_an_lo_statement_hashes_with_an_empty_title(self):
        """`objectiveSourceHash` (#243): `source_hash('', statement)`."""
        want = "62df92465cc34d981136db5f95321525b64e6c4379cf2eb594e8424f55b9335c"
        self.assertEqual(translations.objective_hash(FOR_LOOP_NL), want)
        self.assertEqual(translations.source_hash("", FOR_LOOP_NL), want)


class _Repo(unittest.TestCase):
    """A temporary lessons tree and goal-texts file."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        mod = self.dir / "lessons" / "04-lijsten"
        (mod / "en").mkdir(parents=True)
        (mod / "01-lijsten.html").write_bytes(SHELL.format(lang="nl", title="Lijsten", body=NL_BODY).encode())
        (mod / "en" / "01-lijsten.html").write_bytes(SHELL.format(lang="en", title="Lists", body=EN_BODY).encode())
        self.texts = self.dir / "goal-texts.json"
        self.texts.write_text(json.dumps({"goals": TEXTS}), encoding="utf-8")
        patches = [
            mock.patch.object(translations, "LESSONS", self.dir / "lessons"),
            mock.patch.object(translations, "GOAL_TEXTS", self.texts),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.addCleanup(shutil.rmtree, self.dir)


class BuildDocsTest(_Repo):
    def build(self, content=None, goals=None, texts=None):
        return translations.build_docs(
            content or LIVE_CONTENT,
            goals or LIVE_GOALS,
            translations.lessons("nl"),
            translations.lessons("en"),
            texts or TEXTS,
            now="2026-09-30T17:00:00.000Z",
        )

    def test_body_is_the_trimmed_body_with_lf_endings(self):
        en = translations.lessons("en")["lijsten"]
        self.assertEqual(en["body"], EN_BODY.replace("\r\n", "\n"))
        self.assertEqual(en["title"], "Lists")
        self.assertEqual(en["lang"], "en")

    def test_docs_have_exactly_the_translation_fields(self):
        docs, problems = self.build()
        self.assertEqual(problems, [])
        by_id = {d["id"]: d for d in docs}
        self.assertEqual(
            by_id["content_lijsten"],
            {
                "id": "content_lijsten",
                "language": "en",
                "kind": "content",
                "refId": "lijsten",
                "title": "Lists",
                "body": EN_BODY.replace("\r\n", "\n"),
                "sourceHash": translations.source_hash("Lijsten", NL_BODY),
                "updatedAt": "2026-09-30T17:00:00.000Z",
            },
        )
        self.assertEqual(
            by_id["goal_lijsten"],
            {
                "id": "goal_lijsten",
                "language": "en",
                "kind": "goal",
                "refId": "lijsten",
                "title": "Lists",
                "description": "You can make a list.",
                "sourceHash": translations.source_hash("Lijsten", "Je kan een lijst maken."),
                "updatedAt": "2026-09-30T17:00:00.000Z",
            },
        )
        # A null description hashes as an empty one, as `goalSourceHash`.
        self.assertEqual(by_id["goal_root"]["sourceHash"], translations.source_hash("Hoofddoel", ""))

    def test_a_lesson_whose_dutch_file_drifted_is_left_out(self):
        live = [dict(LIVE_CONTENT[0], body=NL_BODY + "<p>Nieuw.</p>")]
        docs, problems = self.build(content=live)
        self.assertNotIn("content_lijsten", [d["id"] for d in docs])
        self.assertTrue(any("content lijsten" in p for p in problems))

    def test_a_goal_whose_dutch_text_drifted_is_left_out(self):
        live = [LIVE_GOALS[0], dict(LIVE_GOALS[1], description="Je kan een lijst aanpassen.")]
        docs, problems = self.build(goals=live)
        self.assertNotIn("goal_lijsten", [d["id"] for d in docs])
        self.assertTrue(any("goal lijsten" in p for p in problems))

    def test_live_goals_without_text_are_reported(self):
        live = LIVE_GOALS + [{"id": "extra", "title": "Extra", "description": "x"}]
        _, problems = self.build(goals=live)
        self.assertIn("goal extra: live goal without an English text", problems)


class ObjectiveDocsTest(_Repo):
    """#250: one `objective_<subgoal>.<lo>` doc per learning objective."""

    build = BuildDocsTest.build

    def test_an_lo_doc_has_exactly_the_fields_translation_objective_writes(self):
        docs, problems = self.build()
        self.assertEqual(problems, [])
        by_id = {d["id"]: d for d in docs}
        # Field for field `Translation.objective(...).toMap()`: no title.
        self.assertEqual(
            by_id["objective_lijsten.write_for_loop"],
            {
                "id": "objective_lijsten.write_for_loop",
                "language": "en",
                "kind": "objective",
                "refId": "lijsten.write_for_loop",
                "statement": "You can write a for loop that repeats an operation a fixed number of times.",
                "sourceHash": "62df92465cc34d981136db5f95321525b64e6c4379cf2eb594e8424f55b9335c",
                "updatedAt": "2026-09-30T17:00:00.000Z",
            },
        )
        self.assertEqual(sorted(i for i in by_id if i.startswith("objective_")), OBJECTIVE_IDS)

    def test_the_hash_is_of_the_live_statement_line_endings_normalised(self):
        crlf = "Je kan een lijst\r\nmaken."
        live = [LIVE_GOALS[0], dict(LIVE_GOALS[1], objectives=[{"id": "make", "statement": crlf}])]
        texts = [TEXTS[0], dict(TEXTS[1], objectives=[{"id": "make", "nl": "Je kan een lijst\nmaken.", "en": "x"}])]
        docs, problems = self.build(goals=live, texts=texts)
        self.assertEqual(problems, [])
        doc = next(d for d in docs if d["kind"] == "objective")
        self.assertEqual(doc["sourceHash"], translations.source_hash("", "Je kan een lijst\nmaken."))

    def test_an_lo_whose_dutch_statement_drifted_is_left_out(self):
        first, second = LIVE_GOALS[1]["objectives"]
        los = [dict(first), dict(second, statement="Je kan een for-lus schrijven.")]
        live = [LIVE_GOALS[0], dict(LIVE_GOALS[1], objectives=los)]
        docs, problems = self.build(goals=live)
        ids = [d["id"] for d in docs]
        self.assertNotIn("objective_lijsten.write_for_loop", ids)
        self.assertIn("objective_lijsten.predict_index_value", ids, "the other LO is not held back")
        self.assertIn("goal_lijsten", ids, "nor is the subgoal's own text")
        self.assertIn(
            "objective lijsten.write_for_loop: the Dutch statement in goal-texts.json differs from the live one",
            problems,
        )

    def test_a_drifted_subgoal_text_does_not_hold_back_its_los(self):
        live = [LIVE_GOALS[0], dict(LIVE_GOALS[1], description="Je kan een lijst aanpassen.")]
        docs, _ = self.build(goals=live)
        ids = [d["id"] for d in docs]
        self.assertNotIn("goal_lijsten", ids)
        self.assertTrue(set(OBJECTIVE_IDS) <= set(ids))

    def test_missing_extra_and_empty_statements_are_reported(self):
        los = LIVE_GOALS[1]["objectives"] + [{"id": "new_lo", "statement": "Je kan iets nieuws."}]
        live = [LIVE_GOALS[0], dict(LIVE_GOALS[1], objectives=los)]
        objs = [dict(TEXTS[1]["objectives"][0], en="  "), TEXTS[1]["objectives"][1],
                {"id": "gone_lo", "nl": "Je kan iets ouds.", "en": "You can do something old."}]
        texts = [TEXTS[0], dict(TEXTS[1], objectives=objs)]
        docs, problems = self.build(goals=live, texts=texts)
        self.assertEqual([d["id"] for d in docs if d["kind"] == "objective"], ["objective_lijsten.write_for_loop"])
        self.assertEqual(
            sorted(p for p in problems if p.startswith("objective")),
            [
                "objective lijsten.gone_lo: not in the live goals",
                "objective lijsten.new_lo: live learning objective without an English statement",
                "objective lijsten.predict_index_value: no English statement",
            ],
        )

    def test_the_same_lo_id_in_two_subgoals_gives_two_docs(self):
        lo = {"id": "write_for_loop", "statement": FOR_LOOP_NL}
        obj = {"id": "write_for_loop", "nl": FOR_LOOP_NL, "en": "You can write a for loop."}
        live = [{"id": "a", "title": "A", "description": ""}, {"id": "b", "title": "B", "description": ""}]
        live = [dict(g, objectives=[lo]) for g in live]
        texts = [{"id": g["id"], "nl": {"title": g["title"], "description": ""},
                  "en": {"title": g["title"], "description": ""}, "objectives": [obj]} for g in live]
        docs, problems = self.build(goals=live, texts=texts)
        self.assertEqual(problems, [])
        self.assertEqual(
            sorted(d["id"] for d in docs if d["kind"] == "objective"),
            ["objective_a.write_for_loop", "objective_b.write_for_loop"],
        )

    def test_current_hashes_include_every_live_lo(self):
        hashes = translations.current_hashes(LIVE_CONTENT, LIVE_GOALS)
        self.assertEqual(
            hashes["objective_lijsten.write_for_loop"],
            "62df92465cc34d981136db5f95321525b64e6c4379cf2eb594e8424f55b9335c",
        )
        self.assertEqual(sorted(i for i in hashes if i.startswith("objective_")), OBJECTIVE_IDS)


class PushTest(_Repo):
    def test_plan_writes_nothing(self):
        cosmos = _fake_cosmos()
        out = io.StringIO()
        docs, _ = translations.plan(cosmos, out)
        self.assertEqual(len(docs), 5)
        self.assertEqual(cosmos.creates, [])
        self.assertNotIn("<p>", out.getvalue(), "the dry run prints no bodies")
        self.assertNotIn("You can", out.getvalue(), "nor statements")
        self.assertIn("5 docs for `translations`, partition `en` (1 content, 2 goal, 2 objective)", out.getvalue())

    def test_push_creates_and_keeps_an_existing_translation(self):
        teacher = {"id": "goal_lijsten", "language": "en", "kind": "goal", "refId": "lijsten",
                   "title": "Lists (teacher)", "description": "Typed in the goal editor.", "sourceHash": "x"}
        cosmos = _fake_cosmos({"en/goal_lijsten": teacher})
        r = translations.push(cosmos, io.StringIO())
        self.assertEqual(sorted(r["created"]), ["content_lijsten", "goal_root"] + OBJECTIVE_IDS)
        self.assertEqual(r["exists"], ["goal_lijsten"])
        self.assertEqual(cosmos.store["en/goal_lijsten"], teacher, "a 409 leaves the teacher's text alone")
        self.assertEqual(r["stored"], 5)
        self.assertEqual(r["stale"], ["goal_lijsten"], "its hash is not the live one")

    def test_push_keeps_an_existing_lo_translation(self):
        mine = {"id": "objective_lijsten.write_for_loop", "language": "en", "kind": "objective",
                "refId": "lijsten.write_for_loop", "statement": "Mine.", "sourceHash": "x"}
        cosmos = _fake_cosmos({"en/objective_lijsten.write_for_loop": mine})
        r = translations.push(cosmos, io.StringIO())
        self.assertEqual(r["exists"], ["objective_lijsten.write_for_loop"])
        self.assertEqual(cosmos.store["en/objective_lijsten.write_for_loop"], mine)
        self.assertEqual(r["stale"], ["objective_lijsten.write_for_loop"])

    def test_verify_after_a_clean_push_finds_everything_current(self):
        cosmos = _fake_cosmos()
        translations.push(cosmos, io.StringIO())
        r = translations.verify(cosmos, io.StringIO())
        self.assertEqual((r["stored"], len(r["current"]), r["stale"], r["unknown"], r["missing"]), (5, 5, [], [], []))

    def test_verify_knows_the_source_of_an_lo_doc(self):
        """Before #250 every `objective_` doc came out as NO SOURCE."""
        doc = {"id": "objective_lijsten.write_for_loop", "language": "en", "kind": "objective",
               "refId": "lijsten.write_for_loop", "statement": "You can write a for loop.",
               "sourceHash": translations.source_hash("", FOR_LOOP_NL)}
        cosmos = _fake_cosmos({"en/objective_lijsten.write_for_loop": doc})
        out = io.StringIO()
        r = translations.verify(cosmos, out)
        self.assertEqual((r["current"], r["unknown"]), (["objective_lijsten.write_for_loop"], []))
        self.assertIn("MISSING   objective_lijsten.predict_index_value", out.getvalue())
        self.assertNotIn("NO SOURCE", out.getvalue())

    def test_verify_flags_an_lo_doc_whose_dutch_statement_changed(self):
        doc = {"id": "objective_lijsten.write_for_loop", "language": "en", "kind": "objective",
               "refId": "lijsten.write_for_loop", "statement": "You can write a for loop.",
               "sourceHash": translations.source_hash("", "Je kan een for-lus schrijven.")}
        cosmos = _fake_cosmos({"en/objective_lijsten.write_for_loop": doc})
        r = translations.verify(cosmos, io.StringIO())
        self.assertEqual(r["stale"], ["objective_lijsten.write_for_loop"])


class RepoGoalTextsTest(unittest.TestCase):
    """The committed `goals/en/goal-texts.json` (#250): every LO entry is
    complete, and the file is what `build_docs` reads."""

    def test_every_objective_entry_is_complete(self):
        texts = translations.goal_texts()
        seen = 0
        for entry in texts:
            ids = [o["id"] for o in entry.get("objectives") or []]
            self.assertEqual(len(ids), len(set(ids)), f"{entry['id']}: an LO id twice")
            for o in entry.get("objectives") or []:
                seen += 1
                where = f"{entry['id']}.{o['id']}"
                self.assertEqual(set(o), {"id", "nl", "en"}, where)
                self.assertTrue(o["nl"].startswith("Je kan "), where)
                self.assertTrue(o["en"].startswith("You can "), where)
                self.assertTrue(o["en"].endswith("."), where)
        self.assertGreater(seen, 0)


class CheckLessonsTest(unittest.TestCase):
    def test_a_matching_output_block_passes(self):
        n, failures = check_lessons.check_lesson("x", NL_BODY.replace("\r\n", "\n"), "nl")
        self.assertEqual((n, failures), (1, []))

    def test_a_wrong_output_block_fails(self):
        body = EN_BODY.replace("\r\n", "\n").replace("<pre><code>[1, 2]</code></pre>", "<pre><code>[2, 1]</code></pre>")
        _, failures = check_lessons.check_lesson("x", body, "en")
        self.assertEqual(len(failures), 1)
        self.assertIn("but the lesson shows", failures[0])

    def test_an_error_in_the_output_block_counts_as_its_last_line(self):
        body = (
            "<pre><code>t = (3, 5)\nt[0] = 10</code></pre>\n<p>Output:</p>\n"
            "<pre><code>TypeError: 'tuple' object does not support item assignment</code></pre>"
        )
        self.assertEqual(check_lessons.check_lesson("x", body, "en")[1], [])

    def test_an_unexpected_error_fails(self):
        _, failures = check_lessons.check_lesson("x", "<pre><code>print(y)</code></pre>", "en")
        self.assertEqual(len(failures), 1)
        self.assertIn("NameError", failures[0])

    def test_a_loop_that_does_not_stop_fails(self):
        body = "<pre><code>while True:\n    print(1)</code></pre>"
        _, failures = check_lessons.check_lesson("x", body, "en")
        self.assertIn("does not stop", failures[0])

    def test_blocks_share_one_namespace(self):
        body = (
            "<pre><code>x = 2</code></pre>\n<p>Then:</p>\n"
            "<pre><code>print(x * 3)</code></pre>\n<p>Output:</p>\n<pre><code>6</code></pre>"
        )
        self.assertEqual(check_lessons.check_lesson("x", body, "en"), (2, []))

    def test_a_seeded_block_prints_what_the_lesson_shows(self):
        body = (
            "<pre><code>import random\nprint(random.randint(1, 6), random.randint(1, 6))</code></pre>\n"
            "<p>One possible output:</p>\n<pre><code>{}</code></pre>"
        )
        import random

        random.seed(7)
        shown = f"{random.randint(1, 6)} {random.randint(1, 6)}"
        with mock.patch.dict(check_lessons.CASES, {"x": {0: {"seed": 7}}}):
            self.assertEqual(check_lessons.check_lesson("x", body.format(shown), "en"), (1, []))
            _, failures = check_lessons.check_lesson("x", body.format("0 0"), "en")
        self.assertEqual(len(failures), 1)

    def test_a_different_tag_sequence_shows(self):
        self.assertNotEqual(
            check_lessons.tags('<div class="callout warn"><p>a</p></div>'),
            check_lessons.tags('<div class="callout tip"><p>a</p></div>'),
        )

    def test_the_repo_lessons_pass(self):
        """The committed English lessons against the Dutch ones."""
        with mock.patch("sys.stdout", new=io.StringIO()) as out:
            code = check_lessons.main([])
        self.assertEqual(code, 0, out.getvalue())


if __name__ == "__main__":
    unittest.main()
