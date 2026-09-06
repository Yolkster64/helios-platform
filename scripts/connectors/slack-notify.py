#!/usr/bin/env python3
"""Notify from trusted workflow_run metadata; never execute the source run's code."""
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


class ConnectorError(Exception):
    """A sanitized error suitable for a workflow log."""


FAILURES = {"failure", "timed_out", "action_required", "startup_failure"}


def github_get(path):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=35)
    if result.returncode:
        raise ConnectorError("GitHub run history is unavailable; recovery could not be determined.")
    return json.loads(result.stdout)


def previous_conclusion(run, repo, get=github_get):
    """Compare the previous attempt, or the preceding run on the same source lane."""
    attempt = run.get("run_attempt", 1)
    if attempt > 1:
        previous = get(f"repos/{repo}/actions/runs/{run['id']}/attempts/{attempt - 1}")
        return previous.get("conclusion")
    source = (run.get("head_repository") or {}).get("full_name")
    if not source:
        raise ConnectorError("Run source repository is missing; recovery could not be determined.")
    # Branch names can coincide across forks. Match source repository AND event.
    # GitHub caps filtered run history at 1,000; fail visibly if that is exhausted.
    query = urllib.parse.urlencode({"branch": run["head_branch"], "event": run["event"], "per_page": 100})
    for page in range(1, 11):
        response = get(f"repos/{repo}/actions/workflows/{run['workflow_id']}/runs?{query}&page={page}")
        candidates = response["workflow_runs"]
        for previous in sorted(candidates, key=lambda r: r["run_number"], reverse=True):
            if (previous["run_number"] < run["run_number"]
                    and previous.get("head_branch") == run["head_branch"]
                    and previous.get("event") == run["event"]
                    and (previous.get("head_repository") or {}).get("full_name") == source):
                if previous.get("status") != "completed":
                    raise ConnectorError("The preceding run is still active; recovery is undetermined.")
                return previous.get("conclusion")
        if len(candidates) < 100:
            return None
    raise ConnectorError("Run history limit reached; recovery is undetermined.")


def escape(value):
    return str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def notification(config, run, repo, get=github_get):
    policy = config.get("notifyOn", {}).get(run["name"])
    if policy not in {"always", "failures-and-recovery"}:
        raise ConnectorError("Missing or unsupported Slack notification policy.")
    conclusion = run.get("conclusion")
    recovered = False
    if policy == "failures-and-recovery" and conclusion == "success":
        recovered = previous_conclusion(run, repo, get) in FAILURES
        if not recovered:
            return None
    elif policy == "failures-and-recovery" and conclusion not in FAILURES:
        return None
    # Escape every display field, including metadata influenced by fork PRs.
    name, branch, sha = map(escape, (run["name"], run.get("head_branch", ""), run["head_sha"][:7]))
    # Construct the link from the trusted repository context and numeric run ID.
    url = f"https://github.com/{repo}/actions/runs/{int(run['id'])}"
    outcome = "recovered" if recovered else escape(conclusion)
    icon = ":white_check_mark:" if conclusion == "success" else ":x:"
    text = f"{icon} *{name}* {outcome} on {branch} ({sha}) — <{url}|run>"
    if run["name"] == "Absorption Benchmark" and conclusion == "success":
        text = f":clipboard: *{name}* completed on {branch} ({sha}) — benchmark ran; candidate verdict is in the <{url}|run summary and report artifact>"
    return {"text": text, "unfurl_links": False, "unfurl_media": False}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ConnectorError("Slack redirected the webhook request; delivery stopped.")


def deliver(url, payload):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname not in {"hooks.slack.com", "hooks.slack-gov.com"}
            or parsed.username or parsed.password or parsed.port not in {None, 443}
            or not parsed.path.startswith("/services/") or parsed.query or parsed.fragment):
        raise ConnectorError("SLACK_WEBHOOK_URL must be an official HTTPS Slack incoming webhook.")
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
            if response.status != 200 or response.read(1024).strip() != b"ok":
                raise ConnectorError("Slack did not acknowledge delivery.")
    except (urllib.error.URLError, TimeoutError) as error:
        # Exception text can include the secret webhook URL. Never emit it.
        raise ConnectorError("Slack delivery failed; inspect the webhook configuration and retry deliberately.") from error


def main():
    try:
        config = json.loads(Path("config/connectors.json").read_text())["slack"]
        if type(config.get("enabled")) is not bool:
            raise ConnectorError("slack.enabled must be a boolean.")
        if not config["enabled"]:
            print("Slack notifications are disabled in config/connectors.json.")
            return 0
        if config.get("webhookUrlEnv") != "SLACK_WEBHOOK_URL":
            raise ConnectorError("Slack workflow expects webhookUrlEnv=SLACK_WEBHOOK_URL.")
        webhook = os.environ.get("SLACK_WEBHOOK_URL", "")
        if not webhook:
            raise ConnectorError("Slack is enabled but SLACK_WEBHOOK_URL is missing; connection is not ready.")
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        payload = notification(config, event["workflow_run"], os.environ["GITHUB_REPOSITORY"])
        if payload is None:
            print("No Slack notification required by the configured policy.")
        else:
            deliver(webhook, payload)
            print("Slack acknowledged delivery to the webhook's configured channel.")
        return 0
    except ConnectorError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        print("::error::Invalid connector input or unavailable dependency; delivery stopped.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
