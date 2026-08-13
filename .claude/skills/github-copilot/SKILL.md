---
name: github-copilot
description: GitHub Copilot working knowledge for HELIOS — the coding agent (label an issue `copilot` or use the GitHub MCP tools), automatic Copilot code review on every non-draft PR, custom instructions (.github/copilot-instructions.md), and the Copilot CLI / IDE surfaces. Use for ANYTHING involving GitHub Copilot: assigning an issue to Copilot, reviewing or fixing a copilot/* PR, requesting or interpreting a Copilot review, keeping custom instructions in sync with AGENTS.md, or Copilot auth/token questions.
---

# GitHub Copilot — HELIOS

Copilot is a working lane in this repo's multi-LLM loop, not a suggestion engine.
The proven operating model (`docs/architecture/FORWARD_PLAN.md`, "Operating model"):
Copilot authors PRs from epic issues → the Claude session reviews/fixes on the
`copilot/*` branch → Codex review waves until 👍 → merge when checks are green; the
same protocol runs in reverse for session-authored PRs (`request_copilot_review` +
Codex waves). Both directions are automated by
`.github/workflows/copilot-dispatch.yml`.

## The four surfaces (depth: `references/copilot-surfaces.md`)

| Surface | Driven here by | Ground truth |
|---|---|---|
| Coding agent | `copilot` label on an issue → auto-assign; or the GitHub MCP tools (`assign_copilot_to_issue`, `create_pull_request_with_copilot`) | `copilot-dispatch.yml` `assign-coding-agent` job; merged agent PRs #95–#97 |
| Code review | Requested automatically on every non-draft PR; or the `request_copilot_review` MCP tool | `copilot-dispatch.yml` `request-review` job; the PR #99 review wave |
| Custom instructions | `.github/copilot-instructions.md` — read by BOTH the coding agent and the reviewer | that file + the AGENTS.md two-file contract |
| CLI / IDE | One `gh` login covers the standalone `copilot` CLI and Copilot sign-in in VS Code / Visual Studio | `scripts/bootstrap/connect-all.ps1` github + visual-studio lanes |

## Hard rules

- **Copilot's output enters through review, never straight to main.** Agent PRs are
  drafts on `copilot/*` branches; the Claude session owns the review/fix pass before
  Codex waves and merge (`FORWARD_PLAN.md` operating model). Treat the reviewer bot's
  findings as a real reviewer's — the PR #99 wave caught a PII leak, a Windows path
  gap, and a doc-vs-code version mismatch (`references/copilot-surfaces.md`).
- **Scrutinize Copilot's dependency and workflow edits hardest.** PR #95's CPM
  migration dropped the implicit FSharp.Core flow (central pin + rationale now in
  `Directory.Packages.props:14-21`); PR #96 pinned `trivy-action@v0.28.0`, a
  permanently broken release, repaired to `v0.36.0` (`ci-validation.yml:181`).
  Lessons live in `.claude/skills/csharp-orchestrator/references/dotnet-10-and-11.md`
  and `.claude/skills/pipelines-config/references/actions-tooling.md` — read them
  before approving similar edits.
- **Keep `.github/copilot-instructions.md` in sync with `AGENTS.md`** in the same PR
  that changes either — Copilot reads the former, Codex reads the latter, and drift
  makes one agent build against stale rules (the files have already drifted once;
  see `references/copilot-surfaces.md`, "Custom instructions").
- **Automation degrades, never fails.** Both dispatch jobs skip green with a
  `::notice::` when Copilot is unavailable or the API declines
  (`copilot-dispatch.yml:10-14`); do not convert those skips into failures.
- **No PAT in the repo.** The optional `COPILOT_DISPATCH_TOKEN` secret is a
  fine-grained PAT held only in Actions secrets (`copilot-dispatch.yml:38`); auth
  topology detail is in `.claude/skills/github-control/references/auth-topology.md`.

## Which LLM

| Work | Route |
|---|---|
| Writing/refining an epic issue for Copilot assignment | Claude session (context owner) |
| Bulk, well-scoped implementation from an epic | Copilot coding agent (label `copilot`) |
| Reviewing/fixing a `copilot/*` PR | Claude session, then Codex waves |

## Reference material

- `references/copilot-surfaces.md` — the four surfaces in depth: assignment
  mechanics (GraphQL and MCP), what the agent produces and the proven #95–#97 loop,
  review request paths and finding quality, the custom-instructions contract, CLI/IDE
  auth coverage, and the `COPILOT_DISPATCH_TOKEN` fallback.
- Related skills: `.claude/skills/github-control/` (repo governance + auth topology,
  authored in parallel), `pipelines-config` (workflow hygiene the agent's edits must
  meet), `csharp-orchestrator` (the CPM/package rules its C# edits must meet).
