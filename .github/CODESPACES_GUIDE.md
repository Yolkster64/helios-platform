# GitHub Codespaces Quick Start

Repository: `Yolkster64/helios-platform`. The Codespace is defined by
`.devcontainer/devcontainer.json` (the official .NET 10 devcontainer image plus features);
the older `Dockerfile` / `docker-compose.yml` / `onCreateCommand.sh` / `init-db.sh` in
that directory are the standalone local-Docker stack described in
`.devcontainer/README.md` and are not used by Codespaces.

## Launch

### Option 1: Web

1. Go to <https://github.com/Yolkster64/helios-platform>
2. Click **Code** (green button), then the **Codespaces** tab
3. Click **Create codespace on main** (or pick a branch)
4. The container builds in a few minutes; `postCreateCommand` then restores and builds
   `HELIOS.sln` and installs the Python spoke

### Option 2: GitHub CLI

```bash
gh codespace create --repo Yolkster64/helios-platform --branch main --machine standardLinux32gb
gh codespace code --repo Yolkster64/helios-platform     # opens VS Code
gh codespace ssh  --repo Yolkster64/helios-platform     # or a terminal
```

`hostRequirements` in `devcontainer.json` asks for 4 cores / 8 GB, so the 2-core machine
type is filtered out of the picker by the core count (`basicLinux32gb` already has 8 GB);
`standardLinux32gb` (4-core / 16 GB) is the smallest type that qualifies.

### Option 3: VS Code

1. Install the **GitHub Codespaces** extension
2. Command Palette (Ctrl+Shift+P): **Codespaces: Create New Codespace**
3. Select `Yolkster64/helios-platform` and a branch

## What is included

| Piece | Source |
| --- | --- |
| .NET 10 SDK | image `mcr.microsoft.com/devcontainers/dotnet:10.0` |
| Azure CLI, GitHub CLI, PowerShell 7, Node LTS, Python 3.11, Terraform | `features` in `devcontainer.json` |
| Port 5170 forwarded (`helios-ai-api`) | `forwardPorts` |
| `helios-ai` on PATH (symlink to the Release build) | `postCreateCommand` |
| Auth self-check line on every attach | `postAttachCommand` runs `scripts/bootstrap/session-start-check.sh` |

VS Code extensions (the same list in `.devcontainer/devcontainer.json`,
`.vscode/extensions.json`, and `workspace.code-workspace`):

- `ms-dotnettools.csharp`, `ms-dotnettools.csdevkit`
- `ionide.ionide-fsharp`
- `ms-python.python`, `ms-python.vscode-pylance`
- `ms-azuretools.vscode-bicep`
- `hashicorp.terraform`
- `ms-vscode.powershell`
- `github.vscode-pull-request-github`
- `github.copilot`, `github.copilot-chat`

Tasks (Terminal > Run Task, from `.vscode/tasks.json`): `build`, `test`, `stack-smoke`,
`first-run`, `auth-doctor`. The `helios` MCP server for Copilot agent mode is registered
in `.vscode/mcp.json` (see `docs/mcp/CLIENT_SETUP.md`).

## First run

One command, in the Codespace terminal:

```bash
bash scripts/bootstrap/first-run.sh
```

It detects the Codespace, verifies the CLI fleet, runs the read-only auth and REST
probes, the readiness inventory (`scripts/setup/setup-all.ps1`, which now includes an
informational MCP stdio health row), and ends with ONE numbered checklist of the steps
only the owner can do (device-code logins, Key Vault values). Individual pieces:

```bash
pwsh scripts/bootstrap/auth-doctor.ps1      # report-only auth diagnosis per lane
pwsh scripts/setup/setup-all.ps1            # toolchain / auth / CLIs / fleet / MCP inventory
pwsh scripts/verify/stack-smoke.ps1         # API + MCP handshake + CLI, against the Release build
```

`gh` is pre-authenticated inside a Codespace with the `GITHUB_TOKEN` GitHub injects;
Azure needs `az login --use-device-code` once (`scripts/bootstrap/connect-azure.sh`).

## Codespaces secrets

`devcontainer.json` declares these under `secrets` so the creation page prompts for them
and they arrive as environment variables. Names only live in the repo; values never do.
All of them are optional: a missing one makes the matching lane report not-ready instead
of failing.

| Secret name | Used by | Where it comes from |
| --- | --- | --- |
| `OPENAI_API_KEY` | `openai` provider in `config/aihub.json`; the `codex` CLI | OpenAI platform API keys page, or Key Vault secret `openai-api-key` via `scripts/bootstrap/load-env-from-keyvault.sh` |
| `ANTHROPIC_API_KEY` | `anthropic` provider in `config/aihub.json`; the `claude` CLI | Anthropic console, or Key Vault secret `anthropic-api-key` via `load-env-from-keyvault.sh` |
| `GITHUB_MODELS_TOKEN` | `github-models` provider in `config/aihub.json` | `source scripts/bootstrap/connect-github.sh` exports it from the gh login (needs the `models:read` scope), or Key Vault secret `github-models-token` |
| `AZURE_KEY_VAULT_URI` | `load-env-from-keyvault.sh`, `auto-login.ps1`, `auth-doctor.ps1` | Output of `scripts/bootstrap/azure-up.sh` (the `infra/main.bicep` deployment) |
| `AZURE_OPENAI_ENDPOINT` | `azure-openai` provider in `config/aihub.json` — first in the hub's `defaultChain` (an identifier, not a secret; declared here so the creation page prompts for it) | Output of `scripts/bootstrap/azure-up.sh` (`https://<account>.openai.azure.com/`); no Key Vault fallback |
| `AZURE_OPENAI_API_KEY` | `azure-openai` provider, key auth only | Optional: leave it empty to use Entra ID via `DefaultAzureCredential` after `az login --use-device-code`; Azure portal → the OpenAI account → Keys otherwise. No Key Vault fallback |

Set them without ever putting a value on a command line (the CLI prompts for it):

```bash
gh secret set OPENAI_API_KEY        --user --app codespaces --repos Yolkster64/helios-platform
gh secret set ANTHROPIC_API_KEY     --user --app codespaces --repos Yolkster64/helios-platform
gh secret set GITHUB_MODELS_TOKEN   --user --app codespaces --repos Yolkster64/helios-platform
gh secret set AZURE_KEY_VAULT_URI   --user --app codespaces --repos Yolkster64/helios-platform
gh secret set AZURE_OPENAI_ENDPOINT --user --app codespaces --repos Yolkster64/helios-platform
gh secret set AZURE_OPENAI_API_KEY  --user --app codespaces --repos Yolkster64/helios-platform   # skip for Entra ID
```

Or in the browser: Settings > Codespaces > Secrets > New secret, repository access
`Yolkster64/helios-platform`. With only `AZURE_KEY_VAULT_URI` set, `az login` plus
`source scripts/bootstrap/load-env-from-keyvault.sh` pulls the three provider keys from
Key Vault into the session, so they need not be Codespaces secrets at all.
`AZURE_OPENAI_ENDPOINT` has no Key Vault path — `azure-up.sh` exports it only in the
shell that ran the deployment — so store it as a Codespaces secret (or in the gitignored
`.env`) to light the `azure-openai` lane the `defaultChain` starts with; with the key
left empty that lane authenticates through the same `az login`.

## Working in the Codespace

```bash
dotnet build HELIOS.sln -c Release              # what CI runs
dotnet test tests/HELIOS.AIHub.Tests -c Release
cd src/ai/python && python3 -m pytest tests     # dependency-free spoke
helios-ai status                                # provider readiness
```

Branch, commit, and push as usual; `gh pr create` opens the pull request. Every PR gets
the CI workflows plus the bot review loop described in `CLAUDE.md` / `AGENTS.md`.

## Lifecycle

- Idle timeout suspends the Codespace (default 30 minutes; the build cache survives)
- Resume at <https://github.com/codespaces> or `gh codespace code`
- Delete with `gh codespace delete --repo Yolkster64/helios-platform`
- A `Rebuild Container` (Command Palette) is needed after `devcontainer.json` changes

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `helios-ai: command not found` | `dotnet build HELIOS.sln -c Release`, then re-open the terminal (the symlink points at the Release output) |
| `dotnet build` fails on `src/core/HELIOS.Platform` | Expected: the core project is deliberately excluded from `HELIOS.sln`; build the solution, not the folder |
| Provider shows not-ready | The matching env var is unset: set the Codespaces secret above, or `az login` + `source scripts/bootstrap/load-env-from-keyvault.sh` |
| `az` says not logged in | `az login --use-device-code` (or `scripts/bootstrap/connect-azure.sh`) |
| MCP row in `setup-all.ps1` reads `skipped` (no Release build) or `unhealthy` | Build first (`dotnet build HELIOS.sln -c Release`; the probe runs `--no-build` and never builds for you), then `pwsh scripts/verify/stack-smoke.ps1` for the full handshake and tool-name check |
| Extensions missing after rebuild | Wait for the extension host, or Command Palette > **Developer: Reload Window** |
| Out of disk | `dotnet clean HELIOS.sln`, `rm -rf ~/.nuget/packages/.tools`, or pick a larger machine type |

## Checklist before starting work

- [ ] `postCreateCommand` finished (`helios-ai status` answers)
- [ ] `bash scripts/bootstrap/first-run.sh` ran and its owner checklist is empty or understood
- [ ] `git status` shows the branch you meant to work on
- [ ] Secrets you need are present by NAME (`env | grep -E 'OPENAI_API_KEY|ANTHROPIC_API_KEY|GITHUB_MODELS_TOKEN|AZURE_KEY_VAULT_URI|AZURE_OPENAI_ENDPOINT|AZURE_OPENAI_API_KEY' | cut -d= -f1`)
