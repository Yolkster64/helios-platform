"""Real temporary Git repositories: isolation, repeat runs and collision boundaries."""
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts.bootstrap import agent_workspace as work


class AgentWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="helios workspaces ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "canonical repo"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Offline Test")
        self.git("config", "user.email", "offline@example.invalid")
        (self.repo / "hello.txt").write_text("committed content\n")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.sha = self.git("rev-parse", "HEAD").strip()
        self.base = self.root / "canonical repo-workspaces"
        self.registry = self.repo / ".git" / "helios" / "workspaces.json"

    def git(self, *args, repo=None):
        return subprocess.run(["git", "-C", str(repo or self.repo), *args],
                              check=True, capture_output=True, text=True).stdout

    def command(self, *args, repo=None):
        output = io.StringIO()
        code = work.main(["--repo", str(repo or self.repo), *args], stdout=output)
        result = json.loads(output.getvalue())
        self.assertFalse(result["networkCalled"])
        self.assertFalse(result["agentStarted"])
        return code, result

    def create(self, name="claude", agent="claude"):
        code, result = self.command("create", name, "--agent", agent)
        self.assertEqual(code, 0, result)
        return result

    def test_status_and_list_do_not_create_state(self):
        before = set(self.repo.rglob("*"))
        for args in ((), ("status",), ("list",)):
            code, result = self.command(*args)
            self.assertEqual(code, 0)
            self.assertEqual(result["workspaces"], [])
            self.assertEqual(result["sourceSha"], self.sha)
        self.assertEqual(before, set(self.repo.rglob("*")))
        self.assertFalse(self.base.exists())

    def test_nested_git_remains_noninteractive_after_environment_sanitization(self):
        with patch.dict(os.environ, {"GIT_DIR": "/wrong", "GIT_TERMINAL_PROMPT": "1",
                                     "GIT_ALLOW_PROTOCOL": "https", "GIT_ASKPASS": "/prompt"}):
            git = work.Git()
        self.assertNotIn("GIT_DIR", git.env)
        self.assertEqual(git.env["GIT_TERMINAL_PROMPT"], "0")
        self.assertEqual(git.env["GIT_ALLOW_PROTOCOL"], "")
        self.assertEqual(git.env["GCM_INTERACTIVE"], "Never")
        with patch.object(work.subprocess, "run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = ""
            git.run(self.repo, "status", "--porcelain")
            self.assertIs(run.call_args.kwargs["stdin"], subprocess.DEVNULL)

    @unittest.skipIf(os.name == "nt", "POSIX executable remote fixture")
    def test_missing_partial_clone_blob_does_not_start_remote_helper(self):
        marker = self.root / "remote-was-started"
        helper = self.root / "remote-probe"
        helper.write_text("#!/bin/sh\ntouch " + shlex.quote(str(marker)) + "\nexit 1\n")
        helper.chmod(0o755)
        self.git("config", "remote.origin.url", "ext::" + str(helper).replace(" ", "% "))
        self.git("config", "remote.origin.promisor", "true")
        self.git("config", "extensions.partialClone", "origin")
        self.git("config", "protocol.ext.allow", "always")
        blob = self.git("rev-parse", "HEAD:hello.txt").strip()
        (self.repo / ".git" / "objects" / blob[:2] / blob[2:]).unlink()
        # The helper must fail locally, not authenticate or fetch implicitly.
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        self.assertFalse(marker.exists())
        self.assertEqual((self.repo / "hello.txt").read_text(), "committed content\n")

    def test_create_uses_head_and_keeps_dirty_source_and_worktree_separate(self):
        (self.repo / "hello.txt").write_text("uncommitted source edits\n")
        (self.repo / "private-untracked.txt").write_text("untracked fixture\n")
        result = self.create()
        target = Path(result["workspace"]["path"])
        self.assertEqual(target, self.base / "claude")
        self.assertEqual((target / "hello.txt").read_text(), "committed content\n")
        self.assertFalse((target / "private-untracked.txt").exists())
        (target / "hello.txt").write_text("agent edits\n")
        self.assertEqual((self.repo / "hello.txt").read_text(), "uncommitted source edits\n")
        self.assertEqual(self.git("branch", "--show-current", repo=target).strip(), "workspace/claude/claude")

    def test_repeat_preserves_identity_and_local_edits(self):
        first = self.create()
        target = Path(first["workspace"]["path"])
        (target / "hello.txt").write_text("keep this edit\n")
        second = self.create()
        self.assertEqual(second["status"], "existing")
        self.assertEqual(first["workspace"]["workspaceId"], second["workspace"]["workspaceId"])
        self.assertEqual((target / "hello.txt").read_text(), "keep this edit\n")

    def test_each_role_gets_own_registered_branch(self):
        identities = set()
        for agent in work.AGENTS:
            result = self.create(agent, agent)
            identities.add(result["workspace"]["workspaceId"])
        self.assertEqual(len(identities), len(work.AGENTS))
        _, result = self.command("list")
        self.assertEqual(len(result["workspaces"]), len(work.AGENTS))
        self.assertTrue(all(row["status"] == "ready" for row in result["workspaces"]))

    def test_fleet_and_chatgpt_roles_create_local_labeled_worktrees(self):
        for agent in ("hermes", "xcore", "chatgpt"):
            with self.subTest(agent=agent):
                name = agent + "-review"
                result = self.create(name, agent)
                target = Path(result["workspace"]["path"])
                self.assertEqual(result["workspace"]["agent"], agent)
                self.assertEqual(self.git("branch", "--show-current", repo=target).strip(),
                                 f"workspace/{agent}/{name}")
                self.assertEqual((target / "hello.txt").read_text(), "committed content\n")

    def test_existing_name_cannot_change_agent(self):
        self.create()
        code, result = self.command("create", "claude", "--agent", "codex")
        self.assertEqual(code, 2)
        self.assertIn("different agent", result["message"])

    def test_unsafe_and_windows_reserved_names_do_not_write(self):
        for name in ("../other", "UPPER", "two--hyphens", "-flag", "a/b", "a b", "con", "com1", "a" * 49, ""):
            with self.subTest(name=name):
                with self.assertRaises(work.WorkspaceError):
                    work.execute(self.repo, "create", name, "claude")
        self.assertFalse(self.registry.exists())

    def test_path_collision_preserves_existing_directory(self):
        target = self.base / "claude"
        target.mkdir(parents=True)
        marker = target / "keep.txt"
        marker.write_text("existing owner\n")
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        self.assertEqual(marker.read_text(), "existing owner\n")

    def test_branch_collision_is_not_adopted(self):
        self.git("branch", "workspace/claude/claude")
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        self.assertFalse(self.registry.exists())

    def test_changed_branch_is_reported_and_not_reset(self):
        target = Path(self.create()["workspace"]["path"])
        self.git("checkout", "-b", "manual-work", repo=target)
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        _, result = self.command("status")
        self.assertEqual(result["workspaces"][0]["status"], "requires_review")
        self.assertEqual(self.git("branch", "--show-current", repo=target).strip(), "manual-work")

    def test_creation_from_linked_worktree_uses_shared_registry_and_current_head(self):
        target = Path(self.create()["workspace"]["path"])
        (target / "hello.txt").write_text("committed agent work\n")
        self.git("add", ".", repo=target)
        self.git("commit", "-m", "agent work", repo=target)
        code, result = self.command("create", "reviewer", "--agent", "codex", repo=target)
        self.assertEqual(code, 0, result)
        self.assertEqual(result["workspaceRoot"], str(self.base))
        self.assertEqual((self.base / "reviewer" / "hello.txt").read_text(), "committed agent work\n")
        self.assertEqual(len(json.loads(self.registry.read_text())["workspaces"]), 2)

    def test_corrupt_registry_is_preserved(self):
        self.registry.parent.mkdir()
        self.registry.write_text("broken fixture")
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        self.assertEqual(self.registry.read_text(), "broken fixture")

    def test_existing_lock_blocks_without_waiting_or_stealing(self):
        self.registry.parent.mkdir()
        lock = self.registry.parent / "workspaces.lock"
        lock.write_text("another process")
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        self.assertEqual(lock.read_text(), "another process")

    @unittest.skipIf(os.name == "nt", "Symlink creation requires Windows developer permissions")
    def test_symlink_paths_and_registry_are_refused(self):
        other = self.root / "other"
        other.mkdir()
        self.base.symlink_to(other, target_is_directory=True)
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        self.base.unlink()
        self.registry.parent.mkdir()
        marker = other / "registry"
        marker.write_text("unchanged")
        self.registry.symlink_to(marker)
        self.assertEqual(self.command("create", "claude", "--agent", "claude")[0], 2)
        self.assertEqual(marker.read_text(), "unchanged")

    @unittest.skipIf(os.name == "nt", "Uses POSIX hook/filter fixture")
    def test_checkout_hooks_and_filters_are_not_executed(self):
        sentinel = self.root / "must-not-run"
        hook = self.repo / ".git" / "hooks" / "post-checkout"
        hook.write_text("#!/bin/sh\ntouch " + shlex.quote(str(sentinel)) + "\n")
        hook.chmod(0o700)
        (self.repo / ".gitattributes").write_text("hello.txt filter=testdriver\n")
        self.git("add", ".gitattributes")
        self.git("commit", "-m", "filter fixture")
        self.git("config", "filter.testdriver.smudge", "touch " + shlex.quote(str(sentinel)))
        self.git("config", "filter.testdriver.required", "true")
        result = self.create()
        self.assertFalse(sentinel.exists())
        self.assertEqual((Path(result["workspace"]["path"]) / "hello.txt").read_text(), "committed content\n")

    def test_ambient_git_directory_override_does_not_redirect_repo(self):
        with patch.dict(os.environ, {"GIT_DIR": str(self.root / "not-a-repository"), "GIT_CONFIG_COUNT": "1",
                                     "GIT_CONFIG_KEY_0": "core.worktree", "GIT_CONFIG_VALUE_0": str(self.root)}):
            result = self.create()
        self.assertEqual(result["canonicalRepository"], str(self.repo))


if __name__ == "__main__":
    unittest.main()
