"""Tests for the check of access with the user's own sign-in (#306): that it
refuses every container of the app before it signs in, that it sends what
the app sends (a `type=aad` token, the API version, the partition key,
`If-Match`, the batch headers), that it reports each step's status code and
skips what cannot run, and that it never prints the tenant, the client id,
the endpoint, the token or what Cosmos and Entra say about the account.
Standard library only:

    python -m unittest discover -s tooling/school/tests

No test reaches Entra or Cosmos: a fake HTTP layer stands in for the
database, and the sign-in runs against a fake browser and a fake token
endpoint (the redirect goes to the script's own loopback listener).
"""

from __future__ import annotations

import base64
import contextlib
import hashlib
import io
import json
import re
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_signin_access as csa  # noqa: E402

TENANT = "11111111-2222-3333-4444-555555555555"
CLIENT = "66666666-7777-8888-9999-000000000000"
HOST = "example-school.documents.azure.com"
ENDPOINT = f"https://{HOST}:443/"
TOKEN = "eyJ0eXAiOiJKV1QifQ.fake-token-value.signature"
OID = "abcdef01-2345-6789-abcd-ef0123456789"
SETTINGS = csa.Settings(tenant=TENANT, client_id=CLIENT, endpoint=f"https://{HOST}:443/")
SECRETS = (TENANT, CLIENT, HOST, TOKEN, OID, "example-school")


def _response(status: int, body=None, headers=None) -> csa.Response:
    data = b"" if body is None else json.dumps(body).encode("utf-8")
    return csa.Response(status, headers or {}, data)


def _forbidden(action: str) -> csa.Response:
    """A 403 as Cosmos words it for a missing role: with the account and the
    principal in it, which the script must not print."""
    return _response(
        403,
        {
            "code": "Forbidden",
            "message": (
                "Request blocked by Auth example-school : Request is blocked "
                f"because principal [{OID}] does not have required RBAC "
                f"permissions to perform action [{action}] on resource "
                "[dbs/python-tutor/colls/signin_check]."
            ),
        },
    )


class FakeCosmos:
    """One container in memory, answering the REST calls the way Cosmos does
    for what the script sends. [deny] maps an operation (`meta`, `create`,
    `read`, `query`, `replace`, `batch`, `delete`) to the action of its 403."""

    def __init__(self, *, partition_key="/pk", deny=None, batch_codes=None):
        self.partition_key = partition_key
        self.deny = deny or {}
        self.batch_codes = batch_codes
        self.docs: dict[str, dict] = {}
        self.calls: list[tuple[str, str, dict, bytes | None]] = []
        self._etag = 0

    def _next_etag(self) -> str:
        self._etag += 1
        return f'"etag-{self._etag}"'

    def _store(self, doc: dict) -> dict:
        stored = {**doc, "_etag": self._next_etag(), "_rid": "x"}
        self.docs[doc["id"]] = stored
        return stored

    def send(self, method, url, headers, body):
        self.calls.append((method, url, dict(headers), body))
        path = urllib.parse.urlsplit(url).path.strip("/").split("/")
        assert path[:2] == ["dbs", "python-tutor"] and path[2] == "colls", path
        doc = json.loads(body) if body else None
        if len(path) == 4:
            op = "meta"
        elif len(path) == 5:
            if headers.get("x-ms-cosmos-is-batch-request") == "true":
                op = "batch"
            elif headers.get("x-ms-documentdb-isquery") == "true":
                op = "query"
            else:
                op = "create"
        else:
            op = {"GET": "read", "PUT": "replace", "DELETE": "delete"}[method]
        if op in self.deny:
            return _forbidden(self.deny[op])
        doc_id = urllib.parse.unquote(path[5]) if len(path) == 6 else None
        if op == "meta":
            return _response(200, {"id": path[3], "partitionKey": {"paths": [self.partition_key], "kind": "Hash"}})
        if op == "create":
            if doc["id"] in self.docs:
                return _response(409, {"code": "Conflict"})
            return _response(201, self._store(doc))
        if op == "read":
            return _response(200, self.docs[doc_id]) if doc_id in self.docs else _response(404, {})
        if op == "query":
            wanted = {p["name"]: p["value"] for p in doc["parameters"]}["@id"]
            found = [d for d in self.docs.values() if d["id"] == wanted]
            return _response(200, {"Documents": found, "_count": len(found)})
        if op == "replace":
            if doc_id not in self.docs:
                return _response(404, {})
            if headers.get("If-Match") != self.docs[doc_id]["_etag"]:
                return _response(412, {"code": "PreconditionFailed"})
            return _response(200, self._store(doc))
        if op == "batch":
            if self.batch_codes is not None:
                return _response(207, [{"statusCode": c} for c in self.batch_codes])
            results = []
            for o in doc:
                body_doc = o["resourceBody"]
                code = 200 if body_doc["id"] in self.docs else 201
                self._store(body_doc)
                results.append({"statusCode": code})
            return _response(200, results)
        if op == "delete":
            if doc_id not in self.docs:
                return _response(404, {})
            del self.docs[doc_id]
            return _response(204)
        raise AssertionError(op)


def _run_check(fake: FakeCosmos) -> list[csa.Step]:
    cosmos = csa.Cosmos(SETTINGS.endpoint, "python-tutor", "signin_check", TOKEN, fake.send)
    return csa.check(cosmos, run_id="r1", now="2026-11-26T10:00:00+00:00")


def _codes(steps) -> list:
    return [(s.name, s.status, s.ok) for s in steps]


class AppContainersTest(unittest.TestCase):
    def test_reads_every_container_of_the_app(self):
        source = csa.COSMOS_PATHS.read_text(encoding="utf-8")
        found = csa.app_containers(source)
        getters = len(re.findall(r"static CosmosContainer \w+\(\)", source))
        self.assertEqual(len(found), getters)
        self.assertTrue({"accounts", "config", "podium", "questions", "goals"} <= found)


class RefusalTest(unittest.TestCase):
    app = csa.app_containers(csa.COSMOS_PATHS.read_text(encoding="utf-8"))

    def test_refuses_every_container_of_the_app(self):
        for name in sorted(self.app):
            with self.subTest(name=name):
                self.assertIsNotNone(csa.refusal(name, "python-tutor", self.app))

    def test_refuses_another_spelling_and_the_old_container(self):
        for name in ("Accounts", "PODIUM", "period_start_snapshots"):
            with self.subTest(name=name):
                self.assertIsNotNone(csa.refusal(name, "python-tutor", self.app))

    def test_refuses_a_name_that_is_not_a_container_name(self):
        for name in ("../accounts", "a/b", "", "with space"):
            with self.subTest(name=name):
                self.assertIsNotNone(csa.refusal(name, "python-tutor", self.app))
        self.assertIsNotNone(csa.refusal("signin_check", "../db", self.app))

    def test_refuses_when_the_app_containers_cannot_be_read(self):
        self.assertIsNotNone(csa.refusal("signin_check", "python-tutor", set()))

    def test_allows_a_test_container(self):
        self.assertIsNone(csa.refusal("signin_check", "python-tutor", self.app))


class MainTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = self.tmp / ".env"
        self.env.write_text(
            f"ENTRA_TENANT_ID={TENANT}\nENTRA_CLIENT_ID={CLIENT}\n"
            f"COSMOS_ENDPOINT={ENDPOINT}\nCOSMOS_KEY=c2VjcmV0\n",
            encoding="utf-8",
        )

    def _main(self, argv, fake=None, get_token=None):
        out, err = io.StringIO(), io.StringIO()
        signed_in = []

        def token(settings):
            signed_in.append(settings)
            return TOKEN

        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = csa.main(
                argv,
                env_path=self.env,
                get_token=get_token or token,
                send=(fake or FakeCosmos()).send,
            )
        return code, out.getvalue() + err.getvalue(), signed_in

    def test_refuses_a_container_of_the_app_before_anything_else(self):
        fake = FakeCosmos()
        self.env.unlink()  # not even .env is read
        code, text, signed_in = self._main(["--container", "accounts"], fake)
        self.assertEqual(code, 2)
        self.assertEqual(signed_in, [])
        self.assertEqual(fake.calls, [])
        self.assertIn("container van de app", text)

    def test_every_step_ok_gives_exit_code_0(self):
        fake = FakeCosmos()
        code, text, signed_in = self._main(["--container", "signin_check"], fake)
        self.assertEqual(code, 0, text)
        self.assertEqual(len(signed_in), 1)
        self.assertEqual(signed_in[0].endpoint, f"https://{HOST}:443/")
        self.assertIn("Alles werkt", text)
        for status in ("200", "201", "412", "204"):
            self.assertIn(status, text)
        self.assertEqual(fake.docs, {}, "both docs are deleted again")

    def test_prints_no_secret(self):
        fake = FakeCosmos(deny={"create": "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/create"})
        code, text, _ = self._main(["--container", "signin_check"], fake)
        self.assertEqual(code, 1)
        for secret in SECRETS:
            self.assertNotIn(secret, text)
        self.assertNotIn("c2VjcmV0", text)

    def test_a_failed_sign_in_gives_exit_code_1(self):
        def fails(settings):
            raise csa.SignInError("Entra weigerde de aanmelding: access_denied")

        fake = FakeCosmos()
        code, text, _ = self._main(["--container", "signin_check"], fake, get_token=fails)
        self.assertEqual(code, 1)
        self.assertEqual(fake.calls, [])
        self.assertIn("access_denied", text)

    def test_a_missing_env_value_names_the_key_only(self):
        self.env.write_text(f"ENTRA_TENANT_ID={TENANT}\nCOSMOS_ENDPOINT={ENDPOINT}\n", encoding="utf-8")
        with self.assertRaises(SystemExit) as raised:
            self._main(["--container", "signin_check"])
        self.assertIn("ENTRA_CLIENT_ID", str(raised.exception))
        self.assertNotIn(TENANT, str(raised.exception))


class CheckTest(unittest.TestCase):
    def test_runs_every_step_in_order_and_all_pass(self):
        fake = FakeCosmos()
        steps = _run_check(fake)
        self.assertEqual(
            _codes(steps),
            [
                ("container lezen", 200, True),
                ("document aanmaken", 201, True),
                ("document lezen", 200, True),
                ("query", 200, True),
                ("vervangen met If-Match", 200, True),
                ("vervangen met het oude etag", 412, True),
                ("transactionele batch", 200, True),
                ("document verwijderen", 204, True),
                ("batchdocument verwijderen", 204, True),
            ],
        )
        self.assertEqual(fake.docs, {})

    def test_sends_what_the_app_sends(self):
        fake = FakeCosmos()
        _run_check(fake)
        expected_auth = urllib.parse.quote(f"type=aad&ver=1.0&sig={TOKEN}", safe="")
        for method, url, headers, _ in fake.calls:
            self.assertTrue(url.startswith(f"https://{HOST}:443/dbs/python-tutor/colls/signin_check"))
            self.assertEqual(headers["Authorization"], expected_auth)
            self.assertEqual(headers["x-ms-version"], "2018-12-31")
            self.assertIn("x-ms-date", headers)
            if len(urllib.parse.urlsplit(url).path.strip("/").split("/")) > 4:
                self.assertEqual(headers["x-ms-documentdb-partitionkey"], '["signin-check"]')

        replaces = [c for c in fake.calls if c[0] == "PUT"]
        self.assertEqual([h["If-Match"] for _, _, h, _ in replaces], ['"etag-1"', '"etag-1"'])

        batch = [c for c in fake.calls if c[2].get("x-ms-cosmos-is-batch-request") == "true"]
        self.assertEqual(len(batch), 1)
        self.assertEqual(batch[0][2]["x-ms-cosmos-batch-atomic"], "true")
        ops = json.loads(batch[0][3])
        self.assertEqual([o["operationType"] for o in ops], ["Create", "Upsert"])
        self.assertEqual({o["resourceBody"]["pk"] for o in ops}, {"signin-check"})

        query = [c for c in fake.calls if c[2].get("x-ms-documentdb-isquery") == "true"]
        self.assertEqual(query[0][2]["Content-Type"], "application/query+json")

    def test_fills_in_the_partition_key_of_the_container(self):
        fake = FakeCosmos(partition_key="/uid")
        steps = _run_check(fake)
        self.assertTrue(all(s.ok for s in steps))
        creates = [json.loads(c[3]) for c in fake.calls if c[0] == "POST" and c[3] and b'"step": "create"' in c[3]]
        self.assertEqual(creates[0]["uid"], "signin-check")

    def test_a_partition_key_on_id_stops_before_writing(self):
        fake = FakeCosmos(partition_key="/id")
        steps = _run_check(fake)
        self.assertFalse(steps[0].ok)
        self.assertIn("/pk", steps[0].note)
        self.assertTrue(all(s.status is None for s in steps[1:]))
        self.assertEqual(len(fake.calls), 1)

    def test_no_role_stops_at_the_container(self):
        fake = FakeCosmos(deny={"meta": "Microsoft.DocumentDB/databaseAccounts/readMetadata"})
        steps = _run_check(fake)
        self.assertEqual(steps[0].status, 403)
        self.assertEqual(steps[0].note, "ontbreekt: Microsoft.DocumentDB/databaseAccounts/readMetadata")
        self.assertTrue(all(s.status is None and s.note == "overgeslagen" for s in steps[1:]))
        self.assertEqual(len(fake.calls), 1)

    def test_a_reader_role_fails_the_writes_and_names_the_permission(self):
        action = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/create"
        fake = FakeCosmos(deny={"create": action, "batch": action})
        steps = _run_check(fake)
        by_name = {s.name: s for s in steps}
        self.assertEqual(by_name["container lezen"].status, 200)
        self.assertEqual(by_name["document aanmaken"].status, 403)
        self.assertEqual(by_name["document aanmaken"].note, f"ontbreekt: {action}")
        self.assertEqual(by_name["transactionele batch"].status, 403)
        for name in ("document lezen", "query", "vervangen met If-Match", "document verwijderen"):
            self.assertIsNone(by_name[name].status, name)
        report = csa.report("signin_check", steps)
        self.assertIn("NIET OK", report)
        self.assertNotIn(OID, report)
        self.assertNotIn("example-school", report)

    def test_an_if_match_that_is_not_honoured_fails(self):
        fake = FakeCosmos()
        real = fake.send

        def ignores_if_match(method, url, headers, body):
            if method == "PUT":
                headers = {k: v for k, v in headers.items() if k != "If-Match"}
                doc_id = urllib.parse.unquote(url.rsplit("/", 1)[1])
                headers["If-Match"] = fake.docs[doc_id]["_etag"]
            return real(method, url, headers, body)

        cosmos = csa.Cosmos(SETTINGS.endpoint, "python-tutor", "signin_check", TOKEN, ignores_if_match)
        steps = csa.check(cosmos, run_id="r1", now="x")
        stale = next(s for s in steps if s.name == "vervangen met het oude etag")
        self.assertEqual(stale.status, 200)
        self.assertFalse(stale.ok)

    def test_a_failed_batch_is_not_ok_and_its_doc_is_not_deleted(self):
        fake = FakeCosmos(batch_codes=[409, 424])
        steps = _run_check(fake)
        batch = next(s for s in steps if s.name == "transactionele batch")
        self.assertFalse(batch.ok)
        self.assertIn("409, 424", batch.note)
        second = next(s for s in steps if s.name == "batchdocument verwijderen")
        self.assertIsNone(second.status)
        first = next(s for s in steps if s.name == "document verwijderen")
        self.assertEqual(first.status, 204)

    def test_no_answer_is_reported_not_raised(self):
        def offline(method, url, headers, body):
            raise OSError("network down near example-school")

        cosmos = csa.Cosmos(SETTINGS.endpoint, "python-tutor", "signin_check", TOKEN, offline)
        steps = csa.check(cosmos, run_id="r1", now="x")
        self.assertIsNone(steps[0].status)
        self.assertEqual(steps[0].note, "geen antwoord (OSError)")
        self.assertNotIn("example-school", csa.report("signin_check", steps))


class SignInTest(unittest.TestCase):
    """The sign-in against a fake browser: it follows the redirect to the
    script's own loopback listener, the way Entra sends the browser back."""

    def _browser(self, answer):
        seen = {}

        def open_browser(url):
            parts = urllib.parse.urlsplit(url)
            query = dict(urllib.parse.parse_qsl(parts.query))
            seen.update(query, url=url)
            params = answer(query)

            def visit():
                target = query["redirect_uri"] + "?" + urllib.parse.urlencode(params)
                with urllib.request.urlopen(target, timeout=5) as r:
                    seen["landing"] = r.read().decode("utf-8")

            seen["visit"] = threading.Thread(target=visit, daemon=True)
            seen["visit"].start()
            return True

        return open_browser, seen

    def test_exchanges_the_code_with_pkce_for_a_database_token(self):
        open_browser, seen = self._browser(lambda q: {"code": "the-code", "state": q["state"]})
        posted = {}

        def post_form(url, form):
            posted.update(form, url=url)
            return 200, {"access_token": TOKEN, "token_type": "Bearer"}

        token = csa.sign_in(SETTINGS, open_browser=open_browser, post_form=post_form, timeout=10)
        self.assertEqual(token, TOKEN)
        self.assertTrue(seen["url"].startswith(f"https://login.microsoftonline.com/{TENANT}/oauth2/v2.0/authorize?"))
        self.assertEqual(seen["client_id"], CLIENT)
        self.assertEqual(seen["scope"], f"https://{HOST}/user_impersonation")
        self.assertEqual(seen["code_challenge_method"], "S256")
        self.assertRegex(seen["redirect_uri"], r"^http://localhost:\d+/$")
        seen["visit"].join(5)
        self.assertIn("Aangemeld", seen["landing"])

        self.assertEqual(posted["url"], f"https://login.microsoftonline.com/{TENANT}/oauth2/v2.0/token")
        self.assertEqual(posted["grant_type"], "authorization_code")
        self.assertEqual(posted["code"], "the-code")
        self.assertEqual(posted["redirect_uri"], seen["redirect_uri"])
        self.assertEqual(posted["scope"], f"https://{HOST}/user_impersonation")
        challenge = base64.urlsafe_b64encode(
            hashlib.sha256(posted["code_verifier"].encode("ascii")).digest()
        ).rstrip(b"=").decode("ascii")
        self.assertEqual(challenge, seen["code_challenge"])

    def test_a_wrong_state_is_refused(self):
        open_browser, _ = self._browser(lambda q: {"code": "the-code", "state": "forged"})
        with self.assertRaises(csa.SignInError):
            csa.sign_in(SETTINGS, open_browser=open_browser, post_form=lambda u, f: (200, {}), timeout=10)

    def test_an_entra_error_keeps_only_its_code(self):
        description = (
            f"AADSTS65001: The user or administrator has not consented to use the "
            f"application with ID '{CLIENT}' named 'AI Tutor'. Trace ID: x"
        )
        open_browser, _ = self._browser(
            lambda q: {"error": "consent_required", "error_description": description, "state": q["state"]}
        )
        with self.assertRaises(csa.SignInError) as raised:
            csa.sign_in(SETTINGS, open_browser=open_browser, post_form=lambda u, f: (200, {}), timeout=10)
        message = str(raised.exception)
        self.assertIn("consent_required AADSTS65001", message)
        self.assertIn("Admin consent", message)
        self.assertNotIn(CLIENT, message)

    def test_a_refused_token_request_keeps_only_its_code(self):
        open_browser, _ = self._browser(lambda q: {"code": "the-code", "state": q["state"]})

        def post_form(url, form):
            return 400, {"error": "invalid_grant", "error_description": f"AADSTS70008: tenant {TENANT}"}

        with self.assertRaises(csa.SignInError) as raised:
            csa.sign_in(SETTINGS, open_browser=open_browser, post_form=post_form, timeout=10)
        self.assertIn("invalid_grant AADSTS70008", str(raised.exception))
        self.assertNotIn(TENANT, str(raised.exception))

    def test_no_answer_from_entra_keeps_the_url_out(self):
        url = f"https://login.microsoftonline.com/{TENANT}/oauth2/v2.0/token"
        with mock.patch.object(
            csa.urllib.request, "urlopen", side_effect=urllib.error.URLError(f"no route to {url}")
        ):
            with self.assertRaises(csa.SignInError) as raised:
                csa._post_form(url, {"client_id": CLIENT})
        self.assertEqual(str(raised.exception), "geen antwoord van Entra (URLError)")

    def test_no_browser_is_an_error(self):
        with self.assertRaises(csa.SignInError):
            csa.sign_in(SETTINGS, open_browser=lambda url: False, post_form=lambda u, f: (200, {}), timeout=1)

    def test_settings_never_show_their_values(self):
        self.assertNotIn(TENANT, repr(SETTINGS))
        self.assertNotIn(CLIENT, str(SETTINGS))


if __name__ == "__main__":
    unittest.main()
