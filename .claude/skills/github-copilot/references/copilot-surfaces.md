# GitHub Copilot surfaces — how this repo drives them

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* GitHub-side behavior verified against the live repo (PRs #95–#99,
read 2026-08-13) and the official docs pages cited inline.

## Coding agent

**Assignment path 1 — the `copilot` label.** Adding the label IS the delegation
decision (`.github/workflows/copilot-dispatch.yml:3-8`); remove the label / unassign
to take the work back. The `assign-coding-agent` job (gated on the label,
`copilot-dispatch.yml:33`) does the assignment in two GraphQL calls:

- Query `suggestedActors(capabilities:[CAN_BE_ASSIGNED], first:100)` on the
  repository (`copilot-dispatch.yml:52-60`) — the coding agent appears as a suggested
  assignable actor **only when it is enabled for the repository**, under the login
  `copilot-swe-agent` (`copilot-dispatch.yml:62-63`). No `copilot-swe-agent` node =
  not assignable here (no subscription / agent disabled); the job skips green with a
  `::notice::` (`copilot-dispatch.yml:66-69`).
- Mutation `replaceActorsForAssignable(input:{assignableId, actorIds:[botId]})`
  (`copilot-dispatch.yml:71-75`). Note the semantics: it **replaces** the assignee
  set, which is what makes the label an unambiguous handoff.

**Assignment path 2 — the GitHub MCP tool surface** Claude sessions in this program
carry: `assign_copilot_to_issue` (same effect as the label path, no workflow hop) and
`create_pull_request_with_copilot` (skips the issue and hands the agent a task
directly); `get_copilot_job_status` polls the resulting session. Prefer the label
path for epic work — it leaves the delegation decision visible on the board.

**What the agent produces.** A session per assignment, working on a `copilot/*`
branch, opening a **draft PR** (`copilot-dispatch.yml:5-6`). Verified shape from the
merged wave: epics #47/#37/#45 produced PRs #95/#96/#97 on branches
`copilot/absorption-e34-nuget-centralization`, `copilot/absorption-e24-workflow-modernization`,
`copilot/absorption-e32-scorecard-api-tests`, each PR body ending `Fixes #<epic>`
(live reads, 2026-08-13). All three merged through the proven loop —
Copilot authors → Claude session reviews/fixes on the `copilot/*` branch → Codex
review waves until 👍 → merge when green (`docs/architecture/FORWARD_PLAN.md:11-17`;
status row `docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:20`). T8 explicitly reuses
this shape for the next epic batch (`FORWARD_PLAN.md:47-52`).

**Practical knowledge (paid for in review cycles):**

- **The agent works from main as of assignment time.** The #95–#97 wave was opened
  2026-08-11 and merged 2026-08-12/13 after main had moved — expect "update branch"
  / rebases before merge, and re-run reviews after them.
- **Its dependency and workflow edits need the closest reading.** Two recorded
  lessons — cross-reference, don't restate:
  - *#95 (CPM migration)*: central package management stops the F# SDK's implicit
    FSharp.Core flowing into consuming C# outputs; the fix and rationale live in
    `Directory.Packages.props:14-21` and
    `.claude/skills/csharp-orchestrator/references/dotnet-10-and-11.md` ("FSharp.Core
    central pin"); the CPM coordination row is in
    `.claude/skills/csharp-orchestrator/references/nuget-packages.md`.
  - *#96 (workflow modernization)*: it pinned `aquasecurity/trivy-action@v0.28.0` — a
    release whose composite references a deleted upstream tag, so it is *permanently*
    broken; the pin rule and incident are in
    `.claude/skills/pipelines-config/references/actions-tooling.md` ("Pinning lessons
    learned here"), and the repaired pin is `ci-validation.yml:181` (`v0.36.0`).
- Assignees on the agent's PRs include both `Copilot` and the owner; the human merges
  (`merged_by` on #95–#97 is the owner) — the agent never merges its own work.

## Code review

**Request path 1 — automatic.** The `request-review` job requests a Copilot review on
every PR `opened`/`ready_for_review` that is not a draft (`copilot-dispatch.yml:85`),
via `POST /repos/{owner}/{repo}/pulls/{n}/requested_reviewers` with reviewer
`copilot-pull-request-reviewer[bot]` (`copilot-dispatch.yml:94-98`) — the same
REST identity the official docs name for API-requested reviews
(<https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review>).
Non-201 responses skip green with the response head in a `::notice::`
(`copilot-dispatch.yml:99-103`).

**Request path 2 — the `request_copilot_review` MCP tool**, used for session-authored
PRs per the reverse protocol (`FORWARD_PLAN.md:15-16`).

**What comes back.** A PR review authored by `copilot-pull-request-reviewer[bot]`,
always in the `Comment` state — never Approve / Request changes (docs page above) —
so it can't gate a merge by itself; the loop's gate is the Claude session + Codex 👍.
Observed format (PR #99 review, 2026-08-13): a "Pull request overview" summary, a
coverage line ("Copilot reviewed 119 out of 156 changed files in this pull request
and generated 4 comments"), a per-file summary table folded in a `<details>` block,
and the findings as inline review comments. Finding counts are deliberately small;
read the coverage line to know what it did *not* look at.

**Typical finding quality — treat it as a real reviewer.** The #99 wave's four
findings (all live-verified review threads): a PII leak (a real name/email in
`integrations/m365/README.md`, plus its propagation into
`.claude/skills/microsoft-ecosystem/references/graph-and-copilot.md`), a
cross-platform gap (the `absorb-pr.ps1` credential guard checked `~/.config/gh` but
not the Windows gh config location), and a doc-vs-code mismatch (a skill doc claiming
net10.0 while csprojs still targeted net8.0). Security-adjacent hygiene,
cross-platform paths, and doc/code drift are its strong suits here.

## Custom instructions — the two-file contract

`.github/copilot-instructions.md` exists and is read by **both** Copilot surfaces:
repository-wide, always-on instructions for the coding agent and code review
(<https://docs.github.com/en/copilot/concepts/agents/code-review>). Two practical
facts from that page: the file is repository-wide and always-on, and review reads it
from the **head branch** of the PR — so an in-PR instructions edit affects that PR's
own review.

The contract: `.github/copilot-instructions.md` (Copilot reads) and `AGENTS.md`
(Codex reads) are both snapshots of `CLAUDE.md`'s operating knowledge — build
commands, hard rules, hub/tool surface. **Change one, change all, same PR.** They
have already drifted once: `.github/copilot-instructions.md:3` still says ".NET 8"
and its MCP tool list (`:50-53`) stops at `helios_infra_validate`, while `AGENTS.md:3`
says ".NET 10" and lists the absorb/fleet/foundry tools (`AGENTS.md:50-55`). Until
that sync lands, expect Copilot to build with net8-era assumptions. What belongs in
them: exactly what a fresh agent session needs to not break the repo (build entry
points, the root-csproj glob rule, no-secrets rule, tool surface) — not narrative
status, which is what `docs/architecture/` is for.

## Copilot CLI + IDE

One `gh` device-code login covers every Copilot client surface: the `gh` CLI, the
**standalone `copilot` CLI** (`@github/copilot` reuses the GitHub login), and Copilot
sign-in inside VS Code / Visual Studio (`scripts/bootstrap/connect-all.ps1:28-32`,
and the github lane's `Covers` field at `:174`). The `visual-studio` lane is
informational-only — the IDEs authenticate through their own dialogs riding the same
GitHub identity, and nothing headless can verify or launch that
(`connect-all.ps1:354-367`). Caveat that lane enforces: a `gh` login alone does NOT
configure the hub's GitHub Models provider — that reads only
`GITHUB_MODELS_TOKEN`/`GITHUB_TOKEN` env vars or Key Vault (`connect-all.ps1:32-37`).

## Auth: the `COPILOT_DISPATCH_TOKEN` fallback

Both dispatch jobs authenticate with
`${{ secrets.COPILOT_DISPATCH_TOKEN || secrets.GITHUB_TOKEN }}`
(`copilot-dispatch.yml:38` and `:90`). Why the fallback exists
(`copilot-dispatch.yml:10-14`): the workflow-scoped `GITHUB_TOKEN` can be refused for
coding-agent assignment (the API declines on some plans/scopes), and events created
with it do not re-trigger workflows — so when assignment fails with the default
token, the owner mints a **fine-grained PAT of a user with Copilot access** (repo
issues: write), stores it as the `COPILOT_DISPATCH_TOKEN` Actions secret, and the
workflow prefers it automatically. Setup/verification row:
`docs/architecture/CONNECTIONS_SETUP.md:261` (verify: open a non-draft PR → review
request appears; label an issue `copilot` → agent assigned). Full token taxonomy and
when each GitHub auth surface applies:
`.claude/skills/github-control/references/auth-topology.md`.
