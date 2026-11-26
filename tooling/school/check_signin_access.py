"""Checks access with the user's own sign-in (#306) on a test container.

With `"databaseAccess": "signIn"` in the school file, the app reaches the
database with a token from the user's own sign-in instead of the database
key, and Cosmos decides from the roles of the README ("Access with the
user's own sign-in") what that user may do. This script tries every kind of
request the app makes, with such a token, on a container of its own:

1. read the container (its metadata, as the app does for a missing
   container, #170);
2. create a doc;
3. read it;
4. query it;
5. replace it with `If-Match` on its `_etag` (#223);
6. replace it again with the old `_etag`: that one must fail with 412;
7. a transactional batch (create a second doc, upsert the first);
8. delete both docs.

It prints each step's status code. Run it once the admin consent and the
roles are in place, before the sign-in is switched on:

    python tooling/school/check_signin_access.py --container signin_check
    python tooling/school/check_signin_access.py --container signin_check --database python-tutor

The test container is the teacher's to create first (any partition key, for
example `/pk`) and to remove afterwards: a token cannot create containers.
The script refuses every container of the app (`lib/core/cosmos_paths.dart`)
and the old `period_start_snapshots`, before it signs in. The docs it writes
have ids `signin-check-<random>-1` and `-2`; it deletes them at the end.

Sign-in: the app's own (`AuthService.signIn`): authorization code with PKCE,
a browser, back to `http://localhost:<port>/`. So the app registration needs
no change (a device code would need public client flows switched on). The
token is for `https://<account>.documents.azure.com/user_impersonation`, and
lives in memory only. Tenant, client id and database endpoint come from
`.env` (`ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `COSMOS_ENDPOINT`); the script
never prints them, nor the token, nor what Entra or Cosmos say about the
account: only status codes, the Entra error code (`AADSTS...`) and, for a
403, the permission that is missing.

Exit code 0 when every step answered as the app expects, 1 when one did not,
2 when the script refused to start.

Standard library only. Tests (no network, no `.env`):

    python -m unittest discover -s tooling/school/tests
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.server
import json
import re
import secrets
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import formatdate
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / ".env"
COSMOS_PATHS = ROOT / "lib" / "core" / "cosmos_paths.dart"
DEFAULT_DATABASE = "python-tutor"
API_VERSION = "2018-12-31"  # what the app sends (`CosmosClient`)
SIGN_IN_TIMEOUT = 300.0  # seconds to finish the sign-in in the browser
REQUEST_TIMEOUT = 30.0

# Not in cosmos_paths.dart any more, but still in an older database.
LEGACY_CONTAINERS = frozenset({"period_start_snapshots"})

_NAME = re.compile(r"[A-Za-z0-9_-]{1,255}")


# ---- settings ----------------------------------------------------------------


@dataclass(frozen=True)
class Settings:
    tenant: str
    client_id: str
    endpoint: str
    """The database account's origin, with a trailing slash."""

    def __repr__(self) -> str:  # never print the values
        return "Settings(...)"


def load_env(path: Path) -> dict[str, str]:
    if not path.exists():
        sys.exit("geen .env gevonden in de map van de repo")
    env: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def settings_from(env: dict[str, str]) -> Settings:
    missing = [
        k
        for k in ("ENTRA_TENANT_ID", "ENTRA_CLIENT_ID", "COSMOS_ENDPOINT")
        if not env.get(k) or env[k].lower() == "dummy"
    ]
    if missing:
        sys.exit(".env mist een waarde voor: " + ", ".join(missing))
    url = urllib.parse.urlsplit(env["COSMOS_ENDPOINT"])
    if url.scheme != "https" or not url.hostname:
        sys.exit("COSMOS_ENDPOINT in .env is geen https-adres")
    return Settings(
        tenant=env["ENTRA_TENANT_ID"],
        client_id=env["ENTRA_CLIENT_ID"],
        endpoint=f"https://{url.netloc}/",
    )


def cosmos_scope(endpoint: str) -> str:
    """The scope of the database account: its origin without a port, then
    `/user_impersonation` (`CosmosTokenSource.scopeFor`)."""
    return f"https://{urllib.parse.urlsplit(endpoint).hostname}/user_impersonation"


# ---- the guard ---------------------------------------------------------------


def app_containers(source: str) -> set[str]:
    """The containers declared in `cosmos_paths.dart`."""
    return set(re.findall(r"^const String _\w+Container = '([^']+)';", source, re.M))


def refusal(container: str, database: str, app: set[str]) -> str | None:
    """Why the script must not run against [container], or None."""
    if not _NAME.fullmatch(container):
        return f"`{container}` is geen geldige naam voor een container"
    if not _NAME.fullmatch(database):
        return f"`{database}` is geen geldige naam voor een database"
    if not app:
        return (
            "de containers van de app staan niet in lib/core/cosmos_paths.dart "
            "zoals verwacht; het script weigert liever"
        )
    taken = {c.lower() for c in app | LEGACY_CONTAINERS}
    if container.lower() in taken:
        return (
            f"`{container}` is een container van de app. Maak een aparte "
            "testcontainer aan (README) en geef die mee."
        )
    return None


# ---- sign-in -----------------------------------------------------------------


class SignInError(Exception):
    """The sign-in failed. The message is safe to print."""


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def pkce_pair() -> tuple[str, str]:
    verifier = _b64url(secrets.token_bytes(32))
    return verifier, _b64url(hashlib.sha256(verifier.encode("ascii")).digest())


def safe_error(payload: dict) -> str:
    """What Entra said, without what it says about the tenant or the app:
    the error, and the `AADSTS` code of its description."""
    error = str(payload.get("error") or "onbekende fout")
    if not re.fullmatch(r"[a-z_]{1,64}", error):
        error = "onbekende fout"
    code = re.search(r"AADSTS\d+", str(payload.get("error_description") or ""))
    hint = ""
    if code and code.group(0) == "AADSTS65001":
        hint = " (geen toestemming voor de app: zie Admin consent in de README)"
    return error + (f" {code.group(0)}" if code else "") + hint


def _post_form(url: str, form: dict[str, str]) -> tuple[int, dict]:
    data = urllib.parse.urlencode(form).encode("ascii")
    request = urllib.request.Request(url, data=data, method="POST")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as r:
            status, body = r.status, r.read()
    except urllib.error.HTTPError as e:
        status, body = e.code, e.read()
    except OSError as e:  # URLError, a timeout: the url holds the tenant
        raise SignInError(f"geen antwoord van Entra ({type(e).__name__})") from None
    try:
        payload = json.loads(body or b"{}")
    except ValueError:
        payload = {}
    return status, payload if isinstance(payload, dict) else {}


_LANDING = (
    "<!doctype html><meta charset='utf-8'><title>AI Tutor</title>"
    "<p style='font-family:sans-serif'>{}</p>"
)


def _await_redirect(timeout: float, on_ready: Callable[[str], None]) -> dict[str, str]:
    """Listens on a free loopback port; [on_ready] gets the redirect uri.
    Returns the query of the first request that carries a code or an error."""
    got: dict[str, str] = {}
    done = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 (the stdlib's name)
            query = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(self.path).query))
            if done.is_set() or not ({"code", "error"} & query.keys()):
                self.send_response(404)
                self.end_headers()
                return
            got.update(query)
            text = (
                "Aangemeld. Je kan dit venster sluiten."
                if "code" in query
                else "Aanmelden is niet gelukt. Kijk in het venster van het script."
            )
            body = _LANDING.format(text).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            done.set()

        def log_message(self, *args):  # the query holds the code: keep it quiet
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        on_ready(f"http://localhost:{server.server_address[1]}/")
        if not done.wait(timeout):
            raise SignInError("geen aanmelding binnen de tijd")
        return got
    finally:
        server.shutdown()
        server.server_close()


def sign_in(
    settings: Settings,
    *,
    open_browser: Callable[[str], bool] = webbrowser.open,
    post_form: Callable[[str, dict[str, str]], tuple[int, dict]] = _post_form,
    timeout: float = SIGN_IN_TIMEOUT,
) -> str:
    """An access token for the database, from a sign-in in the browser."""
    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(24)
    scope = cosmos_scope(settings.endpoint)
    base = f"https://login.microsoftonline.com/{settings.tenant}/oauth2/v2.0"
    redirect: dict[str, str] = {}

    def launch(uri: str) -> None:
        redirect["uri"] = uri
        url = f"{base}/authorize?" + urllib.parse.urlencode(
            {
                "client_id": settings.client_id,
                "response_type": "code",
                "redirect_uri": uri,
                "response_mode": "query",
                "scope": scope,
                "state": state,
                "code_challenge": challenge,
                "code_challenge_method": "S256",
                "prompt": "select_account",
            }
        )
        if not open_browser(url):
            raise SignInError("kon geen browser openen")

    query = _await_redirect(timeout, launch)
    if "error" in query:
        raise SignInError("Entra weigerde de aanmelding: " + safe_error(query))
    if query.get("state") != state:
        raise SignInError("het antwoord van de aanmelding hoort niet bij dit script")
    status, payload = post_form(
        f"{base}/token",
        {
            "client_id": settings.client_id,
            "grant_type": "authorization_code",
            "code": query["code"],
            "redirect_uri": redirect["uri"],
            "code_verifier": verifier,
            "scope": scope,
        },
    )
    token = payload.get("access_token")
    if status != 200 or not isinstance(token, str) or not token:
        raise SignInError(f"geen token ({status}): " + safe_error(payload))
    return token


# ---- Cosmos with a token -----------------------------------------------------


@dataclass
class Response:
    status: int
    headers: dict[str, str]
    body: bytes

    def json(self) -> dict:
        try:
            out = json.loads(self.body or b"{}")
        except ValueError:
            return {}
        return out if isinstance(out, dict) else {"_list": out}


Send = Callable[[str, str, dict[str, str], "bytes | None"], Response]


def urllib_send(method: str, url: str, headers: dict[str, str], body: bytes | None) -> Response:
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as r:
            return Response(r.status, dict(r.headers.items()), r.read())
    except urllib.error.HTTPError as e:
        return Response(e.code, dict(e.headers.items()), e.read())


class NoAnswer(Exception):
    """No response at all (network, timeout). The message is safe to print."""


class Cosmos:
    """The REST calls of `CosmosClient`, with `type=aad` auth."""

    def __init__(
        self, endpoint: str, database: str, container: str, token: str, send: Send
    ):
        self._endpoint = endpoint
        self._coll = f"dbs/{database}/colls/{container}"
        self._auth = urllib.parse.quote(f"type=aad&ver=1.0&sig={token}", safe="")
        self._send = send

    def _call(
        self, method: str, path: str, extra: dict[str, str] | None = None, body=None
    ) -> Response:
        headers = {
            "Authorization": self._auth,
            "x-ms-version": API_VERSION,
            "x-ms-date": formatdate(usegmt=True),
            **(extra or {}),
        }
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers.setdefault("Content-Type", "application/json")
        try:
            return self._send(method, self._endpoint + path, headers, data)
        except (urllib.error.URLError, OSError) as e:
            raise NoAnswer(type(e).__name__) from None

    @staticmethod
    def _pk(value) -> dict[str, str]:
        return {"x-ms-documentdb-partitionkey": json.dumps([value])}

    def _doc(self, doc_id: str) -> str:
        return f"{self._coll}/docs/{urllib.parse.quote(doc_id, safe='')}"

    def read_container(self) -> Response:
        return self._call("GET", self._coll)

    def create(self, doc: dict, pk) -> Response:
        return self._call("POST", f"{self._coll}/docs", self._pk(pk), doc)

    def read(self, doc_id: str, pk) -> Response:
        return self._call("GET", self._doc(doc_id), self._pk(pk))

    def query(self, sql: str, params: dict, pk) -> Response:
        body = {"query": sql, "parameters": [{"name": k, "value": v} for k, v in params.items()]}
        headers = {
            "Content-Type": "application/query+json",
            "x-ms-documentdb-isquery": "true",
            **self._pk(pk),
        }
        return self._call("POST", f"{self._coll}/docs", headers, body)

    def replace(self, doc_id: str, doc: dict, pk, if_match: str) -> Response:
        return self._call("PUT", self._doc(doc_id), {**self._pk(pk), "If-Match": if_match}, doc)

    def batch(self, ops: list[dict], pk) -> Response:
        headers = {
            **self._pk(pk),
            "x-ms-cosmos-is-batch-request": "true",
            "x-ms-cosmos-batch-atomic": "true",
        }
        return self._call("POST", f"{self._coll}/docs", headers, ops)

    def delete(self, doc_id: str, pk) -> Response:
        return self._call("DELETE", self._doc(doc_id), self._pk(pk))


# ---- the check ---------------------------------------------------------------


@dataclass
class Step:
    name: str
    expected: int
    status: int | None = None
    """None: skipped, or no answer."""
    note: str = ""
    extra_ok: bool = True
    """A check on the answer beyond its status code."""

    @property
    def ok(self) -> bool:
        return self.status == self.expected and self.extra_ok


def _missing_permission(response: Response) -> str:
    """For a 403: the permission Cosmos names, and nothing else it says."""
    message = str(response.json().get("message", ""))
    m = re.search(r"perform action \[([A-Za-z0-9/._*-]+)\]", message)
    return f"ontbreekt: {m.group(1)}" if m else ""


@dataclass
class _Run:
    steps: list[Step] = field(default_factory=list)

    def step(
        self, name: str, expected: int, call: Callable[[], Response] | None
    ) -> Response | None:
        s = Step(name, expected)
        self.steps.append(s)
        if call is None:
            s.note = "overgeslagen"
            return None
        try:
            response = call()
        except NoAnswer as e:
            s.note = f"geen antwoord ({e})"
            return None
        s.status = response.status
        if response.status == 401:
            s.note = "token geweigerd"
        elif response.status == 403:
            s.note = _missing_permission(response)
        return response

    def fail(self, note: str) -> None:
        """The last step answered, but not as the app expects."""
        self.steps[-1].extra_ok = False
        self.steps[-1].note = note


def _partition_field(response: Response) -> str | None:
    """The doc field of the container's partition key: `/pk` gives `pk`.
    None for a key the check cannot fill in: nested, hierarchical, or `/id`
    (the batch puts two docs in one partition)."""
    paths = (response.json().get("partitionKey") or {}).get("paths") or []
    if len(paths) != 1 or not re.fullmatch(r"/[A-Za-z0-9_]+", str(paths[0])):
        return None
    return None if paths[0] == "/id" else paths[0][1:]


def check(cosmos: Cosmos, *, run_id: str, now: str) -> list[Step]:
    """Runs the steps in order. A step that needs what an earlier one did
    not get (the container's partition key, the doc, its etag) is skipped;
    the docs that were written are deleted at the end either way."""
    run = _Run()
    first = f"signin-check-{run_id}-1"
    second = f"signin-check-{run_id}-2"
    pk = "signin-check"

    meta = run.step("container lezen", 200, cosmos.read_container)
    key = None
    if meta is not None and meta.status == 200:
        key = _partition_field(meta)
        if key is None:
            run.fail("maak de testcontainer met een partitiesleutel als /pk")

    def doc(doc_id: str, step: str) -> dict:
        return {"id": doc_id, key: pk, "step": step, "checkedAt": now}

    def when(ready: bool, call: Callable[[], Response]):
        return call if ready else None

    created = run.step(
        "document aanmaken",
        201,
        when(key is not None, lambda: cosmos.create(doc(first, "create"), pk)),
    )
    etag = None
    if created is not None and created.status == 201:
        etag = created.json().get("_etag")
        if not isinstance(etag, str) or not etag:
            etag = None
            run.fail("geen _etag in het antwoord")
    exists = etag is not None

    run.step("document lezen", 200, when(exists, lambda: cosmos.read(first, pk)))

    found = run.step(
        "query",
        200,
        when(
            exists,
            lambda: cosmos.query(
                "SELECT * FROM c WHERE c.id = @id", {"@id": first}, pk
            ),
        ),
    )
    if found is not None and found.status == 200:
        n = len(found.json().get("Documents") or [])
        if n == 1:
            run.steps[-1].note = "1 gevonden"
        else:
            run.fail(f"{n} gevonden, verwacht 1")

    replaced = run.step(
        "vervangen met If-Match",
        200,
        when(exists, lambda: cosmos.replace(first, doc(first, "replace"), pk, etag)),
    )
    replaced_ok = replaced is not None and replaced.status == 200
    if replaced_ok and replaced.json().get("_etag") == etag:
        run.fail("het etag veranderde niet")

    stale = run.step(
        "vervangen met het oude etag",
        412,
        when(
            replaced_ok, lambda: cosmos.replace(first, doc(first, "stale"), pk, etag)
        ),
    )
    if stale is not None and stale.status == 412:
        run.steps[-1].note = "geweigerd, zoals het hoort"

    batched = run.step(
        "transactionele batch",
        200,
        when(
            key is not None,
            lambda: cosmos.batch(
                [
                    {"operationType": "Create", "resourceBody": doc(second, "batch")},
                    {"operationType": "Upsert", "resourceBody": doc(first, "batch")},
                ],
                pk,
            ),
        ),
    )
    batch_ok = batched is not None and batched.status == 200
    if batched is not None and batched.status in (200, 207):
        codes = [
            r.get("statusCode")
            for r in batched.json().get("_list", [])
            if isinstance(r, dict)
        ]
        run.steps[-1].note = "per opdracht: " + ", ".join(str(c) for c in codes)
        if not (
            len(codes) == 2
            and all(isinstance(c, int) and 200 <= c < 300 for c in codes)
        ):
            run.steps[-1].extra_ok = False
            batch_ok = False

    run.step(
        "document verwijderen",
        204,
        when(exists or batch_ok, lambda: cosmos.delete(first, pk)),
    )
    run.step(
        "batchdocument verwijderen",
        204,
        when(batch_ok, lambda: cosmos.delete(second, pk)),
    )
    return run.steps


def report(container: str, steps: list[Step]) -> str:
    lines = [f"Test op de container `{container}`:", ""]
    for s in steps:
        code = "-" if s.status is None else str(s.status)
        verdict = "ok" if s.ok else f"NIET OK (verwacht {s.expected})"
        if s.status is None:
            verdict = "-"
        note = f" ({s.note})" if s.note else ""
        lines.append(f"  {s.name:<30} {code:>4}  {verdict}{note}")
    lines.append("")
    if all(s.ok for s in steps):
        lines.append("Alles werkt zoals de app het verwacht.")
    else:
        lines.append(
            "Niet alles werkt. Een 403 is een rol die ontbreekt (README, Roles per "
            "container); een rol of groep die net veranderde, kan enkele minuten "
            "nodig hebben."
        )
    return "\n".join(lines)


# ---- the run -----------------------------------------------------------------


def main(
    argv: list[str] | None = None,
    *,
    env_path: Path = ENV_PATH,
    cosmos_paths: Path = COSMOS_PATHS,
    get_token: Callable[[Settings], str] = sign_in,
    send: Send = urllib_send,
) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument(
        "--container", required=True, help="de testcontainer, nooit een van de app"
    )
    p.add_argument(
        "--database",
        default=DEFAULT_DATABASE,
        help=f"de database (standaard {DEFAULT_DATABASE})",
    )
    args = p.parse_args(argv)

    source = cosmos_paths.read_text(encoding="utf-8") if cosmos_paths.exists() else ""
    reason = refusal(args.container, args.database, app_containers(source))
    if reason:
        print(reason, file=sys.stderr)
        return 2

    settings = settings_from(load_env(env_path))
    print("Aanmelden: er opent een browser. Meld je aan met het account dat je wilt nakijken.")
    try:
        token = get_token(settings)
    except SignInError as e:
        print(f"Aanmelden is niet gelukt: {e}", file=sys.stderr)
        return 1
    print("Aangemeld.\n")

    cosmos = Cosmos(settings.endpoint, args.database, args.container, token, send)
    steps = check(
        cosmos,
        run_id=secrets.token_hex(4),
        now=datetime.now(timezone.utc).isoformat(timespec="seconds"),
    )
    print(report(args.container, steps))
    return 0 if all(s.ok for s in steps) else 1


if __name__ == "__main__":
    sys.exit(main())
