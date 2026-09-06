# GitHub Ecosystem Design — Workflow, Runners, Projects, Wiki, Connectors

The org-level operating model around helios-platform. This PR ships the design + the
in-repo pieces (CI fixes, agent instruction files, MCP registration); execution of the
org-level pieces is roadmap PR5.

> Practical setup companion: [`CONNECTIONS_SETUP.md`](CONNECTIONS_SETUP.md) — the
> per-connection wiring matrix, owner actions, secrets/variables, and verification steps.
> The repo-level pieces below are applied by the control fabric (§ Control fabric), not
> by hand.

## Repository topology

| Repo | Role |
|---|---|
| **helios-platform** | Main platform: orchestrator core, AIHub, MCP server, infra — everything lands here first ("keep it deep in helios-platform") |
| monado-blade | Architecture scaffold; HELIOS.Platform operations content merges into helios-platform over time |
| hermes-agent-github | Fleet runtime (kanban worker lanes, gateway platforms) |
| ai-hub-knowledge | Codex pipeline skeleton; goal registry pattern to be absorbed by the AIHub roadmap |
| WindowsDeveloperConfig | Dev-box provisioning (winget DSC) — carries the cross-LLM shell workload below |
| actions-runner-controller | ARC fork for self-hosted runners |
| azure-search-openai-demo | RAG reference implementation |
| linear, RL | Upstream forks, tracked as-is |

**New-repo convention**: default branch `main`; branch protection with the
`.NET Build & Test` + `Infra Validation` checks required; `CLAUDE.md`/`AGENTS.md`/
`.github/copilot-instructions.md` from day one (copy this repo's); `.mcp.json` pointing
at the HELIOS MCP server; no repo goes live with a red default-branch check.

## CI/CD workflow model

- **PR gate** (must be green): `dotnet-build.yml` (solution build + tests + CLI smoke),
  `infra-validate.yml` (offline Bicep compile/lint), `ci-validation.yml` + `quality.yml`
  (script/docs hygiene).
- **Deploy**: `helios-deploy.yml` — OIDC (no stored cloud secrets), what-if on dispatch,
  deploy on main-merge touching `infra/**`, graceful skip when the `AZURE_CLIENT_ID`/
  `AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID` federated credential isn't configured.
  The all-echo `deploy.yml` (client-secret fake deploy) is deleted; `helios-deploy.yml`
  is the only deploy lane.
- **Status dashboards**: `status-dashboard.yml` collects **real** run metrics from the
  Actions API (its fabricated-data predecessor is retired) and `pages-dashboard.yml`
  publishes them as the GitHub Pages status dashboard. Pages source = **GitHub
  Actions** is the `pages` item of `scripts/github/apply-repo-settings.ps1`, applied by
  the control fabric; the Settings → Pages click is the fallback.
- **Branch governance (in-repo now)**: `.github/rulesets/main.json` (PR required +
  job-level required checks pinned to the truthful gates), `.github/CODEOWNERS`,
  `.github/dependabot.yml`, and the PR/issue templates are committed;
  `scripts/github/apply-rulesets.ps1` (dry-run by default, idempotent by ruleset name)
  applies the rulesets, driven from `main` by `governance-apply.yml` (§ Control
  fabric). Label-gated auto-merge (`auto-merge.yml`, `automerge` label) rides those
  same required checks.
- **Known-red inventory**: pre-existing broken workflows are catalogued in
  ROADMAP_MULTI_LLM.md rather than papered over; nothing new may depend on them.

## Control fabric (repo truth, applied from `main`)

The repository's GitHub-side configuration is data in the repo, and one workflow
reconciles the live repository against it. **Repo truth**: `.github/rulesets/*.json`
(branch rulesets), `config/github/labels.json` (the 21 labels the automation and the
absorption cadence rely on, the 16 pre-existing ones kept verbatim), and
`config/github/milestones.json` (the four train milestones with due dates). The scalar
settings the automation assumes — Pages source = Actions, `allow_auto_merge`,
`has_wiki`, `delete_branch_on_merge`, the `automerge` label — are encoded in
`scripts/github/apply-repo-settings.ps1`. Changing any of it is a PR: the change is
reviewed like code, `governance-apply.yml`'s `plan` job posts the dry-run diff in the PR
checks, the merge to `main` is the apply, and a daily schedule re-applies any drift.
Nothing is clicked into the UI that the next run would not reproduce.

| Piece | Applies | Driven by | Credential |
|---|---|---|---|
| `scripts/github/apply-rulesets.ps1` | rulesets (create, or PUT by name) | `governance-apply.yml` | `HELIOS_ADMIN_TOKEN` (repo admin) |
| `scripts/github/apply-repo-settings.ps1` | Pages, auto-merge, wiki, delete-branch-on-merge, `automerge` label; boards report-only | `governance-apply.yml` | `HELIOS_ADMIN_TOKEN` |
| `scripts/github/apply-labels.ps1` | `config/github/labels.json` (never deletes or renames) | `governance-apply.yml` | `GITHUB_TOKEN` `issues: write` |
| `scripts/github/apply-milestones.ps1` | `config/github/milestones.json` (never closes) | `governance-apply.yml` | `GITHUB_TOKEN` `issues: write` |
| `scripts/github/prune-branches.ps1` | merged → delete; stale → tag `archive/<branch>` then delete; open-PR heads (here or in the upstream parent) and keep-list kept | `branch-prune.yml` (dispatch only; `max_delete` cap) | `GITHUB_TOKEN` `contents: write` + `pull-requests: read` |
| `scripts/github/close-duplicate-issues.ps1` | #54–#92 Linear-loop twins → `duplicate` + comment + closed | owner login or the PAT, after the Linear switch | push |

The authority split is deliberate and measured: agent sessions that author PRs sit
behind a proxy that rewrites GitHub credentials (`.permissions.*` all false, `/pages`
blocked, `%23` paths rejected), so from there every script runs its dry run and prints
the exact `gh api` commands, and the mutation happens only where the credential is real.
One owner step unlocks the admin items: a fine-grained PAT (Administration, Contents,
Issues, Pull requests, Pages RW; Metadata R; this repository only) stored once as
`HELIOS_ADMIN_TOKEN`; without it the workflow still applies labels and milestones and
reports the rest as "needs HELIOS_ADMIN_TOKEN". All six scripts share one contract:
dry-run by default, `-Apply` mutates, every command printed before it runs, a failed
item never aborts the pass, exit 0 / 1 (replay list) / 2 (precondition). Reversibility:
every pruned stale tip survives as its `archive/` tag; merged tips are already on `main`.
Click path, measured dry runs and verification: [`CONNECTIONS_SETUP.md` § Control
fabric](CONNECTIONS_SETUP.md#control-fabric-governed-writes-from-main); per-script table:
`scripts/github/README.md`.

## Self-hosted runners (ARC)

Runner scale sets via the actions-runner-controller fork (v0.14.2 charts), one scale set
per workload class:

```yaml
# helm install helios-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
githubConfigUrl: https://github.com/Yolkster64/helios-platform   # or the org URL
githubConfigSecret: helios-runners-app        # GitHub App: app id + installation id + private key (quoted strings)
minRunners: 0                                  # scale-to-zero when idle
maxRunners: 9                                  # matches the Xcore-9s ceiling; raise deliberately
containerMode:
  type: dind                                   # docker builds; use kubernetes mode + workVolumeClaim for k8s-native
runnerScaleSetName: helios-x64
```

Auth via a GitHub App (not PAT). GPU/Windows classes get their own scale set with
`runnerGroup` + labels; workflows opt in with `runs-on: helios-x64`. The controller chart
(`gha-runner-scale-set-controller`) installs once per cluster.

## Projects & wiki

- **Project board**: one org Project "HELIOS Platform" with epic-level tracking issues
  (the absorption epics are issues #14–#53), status automation on PR merge, and the
  kanban fleet board handling task-level work (two layers: humans plan in Projects,
  agents execute in Hermes kanban). Milestones are repo truth
  (`config/github/milestones.json`, applied by `apply-milestones.ps1`); the board's
  `DueDate` field is a separate, unsynced setting.
- **Wiki**: `wiki-generator.yml` publishes from `docs/` — treat `docs/architecture/`
  as the wiki source of truth; no hand-edited wiki pages. **One-time prerequisite**:
  the wiki's backing git repository does not exist until the first page is created by
  hand in the GitHub UI (Wiki → "Create the first page"); until that materialization
  click happens the generator has nowhere to push.
- **Pages dashboard lane** (new): `status-dashboard.yml` (real Actions API metrics)
  feeds `pages-dashboard.yml`, which publishes the status dashboard to GitHub Pages —
  a separate publication lane from the wiki, gated on Pages source = GitHub Actions
  (the control fabric's `pages` settings item, or the Settings → Pages click).

## Issue → Copilot coding agent workflow

For scoped, well-specified tasks: create the issue with acceptance criteria →
`assign to Copilot` (or `mcp assign_copilot_to_issue`) → the coding agent opens a draft
PR → the PR gate + `code_review` routing (Claude) review it like any human PR. Keep it to
mechanical, bounded work (dependency bumps, port-this-pattern tasks); architecture-touching
issues go to interactive agent sessions instead. Never let an agent-authored PR merge on
a red or skipped check.

## Cross-LLM shell workload (WindowsDeveloperConfig)

A new `Workloads/cross-llm-shell/configuration.winget` (PR5, in the fork's `src/`):
installs `GitHub.Cli`, `GitHub.Copilot`, `Microsoft.AzureCLI`, Anthropic Claude CLI,
OpenAI Codex CLI, Ollama; a Windows Terminal fragment adds a "HELIOS AI" profile running
`pwsh -NoExit -Command "helios-ai status"`; follows the repo's signed-copy rule (edit
`src/`, never the signed top-level copies). Result: fresh dev box → every CLI the
`cliAgents` config expects, in one `winget configure`.

## Connector strategy (Slack, Linear, SharePoint)

The connector *service* stays deferred to PR4, deliberately: hermes-agent-github already
ships a Slack gateway, MS Graph client (SharePoint/Teams), and 15 other platform
adapters. HELIOS will reuse that gateway as the connector edge (fleet dispatch already
routes through Hermes) rather than hand-writing C# connectors first. Linear has no
Hermes adapter — PR4 adds it as a `src/connectors/HELIOS.Connectors` project using
`@linear/sdk`-equivalent GraphQL calls, or as a Hermes gateway plugin, whichever lands
cleaner after a spike. Credentials for every connector flow through the same Key Vault
pattern as model keys.

### Implemented wiring (this PR)

The Actions-level wiring is live now, driven by one declarative file —
`config/connectors.json` (env-var names and routing only, never values):

- **`notify-slack.yml`** listens via `workflow_run` to `.NET Build & Test`,
  `Infra Validation`, `Python Spoke`, and `Helios Platform Deploy`, and posts
  outcomes to Slack. Per-workflow policy comes from `slack.notifyOn`
  (`always` vs `failures-and-recovery`); pipelines stay notification-agnostic.
- **`linear-sync.yml`** mirrors GitHub issues carrying a `linear.syncLabels`
  label into the configured Linear team (`[GH-<n>]`-prefixed, link-back comment
  on the GitHub issue; close/reopen is noted on the Linear side). One-directional:
  GitHub remains the source of truth.
- **Graceful-skip contract**: with `SLACK_WEBHOOK_URL` / `LINEAR_API_KEY` unset,
  both workflows exit green with a clear notice — they can never be the red check.
  Enable with `gh secret set SLACK_WEBHOOK_URL` and `gh secret set LINEAR_API_KEY`.
- PR4's HELIOS.Connectors consumes the same `config/connectors.json`, so enabling
  the service later changes no routing decisions, only who executes them.
