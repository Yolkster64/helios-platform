from __future__ import annotations

import json
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/validation/ai_code_review_changed_files.py"
WORKFLOW = ROOT / ".github/workflows/ai-code-review.yml"


class AiCodeReviewChangedFilesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.maxDiff = None

    def _git(self, repo: pathlib.Path, *args: str) -> subprocess.CompletedProcess[str]:
        env = os.environ | {
            "GIT_AUTHOR_NAME": "HELIOS Tests",
            "GIT_AUTHOR_EMAIL": "helios-tests@example.com",
            "GIT_COMMITTER_NAME": "HELIOS Tests",
            "GIT_COMMITTER_EMAIL": "helios-tests@example.com",
        }
        return subprocess.run(
            ["git", "-C", str(repo), *args],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

    def _write(self, repo: pathlib.Path, relative_path: str, content: str) -> None:
        path = repo / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _run_script(
        self,
        repo: pathlib.Path,
        event_name: str,
        event_path: pathlib.Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ | {
            "GITHUB_WORKSPACE": str(repo),
            "GITHUB_EVENT_NAME": event_name,
        }
        if event_path is not None:
            env["GITHUB_EVENT_PATH"] = str(event_path)
        return subprocess.run(
            ["python3", str(SCRIPT)],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    def test_pull_request_uses_merge_base_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = pathlib.Path(temp_dir)
            self._git(repo, "init", "-b", "main")
            self._write(repo, "shared.txt", "base\n")
            self._git(repo, "add", "shared.txt")
            self._git(repo, "commit", "-m", "base")
            base_branch_sha = self._git(repo, "rev-parse", "HEAD").stdout.strip()

            self._git(repo, "checkout", "-b", "feature")
            self._write(repo, "feature.txt", "feature branch change\n")
            self._git(repo, "add", "feature.txt")
            self._git(repo, "commit", "-m", "feature change")
            feature_sha = self._git(repo, "rev-parse", "HEAD").stdout.strip()

            self._git(repo, "checkout", "main")
            self._write(repo, "main-only.txt", "main branch change\n")
            self._git(repo, "add", "main-only.txt")
            self._git(repo, "commit", "-m", "main change")
            base_sha = self._git(repo, "rev-parse", "HEAD").stdout.strip()

            event_path = repo / "event.json"
            event_path.write_text(
                json.dumps(
                    {
                        "pull_request": {
                            "base": {"sha": base_sha},
                            "head": {"sha": feature_sha},
                        }
                    }
                ),
                encoding="utf-8",
            )

            completed = self._run_script(repo, "pull_request", event_path)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                completed.stdout.splitlines(),
                ["Changed files:", "  - feature.txt"],
            )
            self.assertNotEqual(base_branch_sha, base_sha)

    def test_workflow_dispatch_uses_last_commit_when_head_has_parent(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = pathlib.Path(temp_dir)
            self._git(repo, "init", "-b", "main")
            self._write(repo, "first.txt", "first\n")
            self._git(repo, "add", "first.txt")
            self._git(repo, "commit", "-m", "first")
            self._write(repo, "second.txt", "second\n")
            self._git(repo, "add", "second.txt")
            self._git(repo, "commit", "-m", "second")

            completed = self._run_script(repo, "workflow_dispatch")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                completed.stdout.splitlines(),
                ["Changed files:", "  - second.txt"],
            )

    def test_workflow_dispatch_supports_single_commit_manual_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = pathlib.Path(temp_dir)
            self._git(repo, "init", "-b", "main")
            self._write(repo, "root.txt", "root\n")
            self._git(repo, "add", "root.txt")
            self._git(repo, "commit", "-m", "root")

            completed = self._run_script(repo, "workflow_dispatch")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                completed.stdout.splitlines(),
                ["Changed files:", "  - root.txt"],
            )

    def test_git_failures_propagate_nonzero_exit(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = pathlib.Path(temp_dir)
            self._git(repo, "init", "-b", "main")
            self._write(repo, "file.txt", "content\n")
            self._git(repo, "add", "file.txt")
            self._git(repo, "commit", "-m", "root")

            event_path = repo / "event.json"
            event_path.write_text(
                json.dumps(
                    {
                        "pull_request": {
                            "base": {"sha": "deadbeef"},
                            "head": {"sha": "badc0ffee"},
                        }
                    }
                ),
                encoding="utf-8",
            )

            completed = self._run_script(repo, "pull_request", event_path)
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("fatal:", completed.stderr)

    def test_workflow_uses_helper_and_same_repo_comment_guard(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("python3 scripts/validation/ai_code_review_changed_files.py", text)
        self.assertIn("steps.comment-scope.outputs.same_repo == 'true'", text)
        self.assertIn("steps.comment-scope.outputs.same_repo != 'true'", text)
        self.assertIn("EVENT_PATH: ${{ github.event_path }}", text)
        self.assertIn("REPO: ${{ github.repository }}", text)
        self.assertIn("blob/${context.sha}/ai-integration/README.md", text)
        self.assertNotIn("/blob/main/ai-integration/README.md", text)
        self.assertNotIn("github.event.pull_request.base.sha", text)
        self.assertNotIn("github.event.pull_request.head.sha", text)


if __name__ == "__main__":
    unittest.main()
