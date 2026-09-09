#!/usr/bin/env python3
"""Explicit, bounded Claude/Codex -> ChatGPT Workspace Agent handoff.

Contract: https://developers.openai.com/workspace-agents/trigger-runs
This API continues the published agent's conversation, not an arbitrary chat.
Only send/poll make requests. Credentials and prompt contents never enter output.
"""
from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import socket
import ssl
import sys
import threading
import uuid
from typing import Any

HOST = "api.chatgpt.com"
TOKEN_ENV = "HELIOS_WORKSPACE_AGENT_TOKEN"
CHANNEL_ENV = "HELIOS_WORKSPACE_AGENT_CHANNEL_ID"
MAX_BYTES = 64 * 1024
KEY_PATTERN = r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}"
CHANNEL_PATTERN = r"agtch_[A-Za-z0-9_-]{1,200}"
RUN_PATTERN = r"apirun_[A-Za-z0-9_-]{1,200}"
URL_PATTERN = r"https://chatgpt\.com/c/[A-Za-z0-9_-]{1,200}"
STATES = {"queued", "in_progress", "suspended", "completed", "failed"}


class HandoffError(Exception):
    def __init__(self, status: str, code: str, exit_code: int = 2):
        super().__init__(code)
        self.status, self.code, self.exit_code = status, code, exit_code


class SafeParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        # argparse's normal diagnostic repeats arguments, which may be sensitive.
        raise HandoffError("invalid_input", "invalid_arguments")


def parser() -> argparse.ArgumentParser:
    result = SafeParser(description=__doc__)
    result.add_argument("action", nargs="?", choices=("plan", "status", "send", "poll"), default="plan")
    result.add_argument("--conversation-key", default="helios-control", help="Stable agent conversation key; local limit 128 ASCII characters.")
    result.add_argument("--event-id", help="Idempotency key: reuse only for the same input event.")
    result.add_argument("--run-id", help="apirun_ identifier returned by send; required for poll.")
    result.add_argument("--timeout", type=int, default=20, help="Network deadline in seconds, 1-60 (default 20).")
    return result


def valid(value: Any, pattern: str) -> bool:
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def configuration(environ: Any) -> tuple[str, str]:
    # Deliberately read only these two variables; no token files, fallback model key,
    # CLI login, browser session, .env loader or process/environment enumeration.
    return environ.get(TOKEN_ENV, ""), environ.get(CHANNEL_ENV, "")


def require_configuration(token: str, channel: str) -> None:
    if not token or not channel:
        raise HandoffError("unconfigured", "workspace_agent_credentials_required")
    if len(token) > 8192 or any(ord(char) < 33 or ord(char) > 126 for char in token):
        raise HandoffError("unconfigured", "invalid_workspace_agent_token")
    if not valid(channel, CHANNEL_PATTERN):
        raise HandoffError("unconfigured", "invalid_workspace_agent_channel")


def read_prompt(stream: Any) -> str:
    if stream.isatty():
        raise HandoffError("invalid_input", "redirect_utf8_prompt_to_stdin")
    raw = getattr(stream, "buffer", stream).read(MAX_BYTES + 1)
    if isinstance(raw, str):
        raw = raw.encode("utf-8")
    if len(raw) > MAX_BYTES:
        raise HandoffError("invalid_input", "prompt_too_large")
    try:
        prompt = raw.decode("utf-8")
    except UnicodeError:
        raise HandoffError("invalid_input", "prompt_must_be_utf8") from None
    if not prompt.strip() or "\x00" in prompt:
        raise HandoffError("invalid_input", "prompt_empty_or_invalid")
    return prompt


def request(method: str, path: str, token: str, body: bytes | None, timeout: int,
            event_id: str | None = None) -> tuple[int, dict[str, Any]]:
    """One TLS request, without proxies, redirects, retries or body diagnostics."""
    connection = http.client.HTTPSConnection(HOST, timeout=timeout, context=ssl.create_default_context())
    expired = threading.Event()

    def abort() -> None:
        expired.set()
        current_socket = connection.sock
        if current_socket is not None:
            try:
                current_socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            # Leave the closed socket attached until finally: http.client would
            # otherwise silently reconnect if the deadline races with request().
            current_socket.close()

    timer = threading.Timer(timeout, abort)
    timer.daemon = True
    timer.start()
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json",
               "Content-Type": "application/json", "OpenAI-Beta": "workspace_agent_runs=v1"}
    if event_id:
        headers["Idempotency-Key"] = event_id
    try:
        connection.connect()
        if expired.is_set():
            raise TimeoutError
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        # Error bodies can contain credentials or source input: never read/print them.
        expected = 202 if method == "POST" else 200
        if response.status != expected:
            return response.status, {}
        if response.getheader("Content-Type", "").split(";", 1)[0].strip().lower() != "application/json":
            raise HandoffError("unknown" if method == "POST" else "unverified", "invalid_response", 3)
        encoding = response.getheader("Content-Encoding", "identity").lower()
        if encoding not in ("", "identity"):
            raise HandoffError("unknown" if method == "POST" else "unverified", "invalid_response", 3)
        raw = response.read(MAX_BYTES + 1)
        if expired.is_set():
            raise TimeoutError
        if len(raw) > MAX_BYTES:
            raise HandoffError("unknown" if method == "POST" else "unverified", "response_too_large", 3)
        try:
            data = json.loads(raw)
        except (ValueError, UnicodeError, RecursionError):
            raise HandoffError("unknown" if method == "POST" else "unverified", "invalid_response", 3) from None
        if not isinstance(data, dict):
            raise HandoffError("unknown" if method == "POST" else "unverified", "invalid_response", 3)
        return response.status, data
    except (OSError, http.client.HTTPException):
        raise HandoffError("unknown" if method == "POST" else "unverified", "request_interrupted", 3) from None
    finally:
        timer.cancel()
        connection.close()


def require_success(status: int, expected: int, sending: bool) -> None:
    if status == expected:
        return
    codes = {401: "authentication_failed", 403: "permission_denied", 404: "channel_or_run_unavailable",
             409: "agent_not_runnable", 429: "rate_limited"}
    # Server errors, unexpected success and redirection do not establish delivery.
    state = "rejected" if 400 <= status < 500 else ("unknown" if sending else "unverified")
    raise HandoffError(state, codes.get(status, "unexpected_http_status"), 3)


def receipt(data: dict[str, Any], token: str, sending: bool, run_id: str | None = None,
            channel: str | None = None) -> dict[str, Any]:
    def invalid_receipt() -> None:
        raise HandoffError("unknown" if sending else "unverified", "invalid_receipt", 3)

    url = data.get("conversation_url")
    if not valid(url, URL_PATTERN) or token in url:
        invalid_receipt()
    if sending:
        run = data.get("agent_trigger_run_id")
        # Beta tracking may be unavailable while the stable trigger still succeeds.
        if run is not None and (not valid(run, RUN_PATTERN) or token in run):
            invalid_receipt()
        result = {"status": "accepted", "conversation_url": url}
        if run is not None:
            result["run_id"] = run
        return result
    if (data.get("object") != "workspace_agent.trigger_run" or data.get("id") != run_id
            or data.get("api_trigger_id") != channel or not isinstance(data.get("status"), str)
            or data.get("status") not in STATES):
        invalid_receipt()
    result = {"status": data["status"], "conversation_url": url, "run_id": run_id}
    if result["status"] == "failed":
        error = data.get("error")
        code = error.get("code") if isinstance(error, dict) else None
        result["code"] = code if code in ("dispatch_failed", "run_failed") else "run_failed"
    return result


def main(argv: list[str] | None = None, *, environ: Any = None, stdin: Any = None,
         stdout: Any = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    # Convenience spelling for callers that use the explicit --send action switch.
    if argv and argv[0] == "--send":
        argv = ["send", *argv[1:]]
    token = ""
    event_id = None
    output = stdout if stdout is not None else sys.stdout
    try:
        args = parser().parse_args(argv)
        if not 1 <= args.timeout <= 60 or not valid(args.conversation_key, KEY_PATTERN):
            raise HandoffError("invalid_input", "invalid_local_limits")
        if args.event_id is not None and not valid(args.event_id, KEY_PATTERN):
            raise HandoffError("invalid_input", "invalid_event_id")
        if args.run_id is not None and not valid(args.run_id, RUN_PATTERN):
            raise HandoffError("invalid_input", "invalid_run_id")
        if ((args.action == "poll") != (args.run_id is not None)
                or (args.event_id is not None and args.action != "send")):
            raise HandoffError("invalid_input", "invalid_arguments")
        token, channel = configuration(os.environ if environ is None else environ)
        if args.action in ("plan", "status"):
            result = {"status": "configured_unverified" if token and channel else "unconfigured",
                      "network_called": False, "environment": {TOKEN_ENV: bool(token), CHANNEL_ENV: bool(channel)},
                      "next": "send reads UTF-8 input from redirected stdin"}
            exit_code = 0
        else:
            require_configuration(token, channel)
            if token in args.conversation_key or (args.event_id and token in args.event_id) or (args.run_id and token in args.run_id):
                raise HandoffError("invalid_input", "credential_in_identifier")
            base = "/v1/workspace_agents/" + channel
            if args.action == "send":
                prompt = read_prompt(sys.stdin if stdin is None else stdin)
                if token in prompt:
                    raise HandoffError("invalid_input", "credential_in_input")
                event_id = args.event_id or str(uuid.uuid4())
                body = json.dumps({"input": prompt, "conversation_key": args.conversation_key}, ensure_ascii=False).encode("utf-8")
                status, data = request("POST", base + "/trigger", token, body, args.timeout, event_id)
                require_success(status, 202, True)
                result = receipt(data, token, True)
                result["event_id"] = event_id
            else:
                status, data = request("GET", base + "/runs/" + args.run_id, token, None, args.timeout)
                require_success(status, 200, False)
                result = receipt(data, token, False, args.run_id, channel)
            exit_code = 3 if result["status"] == "failed" else 0
    except HandoffError as error:
        result = {"status": error.status, "code": error.code}
        if event_id:
            result["event_id"] = event_id
        exit_code = error.exit_code
    except (OSError, UnicodeError):
        result, exit_code = {"status": "invalid_input", "code": "input_unreadable"}, 2
    # Only a fixed response allowlist is rendered. Do not dump server error bodies,
    # prompts, channel IDs, token values, exception details or process arguments.
    output.write(json.dumps(result, sort_keys=True) + "\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
