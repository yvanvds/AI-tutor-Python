"""Figures for the lessons, as inline SVG.

A lesson body cannot hold an image file (there is no hosting for lesson
images), but the lesson view renders the HTML as it is, so a drawing can be
part of the text itself: an `<svg>` element with no script and no `style`
attribute, coloured with the variables of `assets/lesson/lesson.css`. It
scales with the width of the page and follows the app's colours.

Every figure is a function of the language, because its labels are text.
The Dutch and the English figure have the same elements in the same order,
so `tooling/translations/check_lessons.py` still sees the same structure.

    python tooling/curriculum/figures.py            # list the figures
    python tooling/curriculum/figures.py preview    # write build/figures_preview.html

A lesson is written with the figure in place: paste the output of
`figure(name, language)` where it belongs. Standard library only.
"""

from __future__ import annotations

import html
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

COLOURS = {
    "fg": "var(--fg)",
    "mute": "var(--fg-mute)",
    "faint": "var(--fg-faint)",
    "line": "var(--ink-4)",
    "accent": "var(--accent)",
    "blue": "var(--syntax-fn)",
    "yellow": "var(--syntax-num)",
    "red": "var(--danger)",
    "pink": "var(--syntax-kw)",
}


class Plot:
    """A small coordinate system: curves, points, lines and labels in data
    coordinates, written out as one `<svg>` element."""

    def __init__(self, x0, x1, y0, y1, label, width=640, height=300, left=46, right=18, top=16, bottom=34):
        self.x0, self.x1, self.y0, self.y1 = x0, x1, y0, y1
        self.w, self.h = width, height
        self.l, self.r, self.t, self.b = left, right, top, bottom
        self.label = label
        self.parts: list[str] = []

    # ---- coordinates ---------------------------------------------------------

    def px(self, x):
        return round(self.l + (x - self.x0) / (self.x1 - self.x0) * (self.w - self.l - self.r), 1)

    def py(self, y):
        return round(self.t + (self.y1 - y) / (self.y1 - self.y0) * (self.h - self.t - self.b), 1)

    # ---- elements ------------------------------------------------------------

    def axes(self, xticks=(), yticks=(), grid=False):
        """The horizontal axis at y = 0 (or the bottom edge when 0 is out of
        range), the vertical axis at the left edge, and numbered ticks."""
        base = self.py(0) if self.y0 <= 0 <= self.y1 else self.py(self.y0)
        for x in xticks:
            if grid:
                self.parts.append(f'<line x1="{self.px(x)}" y1="{self.t}" x2="{self.px(x)}" y2="{self.h - self.b}" stroke="{COLOURS["line"]}" stroke-width="1"/>')
            self.parts.append(f'<text x="{self.px(x)}" y="{self.h - self.b + 20}" text-anchor="middle" fill="{COLOURS["faint"]}" font-family="var(--font-mono)" font-size="13">{_num(x)}</text>')
        for y in yticks:
            if grid:
                self.parts.append(f'<line x1="{self.l}" y1="{self.py(y)}" x2="{self.w - self.r}" y2="{self.py(y)}" stroke="{COLOURS["line"]}" stroke-width="1"/>')
            self.parts.append(f'<text x="{self.l - 8}" y="{self.py(y) + 4}" text-anchor="end" fill="{COLOURS["faint"]}" font-family="var(--font-mono)" font-size="13">{_num(y)}</text>')
        self.parts.append(f'<line x1="{self.l}" y1="{base}" x2="{self.w - self.r}" y2="{base}" stroke="{COLOURS["mute"]}" stroke-width="1.5"/>')
        self.parts.append(f'<line x1="{self.l}" y1="{self.t}" x2="{self.l}" y2="{self.h - self.b}" stroke="{COLOURS["mute"]}" stroke-width="1.5"/>')

    def curve(self, f, colour="blue", start=None, end=None, n=120, width=2.5):
        start = self.x0 if start is None else start
        end = self.x1 if end is None else end
        pts = []
        for i in range(n + 1):
            x = start + (end - start) * i / n
            y = f(x)
            if self.y0 <= y <= self.y1:
                pts.append(f"{self.px(x)},{self.py(y)}")
        self.parts.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{COLOURS[colour]}" stroke-width="{width}"/>')

    def segment(self, xa, ya, xb, yb, colour="mute", width=1.5, dashed=False):
        dash = ' stroke-dasharray="5 4"' if dashed else ""
        self.parts.append(f'<line x1="{self.px(xa)}" y1="{self.py(ya)}" x2="{self.px(xb)}" y2="{self.py(yb)}" stroke="{COLOURS[colour]}" stroke-width="{width}"{dash}/>')

    def bar(self, xa, xb, y, colour="accent", thickness=10, opacity=0.45):
        """A horizontal band from xa to xb, centred on height y."""
        self.parts.append(f'<rect x="{self.px(xa)}" y="{self.py(y) - thickness / 2}" width="{round(self.px(xb) - self.px(xa), 1)}" height="{thickness}" rx="3" fill="{COLOURS[colour]}" opacity="{opacity}"/>')

    def point(self, x, y, colour="fg", radius=5):
        self.parts.append(f'<circle cx="{self.px(x)}" cy="{self.py(y)}" r="{radius}" fill="{COLOURS[colour]}"/>')

    def text(self, x, y, s, colour="fg", anchor="middle", dx=0, dy=0, mono=False, size=14):
        font = "var(--font-mono)" if mono else "var(--font-sans)"
        self.parts.append(f'<text x="{round(self.px(x) + dx, 1)}" y="{round(self.py(y) + dy, 1)}" text-anchor="{anchor}" fill="{COLOURS[colour]}" font-family="{font}" font-size="{size}">{html.escape(s, quote=False)}</text>')

    def svg(self) -> str:
        # The description is a <title> child, not an attribute: the tags of
        # the Dutch and the English figure stay identical, and the text
        # travels with the page when it is read as plain text.
        head = f'<svg viewBox="0 0 {self.w} {self.h}" width="100%" role="img">'
        title = f"<title>{html.escape(self.label, quote=False)}</title>"
        return "\n".join([head, title, *self.parts, "</svg>"])


def _num(v) -> str:
    return str(int(v)) if float(v) == int(v) else str(v)


# ---- goal 8: vergelijkingen oplossen -------------------------------------------


def _cubic(x):
    return x ** 3 - x - 1


def _zero_of_cubic(lang):
    t = {
        "nl": ("De grafiek van f snijdt de horizontale as tussen 1 en 2", "nulpunt", "f(x) = x³ - x - 1"),
        "en": ("The graph of f crosses the horizontal axis between 1 and 2", "zero", "f(x) = x³ - x - 1"),
    }[lang]
    p = Plot(0, 2, -2, 5, t[0])
    p.axes(xticks=(0, 0.5, 1, 1.5, 2), yticks=(-2, 0, 2, 4), grid=True)
    p.curve(_cubic)
    p.point(1.3247, 0, "accent", 6)
    p.text(1.3247, 0, t[1], "accent", anchor="start", dx=10, dy=18)
    p.text(0.1, 4.2, t[2], "blue", anchor="start", mono=True)
    return p.svg()


def _bisection_step(lang):
    t = {
        "nl": ("Een bisectiestap: het midden m van het interval van a tot b", "f(a) is negatief", "f(m) is positief", "f(b) is positief", "nieuw interval"),
        "en": ("A bisection step: the midpoint m of the interval from a to b", "f(a) is negative", "f(m) is positive", "f(b) is positive", "new interval"),
    }[lang]
    p = Plot(0.8, 2.2, -2.2, 6, t[0])
    p.axes()
    p.bar(1, 1.5, 0, thickness=12)
    p.curve(_cubic)
    for x, name, colour in ((1, "a", "fg"), (1.5, "m", "yellow"), (2, "b", "fg")):
        p.segment(x, 0, x, _cubic(x), colour, 1, dashed=True)
        p.point(x, _cubic(x), colour)
    p.text(1, 0, "a = 1", "fg", dy=-12, mono=True)
    p.text(1, _cubic(1), t[1], "mute", dy=22, size=13)
    p.text(1.5, 0, "m = 1.5", "yellow", dy=22, mono=True)
    p.text(1.5, _cubic(1.5), t[2], "mute", anchor="start", dx=12, dy=16, size=13)
    p.text(2, 0, "b = 2", "fg", dy=22, mono=True)
    p.text(2, _cubic(2), t[3], "mute", anchor="end", dx=-10, dy=-2, size=13)
    p.text(1.25, 0, t[4], "accent", dy=-14, size=13)
    return p.svg()


def _halving(lang):
    t = {
        "nl": ("Het interval wordt bij elke stap half zo breed", "start", "stap", "breedte"),
        "en": ("The interval becomes half as wide at every step", "start", "step", "width"),
    }[lang]
    p = Plot(0.8, 2.25, -0.5, 5.6, t[0], height=250, left=70, bottom=30)
    a, b = 1.0, 2.0
    for step in range(6):
        y = 5 - step
        p.bar(a, b, y, thickness=14, opacity=0.5)
        p.text(0.8, y, t[1] if step == 0 else f"{t[2]} {step}", "mute", anchor="end", dx=42, dy=5, size=13)
        p.text(2.25, y, f"{t[3]} {_num(b - a)}", "faint", anchor="end", dy=5, mono=True, size=12)
        m = (a + b) / 2
        if _cubic(a) * _cubic(m) < 0:
            b = m
        else:
            a = m
    p.segment(1.3247, -0.4, 1.3247, 5.5, "accent", 1.5, dashed=True)
    base = p.py(-0.5)
    p.parts.append(f'<line x1="{p.px(1)}" y1="{base}" x2="{p.px(2)}" y2="{base}" stroke="{COLOURS["mute"]}" stroke-width="1.5"/>')
    for x in (1, 1.25, 1.5, 1.75, 2):
        p.text(x, -0.5, _num(x), "faint", dy=18, mono=True, size=13)
    return p.svg()


def _newton_step(lang):
    t = {
        "nl": ("Een Newton-stap: de raaklijn in de schatting snijdt de as in de volgende schatting", "raaklijn", "schatting", "volgende schatting", "nulpunt"),
        "en": ("A Newton step: the tangent line at the estimate crosses the axis at the next estimate", "tangent line", "estimate", "next estimate", "zero"),
    }[lang]
    x0 = 2.0
    slope = 3 * x0 ** 2 - 1
    x1 = x0 - _cubic(x0) / slope
    p = Plot(0.9, 2.3, -2, 8.5, t[0])
    p.axes()
    p.curve(_cubic)
    p.segment(x1 - 0.12, -0.12 * slope, 2.25, _cubic(x0) + 0.25 * slope, "yellow", 2)
    p.segment(x0, 0, x0, _cubic(x0), "faint", 1, dashed=True)
    p.point(x0, _cubic(x0), "fg")
    p.point(x0, 0, "fg", 4)
    p.point(x1, 0, "yellow", 6)
    p.point(1.3247, 0, "accent", 5)
    p.text(x0, 0, f"{t[2]}: x = 2", "fg", dy=22, mono=True, size=13)
    p.text(x1, 0, f"{t[3]}: x = {round(x1, 3)}", "yellow", dx=-14, dy=-34, anchor="end", mono=True, size=13)
    p.text(1.3247, 0, t[4], "accent", dy=22, size=13)
    p.text(2.12, _cubic(x0) + 0.12 * slope, t[1], "yellow", anchor="end", dx=-12, dy=-2, size=13)
    return p.svg()


def _cooling(lang):
    t = {
        "nl": ("De temperatuur daalt en bereikt 40 graden na ongeveer 11,9 minuten", "tijd (minuten)", "temperatuur", "40 graden", "t = 11.89"),
        "en": ("The temperature falls and reaches 40 degrees after about 11.9 minutes", "time (minutes)", "temperature", "40 degrees", "t = 11.89"),
    }[lang]

    def temp(x):
        return 20 + 70 * 0.9 ** x

    p = Plot(0, 30, 0, 100, t[0], bottom=50)
    p.axes(xticks=(0, 5, 10, 15, 20, 25, 30), yticks=(20, 40, 60, 80), grid=True)
    p.curve(temp)
    p.segment(0, 40, 30, 40, "yellow", 1.5, dashed=True)
    p.segment(11.89, 0, 11.89, 40, "accent", 1.5, dashed=True)
    p.point(11.89, 40, "accent", 6)
    p.text(29.5, 40, t[3], "yellow", anchor="end", dy=-8, size=13)
    p.text(11.89, 40, t[4], "accent", anchor="start", dx=10, dy=-10, mono=True, size=13)
    p.text(2.5, 88, t[2], "blue", anchor="start", size=13)
    p.text(15, 0, t[1], "mute", dy=44, size=13)
    return p.svg()


FIGURES = {
    "nulpunt": _zero_of_cubic,
    "bisectiestap": _bisection_step,
    "halveren": _halving,
    "newtonstap": _newton_step,
    "afkoeling": _cooling,
}


def figure(name: str, language: str) -> str:
    """The `<svg>` element of figure [name] with its labels in [language]."""
    return FIGURES[name](language)


def preview(out: Path | None = None) -> Path:
    """Every figure in both languages on one page with the lesson stylesheet."""
    css = (ROOT / "assets" / "lesson" / "lesson.css").read_text(encoding="utf-8")
    body = "".join(f"<h2>{name} ({lang})</h2>\n{figure(name, lang)}\n" for name in FIGURES for lang in ("nl", "en"))
    out = out or ROOT / "build" / "figures_preview.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        f'<!doctype html>\n<html lang="nl">\n<head>\n<meta charset="utf-8">\n<title>Figuren</title>\n<style>\n{css}\n</style>\n</head>\n<body class="lesson">\n{body}</body>\n</html>\n',
        encoding="utf-8",
    )
    return out


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if args[:1] == ["preview"]:
        print(preview(Path(args[1]) if len(args) > 1 else None))
        return 0
    for name in FIGURES:
        print(f"{name}: {len(figure(name, 'nl'))} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
