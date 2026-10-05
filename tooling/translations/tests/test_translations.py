"""Tests for the translation tooling (#209): the `sourceHash` against the
app's own test vectors, the docs it would write, create-only pushing, and
the lesson checker. Standard library only:

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
LIVE_GOALS = [
    {"id": "root", "title": "Hoofddoel", "description": None, "parentId": None},
    {"id": "lijsten", "title": "Lijsten", "description": "Je kan een lijst maken.", "parentId": "root"},
]
TEXTS = [
    {"id": "root", "nl": {"title": "Hoofddoel", "description": ""}, "en": {"title": "Main goal", "description": ""}},
    {
        "id": "lijsten",
        "nl": {"title": "Lijsten", "description": "Je kan een lijst maken."},
        "en": {"title": "Lists", "description": "You can make a list."},
    },
]


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


class PushTest(_Repo):
    def test_plan_writes_nothing(self):
        cosmos = _fake_cosmos()
        out = io.StringIO()
        docs, _ = translations.plan(cosmos, out)
        self.assertEqual(len(docs), 3)
        self.assertEqual(cosmos.creates, [])
        self.assertNotIn("<p>", out.getvalue(), "the dry run prints no bodies")

    def test_push_creates_and_keeps_an_existing_translation(self):
        teacher = {"id": "goal_lijsten", "language": "en", "kind": "goal", "refId": "lijsten",
                   "title": "Lists (teacher)", "description": "Typed in the goal editor.", "sourceHash": "x"}
        cosmos = _fake_cosmos({"en/goal_lijsten": teacher})
        r = translations.push(cosmos, io.StringIO())
        self.assertEqual(sorted(r["created"]), ["content_lijsten", "goal_root"])
        self.assertEqual(r["exists"], ["goal_lijsten"])
        self.assertEqual(cosmos.store["en/goal_lijsten"], teacher, "a 409 leaves the teacher's text alone")
        self.assertEqual(r["stored"], 3)
        self.assertEqual(r["stale"], ["goal_lijsten"], "its hash is not the live one")

    def test_verify_after_a_clean_push_finds_everything_current(self):
        cosmos = _fake_cosmos()
        translations.push(cosmos, io.StringIO())
        r = translations.verify(cosmos, io.StringIO())
        self.assertEqual((r["stored"], len(r["current"]), r["stale"], r["missing"]), (3, 3, [], []))


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
