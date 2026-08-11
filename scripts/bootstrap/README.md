# Bootstrap: browser auth + cross-LLM environment bring-up

One command stands up the whole cross-LLM shell in **Azure Cloud Shell** (the reference
environment), **GitHub Codespaces**, or a **local** Linux/macOS shell:

```bash
scripts/bootstrap/cloud-shell-setup.sh
```

That verifies/installs the CLI fleet (`az`, `gh`, `claude`, `codex`, `copilot`,
optionally `ollama`), browser-authenticates GitHub and Azure via device-code flows,
prints the env-wiring commands, smoke-tests `helios-ai status` / `routing` in
parallel, and finishes with the unified readiness inventory
(`scripts/setup/setup-all.ps1`, below).

## The pieces (each usable on its own)

| Script | What it does |
| --- | --- |
| `connect-github.sh` | `gh auth login --web` device-code flow. **Source it** to also export `GITHUB_MODELS_TOKEN` from the gh token, which flips the `github-models` provider in `config/aihub.json` to Ready with no manually-handled key. |
| `connect-azure.sh` | `az login --use-device-code` (URL + one-time code, works from any browser on any device). Detects Cloud Shell's implicit login and skips. `--subscription <id>` selects a subscription. |
| `connect-azure.ps1` | Azure PowerShell twin: `Connect-AzAccount -UseDeviceAuthentication`, same Cloud Shell detection and `-Subscription` selection, for shells where Az cmdlets are the native tool. |
| `load-env-from-keyvault.sh` | **Source it** after Azure login. Pulls `openai-api-key`, `anthropic-api-key`, `github-models-token` from the Key Vault at `AZURE_KEY_VAULT_URI` (provisioned by `infra/main.bicep`) into the matching env vars from `config/aihub.json`. |
| `azure-up.sh` | End-to-end cloud bring-up: device-code login → resource group → `infra/main.bicep` deployment (with your objectId for the RBAC grants) → writes endpoint wiring to `.helios/azure.env` and points `AIHUB_CONFIG` at the cloud profile. |
| `azure-up.ps1` | Azure PowerShell twin of `azure-up.sh` (`New-AzResourceGroupDeployment`); writes `.helios/azure.env.ps1` for dot-sourcing. |
| `setup-ai-clis.ps1` | Installs/verifies the AI agent CLIs behind `config/aihub.json`'s `cliAgents`: `claude`, `codex`, `copilot` (all npm), and verifies `gh` for gh-models. Idempotent; prints headless-auth guidance per CLI; never prompts, never stores secrets. |
| `cloud-shell-setup.sh` | Orchestrates the CLI fleet + both auth flows. `--skip-auth` / `--skip-smoke` to narrow it. |

## AI CLI setup: `setup-ai-clis.ps1`

Installs/verifies exactly the CLIs the AIHub's `cliAgents` entries invoke, matched to
the binary shape in `config/aihub.json`:

| cliAgent | Binary | Package | Invocation shape |
| --- | --- | --- | --- |
| `claude-cli` | `claude` | npm `@anthropic-ai/claude-code` | `claude -p {prompt}` |
| `codex` | `codex` | npm `@openai/codex` | `codex exec {prompt}` |
| `copilot` | `copilot` | npm `@github/copilot` | `copilot -p {prompt}` |
| `gh-models` | `gh` | verified only, never installed | `gh models run {model} {prompt}` |

**Copilot packaging**: `config/aihub.json` calls a standalone `copilot` binary with
`-p {prompt}`; only npm's `@github/copilot` (GitHub Copilot CLI) provides that shape.
The gh extension (`gh extension install github/gh-copilot`) would instead add
`gh copilot suggest|explain` — wrong binary, wrong argument grammar — so it is not
used (and this matches what `cloud-shell-setup.sh` already installs).

```powershell
pwsh scripts/bootstrap/setup-ai-clis.ps1               # install what's missing
pwsh scripts/bootstrap/setup-ai-clis.ps1 -VerifyOnly   # report-only (repo verify-only convention)
pwsh scripts/bootstrap/setup-ai-clis.ps1 -Skip codex,copilot
```

Idempotent (present CLIs are skipped with their version printed) and secret-free: it
prints per-CLI headless-auth guidance — `ANTHROPIC_API_KEY` / `claude setup-token`,
`OPENAI_API_KEY` / `codex login`, `gh auth login --web` device-code for copilot/gh,
`az login --use-device-code` (skipped advice in pre-authed Cloud Shell) — but never
runs a login flow itself. Exit 0 = all present, 2 = something missing (npm absent when
installs are needed is a clear error).

## One-command readiness: `scripts/setup/setup-all.ps1`

The unified entrypoint from absorption ledger epic E1 — an orchestrator that calls the
scripts above (never reimplements them) and prints one INVENTORY table:
component / status (`ready` | `needs-attention`) / detail / next command to fix.

| Step | Delegated to |
| --- | --- |
| Toolchain | `scripts/build/verify-readiness.ps1 -Json` |
| GitHub auth | `connect-github.sh --verify-only` (read-only) |
| Azure auth | `connect-azure.sh --verify-only` / `connect-azure.ps1 -VerifyOnly` (read-only) |
| AI CLIs | `setup-ai-clis.ps1` (`-VerifyOnly` unless `-Fix`) |
| Fleet topology | `config/fleet/fleet-topology.json` parses + pools listed |
| MCP registration | `.mcp.json` parses + server project exists |

```powershell
pwsh scripts/setup/setup-all.ps1         # verify everything, print the inventory
pwsh scripts/setup/setup-all.ps1 -Fix    # also install missing AI CLIs (never auth-mutating)
pwsh scripts/setup/setup-all.ps1 -Json   # machine-readable inventory, nothing else on stdout
```

Exit 0 when every component is ready, 2 otherwise. Auth is never mutated in either
mode — device-code logins stay behind the `connect-*` scripts, run by a human when the
inventory says so.

## Cloud-only profile

`config/aihub.cloud.json` is the hub with every local dependency removed: hosted LLM
APIs only (azure-openai, azure-foundry, openai, anthropic, github-models), no ollama,
no CLI subprocess agents, and the learning loop enabled from day one. Select it per
shell with `AIHUB_CONFIG=config/aihub.cloud.json` (azure-up writes exactly that into
`.helios/azure.env`), or per invocation with `--aihub-config`. After `azure-up.sh`,
the `azure-openai` provider authenticates with your Entra ID login — no API key ever
touches the machine.

## Secrets policy

Nothing here writes a secret to disk. `gh` and `az` keep their tokens in their own
stores; Key Vault values land only in process environment variables. This matches the
repo rule in `CLAUDE.md`: config carries env-var *names*, keys come from the
environment or Key Vault.

## Why device-code everywhere

Device-code login shows a URL and a one-time code you complete in any browser — the
same flow whether the shell is Cloud Shell, a Codespace, an SSH box, or your laptop.
Where a local browser exists, `gh`/`az` open it automatically; where none does, you
finish auth on your phone or another machine. One flow, every environment.
