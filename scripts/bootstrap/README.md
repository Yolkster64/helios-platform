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
| `load-env-from-keyvault.sh` | **Source it** after Azure login. Pulls `openai-api-key`, `anthropic-api-key`, `github-models-token` from the Key Vault at `AZURE_KEY_VAULT_URI` (provisioned by `infra/main.bicep`) into the matching env vars from `config/aihub.json`. |
| `cloud-shell-setup.sh` | Orchestrates all of the above. `--skip-auth` / `--skip-smoke` to narrow it. |

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
