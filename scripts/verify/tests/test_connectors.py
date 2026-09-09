"""Execute the real connector logic with inert CLI/HTTP boundaries. No live writes."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("slack_notify", ROOT / "scripts/connectors/slack-notify.py")
slack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(slack)

# curl validates the ACTUAL shell-constructed request JSON. This reproduces the
# former extra-brace failure, rather than testing a separate JSON builder.
FAKE_CLI = r'''
import json, os, pathlib, sys
args = sys.argv[1:]
scenario = os.environ.get("SCENARIO", "create")
log = pathlib.Path(os.environ["CALL_LOG"])
if pathlib.Path(sys.argv[0]).name == "gh":
    if args[0] == "api":
        if scenario == "github_down": sys.exit(1)
        issue = {"title":"Current title", "html_url":"https://github.com/example/repo/issues/7", "state":"open", "labels":[{"name":"bug"}]}
        if scenario == "remove_last": issue["labels"] = []
        if scenario == "create_closed": issue["state"] = "closed"
        if scenario == "mirror_title": issue["title"] = "[GH-7] Current title"
        if scenario == "duplicate_label": issue["labels"].append({"name":"duplicate"})
        print(json.dumps(issue))
    else:
        with log.open("a") as f: f.write(json.dumps({"github_comment":args}) + "\n")
    sys.exit(0)
body = json.loads(args[args.index("--data") + 1])
assert isinstance(body["variables"], dict)
with log.open("a") as f: f.write(json.dumps(body) + "\n")
q, v = body["query"], body["variables"]
if scenario == "graphql_error":
    print(json.dumps({"data":{"teams":{"nodes":[]}}, "errors":[{"message":"secret-must-not-appear"}]})); sys.exit(0)
if "teams(filter:" in q:
    assert v == {"key":"JOH"}
    data = {"teams":{"nodes":[{"id":"team","key":"JOH","archivedAt":None}]}}
    if scenario == "archived_team": data["teams"]["nodes"][0]["archivedAt"] = "2026-01-01"
elif "project(" in q:
    assert v["id"] == "3a4dee89-2c83-4bbd-a067-4e6cfbcb308a"
    data = {"project":{"id":v["id"],"archivedAt":None,"teams":{"nodes":[{"id":"team"}],"pageInfo":{"hasNextPage":False}}}}
    if scenario == "missing_project": data["project"] = None
    if scenario == "archived_project": data["project"]["archivedAt"] = "2026-01-01"
    if scenario == "wrong_team": data["project"]["teams"]["nodes"] = [{"id":"other"}]
    if scenario == "team_page_incomplete": data["project"]["teams"]["pageInfo"]["hasNextPage"] = True
elif "issues(" in q:
    assert v["team"] == "team" and v["u"].endswith("/issues/7")
    assert "includeArchived:true" in q
    nodes = [] if scenario in {"create", "create_closed", "no_mirror", "wrong_create_project", "missing_create_id"} else [{"id":"existing", "description":v["u"],"archivedAt":None,"project":{"id":"3a4dee89-2c83-4bbd-a067-4e6cfbcb308a"}}]
    if scenario == "wrong_mirror_project": nodes[0]["project"]["id"] = "other"
    if scenario == "archived_mirror": nodes[0]["archivedAt"] = "2026-01-01"
    if scenario == "duplicate": nodes *= 2
    data = {"issues":{"nodes":nodes}}
elif "issueLabels(" in q: data = {"issueLabels":{"nodes":[{"id":"label"}]}}
elif "issueCreate(" in q:
    assert v["input"]["title"] == "[GH-7] Current title"
    if scenario == "create_closed": assert v["input"]["stateId"] == "done"
    assert v["input"]["projectId"] == "3a4dee89-2c83-4bbd-a067-4e6cfbcb308a"
    data = {"issueCreate":{"success":True,"issue":{"id":"created","identifier":"JOH-7","url":"https://linear.app/example/issue/JOH-7","project":{"id":v["input"]["projectId"]}}}}
    if scenario == "wrong_create_project": data["issueCreate"]["issue"]["project"]["id"] = "other"
    if scenario == "missing_create_id": del data["issueCreate"]["issue"]["id"]
elif "team(" in q:
    data = {"team":{"states":{"nodes":[{"id":"todo","type":"unstarted","position":1},{"id":"done","type":"completed","position":2}]}}}
elif "issueUpdate(" in q:
    data = {"issueUpdate":{"success":scenario != "mutation_false"}}
    if scenario == "mutation_missing": data = {"issueUpdate":{}}
else: raise AssertionError("Unexpected API operation")
print(json.dumps({"data":data}))
'''


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "bash and jq required")
class LinearTests(unittest.TestCase):
    def run_sync(self, scenario="create", action="labeled", enabled=True, key=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config").mkdir()
            config = json.loads((ROOT / "config/connectors.json").read_text())
            if enabled is None:
                config["linear"].pop("enabled", None)
            else:
                config["linear"]["enabled"] = enabled
            (root / "config/connectors.json").write_text(json.dumps(config))
            for cli in ["curl", "gh"]:
                path = root / cli
                path.write_text(f"#!{sys.executable}\n" + FAKE_CLI)
                path.chmod(0o755)
            log = root / "calls.jsonl"
            env = {"PATH":str(root) + os.pathsep + os.environ["PATH"], "SCENARIO":scenario,
                   "CALL_LOG":str(log), "REPO":"example/repo", "ISSUE_NUMBER":"7",
                   "ISSUE_TITLE":"stale title", "ISSUE_STATE":"closed", "ISSUE_LABELS":"stale",
                   "EVENT_ACTION":action}
            if key: env["LINEAR_API_KEY"] = "inert-test-key"
            result = subprocess.run(["bash", str(ROOT / "scripts/connectors/linear-sync.sh")], cwd=root, env=env, capture_output=True, text=True, timeout=20)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_create_serializes_variables_and_uses_live_title(self):
        result, calls = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum("issueCreate(" in c.get("query", "") for c in calls), 1)
        self.assertEqual(sum("github_comment" in c for c in calls), 1)

    def test_disabled_does_not_call_any_service(self):
        result, calls = self.run_sync(enabled=False, key=False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_missing_enabled_preserves_default_on(self):
        result, calls = self.run_sync(enabled=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("issueCreate(" in c.get("query", "") for c in calls))

    def test_mirror_title_never_syncs_back(self):
        for action in ["opened", "edited", "labeled", "unlabeled", "closed", "reopened"]:
            result, calls = self.run_sync("mirror_title", action)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, [])

    def test_duplicate_label_does_not_create_mirror(self):
        for action in ["opened", "labeled"]:
            result, calls = self.run_sync("duplicate_label", action)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, [])

    def test_duplicate_label_still_allows_existing_state_sync(self):
        result, calls = self.run_sync("duplicate_label", "closed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1]["variables"]["stateId"], "todo")

    def test_project_and_team_fail_before_any_mutation(self):
        for scenario in ["archived_team", "missing_project", "archived_project", "wrong_team", "team_page_incomplete", "wrong_mirror_project", "archived_mirror"]:
            with self.subTest(scenario=scenario):
                result, calls = self.run_sync(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c.get("query", "").startswith("mutation") for c in calls))

    def test_create_receipt_requires_project_and_issue_id(self):
        for scenario in ["wrong_create_project", "missing_create_id"]:
            result, calls = self.run_sync(scenario)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(any("github_comment" in c for c in calls))

    def test_enabled_without_key_is_not_ready(self):
        result, calls = self.run_sync(key=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_invalid_enabled_never_contacts_services(self):
        result, calls = self.run_sync(enabled="false")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_graphql_200_errors_stop_without_leaking_body(self):
        result, calls = self.run_sync("graphql_error")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertNotIn("secret-must-not-appear", result.stdout + result.stderr)

    def test_unsuccessful_or_missing_mutation_receipt_fails(self):
        for scenario in ["mutation_false", "mutation_missing"]:
            with self.subTest(scenario=scenario):
                result, _ = self.run_sync(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Refreshed", result.stdout)

    def test_github_failure_never_uses_stale_payload(self):
        result, calls = self.run_sync("github_down")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_ambiguous_mirrors_stop_before_mutation(self):
        result, calls = self.run_sync("duplicate")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c.get("query", "").startswith("mutation") for c in calls))

    def test_removing_last_label_clears_existing_mirror(self):
        result, calls = self.run_sync("remove_last", "unlabeled")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1]["variables"]["labelIds"], [])

    def test_delayed_close_uses_live_open_state_without_comment(self):
        result, calls = self.run_sync("existing", "closed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1]["variables"]["stateId"], "todo")
        self.assertFalse(any("commentCreate" in c.get("query", "") for c in calls))

    def test_state_event_without_mirror_does_not_create_labels_or_issues(self):
        result, calls = self.run_sync("no_mirror", "reopened")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c.get("query", "").startswith("mutation") for c in calls))

    def test_delayed_label_creates_closed_mirror_in_completed_state(self):
        result, _ = self.run_sync("create_closed")
        self.assertEqual(result.returncode, 0, result.stderr)


class SlackTests(unittest.TestCase):
    def setUp(self):
        self.config = {"notifyOn":{"Build":"failures-and-recovery"}}
        self.run = {"id":123, "run_number":10, "run_attempt":1, "workflow_id":9,
                    "name":"Build", "head_branch":"feature", "head_sha":"abcdef0123",
                    "event":"pull_request", "head_repository":{"full_name":"fork/repo"},
                    "conclusion":"success", "status":"completed"}

    def history(self, conclusion="failure", **kwargs):
        previous = copy.deepcopy(self.run)
        previous.update(run_number=9, conclusion=conclusion, **kwargs)
        return {"workflow_runs":[previous]}

    def test_success_after_failure_posts_recovery(self):
        payload = slack.notification(self.config, self.run, "example/repo", lambda _: self.history())
        self.assertIn("recovered", payload["text"])

    def test_routine_success_and_cancelled_predecessor_are_quiet(self):
        for conclusion in ["success", "cancelled"]:
            self.assertIsNone(slack.notification(self.config, self.run, "example/repo", lambda _: self.history(conclusion)))

    def test_colliding_fork_branch_is_not_recovery(self):
        self.assertIsNone(slack.notification(self.config, self.run, "example/repo", lambda _: self.history(head_repository={"full_name":"other/repo"})))

    def test_recovery_on_rerun_uses_previous_attempt(self):
        self.run["run_attempt"] = 2
        paths = []
        def get(path):
            paths.append(path)
            return {"conclusion":"failure"}
        self.assertIn("recovered", slack.notification(self.config, self.run, "example/repo", get)["text"])
        self.assertTrue(paths[0].endswith("/attempts/1"))

    def test_unknown_history_fails_instead_of_claiming_no_recovery(self):
        with self.assertRaises(slack.ConnectorError):
            slack.notification(self.config, self.run, "example/repo", lambda _: self.history(status="in_progress"))

    def test_untrusted_fields_cannot_expand_slack_mentions(self):
        self.run.update(conclusion="failure", head_branch="<!channel>&branch")
        text = slack.notification(self.config, self.run, "example/repo")["text"]
        self.assertNotIn("<!channel>", text)
        self.assertIn("&lt;!channel&gt;&amp;branch", text)

    def test_benchmark_success_does_not_claim_candidate_passed(self):
        self.run["name"] = "Absorption Benchmark"
        payload = slack.notification({"notifyOn":{"Absorption Benchmark":"always"}}, self.run, "example/repo")
        self.assertIn("candidate verdict", payload["text"])
        self.assertNotIn(":white_check_mark:", payload["text"])

    def test_foreign_webhook_rejected_without_network(self):
        with patch.object(slack.urllib.request, "build_opener") as opener:
            with self.assertRaises(slack.ConnectorError):
                slack.deliver("https://example.com/services/not-slack", {"text":"test"})
            opener.assert_not_called()

    def test_delivery_errors_do_not_disclose_secret_webhook(self):
        with patch.object(slack.urllib.request, "build_opener") as opener:
            opener.return_value.open.side_effect = slack.urllib.error.URLError("secret-webhook-token")
            with self.assertRaises(slack.ConnectorError) as error:
                slack.deliver("https://hooks.slack.com/services/inert/test/secret", {"text":"test"})
            self.assertNotIn("secret-webhook-token", str(error.exception))
            opener.return_value.open.assert_called_once()

    def test_disabled_skips_before_loading_event_or_credentials(self):
        with patch.object(slack.Path, "read_text", return_value=json.dumps({"slack":{"enabled":False}})) as read, \
                patch.dict(os.environ, {}, clear=True), patch.object(slack, "deliver") as send:
            self.assertEqual(slack.main(), 0)
            read.assert_called_once()
            send.assert_not_called()

    def test_enabled_and_default_enabled_without_key_fail(self):
        for switch in [{"enabled":True}, {}]:
            config = {"slack":{"webhookUrlEnv":"SLACK_WEBHOOK_URL", **switch}}
            with patch.object(slack.Path, "read_text", return_value=json.dumps(config)), \
                    patch.dict(os.environ, {}, clear=True), patch.object(slack, "deliver") as send:
                self.assertEqual(slack.main(), 1)
                send.assert_not_called()

    def test_invalid_enabled_fails_without_delivery(self):
        with patch.object(slack.Path, "read_text", return_value=json.dumps({"slack":{"enabled":"false"}})), \
                patch.object(slack, "deliver") as send:
            self.assertEqual(slack.main(), 1)
            send.assert_not_called()

    def test_delivery_requires_positive_slack_acknowledgement(self):
        for status, body in [(200, b"ok"), (200, b"invalid_payload"), (204, b"")]:
            with self.subTest(status=status, body=body), patch.object(slack.urllib.request, "build_opener") as opener:
                response = opener.return_value.open.return_value.__enter__.return_value
                response.status = status
                response.read.return_value = body
                if status == 200 and body == b"ok":
                    slack.deliver("https://hooks.slack.com/services/inert/test/token", {"text":"test"})
                else:
                    with self.assertRaises(slack.ConnectorError):
                        slack.deliver("https://hooks.slack.com/services/inert/test/token", {"text":"test"})
                opener.return_value.open.assert_called_once()


if __name__ == "__main__":
    unittest.main()
