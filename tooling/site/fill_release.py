"""Writes the latest release into the download section of the site (#291):
version, date, size and SHA-256 of the installer, next to the download button.

Runs in static.yml just before the upload, on the runner's checkout of
public/, so what gets filled is only the published copy: the pages in the
repo keep their fallback text. No JavaScript and no call to the GitHub API
from the browser either: a class behind one IP address would hit the limit of
60 requests per hour within a lesson.

A page opts in with two markers and a template, in this order:

    <!-- release:start -->
    <p>…fallback: a link to all releases…</p>
    <!-- release:end -->
    <template data-release-template lang="nl">
      …markup with {{version}} {{date}} {{date_iso}} {{size}} {{sha256}}…
    </template>

The markers and everything between them are replaced by the filled template,
and the template itself is removed. `lang` ("nl" or "en", default "nl") picks
the date and number format, so the English copy under /en/ (#294) brings its
own template and labels. An unknown {{placeholder}} is an error, so a typo
never reaches the site as raw braces.

Every *.html under --site with the markers is filled, at any depth: today
index.html and en/index.html, so static.yml needs no list of pages.

All or nothing: the release must have the installer and its SHA-256, and every
page must fill, before any file is written. On any failure this exits 1 and
leaves every page as it was; static.yml runs the step with
continue-on-error, so the deploy still goes out, with the fallback text.

Where the values come from (`gh` on PATH, GH_TOKEN set in CI):
- `gh release view --json tagName,publishedAt,assets,body` for the latest
  release: the tag without its "v" is the version the app shows in
  Opties → Over; the installer asset gives the size;
- the SHA-256 is the content of the `python_teacher_install.exe.sha256` asset
  (the file the app checks an update against), else the `SHA256:` line that
  tooling/build_release.ps1 writes into the release notes. When GitHub reports
  a digest for the installer asset, it must agree.

Run from the repo root, against a copy of public/ (it edits in place):

    python tooling/site/fill_release.py --site <copy of public>
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import subprocess
import sys
import textwrap
from datetime import datetime, timedelta, timezone
from pathlib import Path

INSTALLER = "python_teacher_install.exe"  # kInstallerAssetName, build_release.ps1
CHECKSUM = INSTALLER + ".sha256"
DEFAULT_REPO = "yvanvds/AI-tutor-Python"

START = "<!-- release:start -->"
END = "<!-- release:end -->"
TEMPLATE_RE = re.compile(
    r"[ \t]*<template\b(?P<attrs>[^>]*\bdata-release-template\b[^>]*)>"
    r"(?P<body>.*?)</template>[ \t]*(?:\r?\n)?",
    re.S,
)
LANG_RE = re.compile(r'\blang="([a-z]{2})"')
PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-z_0-9]+)\s*\}\}")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")

MONTHS = {
    "nl": ["januari", "februari", "maart", "april", "mei", "juni", "juli",
           "augustus", "september", "oktober", "november", "december"],
    "en": ["January", "February", "March", "April", "May", "June", "July",
           "August", "September", "October", "November", "December"],
}


class FillError(Exception):
    pass


# --- Release data ------------------------------------------------------------


def _gh(*args: str) -> str:
    result = subprocess.run(
        ["gh", *args], capture_output=True, text=True, encoding="utf-8"
    )
    if result.returncode != 0:
        raise FillError(f"gh {' '.join(args[:2])} failed: {result.stderr.strip()}")
    return result.stdout


def fetch_release(repo: str) -> dict:
    return json.loads(
        _gh("release", "view", "--repo", repo,
            "--json", "tagName,publishedAt,assets,body")
    )


def fetch_checksum_file(repo: str, tag: str) -> str | None:
    try:
        return _gh("release", "download", tag, "--repo", repo,
                   "--pattern", CHECKSUM, "--output", "-")
    except FillError as e:
        print(f"note: no {CHECKSUM} asset ({e}); trying the release notes",
              file=sys.stderr)
        return None


def _sha_from_checksum_file(text: str) -> str | None:
    # `sha256sum` shape: "<hash>  python_teacher_install.exe"
    parts = text.strip().split()
    if len(parts) == 2 and parts[1].lstrip("*") == INSTALLER:
        return parts[0].lower()
    if len(parts) == 1:
        return parts[0].lower()
    return None


def _sha_from_notes(body: str) -> str | None:
    m = re.search(r"SHA256:\s*`?([0-9a-fA-F]{64})`?", body or "")
    return m.group(1).lower() if m else None


def _brussels(utc: datetime) -> datetime:
    """UTC to Belgian time with the EU summer-time rule, so the date is the
    one on the classroom's calendar without needing a tz database."""

    def last_sunday(year: int, month: int) -> datetime:
        d = datetime(year, month + 1, 1, 1, tzinfo=timezone.utc) - timedelta(days=1)
        return d - timedelta(days=(d.weekday() + 1) % 7)

    summer = last_sunday(utc.year, 3) <= utc < last_sunday(utc.year, 10)
    return utc + timedelta(hours=2 if summer else 1)


def release_facts(release: dict, checksum_file: str | None) -> dict:
    tag = release.get("tagName") or ""
    if not tag:
        raise FillError("the release has no tag")
    version = tag[1:] if tag.startswith("v") else tag

    asset = next((a for a in release.get("assets") or []
                  if a.get("name") == INSTALLER), None)
    if asset is None or not asset.get("size"):
        raise FillError(f"release {tag} has no {INSTALLER} asset")

    sha = _sha_from_checksum_file(checksum_file) if checksum_file else None
    if sha is None:
        sha = _sha_from_notes(release.get("body") or "")
    if sha is None or not SHA_RE.match(sha):
        raise FillError(f"release {tag} has no usable SHA-256 for {INSTALLER}")
    digest = asset.get("digest") or ""
    if digest.startswith("sha256:") and digest[7:].lower() != sha:
        raise FillError(
            f"release {tag}: the published SHA-256 {sha} does not match "
            f"GitHub's digest {digest[7:]} of {INSTALLER}"
        )

    published = datetime.fromisoformat(
        release["publishedAt"].replace("Z", "+00:00")
    ).astimezone(timezone.utc)
    return {
        "version": version,
        "published": _brussels(published).date(),
        # MiB with one decimal, the number build_release.ps1 prints as "MB"
        "size_mb": asset["size"] / (1024 * 1024),
        "sha256": sha,
    }


# --- Pages -------------------------------------------------------------------


def _values(facts: dict, lang: str) -> dict[str, str]:
    if lang not in MONTHS:
        raise FillError(f'template lang="{lang}" is not one of {sorted(MONTHS)}')
    day = facts["published"]
    size = f"{facts['size_mb']:.1f}"
    if lang == "nl":
        size = size.replace(".", ",")
    return {
        "version": facts["version"],
        "date": f"{day.day} {MONTHS[lang][day.month - 1]} {day.year}",
        "date_iso": day.isoformat(),
        "size": f"{size} MB",
        "sha256": facts["sha256"],
    }


def fill_page(text: str, facts: dict, name: str) -> str | None:
    """The page with its release section filled, or None if it has none."""
    if START not in text and END not in text:
        return None
    start, end = text.find(START), text.find(END)
    if start < 0 or end < start:
        raise FillError(f"{name}: {START} and {END} are not a pair")
    template = TEMPLATE_RE.search(text, end)
    if template is None:
        raise FillError(f"{name}: no <template data-release-template> after {END}")

    lang_match = LANG_RE.search(template.group("attrs"))
    values = _values(facts, lang_match.group(1) if lang_match else "nl")

    def substitute(m: re.Match) -> str:
        key = m.group(1)
        if key not in values:
            raise FillError(f"{name}: unknown placeholder {{{{{key}}}}}")
        return html.escape(values[key])

    body = PLACEHOLDER_RE.sub(substitute, template.group("body"))
    # Re-indented to the start marker's column, which text[:start] ends with.
    line_start = text.rfind("\n", 0, start) + 1
    indent = text[line_start:start] if not text[line_start:start].strip() else ""
    filled = textwrap.indent(textwrap.dedent(body).strip("\r\n"), indent).lstrip()

    # The filled markup takes the place of the markers; the template goes.
    return (
        text[:start]
        + filled
        + text[end + len(END):template.start()]
        + text[template.end():]
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--site", required=True, type=Path,
                        help="the copy of public/ to fill in place")
    parser.add_argument("--repo",
                        default=os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPO))
    args = parser.parse_args(argv)

    try:
        release = fetch_release(args.repo)
        facts = release_facts(release, fetch_checksum_file(args.repo, release["tagName"]))

        pages: dict[Path, str] = {}
        for path in sorted(args.site.rglob("*.html")):
            text = path.read_bytes().decode("utf-8")
            filled = fill_page(text, facts, str(path.relative_to(args.site)))
            if filled is not None:
                pages[path] = filled
        if not pages:
            raise FillError(f"no page under {args.site} has {START}")
    except (FillError, KeyError, ValueError, OSError) as e:
        print(f"error: {e}. The pages keep their fallback text.", file=sys.stderr)
        return 1

    # Only now, with every page filled in memory, write them.
    for path, text in pages.items():
        path.write_bytes(text.encode("utf-8"))
    print(f"{facts['version']} ({facts['published']}, {facts['size_mb']:.1f} MB, "
          f"sha256 {facts['sha256'][:12]}...) -> "
          + ", ".join(str(p.relative_to(args.site)) for p in pages))
    return 0


if __name__ == "__main__":
    sys.exit(main())
