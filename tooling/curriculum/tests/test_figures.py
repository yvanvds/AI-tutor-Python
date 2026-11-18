"""Tests for `figures.py`: every figure is inert inline SVG that the lesson
view can show, and its Dutch and English version have the same structure.
Standard library only:

    python -m unittest discover -s tooling/curriculum/tests
"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import figures  # noqa: E402

_TAG = re.compile(r"<[^>]+>")


class Figures(unittest.TestCase):
    def test_both_languages_have_the_same_tags_and_different_text(self):
        for name in figures.FIGURES:
            nl, en = figures.figure(name, "nl"), figures.figure(name, "en")
            self.assertEqual(_TAG.findall(nl), _TAG.findall(en), name)
            self.assertNotEqual(nl, en, name)

    def test_a_figure_is_one_inert_svg_element(self):
        for name in figures.FIGURES:
            svg = figures.figure(name, "nl")
            self.assertTrue(svg.startswith("<svg ") and svg.endswith("</svg>"), name)
            self.assertEqual(svg.count("<svg"), 1, name)
            self.assertIn("<title>", svg, name)
            for forbidden in ("<script", "style=", "<style", "href", "<image", "onload", "onclick"):
                self.assertNotIn(forbidden, svg, f"{name}: {forbidden}")

    def test_colours_come_from_the_lesson_stylesheet(self):
        css = (figures.ROOT / "assets" / "lesson" / "lesson.css").read_text(encoding="utf-8")
        for name in figures.FIGURES:
            svg = figures.figure(name, "nl")
            for attr, value in re.findall(r'(fill|stroke)="([^"]+)"', svg):
                self.assertTrue(value == "none" or value.startswith("var(--"), f"{name}: {attr}={value}")
            for var in set(re.findall(r"var\((--[a-z0-9-]+)\)", svg)):
                self.assertIn(var + ":", css, f"{name}: {var} is not defined in lesson.css")

    def test_every_coordinate_stays_inside_the_view_box(self):
        for name in figures.FIGURES:
            svg = figures.figure(name, "nl")
            w, h = (float(v) for v in re.search(r'viewBox="0 0 (\S+) (\S+)"', svg).groups())
            for x in re.findall(r'\b(?:x|x1|x2|cx)="([-\d.]+)"', svg):
                self.assertTrue(0 <= float(x) <= w, f"{name}: x={x}")
            for y in re.findall(r'\b(?:y|y1|y2|cy)="([-\d.]+)"', svg):
                self.assertTrue(0 <= float(y) <= h, f"{name}: y={y}")


if __name__ == "__main__":
    unittest.main()
