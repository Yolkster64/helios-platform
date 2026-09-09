# One HELIOS project, a workspace for each contributor

Everyone works from the same GitHub repository and
[HELIOS Linear project](https://linear.app/641974/project/helios-4f592efea071).
Each coding agent or teammate gets an isolated Git worktree and branch. Their edits
stay separate until reviewed; shared instructions and the project map travel with
the committed source.

## Start with the local list

From the repository folder:

```bash
python3 scripts/bootstrap/agent_workspace.py
python3 scripts/bootstrap/agent_workspace.py list
```

Both commands inspect local Git state without creating files, contacting services
or starting an agent. `status` is also an explicit alias for the default command.
On Windows, use `python` if that is your installed Python command.

## Create a workspace

Commit the shared integration changes first so each new worktree contains them:

```bash
python3 scripts/bootstrap/agent_workspace.py create claude --agent claude
python3 scripts/bootstrap/agent_workspace.py create codex --agent codex
python3 scripts/bootstrap/agent_workspace.py create copilot --agent copilot
```

The complete role allowlist is `claude`, `codex`, `copilot`, `hermes`, `xcore`,
`chatgpt`, and `human`. Fleet work can use the same isolated local workspace:

```bash
python3 scripts/bootstrap/agent_workspace.py create hermes-review --agent hermes
python3 scripts/bootstrap/agent_workspace.py create xcore-review --agent xcore
python3 scripts/bootstrap/agent_workspace.py create chatgpt-review --agent chatgpt
```

These are local ownership labels. They do not start Hermes or XCore workers or create
cloud accounts. A `chatgpt` workspace label is not a hosted ChatGPT Workspace Agent;
the published agent and its return channel require their separate supported setup.

For another contributor, choose a local label; this does not create a service account:

```bash
python3 scripts/bootstrap/agent_workspace.py create reviewer-one --agent human
```

Names use lowercase letters, digits and single hyphens, start with a letter, and
contain at most 48 characters. Windows reserved names are excluded.
Use `--repo PATH` before the command to select another existing checkout explicitly.

| Item | Location or behavior |
| --- | --- |
| Canonical checkout | The primary checkout registered with the shared Git repository |
| New directory | Its sibling `<repository-name>-workspaces/<name>` |
| Branch | `workspace/<agent>/<name>` |
| Starting commit | The invoking checkout's current `HEAD` |
| Stable local identity | `workspaceId` in the JSON receipt and shared Git registry |
| Registry | `helios/workspaces.json` inside Git's common directory |
| Work coordination | The existing HELIOS Linear project, Slack canvas and GitHub PRs |

Uncommitted, untracked and ignored files are not copied. A worktree includes tracked
project instructions and plugins from its starting commit. It does not install
software, authenticate the client, or activate a plugin in ChatGPT. Git hooks and
checkout filters are suppressed during creation; LFS files therefore remain pointer
files until you explicitly prepare their content. Dependencies and submodules are
also a separate setup step.

Rerunning the same command returns the existing workspace after checking its registry
ownership, path, branch and Git common directory. It preserves local edits and does
not reset the branch to a newer commit. Existing directories or branches are never
adopted automatically. Symlinks, Windows junctions and conflicting ownership are
rejected.

Creation uses a shared local lock. Interrupted or incomplete creation remains marked
for review, with its files and branch preserved. The helper has no remove, prune,
reset, fetch, push, account-creation or agent-launch command. Review an incomplete
operation before handling its stale lock or registry entry manually.

## Open the intended client

Use the returned `workspace.path` as the working folder. From that folder, the shared
launcher can open Claude Code or Codex after the client is installed and signed in:

```bash
./connect.sh claude
./connect.sh codex
```

For Copilot or a human workspace, open the returned directory in your editor and use
its supported sign-in flow. The role label and workspace ID describe local ownership;
neither grants GitHub, Azure, Linear or Slack permission. New work stays on its own
branch. Open a reviewed PR back to the integration branch or current canonical base.

## Share handoffs and plugins

The local MCP configuration gives Claude and Codex access to the same HELIOS tool
contracts. Standard linked Git worktrees on one machine resolve their handoff storage
to the primary checkout's `.helios/bridge`, through validated Git worktree metadata.
The optional `HELIOS_HANDOFF_ROOT` selects an absolute primary checkout when a reviewed
layout needs an explicit root. Never copy credentials between worktrees.

Independent clones and different machines do not share a Git common directory.
Point every client at **one authenticated HELIOS HTTP MCP service** to share the same
inbox and project snapshot. Starting separate bridges against independent checkouts
creates separate inboxes. See [remote bridge setup](mcp/REMOTE_BRIDGE.md).

ChatGPT must have that reachable endpoint installed and authorized through its own
plugin/account-linking flow. Repository configuration cannot silently install a
ChatGPT plugin or attach an existing browser conversation. The service exposes the
bounded project documents and handoff tools; published project files alone do not
prove the connection is live.

For an event to start work in ChatGPT, use the separately configured
[Workspace Agent return channel](mcp/WORKSPACE_AGENT_RETURN.md). Its stable
`conversation_key` keeps updates in one dedicated ChatGPT agent conversation. The
stored handoff and the trigger receipt remain separate evidence: saving a note does
not by itself wake another agent or prove that the requested work finished.

## Verify

```bash
python3 -m unittest scripts.verify.tests.test_agent_workspace -v
```

The tests use real temporary Git repositories to check isolation from dirty source,
stable reruns, every client role, linked-worktree invocation, ownership collisions,
changed branches, invalid registry/locks, and suppressed hooks and checkout filters.
POSIX symlink and shell-hook fixtures are skipped on Windows; junction rejection is
implemented with reparse-point detection and still needs a native Windows check.
