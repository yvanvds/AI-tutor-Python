"""Exports the live content to the bundle the stand-alone mode ships with
(#265, part of #261): goals, lessons, modules, prompts, translations, the
default settings and the question bank, as they are live.

    python tooling/curriculum/export_bundle.py diff     # what would change
    python tooling/curriculum/export_bundle.py export   # write the bundle

`diff` compares what is live with the bundle on disk, per goal, lesson,
prompt section, translation and question, so the teacher sees what goes out
before it does. `diff --old A --new B` compares two bundles on disk.

Read-only on the database: it only queries and reads. Standard library only;
the Cosmos client is `tooling/evaluation/cosmos.py`.

What leaves
-----------

Per container a list of fields that may leave (`ALLOWED`), never a list of
fields that must stay: a field that is not on the list is dropped, so a new
field never leaves until someone adds it here. On top of that:

  - only the containers in `ALLOWED` are read; a container with student data
    (`STUDENT_CONTAINERS`) can never be one of them;
  - `config`: only the doc `global`, and of it only `Model` and the
    question-bank settings;
  - `questions`: only `status: active`, without `createdByUid`, the counters
    and the hide history;
  - no field whose name looks like a key, secret or password ever leaves,
    whatever the list says and however deep it sits (`_is_key_like`); nor a
    string value that looks like a key (`_looks_like_secret`). Either one
    stops the export instead of dropping the field silently.

The bundle format (read by the app in #266)
-------------------------------------------

A folder (`assets/curriculum/`) with one JSON file per container plus
`manifest.json`, all UTF-8:

    manifest.json
        {
          "format": 1,
          "contentVersion": "<sha256, hex>",
          "exportedAt": "2026-11-19T10:00:00.000000Z",
          "containers": {"goals": {"file": "goals.json", "count": 12}, ...}
        }

    <container>.json   (goals, content, modules, instructions, translations,
                        config, questions)
        {
          "container": "goals",
          "partitionKeyField": "type",
          "docs": [ {...}, ... ]
        }

Each doc is a Cosmos doc as the app writes it, minus what the allow-list
drops and minus Cosmos' own `_rid`/`_etag`/`_ts`/... fields. A doc's
partition key is `doc[partitionKeyField]`: `type` for goals, content,
modules, instructions and config, `language` for translations, `subgoalId`
for questions (as `kCosmosPartitionKeyFields` in
`lib/core/local_cosmos_client.dart`). Docs are sorted by partition key,
then id.

`contentVersion` is the sha256 of the container files' content in canonical
form (sorted keys, no whitespace), so it stays the same as long as the
content does: not the export date, not the order the database returned the
docs in. The app compares it with the version it loaded last. An export
whose content did not change keeps the old `exportedAt`, so the bundle in
git does not change either.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUNDLE_DIR = ROOT / "assets" / "curriculum"
FORMAT = 1
MANIFEST = "manifest.json"

# The fields that may leave, per container. Everything else stays behind.
ALLOWED: dict[str, frozenset[str]] = {
    # `GoalsService._docMap`, `LearningObjective.toMap` inside `objectives`.
    "goals": frozenset({
        "id", "type", "title", "description", "parentId", "order", "optional",
        "teachingTips", "allowChains", "objectives", "contentId", "moduleId",
    }),
    # `Content.toMap`: a lesson.
    "content": frozenset({"id", "type", "title", "body", "updatedAt"}),
    # `Module.toMap`.
    "modules": frozenset({"id", "type", "title", "order", "updatedAt"}),
    # `Instruction.toMap`: the prompts, one section per key.
    "instructions": frozenset({"id", "type", "sections", "updatedAt"}),
    # `Translation.toMap`, every language.
    "translations": frozenset({
        "id", "language", "kind", "refId", "title", "body", "description",
        "statement", "sourceHash", "updatedAt",
    }),
    # `GlobalConfig.toMap`, only the doc `global`: the model and the
    # question-bank settings. Not `MinimumVersion` or `TurnContentKeepUntil`:
    # those are the school's.
    "config": frozenset({"id", "type", "Model", "QuestionBankMinimum", "QuestionBankShare"}),
    # `BankQuestion.toMap` without who got it first (`createdByUid`), the
    # counters (`askedCount`, `answeredCount`, `correctCount`, `lastAskedAt`,
    # `keyDisputedCount`, `keyDisputedAt`) and the hide history (`hiddenBy`,
    # `hiddenAt`, `keptByTeacher`): those are about our students.
    "questions": frozenset({
        "id", "type", "subgoalId", "rootGoalId", "targetLOIds", "questionType",
        "difficulty", "language", "payload", "model", "createdAt",
        "optionFeedback", "status",
    }),
}

# The partition-key field of each exported container (as the app's
# `kCosmosPartitionKeyFields`).
PARTITION_FIELD: dict[str, str] = {
    "goals": "type",
    "content": "type",
    "modules": "type",
    "instructions": "type",
    "translations": "language",
    "config": "type",
    "questions": "subgoalId",
}

# Containers that hold data about students. None of them is ever read.
# `podium` holds the class podium's places, each with a student's uid (#338).
STUDENT_CONTAINERS: frozenset[str] = frozenset({
    "accounts", "progress", "progress_history", "status_reports", "lo_beliefs",
    "turn_history", "turn_content", "playground_files", "grade_proposals",
    "reports", "podium",
})

CONTAINERS: tuple[str, ...] = tuple(ALLOWED)

if STUDENT_CONTAINERS & set(ALLOWED) or set(ALLOWED) != set(PARTITION_FIELD):
    raise SystemExit("export_bundle: the container lists do not add up")


class SecretFound(Exception):
    """A key-like field or value in what would leave. The export stops."""


# ---- the guards ----------------------------------------------------------------

_KEY_NAME = re.compile(
    r"(key|keys|secret|secrets|passwd|token|credentials?)$"
    r"|apikey|secret|password|credential|connectionstring|privatekey|accesskey|masterkey"
)


def _is_key_like(name: str) -> bool:
    """`ApiKey`, `api_key`, `OPENAI_KEY`, `CosmosKey`, `clientSecret`, ...:
    a field name that looks like a key, whatever its case or separators."""
    flat = re.sub(r"[^a-z0-9]", "", name.lower())
    return bool(_KEY_NAME.search(flat))


_SECRET_VALUE = re.compile(
    r"\bsk-[A-Za-z0-9_\-]{16,}"                     # OpenAI-style keys
    r"|AccountKey="                                 # connection strings
    r"|SharedAccessSignature|[?&]sig=[A-Za-z0-9%]{16,}"
    r"|^[A-Za-z0-9+/]{40,}={1,2}$"                  # a padded base64 blob
)


def _looks_like_secret(value: str) -> bool:
    return bool(_SECRET_VALUE.search(value))


def _check(value, where: str) -> None:
    """Walks [value] and raises [SecretFound] at a key-like field name or a
    key-like string anywhere inside it."""
    if isinstance(value, dict):
        for k, v in value.items():
            if _is_key_like(str(k)):
                raise SecretFound(f"{where}.{k}: a key-like field")
            _check(v, f"{where}.{k}")
    elif isinstance(value, list):
        for i, v in enumerate(value):
            _check(v, f"{where}[{i}]")
    elif isinstance(value, str) and _looks_like_secret(value):
        raise SecretFound(f"{where}: a key-like value")


def clean(container: str, doc: dict) -> dict:
    """[doc] with only the fields that may leave [container]. A key-like
    field name is never kept at the top, even when it is on the list."""
    allowed = ALLOWED[container]
    out = {k: v for k, v in doc.items() if k in allowed and not _is_key_like(k)}
    _check(out, f"{container}/{doc.get('id')}")
    return out


# ---- reading -------------------------------------------------------------------


def _cosmos():
    """The REST client. Imported late: it reads `.env` on import."""
    sys.path.insert(0, str(ROOT / "tooling" / "evaluation"))
    import cosmos

    return cosmos


def _sort_key(container: str):
    field = PARTITION_FIELD[container]
    return lambda d: (str(d.get(field) or ""), str(d.get("id") or ""))


def read_live(source) -> dict[str, list[dict]]:
    """Every exported container's docs from [source] (the `cosmos` module or
    a fake with the same `query`/`read`), cleaned and sorted. Reads only the
    containers in `ALLOWED`."""
    out: dict[str, list[dict]] = {}
    for container in CONTAINERS:
        assert container not in STUDENT_CONTAINERS
        if container == "config":
            doc = source.read("config", "global", "config")
            raw = [doc] if doc else []
        elif container == "questions":
            raw = source.query("questions", "SELECT * FROM c WHERE c.status = 'active'")
        else:
            raw = source.query(container, "SELECT * FROM c")
        docs = []
        for doc in raw:
            if container == "config" and doc.get("id") != "global":
                continue
            # Checked here as well: the query is not the only gate.
            if container == "questions" and doc.get("status") != "active":
                continue
            docs.append(clean(container, doc))
        out[container] = sorted(docs, key=_sort_key(container))
    return out


# ---- the bundle ----------------------------------------------------------------


def _canonical(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _container_file(container: str, docs: list[dict]) -> dict:
    return {"container": container, "partitionKeyField": PARTITION_FIELD[container], "docs": docs}


def content_version(containers: dict[str, list[dict]]) -> str:
    """The sha256 of the content: the same docs give the same hash, in
    whatever order they came."""
    h = hashlib.sha256()
    for container in sorted(containers):
        docs = sorted(containers[container], key=_sort_key(container))
        h.update(container.encode("utf-8") + b"\n")
        h.update(_canonical(_container_file(container, docs)) + b"\n")
    return h.hexdigest()


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _dump(value) -> str:
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def write_bundle(containers: dict[str, list[dict]], out_dir: Path, now: str | None = None) -> dict:
    """Writes the bundle to [out_dir] and returns its manifest. When the
    manifest there already has the same content version, its `exportedAt`
    is kept: nothing in the folder changes."""
    out_dir.mkdir(parents=True, exist_ok=True)
    version = content_version(containers)
    exported_at = now or _now()
    old = read_manifest(out_dir)
    if old and old.get("contentVersion") == version and old.get("exportedAt"):
        exported_at = old["exportedAt"]
    manifest = {
        "format": FORMAT,
        "contentVersion": version,
        "exportedAt": exported_at,
        "containers": {
            c: {"file": f"{c}.json", "count": len(containers[c])} for c in sorted(containers)
        },
    }
    for c in sorted(containers):
        docs = sorted(containers[c], key=_sort_key(c))
        (out_dir / f"{c}.json").write_text(_dump(_container_file(c, docs)), encoding="utf-8", newline="\n")
    (out_dir / MANIFEST).write_text(_dump(manifest), encoding="utf-8", newline="\n")
    return manifest


def read_manifest(bundle_dir: Path) -> dict | None:
    path = bundle_dir / MANIFEST
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def read_bundle(bundle_dir: Path) -> dict[str, list[dict]]:
    """The docs of a bundle on disk, per container. A folder without a
    bundle reads as empty: the first export shows everything as new."""
    manifest = read_manifest(bundle_dir)
    if manifest is None:
        return {c: [] for c in CONTAINERS}
    out = {}
    for c, entry in manifest["containers"].items():
        data = json.loads((bundle_dir / entry["file"]).read_text(encoding="utf-8"))
        out[c] = data["docs"]
    return out


# ---- diff ----------------------------------------------------------------------


def _label(container: str, doc: dict) -> str:
    title = doc.get("title")
    if container == "goals":
        return f"goal {doc['id']}" + (f" ({title})" if title else "")
    if container == "content":
        return f"lesson {doc['id']}" + (f" ({title})" if title else "")
    if container == "modules":
        return f"module {doc['id']}"
    if container == "instructions":
        return f"instructions {doc['id']}"
    if container == "translations":
        return f"translation {doc.get('language')}/{doc['id']}"
    if container == "config":
        return f"config {doc['id']}"
    return f"question {doc.get('subgoalId')}/{doc['id']}"


def _key(container: str, doc: dict) -> tuple[str, str]:
    return (str(doc.get(PARTITION_FIELD[container]) or ""), str(doc.get("id") or ""))


def diff(old: dict[str, list[dict]], new: dict[str, list[dict]]) -> list[str]:
    """What changed from [old] to [new], one line each: `+` added, `-`
    removed, `~` changed (with the fields, and for instructions the
    sections, that changed). Empty when nothing did."""
    lines: list[str] = []
    for c in CONTAINERS:
        before = {_key(c, d): d for d in old.get(c, [])}
        after = {_key(c, d): d for d in new.get(c, [])}
        for k in sorted(after.keys() - before.keys()):
            lines.append(f"+ {_label(c, after[k])}")
        for k in sorted(before.keys() - after.keys()):
            lines.append(f"- {_label(c, before[k])}")
        for k in sorted(before.keys() & after.keys()):
            a, b = before[k], after[k]
            if a == b:
                continue
            fields = sorted(f for f in a.keys() | b.keys() if a.get(f) != b.get(f))
            if c == "instructions" and "sections" in fields:
                sa, sb = a.get("sections") or {}, b.get("sections") or {}
                parts = [f"+{s}" for s in sorted(sb.keys() - sa.keys())]
                parts += [f"-{s}" for s in sorted(sa.keys() - sb.keys())]
                parts += [f"~{s}" for s in sorted(sa.keys() & sb.keys()) if sa[s] != sb[s]]
                fields = [f for f in fields if f != "sections"] + [f"sections: {', '.join(parts)}"]
            lines.append(f"~ {_label(c, b)}: {'; '.join(fields)}")
    return lines


# ---- commands ------------------------------------------------------------------


def _print_diff(lines: list[str]) -> None:
    if not lines:
        print("no changes")
        return
    for line in lines:
        print(line)
    print(f"\n{len(lines)} change(s)")


def main(argv: list[str] | None = None, source=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    exp = sub.add_parser("export", help="read live, write the bundle")
    exp.add_argument("--out", type=Path, default=BUNDLE_DIR)
    d = sub.add_parser("diff", help="what would change in the bundle")
    d.add_argument("--old", type=Path, default=BUNDLE_DIR, help="the bundle to compare with")
    d.add_argument("--new", type=Path, help="a second bundle on disk instead of what is live")
    args = ap.parse_args(argv)

    try:
        if args.cmd == "diff":
            old = read_bundle(args.old)
            new = read_bundle(args.new) if args.new else read_live(source or _cosmos())
            _print_diff(diff(old, new))
            return 0
        old = read_bundle(args.out)
        live = read_live(source or _cosmos())
        manifest = write_bundle(live, args.out)
    except SecretFound as e:
        print(f"stopped, nothing written: {e}", file=sys.stderr)
        return 2
    _print_diff(diff(old, live))
    counts = ", ".join(f"{c} {e['count']}" for c, e in manifest["containers"].items())
    print(f"bundle {manifest['contentVersion'][:12]} in {args.out}: {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
