---
name: github-control
description: Full GitHub control for HELIOS — authentication (Actions GITHUB_TOKEN, classic and fine-grained PATs, GitHub App, gh CLI device flow), GitHub→Azure OIDC federation, rulesets and branch protection, auto-merge and merge-queue policy, the Projects v2 GraphQL API, wiki automation, and GitHub Pages. Use whenever a task touches GitHub credentials or the GitHub control plane — picking an auth surface, wiring a workflow token, driving the project board, configuring required checks, publishing the wiki or Pages, or automating issues/PRs.
---

# GitHub Control — HELIOS

Two reference packs carry the depth; this file is the decision map.

- `references/auth-topology.md` — which of the five auth surfaces to use, the
  OIDC federation contract, and the credential-guard interaction.
- `references/control-plane.md` — Projects v2 GraphQL (what is and is not
  automatable), rulesets/branch protection, auto-merge boundaries, wiki and
  Pages publication, issues automation.

The multi-LLM review protocol that sits on top of this control plane is a
runbook, not a skill: `docs/architecture/REVIEW_LOOP.md`. The governance lane
that owns rulesets/CODEOWNERS/merge-queue rollout is tranche T9 in
`docs/architecture/FORWARD_PLAN.md`.

## Auth: pick the surface first

| Need | Surface | Ground truth |
|---|---|---|
| Workflow acting on its own repo | Actions `GITHUB_TOKEN`, deny-all default + per-job opt-ins | `.github/workflows/claude-foundry.yml:24` |
| Projects v2 (board fields/items) | **Classic PAT, `project` scope — the only thing that works** | `docs/architecture/CONNECTIONS_SETUP.md:248-250` |
| Copilot coding-agent assignment when `GITHUB_TOKEN` is refused | Fine-grained PAT secret with `GITHUB_TOKEN` fallback | `.github/workflows/copilot-dispatch.yml:38` |
| Workflow cascades, org-scale automation, ARC runners | GitHub App (none exists in this repo yet) | `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md:47,55` |
| A human's interactive CLI | `gh` device flow (`models:read` scope for the models provider) | `scripts/bootstrap/connect-github.sh:70` |
| Workflow acting on **Azure** | OIDC federation — identifiers only, no client secret | `scripts/bootstrap/azure-oidc-setup.sh`, `helios-deploy.yml:62-64` |

Full decision detail, the vars-`||`-secrets idiom, and the one remaining
anti-pattern: `references/auth-topology.md`.

## Hard rules

- **Every new workflow declares `permissions:`** — workflow-level `{}` plus
  per-job opt-ins is the exemplar (`claude-foundry.yml:24`); seven legacy
  workflows still have no block at all and are the backlog, not the pattern
  (list in `references/auth-topology.md`).
- **No stored Azure client secret.** Deploy auth is OIDC with repo *variables*
  for the three identifiers (`azure-oidc-setup.sh:7-8`); `deploy.yml`'s
  `AZURE_CLIENT_SECRET` env read is a known-red anti-pattern being removed in
  this tranche (`docs/architecture/ROADMAP_MULTI_LLM.md:53`).
- **Required checks pin job-level check names** (e.g. `Build solution & run
  tests`, `.github/workflows/dotnet-build.yml:44`), never "everything in the
  workflow" — the allowed-to-fail `net11-preview` lane lives in the same file
  (`dotnet-build.yml:228-236`) and must never gate a merge.
- **Nothing known-red may become a required check**
  (`docs/architecture/ROADMAP_MULTI_LLM.md:50-66`).
- **Auto-merge has a scope boundary**: session-stewarded PRs may use
  `gh pr merge --auto`; absorption-pipeline candidates never auto-merge
  (`docs/architecture/ABSORPTION_PIPELINE.md:50`); claude-foundry patches open
  as drafts (`claude-foundry.yml:303-308`).
- **Projects v2 honesty**: fields and items are real GraphQL; views, templates,
  and built-in workflows have **no API** — the board scripts document manual
  click paths instead of pretending (`scripts/board-setup/setup-views.ps1:3-11`).
- **Tokens never cross process boundaries.** Scripts check env-var presence by
  name only and never run `gh auth token` for you
  (`scripts/bootstrap/connect-all.ps1:34-37`); any GitHub token in the
  environment makes the absorption benchmark refuse to run untrusted code
  (`scripts/absorption/absorb-pr.ps1:53-55`).
