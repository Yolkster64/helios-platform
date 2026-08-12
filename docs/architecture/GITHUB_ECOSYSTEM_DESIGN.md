# GitHub Ecosystem Design — Workflow, Runners, Projects, Wiki, Connectors

The org-level operating model around helios-platform. This PR ships the design + the
in-repo pieces (CI fixes, agent instruction files, MCP registration); execution of the
org-level pieces is roadmap PR5.

> Practical setup companion: [`CONNECTIONS_SETUP.md`](CONNECTIONS_SETUP.md) — the
> per-connection wiring matrix, owner actions, secrets/variables, and verification steps.

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
- **Known-red inventory**: pre-existing broken workflows are catalogued in
  ROADMAP_MULTI_LLM.md rather than papered over; nothing new may depend on them.

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
  (created from this PR's roadmap), status automation on PR merge, and the kanban fleet
  board handling task-level work (two layers: humans plan in Projects, agents execute in
  Hermes kanban).
- **Wiki**: `wiki-generator.yml` already publishes from `docs/` — treat `docs/architecture/`
  as the wiki source of truth; no hand-edited wiki pages.

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
