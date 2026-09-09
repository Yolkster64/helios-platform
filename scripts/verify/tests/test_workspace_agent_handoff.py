"""Exercise the real handoff code against an inert HTTPS boundary only."""
import io
import json
import ssl
import unittest
from unittest.mock import Mock, patch

from scripts.bootstrap import workspace_agent_handoff as handoff


TOKEN = "synthetic-workspace-token-for-offline-test"
CHANNEL = "agtch_helios_test"
RUN = "apirun_offline_test"
URL = "https://chatgpt.com/c/helios-test"
ENV = {handoff.TOKEN_ENV: TOKEN, handoff.CHANNEL_ENV: CHANNEL}
PROMPT = "Review the HELIOS change and return a linked evidence summary."


class GuardEnvironment:
    def get(self, key, default=None):
        if key not in ENV:
            raise AssertionError("Unexpected environment access")
        return ENV[key]


class NoStdin:
    def isatty(self):
        raise AssertionError("Offline status must not inspect stdin")


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.factory = patch.object(handoff.http.client, "HTTPSConnection").start()
        self.addCleanup(patch.stopall)
        self.connection = self.factory.return_value
        self.connection.sock = None
        self.response = self.connection.getresponse.return_value
        self.respond()

    def respond(self, data=None, status=202, content_type="application/json", encoding="identity", raw=None):
        if data is None:
            data = {"conversation_url": URL, "agent_trigger_run_id": RUN}
        self.response.status = status
        self.response.getheader.side_effect = lambda name, default=None: {
            "Content-Type": content_type, "Content-Encoding": encoding
        }.get(name, default)
        self.response.read.return_value = json.dumps(data).encode() if raw is None else raw

    def run_command(self, args=None, env=None, stdin=None):
        output = io.StringIO()
        code = handoff.main(args or [], environ=ENV if env is None else env,
                            stdin=io.StringIO(PROMPT) if stdin is None else stdin, stdout=output)
        serialized = output.getvalue()
        self.assertNotIn(TOKEN, serialized)
        self.assertNotIn(PROMPT, serialized)
        return code, json.loads(serialized)

    def test_default_plan_and_status_are_offline_presence_only(self):
        for args in ([], ["plan"], ["status"]):
            with self.subTest(args=args):
                code, result = self.run_command(args, env=GuardEnvironment(), stdin=NoStdin())
                self.assertEqual(code, 0)
                self.assertEqual(result["status"], "configured_unverified")
                self.assertFalse(result["network_called"])
                self.assertEqual(result["environment"], {name: True for name in ENV})
        self.factory.assert_not_called()

    def test_unconfigured_status_does_not_claim_authentication(self):
        code, result = self.run_command(env={})
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "unconfigured")
        self.factory.assert_not_called()

    def test_model_api_key_is_not_a_workspace_credential(self):
        code, result = self.run_command(["send"], env={"OPENAI_API_KEY": "not-a-workspace-token"}, stdin=NoStdin())
        self.assertEqual(code, 2)
        self.assertEqual(result["status"], "unconfigured")
        self.factory.assert_not_called()

    def test_send_uses_exact_host_contract_and_private_stdin(self):
        code, result = self.run_command(["send", "--event-id", "github-commit-123"])
        self.assertEqual(code, 0)
        self.assertEqual(result, {"status": "accepted", "conversation_url": URL,
                                  "run_id": RUN, "event_id": "github-commit-123"})
        args, kwargs = self.factory.call_args
        self.assertEqual(args, ("api.chatgpt.com",))
        self.assertEqual(kwargs["timeout"], 20)
        self.assertEqual(kwargs["context"].verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(kwargs["context"].check_hostname)
        args, kwargs = self.connection.request.call_args
        self.assertEqual(args, ("POST", "/v1/workspace_agents/" + CHANNEL + "/trigger"))
        self.assertEqual(json.loads(kwargs["body"]), {"input": PROMPT, "conversation_key": "helios-control"})
        self.assertEqual(kwargs["headers"]["Authorization"], "Bearer " + TOKEN)
        self.assertEqual(kwargs["headers"]["Idempotency-Key"], "github-commit-123")
        self.assertEqual(kwargs["headers"]["OpenAI-Beta"], "workspace_agent_runs=v1")
        self.response.read.assert_called_once_with(handoff.MAX_BYTES + 1)
        self.connection.close.assert_called_once()

    def test_send_alias_unicode_and_generated_event_id(self):
        code, result = self.run_command(["--send", "--conversation-key", "helios-issue-123"], stdin=io.StringIO("Claude → HELIOS ✓"))
        self.assertEqual(code, 0)
        self.assertRegex(result["event_id"], r"^[a-f0-9-]{36}$")
        payload = json.loads(self.connection.request.call_args.kwargs["body"])
        self.assertEqual(payload["conversation_key"], "helios-issue-123")
        self.assertEqual(payload["input"], "Claude → HELIOS ✓")

    def test_stable_trigger_receipt_without_beta_run_id_is_accepted(self):
        self.respond({"conversation_url": URL})
        code, result = self.run_command(["send"])
        self.assertEqual(code, 0)
        self.assertNotIn("run_id", result)

    def test_missing_config_and_header_injection_are_rejected_before_input(self):
        for env in ({}, {**ENV, handoff.TOKEN_ENV: "bad\r\nAuthorization: injected"},
                    {**ENV, handoff.TOKEN_ENV: "x" * 8193},
                    {**ENV, handoff.CHANNEL_ENV: "agtch_abc/../../other"},
                    {**ENV, handoff.CHANNEL_ENV: "agt_ordinary_agent"}):
            with self.subTest(env=list(env)):
                code, _ = self.run_command(["send"], env=env, stdin=NoStdin())
                self.assertEqual(code, 2)
        self.factory.assert_not_called()

    def test_bad_identifiers_timeout_and_unknown_arguments_are_redacted(self):
        for args in (["send", "--event-id", "bad\nvalue"], ["send", "--conversation-key", "x" * 129],
                     ["send", "--timeout", "0"], ["send", "--timeout", "61"],
                     ["poll"], ["poll", "--run-id", "apirun_../other"],
                     ["status", "--run-id", RUN], ["status", "--event-id", "event"],
                     ["send", "--unknown-secret", TOKEN], ["send", "--timeout", TOKEN]):
            with self.subTest(args=args[:2]):
                code, result = self.run_command(args)
                self.assertEqual(code, 2)
                self.assertEqual(result["status"], "invalid_input")
        self.factory.assert_not_called()

    def test_stdin_requires_redirected_nonempty_bounded_utf8(self):
        terminal = Mock()
        terminal.isatty.return_value = True
        for stdin in (terminal, io.StringIO(" \n"), io.BytesIO(b"\xff"), io.BytesIO(b"a" * (handoff.MAX_BYTES + 1)), io.StringIO("nul\x00byte")):
            with self.subTest(stdin=type(stdin).__name__):
                code, _ = self.run_command(["send"], stdin=stdin)
                self.assertEqual(code, 2)
        self.factory.assert_not_called()

    def test_credential_in_prompt_or_identifier_never_leaves_machine(self):
        for args, stdin in ((["send"], io.StringIO("contains " + TOKEN)),
                            (["send", "--event-id", TOKEN], io.StringIO(PROMPT)),
                            (["send", "--conversation-key", TOKEN], io.StringIO(PROMPT))):
            code, _ = self.run_command(args, stdin=stdin)
            self.assertEqual(code, 2)
        self.factory.assert_not_called()

    def test_http_errors_ignore_bodies_and_never_retry_or_follow_redirects(self):
        for status in (200, 301, 302, 307, 308, 400, 401, 403, 404, 409, 429, 500, 503):
            with self.subTest(status=status):
                self.connection.request.reset_mock()
                self.response.read.reset_mock()
                self.respond(status=status, raw=TOKEN.encode())
                code, result = self.run_command(["send", "--event-id", "same-event"])
                self.assertEqual(code, 3)
                self.assertIn(result["status"], ("rejected", "unknown"))
                self.assertEqual(result["event_id"], "same-event")
                self.connection.request.assert_called_once()
                self.response.read.assert_not_called()

    def test_timeout_and_disconnect_report_unknown_with_retry_key(self):
        for error in (TimeoutError(TOKEN), ConnectionResetError(TOKEN), handoff.http.client.RemoteDisconnected(TOKEN)):
            with self.subTest(error=type(error).__name__):
                self.connection.request.reset_mock()
                self.connection.request.side_effect = error
                code, result = self.run_command(["send", "--event-id", "same-event"])
                self.assertEqual(code, 3)
                self.assertEqual(result, {"status": "unknown", "code": "request_interrupted", "event_id": "same-event"})
                self.connection.request.assert_called_once()

    def test_bad_json_content_encoding_and_large_responses_are_unknown(self):
        for raw, content_type, encoding in ((b"broken", "application/json", "identity"),
                                           (b"[]", "application/json", "identity"),
                                           (b"{}", "text/html", "identity"),
                                           (b"{}", "application/json", "gzip"),
                                           (b"x" * (handoff.MAX_BYTES + 1), "application/json", "identity"),
                                           (b"[" * 2000, "application/json", "identity")):
            with self.subTest(content_type=content_type, encoding=encoding, length=len(raw)):
                self.respond(raw=raw, content_type=content_type, encoding=encoding)
                code, result = self.run_command(["send"])
                self.assertEqual(code, 3)
                self.assertEqual(result["status"], "unknown")

    def test_untrusted_receipt_urls_and_run_ids_are_never_rendered(self):
        for url in ("https://evil.example/c/123", "http://chatgpt.com/c/123", "https://chatgpt.com.evil/c/123",
                    "https://user@chatgpt.com/c/123", URL + "?token=" + TOKEN, "https://chatgpt.com/c/" + TOKEN, None):
            self.respond({"conversation_url": url})
            code, result = self.run_command(["send"])
            self.assertEqual(code, 3)
            self.assertNotIn("conversation_url", result)
        self.respond({"conversation_url": URL, "agent_trigger_run_id": "bad\n" + TOKEN})
        self.assertEqual(self.run_command(["send"])[0], 3)

    def test_poll_is_one_get_and_returns_only_safe_state(self):
        for state in handoff.STATES:
            with self.subTest(state=state):
                self.connection.request.reset_mock()
                self.respond({"object": "workspace_agent.trigger_run", "id": RUN,
                              "api_trigger_id": CHANNEL, "status": state, "conversation_url": URL,
                              "error": {"code": "run_failed", "message": TOKEN}, "private_prompt": PROMPT}, status=200)
                code, result = self.run_command(["poll", "--run-id", RUN])
                self.assertEqual(code, 3 if state == "failed" else 0)
                self.assertEqual(result["status"], state)
                self.connection.request.assert_called_once()
                args, kwargs = self.connection.request.call_args
                self.assertEqual(args, ("GET", "/v1/workspace_agents/" + CHANNEL + "/runs/" + RUN))
                self.assertIsNone(kwargs["body"])
                self.assertNotIn("Idempotency-Key", kwargs["headers"])

    def test_poll_rejects_mismatched_channel_run_object_and_unknown_status(self):
        valid = {"object": "workspace_agent.trigger_run", "id": RUN, "api_trigger_id": CHANNEL,
                 "status": "completed", "conversation_url": URL}
        for update in ({"id": "apirun_other"}, {"api_trigger_id": "agtch_other"}, {"object": "other"},
                       {"status": "bogus"}, {"status": []}):
            self.respond({**valid, **update}, status=200)
            code, result = self.run_command(["poll", "--run-id", RUN])
            self.assertEqual(code, 3)
            self.assertEqual(result["status"], "unverified")

    def test_deadline_before_connect_finishes_never_dispatches(self):
        class ExpiredTimer:
            def __init__(self, seconds, callback):
                self.callback = callback
            def start(self):
                self.callback()
            def cancel(self):
                pass
        with patch.object(handoff.threading, "Timer", ExpiredTimer):
            code, result = self.run_command(["send"])
        self.assertEqual(code, 3)
        self.assertEqual(result["status"], "unknown")
        self.connection.request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
