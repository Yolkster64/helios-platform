# HELIOS Platform

HELIOS is an active Windows-platform and multi-LLM integration project owned at
[`Yolkster64/helios-platform`](https://github.com/Yolkster64/helios-platform). The
currently buildable cross-platform slice combines a .NET 10 AI hub, F# policy logic, an
optional C++ native accelerator, a dependency-free Python analytics/advisory spoke, REST,
CLI, MCP, Docker, and review-only Azure infrastructure.

## 60-second quickstart

```bash
git clone https://github.com/Yolkster64/helios-platform
cd helios-platform

pwsh scripts/setup/setup-all.ps1 -Fix        # one-command readiness (details below)
dotnet build HELIOS.sln -c Release           # expect: 0 Error(s)
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- status
```

`setup-all.ps1` is the fully automated setup entrypoint. It inventories five things —
build/test toolchain, GitHub/Azure auth state (read-only probes), the AI agent CLIs
(`claude`/`codex`/`copilot`/`gh`), the fleet topology config, and the MCP registration —
and prints one INVENTORY table with a fix command per gap. `-Fix` installs the missing AI
CLIs via npm; **it never touches authentication** in either mode — device-code logins stay
behind the `scripts/bootstrap/connect-*` scripts, run by a human when the inventory says
so. Exit 0 = everything ready, 2 = attention needed (`-Json` for machine output). Details:
[`scripts/bootstrap/README.md`](scripts/bootstrap/README.md).

The first `helios-ai status` works with **zero** providers configured: unconfigured
providers report `Unconfigured` with the exact env var to set — that is the expected
first-run state, not an error.

**To test-run every surface end to end, follow
[docs/TEST_RUN_PLAYBOOK.md](docs/TEST_RUN_PLAYBOOK.md)** — copy-pasteable commands with
expected outcomes for build, tests, CLI, API, MCP, Docker, fleet, absorption, and infra.

## Current status

This repository is under consolidation; it is not a finished or production-certified
Windows management product.

- `HELIOS.sln` contains the buildable AIHub, CLI, API, MCP, F# domain, and test projects.
- `src/core/HELIOS.Platform` is deliberately excluded because it has hundreds of
  pre-existing compile errors. The legacy root status/phase reports are historical, not
  evidence that those subsystems are deployed.
- The WinUI 3 shell lives in `src/gui/HELIOS.Shell.sln` and requires Windows.
- Azure and Microsoft 365 mutations are never performed by a build or catalog command.
  Validate Bicep and inspect a `what-if` before any separately approved deployment.
- Recovered engine names marked `prototype` or `concept` are proposal vocabulary. Only
  `implemented` entries with `runtime_available=true` enter an advisory plan.

See [AGENTS.md](AGENTS.md) and
[MULTI_LLM_INTEGRATION.md](docs/architecture/MULTI_LLM_INTEGRATION.md) for the current
engineering contract.

## The map: every surface at a glance

| Surface | Entry point | Deep doc |
|---|---|---|
| CLI (`helios-ai`) | `dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- status` | [PROJECT_SETUP.md](docs/PROJECT_SETUP.md) (CLI quick tour), [LLM_STRENGTHS_PLAYBOOK.md](docs/architecture/LLM_STRENGTHS_PLAYBOOK.md) |
| REST API (`helios-ai-api`) | `dotnet run --project src/ai/HELIOS.AIHub.Api -c Release` → `http://localhost:5170` | [MULTI_LLM_INTEGRATION.md](docs/architecture/MULTI_LLM_INTEGRATION.md); endpoint table below |
| MCP server (`helios`) | `.mcp.json` (auto-picked up by Claude Code in this repo) → `src/mcp/HELIOS.Mcp` | [docs/mcp/CLIENT_SETUP.md](docs/mcp/CLIENT_SETUP.md) |
| Python spoke (`helios-agents`) | `cd src/ai/python && python3 -m pytest tests` | [MULTI_LLM_INTEGRATION.md](docs/architecture/MULTI_LLM_INTEGRATION.md) |
| Agent fleet | `pwsh scripts/fleet/start-fleet.ps1 -DryRun` (also `seed-absorption-tasks` / `fleet-status` / `scale-fleet` / `stop-fleet`) | [HERMES_FLEET_AND_XCORE.md](docs/architecture/HERMES_FLEET_AND_XCORE.md), [CLOUD_SHELL_AND_LOCAL_FLEET.md](docs/architecture/CLOUD_SHELL_AND_LOCAL_FLEET.md) |
| Absorption program | `config/absorption/pr-watchlist.json` → the keyless `Absorption Benchmark` workflow (or `pwsh scripts/absorption/absorb-pr.ps1 -PrNumber <N>` locally — it executes the candidate's build code, so reserve that for reviewed PRs on credential-free hosts) → `helios-ai absorb-status` | [ABSORPTION_PIPELINE.md](docs/architecture/ABSORPTION_PIPELINE.md), [ABSORPTION_LEDGER.md](docs/architecture/ABSORPTION_LEDGER.md) |
| Infrastructure | `infra/main.bicep` (source of truth) + `infra/arm/` (generated) + `infra/terraform/` (mirror) | [infra/README.md](infra/README.md) |
| GUI shell (**Windows-only**) | `dotnet build src/gui/HELIOS.Shell.sln -c Debug -p:Platform=x64` on Windows | [src/gui/README.md](src/gui/README.md), [GUI_THEME_ANALYSIS.md](docs/architecture/GUI_THEME_ANALYSIS.md) |
| Setup & bootstrap | `pwsh scripts/setup/setup-all.ps1` + `scripts/bootstrap/` | [scripts/bootstrap/README.md](scripts/bootstrap/README.md), [OWNER_START_HERE.md](docs/OWNER_START_HERE.md) |

## Prerequisites

- .NET SDK 10 (see `global.json` for the minimum SDK and roll-forward policy)
- PowerShell 7 (`pwsh`) for the automation layer under `scripts/`
- Python 3.10 or newer
- Git
- Optional: CMake plus a C++ compiler for the native spoke
- Optional: Docker with Compose for the local API container
- Optional: Azure CLI/Bicep for infrastructure validation, Terraform for the mirror

Provider credentials are optional. Without them, provider status is reported as
`Unconfigured`; keyless tests and local catalog operations still work.

## Build and test

```bash
dotnet restore HELIOS.sln
dotnet build HELIOS.sln -c Release --no-restore
dotnet test tests/HELIOS.AIHub.Tests/HELIOS.AIHub.Tests.csproj -c Release --no-build

cd src/ai/python
python3 -m pip install '.[dev]'
python3 -m pytest tests -q
```

To exercise the optional native code before the .NET build:

```bash
./scripts/build/build-native.sh
```

Infrastructure validation is read-only:

```bash
az bicep build --file infra/main.bicep --stdout >/dev/null
az bicep build-params --file infra/main.bicepparam --stdout >/dev/null
```

Expected results for all of these (including current test counts) are in
[docs/TEST_RUN_PLAYBOOK.md](docs/TEST_RUN_PLAYBOOK.md).

## Multi-LLM surfaces

The CLI uses `config/aihub.json` and reads secrets only from environment variables or the
configured Azure Key Vault.

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- status
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- routing
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- engines
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- absorb-status
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- \
  engine-plan --security-profile hardened --pressure 0.8 \
  --fleet-size 36 --include-candidates
```

CLI commands: `ask`, `route`, `tandem`, `compare`, `status`, `providers` (`list`),
`routing`, `engines`, `engine-plan`, and `absorb-status`.

The MCP server is registered in `.mcp.json` and exposes provider calls, status/routing
reads, engine catalog/recommendation reads, absorption/fleet status reads, and local
infrastructure validation. Client examples are in
[docs/mcp/CLIENT_SETUP.md](docs/mcp/CLIENT_SETUP.md).

## REST API

Run locally:

```bash
dotnet run --project src/ai/HELIOS.AIHub.Api -c Release
curl http://localhost:5170/healthz
curl http://localhost:5170/v1/status
```

`/healthz` is public. Direct loopback calls to `/v1/*` need no access key. A Docker-bridge
or remote caller must configure `HELIOS_API_ACCESS_KEY` and send it as
`X-HELIOS-Api-Key`. For hosted use, put the service behind identity-aware, rate-limited
ingress; the local access key is not a replacement for user authorization.

| Endpoint | Verb | Purpose |
|---|---|---|
| `/healthz` | GET | Process liveness |
| `/v1/status` | GET | Provider readiness without provider calls |
| `/v1/routing` | GET | Default and task-specific provider chains |
| `/v1/learning` | GET | Recorded outcomes for one task type |
| `/v1/learning` | POST | Provenance-required advisory outcome ingestion |
| `/v1/insights` | GET | Python summary and drift analysis |
| `/v1/metrics` | GET | Per-provider latency/success/cost telemetry over recent outcomes |
| `/v1/engines` | GET | Implemented capabilities and runtime availability |
| `/v1/engines/recommend` | POST | Deterministic engine advisory plan |
| `/v1/ask` | POST | One provider or the default routed chain |
| `/v1/route` | POST | Task-type routing with fallback |
| `/v1/tandem` | POST | Concurrent provider-chain execution |
| `/v1/compare` | POST | Parallel provider comparison and deduplication |

The Python boundary is capped at four concurrent child processes. Advisory learning
records carry a required `source` and are excluded from adaptive provider routing.

## Local Docker

Compose publishes the API on host loopback only. Set a non-default local key so host
requests crossing Docker's bridge can reach `/v1/*`:

```bash
export HELIOS_API_ACCESS_KEY='replace-with-a-local-secret'
docker compose up --build -d helios-ai-api

curl http://localhost:5170/healthz
curl -H "X-HELIOS-Api-Key: $HELIOS_API_ACCESS_KEY" \
  http://localhost:5170/v1/engines
```

The image runs as a non-root user and includes Python plus the checked-in spoke. Compose
persists `.helios/learning` in a named volume. Provider credentials pass through from the
host; unset providers remain unconfigured. `.env` and `.env.*` are excluded from the
Docker build context so local credentials are not sent to the daemon.

The optional `fleet` profile runs the dependency-free local kanban stub:

```bash
mkdir -p .helios/fleet
export FLEET_UID="$(id -u)" FLEET_GID="$(id -g)"
docker compose --profile fleet up fleet-stub
```

The stub performs no model work and makes no network calls.

## What to add and where

The contributor routing table — find your kind of change, go to its home, follow its
skill/doc. Coding skills live in `.claude/skills/` and are picked up by Claude Code
automatically in this repo.

| You are adding… | It goes in… | Follow |
|---|---|---|
| A new LLM provider, `helios-ai` CLI command, or MCP tool | `src/ai/` / `src/mcp/` + `config/aihub.json` | `.claude/skills/api-creator` — the end-to-end recipe listing every file that must change together |
| A GitHub Actions workflow or CI change | `.github/workflows/` | `.claude/skills/pipelines-config`; nothing new may depend on a known-red workflow ([ROADMAP inventory](docs/architecture/ROADMAP_MULTI_LLM.md)) |
| Infrastructure | `infra/` — **Bicep first** (`main.bicep` + `modules/`); regenerate `infra/arm/main.json` from it (never hand-edit; CI fails on drift); port to the `infra/terraform/` mirror | `.claude/skills/iac-azure`, [infra/README.md](infra/README.md) |
| Fleet behavior or pools | `scripts/fleet/` + `config/fleet/fleet-topology.json` | [HERMES_FLEET_AND_XCORE.md](docs/architecture/HERMES_FLEET_AND_XCORE.md) |
| An absorption candidate (upstream PR worth benchmarking) | `config/absorption/pr-watchlist.json`, tied to a ledger epic | [ABSORPTION_PIPELINE.md](docs/architecture/ABSORPTION_PIPELINE.md), [ABSORPTION_LEDGER.md](docs/architecture/ABSORPTION_LEDGER.md) |
| Architecture/operations docs | `docs/architecture/` — merged docs auto-publish to the GitHub wiki via the Wiki Sync workflow | `CLAUDE.md` doc rules (root-level `*_COMPLETE/*_REPORT` files are historical; do not extend them) |
| GUI work | `src/gui/` — its **own** solution, built on Windows | [src/gui/README.md](src/gui/README.md) ("Fork & contribute GUI work") |
| PowerShell automation | `scripts/` — PS7 wraps the C# CLI, never reimplements it | `.claude/skills/powershell-automation` |

Two hard rules that bite newcomers (full list in `CLAUDE.md`):

1. **The root `HELIOS.Platform.csproj` recursively globs `**/*.cs`.** Any new C#
   directory outside `src/ai`/`src/mcp` must be added to its `<Compile Remove>` list in
   the same commit, or it silently breaks the root WPF project.
2. **No secrets in the repo, ever.** Config files carry env-var *names* only; values come
   from your shell, GitHub Actions secrets, or Azure Key Vault. Bicep takes secrets as
   `@secure()` parameters and never outputs them.

## Fork & contribute

1. Fork [`Yolkster64/helios-platform`](https://github.com/Yolkster64/helios-platform)
   and clone your fork.
2. Run the quickstart above, then the relevant lanes of
   [docs/TEST_RUN_PLAYBOOK.md](docs/TEST_RUN_PLAYBOOK.md) so you know your baseline is
   green before you change anything.
3. Branch, make the change in its home (table above), run the same local gates CI runs
   (`CLAUDE.md`, "Build & test").
4. Open a PR against `main`.

What the automation does to your PR, automatically:

- **CI suite** (each path-filtered, so only relevant ones run): `.NET Build & Test`
  (solution build + tests), `Python Spoke` (pytest, bare + `[ml]` matrix), `Infra
  Validation` (Bicep compile, ARM-freshness drift gate, Terraform fmt/validate), `Docker
  Validation` (image build + compose validation), `CI - Code Validation & Testing`
  (including a blocking PowerShell parse gate against the legacy baseline), `Code Quality
  & Linting` (markdownlint + PSScriptAnalyzer — currently advisory, `continue-on-error`).
- **Copilot review**: the `Copilot Dispatch` workflow requests a GitHub Copilot code
  review on every non-draft PR; it skips green when Copilot is unavailable in the repo.
- **Heuristic review**: `AI Code Review Pipeline` runs regex-based scans (credential
  patterns, risky PowerShell). Despite the name it makes no LLM calls today — it is on
  the known-red inventory to be replaced with real `code_review` routing
  ([ROADMAP](docs/architecture/ROADMAP_MULTI_LLM.md)).
- **When the owner has set the secrets** (see
  [OWNER_START_HERE.md](docs/OWNER_START_HERE.md)): `Slack Notifications` posts CI/deploy
  outcomes (`SLACK_WEBHOOK_URL`), and `Linear Sync` mirrors labeled issues into Linear
  (`LINEAR_API_KEY`). Without the secrets both skip green — they are never the red check.
- **Hand work to an agent**: adding the `copilot` label to an issue assigns the GitHub
  Copilot coding agent, which opens a draft PR (requires Issues enabled on the repo and a
  Copilot subscription; degrades to a notice otherwise).
- **After merge to `main`**: the Wiki Sync workflow publishes `docs/**` to the GitHub
  wiki (`docs/architecture/X.md` → `Architecture-X`).

GUI contributions build on Windows against `src/gui/HELIOS.Shell.sln` — the Linux CI
cannot compile them, so build locally before the PR and read
[src/gui/README.md](src/gui/README.md) first.

## Configuration

Copy `.env.template` to an ignored local file and replace only the variables you use.
Never commit provider keys or API access keys.

Primary provider variables:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `AZURE_OPENAI_ENDPOINT` and optional `AZURE_OPENAI_API_KEY`
- `AZURE_FOUNDRY_PROJECT_ENDPOINT`
- `AZURE_KEY_VAULT_URI`
- `GITHUB_MODELS_TOKEN`
- `OLLAMA_BASE_URL`

## Architecture and operations

- [Multi-LLM integration](docs/architecture/MULTI_LLM_INTEGRATION.md)
- [Recovered engine integration record](docs/architecture/RECOVERED_AI_ENGINE_FABRIC.md)
- [Consolidation blueprint](docs/CONSOLIDATION_BLUEPRINT.md)
- [Hermes fleet and XCore](docs/architecture/HERMES_FLEET_AND_XCORE.md)
- [Cloud Shell & local fleet bring-up](docs/architecture/CLOUD_SHELL_AND_LOCAL_FLEET.md)
- [Absorption pipeline](docs/architecture/ABSORPTION_PIPELINE.md)
- [Fork observation](docs/architecture/FORK_OBSERVATION.md)
- [Roadmap](docs/architecture/ROADMAP_MULTI_LLM.md)

The absorption pipeline may benchmark prior upstream PRs in disposable worktrees, but
`Yolkster64/helios-platform` remains the write target. Nothing is auto-merged or pushed to
an upstream repository.

## Contributing

Open issues and pull requests against
[`Yolkster64/helios-platform`](https://github.com/Yolkster64/helios-platform). Keep changes
inside the buildable project boundaries described in [AGENTS.md](AGENTS.md), run the
relevant local gates, and do not claim deployment or security properties without
verifiable evidence.

## License

See [LICENSE](LICENSE).
