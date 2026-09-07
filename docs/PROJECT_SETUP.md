# HELIOS Project Setup

The canonical clone-to-working-hub guide for this repository. It covers the
toolchain, the exact build/test commands CI runs, how configuration and secrets
flow, a quick tour of the `helios-ai` CLI, and MCP registration. For what an
*owner* must configure (secrets, GitHub settings, Azure identity), see
[`OWNER_START_HERE.md`](OWNER_START_HERE.md).

## Prerequisites

Required on every development box — these are what the standard build/test
commands need:

| Tool | Version | Used for |
| --- | --- | --- |
| .NET SDK | 10.x (`global.json` pins 10.0.100) | `dotnet build HELIOS.sln` (AIHub + CLI + API + MCP + tests) |
| PowerShell | 7.x (`pwsh`) | The automation layer under `scripts/` (portable; runs on Linux CI too) |
| Python | 3.10+ (`python3`) | The Python spoke `src/ai/python` (its tests are dependency-free) |
| Bicep CLI | any current | `bicep build infra/main.bicep` (or use `az bicep` instead) |

Optional — each unlocks an extra lane and nothing breaks without it:

| Tool | Unlocks |
| --- | --- |
| Azure CLI (`az`) | Azure login, Key Vault env loading, `azure-up.sh` bring-up, `az bicep` as the Bicep fallback |
| Terraform | The `infra/terraform/` dialect of the same infrastructure |
| CMake + a C++ compiler (`g++`/MSVC) | The native spoke (`src/ai/HELIOS.AIHub.Native` via `scripts/build/build-native.sh`/`.ps1`); AIHub degrades to managed fallbacks when absent |
| Docker | The `docker-compose.yml` stack |

Check your box in one command (exit 0 = all required tools present, 2 = not):

```bash
pwsh scripts/build/verify-readiness.ps1          # human table
pwsh scripts/build/verify-readiness.ps1 -Json    # machine-readable
```

For the *whole* readiness picture in one command — toolchain plus auth state, AI CLIs,
fleet topology, and MCP registration — use the unified entrypoint instead:
`pwsh scripts/setup/setup-all.ps1` (`-Fix` installs missing AI CLIs; auth is never
mutated). See `scripts/bootstrap/README.md` and the README quickstart.

## Clone, build, test

These are exactly the commands CI runs (see `CLAUDE.md`, which is authoritative):

```bash
git clone https://github.com/Yolkster64/helios-platform
cd helios-platform

dotnet build HELIOS.sln -c Release          # AIHub + CLI + MCP + tests ONLY
dotnet test tests/HELIOS.AIHub.Tests -c Release
cd src/ai/python && python3 -m pytest tests # Python spoke (dependency-free; [ml] extra optional)
cd ../../..
bicep build infra/main.bicep --stdout       # or: az bicep build --file infra/main.bicep
python3 scripts/validation/validate_yolkster_cutover.py  # cutover contract (read-only)
```

Expected outcomes for these commands — and smoke runs for every other surface (CLI, API,
MCP, Docker, fleet, absorption, infra) — are in
[`TEST_RUN_PLAYBOOK.md`](TEST_RUN_PLAYBOOK.md).

Two things to know before you touch the solution:

- **`HELIOS.sln` deliberately excludes `src/core/HELIOS.Platform`** — the core
  project does not compile today (~323 errors). Do not add it back until it
  builds.
- The root `HELIOS.Platform.csproj` recursively globs `**/*.cs`; any new C#
  directory outside `src/ai`/`src/mcp` must be added to its `<Compile Remove>`
  list in the same commit.

## Configuration overview

**No secrets ever live in this repo.** Configuration files carry environment
variable *names*; values come from your shell or Azure Key Vault.

- `config/aihub.json` — providers and the task-routing table. Each provider
  names its credential env var (`apiKeyEnv`/`endpointEnv`): `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`, `AZURE_OPENAI_ENDPOINT`/`AZURE_OPENAI_API_KEY`,
  `GITHUB_MODELS_TOKEN`, `OLLAMA_BASE_URL`, `AZURE_FOUNDRY_PROJECT_ENDPOINT`.
  Resolution order per provider: env var → Azure Key Vault
  (`AZURE_KEY_VAULT_URI`) → Unconfigured.
- `.env.template` — tracked placeholders for all of the above. Copy it to
  `.env` (git-ignored), fill in real values there only, and `source .env`.
- `config/aihub.cloud.json` — the hosted-APIs-only profile (no ollama, no CLI
  subprocess agents). Select per shell with
  `AIHUB_CONFIG=config/aihub.cloud.json`.
- `config/connectors.json` — Slack/Linear wiring; env-var names only (see
  `OWNER_START_HERE.md` for setting the values).
- Browser auth + Key Vault loading: `scripts/bootstrap/` (see its README).
  `source scripts/bootstrap/load-env-from-keyvault.sh` pulls provider keys from
  the Key Vault at `AZURE_KEY_VAULT_URI` into the matching env vars.

## Authoring config and workflows

Every manifest the scripts, workflows and binders consume (`config/github/*.json`,
`config/connectors.json`, `config/fork-watch.json`, `config/absorption/*.json`,
`config/fleet/*.json`, `config/aihub*.json`, the model catalog and the Fabric
contract) has a JSON Schema (draft 2020-12) under `config/schemas/`, and
`config/schemas/manifests.json` is the one map from manifest to schema. Three
consumers read that map, so the check is the same everywhere:

- **Editor.** `.vscode/settings.json` binds each manifest to its schema
  (`json.schemas`) and `.github/workflows/*.yml` to the SchemaStore workflow schema
  (`yaml.schemas`, through the recommended `redhat.vscode-yaml` extension), so
  errors and completions appear as you type. `config/github/labels.json` and
  `config/github/milestones.json` carry no `$schema` key on purpose — their apply
  scripts also accept a bare array, which cannot hold one — so their binding lives
  only in the workspace settings; the other manifests carry a relative `$schema`
  too, for editors that honour it.
- **Command line and CI.** `python3 scripts/validation/validate_config_schemas.py`
  validates every mapped manifest (or one path, or a draft with `--schema`), using
  `python-jsonschema` when installed and its built-in engine otherwise, so it runs
  on a bare runner. The `quality.yml` JSON job runs it, and
  `.claude/skills/automation-wiring/scripts/validate_all.py` folds the same check
  into its JSON/YAML/Bicep/Actions sweep.
- **MCP.** `helios_config_validate` (tool list in
  [`mcp/CLIENT_SETUP.md`](mcp/CLIENT_SETUP.md)) returns
  `{ path, schema, valid, errors }` for a repo-relative manifest, read-only.

Starters for the files people author most often — a workflow skeleton with every
guard explained (`permissions: {}` plus per-job opt-ins, the `env:` idiom for
`${{ }}` values, pinned action majors, `concurrency`, `workflow_dispatch` inputs)
and the labels / milestones manifests — live in
[`templates/`](../templates/README.md). Copy, edit, validate; on `main` the control
fabric (`governance-apply.yml`) applies the manifests.

## CLI quick tour

`helios-ai` is `src/ai/HELIOS.AIHub.Cli`. Run it from the repo root:

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- status      # provider readiness
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- routing     # task-type routing table
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- providers list
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- ask "prompt"
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- route code_review "prompt"
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- tandem "prompt"
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- compare --providers openai,anthropic "prompt"
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- engines     # engine catalog
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- engine-plan # advisory mix; never auto-executes
```

`status` and `routing` work with zero providers configured — they are the first
thing to run after a build. Which model suits which task:
`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md`.

## MCP registration

`.mcp.json` at the repo root registers the MCP server for MCP-capable clients
(Claude Code picks it up automatically when started in the repo):

```json
{
  "mcpServers": {
    "helios": {
      "command": "dotnet",
      "args": ["run", "--project", "src/mcp/HELIOS.Mcp", "-c", "Release"],
      "env": {
        "HELIOS_REPO_ROOT": "."
      }
    }
  }
}
```

The tool list lives in one place, [docs/mcp/CLIENT_SETUP.md](mcp/CLIENT_SETUP.md)
(`scripts/verify/stack-smoke.ps1` parses it), together with the per-client registration
for Claude Code, VS Code / Copilot, Codex and Cursor and the Playwright browser server
that rides next to `helios` in each of them.

## Fleet quickstart

The Hermes agent fleet and XCore design — including the opt-in Azure VMSS burst
capacity — lives in
[`docs/architecture/HERMES_FLEET_AND_XCORE.md`](architecture/HERMES_FLEET_AND_XCORE.md).
The VMSS lane is OFF by default and doubly gated in `infra/main.bicep`
(`deployFleetVmss` and a non-empty SSH key) — see `infra/README.md`, "Fleet
burst capacity (VMSS)".

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `dotnet build HELIOS.sln` errors mention `src/core/HELIOS.Platform` | The core project is excluded on purpose (~323 errors); do not re-add it. Build the solution as shipped. |
| Providers show `Unconfigured` in `helios-ai status` | Expected until env vars are set. Copy `.env.template` → `.env` and fill in, or `source scripts/bootstrap/load-env-from-keyvault.sh` after `az login`. |
| `github-models` provider returns 403 | The gh token lacks the `models:read` scope. `gh auth refresh --hostname github.com --scopes models:read` (see `scripts/bootstrap/connect-github.sh`). |
| `bicep: command not found` | Use the Azure CLI bundle instead: `az bicep build --file infra/main.bicep`. |
| Python spoke tests fail on missing numpy/scikit-learn | Only the `[ml]` extra needs them; the bare path is dependency-free. `pip install '.[ml]'` inside `src/ai/python` if you want the ML backends. |
| CI's "Python compile check" fails | `python3 -m compileall -q src/ai/python scripts` — a `.py` file under those trees has a syntax error; run the same command locally. |
| MCP client does not list the `helios` server | Start the client from the repo root so it reads `.mcp.json`; the server itself needs the .NET 10 SDK. |
| Fleet VMSS missing after a deploy | Both gates must open: `deployFleetVmss=true` **and** a non-empty `vmssAdminPublicKey` (`infra/main.bicepparam`, `infra/README.md`). |
| A `scripts/**.ps1` fails under Windows PowerShell 5.x | Scripts target PowerShell 7 (`#Requires -Version 7`); run them with `pwsh`. |

## Where to go next

- `CLAUDE.md` — build commands and the repo's hard rules (read first).
- [`TEST_RUN_PLAYBOOK.md`](TEST_RUN_PLAYBOOK.md) — test-run every surface with expected
  outcomes.
- `docs/CONSOLIDATION_BLUEPRINT.md` and `docs/architecture/` — the trustworthy
  architecture docs (root-level `*_COMPLETE/*_REPORT/*_SUMMARY.md` files are
  historical and unreliable).
- `docs/architecture/MULTI_LLM_INTEGRATION.md` — the multi-LLM hub design.
- `docs/OWNER_START_HERE.md` — day-one owner configuration.
