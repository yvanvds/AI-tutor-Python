"""Minimal Cosmos DB (NoSQL) REST client for the evaluation tooling.

Reads `COSMOS_ENDPOINT` and `COSMOS_KEY` from the repo's `.env` — the same
master key the app uses. The `az` CLI is control-plane only and cannot read
or write documents, hence this.

Standard library only. Writes are guarded with `If-Match` on the doc's
`_etag`, so a concurrent write by a student's app fails loudly (412) instead
of being silently overwritten.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from email.utils import formatdate
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = "python-tutor"
API_VERSION = "2018-12-31"


def _load_env() -> dict[str, str]:
    env: dict[str, str] = {}
    path = ROOT / ".env"
    if not path.exists():
        sys.exit(f"geen .env gevonden op {path}")
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


_ENV = _load_env()
ENDPOINT = _ENV["COSMOS_ENDPOINT"].rstrip("/")
_KEY = base64.b64decode(_ENV["COSMOS_KEY"])


class Conflict(Exception):
    """412: the doc changed since it was read."""


def _auth(verb: str, rtype: str, rlink: str, date: str) -> str:
    payload = f"{verb.lower()}\n{rtype.lower()}\n{rlink}\n{date.lower()}\n\n"
    sig = base64.b64encode(
        hmac.new(_KEY, payload.encode(), hashlib.sha256).digest()
    ).decode()
    return urllib.parse.quote(f"type=master&ver=1.0&sig={sig}", safe="")


def _headers(verb: str, rtype: str, rlink: str, pk=None) -> dict[str, str]:
    date = formatdate(usegmt=True)
    h = {
        "Authorization": _auth(verb, rtype, rlink, date),
        "x-ms-version": API_VERSION,
        "x-ms-date": date,
    }
    if pk is not None:
        h["x-ms-documentdb-partitionkey"] = json.dumps([pk])
    return h


def query(coll: str, sql: str, params: dict | None = None, pk=None, cross=True):
    """Runs [sql] against [coll], following continuation tokens.

    Single-partition when [pk] is given (one student), cross-partition
    otherwise. Note: `ORDER` is a reserved word — read `c["order"]` or just
    `SELECT *`.
    """
    rlink = f"dbs/{DB}/colls/{coll}"
    out, cont = [], None
    while True:
        h = _headers("POST", "docs", rlink, pk)
        h.update(
            {
                "Content-Type": "application/query+json",
                "x-ms-documentdb-isquery": "True",
                "x-ms-max-item-count": "1000",
            }
        )
        if cross and pk is None:
            h["x-ms-documentdb-query-enablecrosspartition"] = "True"
        if cont:
            h["x-ms-continuation"] = cont
        body = json.dumps(
            {
                "query": sql,
                "parameters": [
                    {"name": k, "value": v} for k, v in (params or {}).items()
                ],
            }
        ).encode()
        req = urllib.request.Request(
            f"{ENDPOINT}/{rlink}/docs", data=body, headers=h, method="POST"
        )
        try:
            with urllib.request.urlopen(req) as r:
                data = json.loads(r.read())
                cont = r.headers.get("x-ms-continuation")
        except urllib.error.HTTPError as e:
            print("HTTP", e.code, e.read()[:400].decode(errors="replace"), file=sys.stderr)
            raise
        out.extend(data.get("Documents", []))
        if not cont:
            return out


def read(coll: str, doc_id: str, pk):
    rlink = f"dbs/{DB}/colls/{coll}/docs/{doc_id}"
    req = urllib.request.Request(
        f"{ENDPOINT}/{rlink}", headers=_headers("GET", "docs", rlink, pk), method="GET"
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def upsert(coll: str, doc: dict, pk, etag: str | None = None) -> dict:
    """Upserts [doc]. With [etag], a concurrent change raises [Conflict]."""
    rlink = f"dbs/{DB}/colls/{coll}"
    h = _headers("POST", "docs", rlink, pk)
    h.update({"Content-Type": "application/json", "x-ms-documentdb-is-upsert": "True"})
    if etag:
        h["If-Match"] = etag
    body = json.dumps({k: v for k, v in doc.items() if not k.startswith("_")}).encode()
    req = urllib.request.Request(f"{ENDPOINT}/{rlink}/docs", data=body, headers=h, method="POST")
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 412:
            raise Conflict(doc.get("id"))
        print("HTTP", e.code, e.read()[:400].decode(errors="replace"), file=sys.stderr)
        raise


# ---- convenience reads used by every command --------------------------------


def accounts(klas: str) -> list[dict]:
    rows = query("accounts", "SELECT * FROM c WHERE c.className = @k", {"@k": klas})
    return sorted(rows, key=lambda a: (a.get("lastName", ""), a.get("firstName", "")))


def goals() -> dict[str, dict]:
    return {g["id"]: g for g in query("goals", "SELECT * FROM c")}


def milestones() -> list[dict]:
    return query("milestones", "SELECT * FROM c")


def turns(uid: str) -> list[dict]:
    rows = query("turn_history", "SELECT * FROM c WHERE c.uid = @u", {"@u": uid}, pk=uid, cross=False)
    return sorted(rows, key=lambda t: t["turnAt"])


def beliefs(uid: str) -> dict[tuple[str, str], dict]:
    rows = query("lo_beliefs", "SELECT * FROM c WHERE c.uid = @u", {"@u": uid}, pk=uid, cross=False)
    return {(b["subgoalId"], b["loId"]): b for b in rows}
