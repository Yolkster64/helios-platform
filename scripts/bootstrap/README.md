# Bootstrap: browser auth + cross-LLM environment bring-up

One command stands up the whole cross-LLM shell in **Azure Cloud Shell** (the reference
environment), **GitHub Codespaces**, or a **local** Linux/macOS shell:

```bash
scripts/bootstrap/cloud-shell-setup.sh
```

That verifies/installs the CLI fleet (`az`, `gh`, `claude`, `codex`, `copilot`,
optionally `ollama`), browser-authenticates GitHub and Azure via device-code flows,
prints the env-wiring commands, and smoke-tests `helios-ai status` / `routing` in
parallel.

## The pieces (each usable on its own)

| Script | What it does |
| --- | --- |
| `connect-github.sh` | `gh auth login --web` device-code flow. **Source it** to also export `GITHUB_MODELS_TOKEN` from the gh token, which flips the `github-models` provider in `config/aihub.json` to Ready with no manually-handled key. |
| `connect-azure.sh` | `az login --use-device-code` (URL + one-time code, works from any browser on any device). Detects Cloud Shell's implicit login and skips. `--subscription <id>` selects a subscription. |
| `connect-azure.ps1` | Azure PowerShell twin: `Connect-AzAccount -UseDeviceAuthentication`, same Cloud Shell detection and `-Subscription` selection, for shells where Az cmdlets are the native tool. |
| `load-env-from-keyvault.sh` | **Source it** after Azure login. Pulls `openai-api-key`, `anthropic-api-key`, `github-models-token` from the Key Vault at `AZURE_KEY_VAULT_URI` (provisioned by `infra/main.bicep`) into the matching env vars from `config/aihub.json`. |
| `azure-up.sh` | End-to-end cloud bring-up: device-code login → resource group → `infra/main.bicep` deployment (with your objectId for the RBAC grants) → writes endpoint wiring to `.helios/azure.env` and points `AIHUB_CONFIG` at the cloud profile. |
| `azure-up.ps1` | Azure PowerShell twin of `azure-up.sh` (`New-AzResourceGroupDeployment`); writes `.helios/azure.env.ps1` for dot-sourcing. |
| `cloud-shell-setup.sh` | Orchestrates the CLI fleet + both auth flows. `--skip-auth` / `--skip-smoke` to narrow it. |

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
