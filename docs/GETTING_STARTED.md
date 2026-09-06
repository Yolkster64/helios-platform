# Getting started with HELIOS

This is the five-minute path from `git clone` to a working `helios-ai ask`, for three kinds
of reader: someone with only a GitHub account, someone with a ChatGPT/Codex login, and the
repository owner with an Azure tenant. Everything here was run from a Linux shell against
this repository; nothing needs a paid API key to reach the first answer.

## What HELIOS is

HELIOS Control is an enterprise Windows-management and multi-agent control platform under
consolidation. The part that builds and runs everywhere today is the **multi-LLM hub**: a
.NET 10 command line (`helios-ai`), a REST API (`helios-ai-api`), and an MCP server
(`helios`) that route one prompt to any of several providers (OpenAI, Anthropic, Claude in
Microsoft Foundry, Azure OpenAI, GitHub Models, a local Ollama) or to the agent CLIs you
already have (`codex`, `claude`, `copilot`, `gh models`), record every outcome, and learn
which lane answers best. Around it sit a Python analytics spoke, an F# routing domain and a
C++ learning kernel, review-only Azure and Foundry infrastructure, an agent fleet (Xcore-9
pools with Hermes lanes), and a WinUI 3 desktop shell that builds on Windows only. It is not
a finished product: the [README](../README.md#current-status) says what is real and what is
historical, the coverage matrix
([#242](https://github.com/Yolkster64/helios-platform/issues/242)) says, per item, where it
lives and what is still a gap, and the onboarding epic
([#223](https://github.com/Yolkster64/helios-platform/issues/223)) tracks the lanes that
make the first hour easier.

## Pick your path

| You have | Path | First provider that answers |
|---|---|---|
| A GitHub account | [Path A](#path-a-github-only-five-minutes) | `github-models` |
| A ChatGPT (Codex) login and GitHub | [Path B](#path-b-chatgpt--codex-and-github) | the `codex` CLI agent |
| The owner's Azure tenant | [Path C](#path-c-the-owner-with-azure) | the whole routing chain |
| Nothing but a laptop | [Free and offline](#free-and-offline-ollama) | `ollama` |

Zero-install alternative: open the repository in a Codespace and skip the toolchain
section entirely — see [`.github/CODESPACES_GUIDE.md`](../.github/CODESPACES_GUIDE.md).

## Prerequisites

| Tool | Why | Check |
|---|---|---|
| .NET SDK **10** (`global.json` pins 10.0.100) | builds `HELIOS.sln` | `dotnet --version` |
| PowerShell 7 (`pwsh`) | every automation script under `scripts/` | `pwsh --version` |
| Python 3.10+ | the analytics spoke, and the `first-run` checklist merge (without it the checklist prints empty) | `python3 --version` |
| Git and the GitHub CLI (`gh`) | clone, login, GitHub Models token | `gh --version` |
| Optional: `az`, `codex`, `claude`, `copilot`, `ollama`, `hermes`, Docker, CMake | the lanes you choose below | `pwsh scripts/setup/setup-all.ps1` lists what is missing |

`pwsh scripts/build/verify-readiness.ps1` checks the toolchain in one go; `pwsh
scripts/setup/setup-all.ps1 -Fix` installs the missing AI CLIs (it never touches logins).

## Clone, build, and make `helios-ai` short

```bash
git clone https://github.com/Yolkster64/helios-platform
cd helios-platform
dotnet build HELIOS.sln -c Release          # expect: 0 Error(s)
```

The CLI is `src/ai/HELIOS.AIHub.Cli/bin/Release/net10.0/helios-ai`. A Codespace symlinks
it to `/usr/local/bin/helios-ai`; in a local shell make the same short name yourself:

```bash
alias helios-ai="$PWD/src/ai/HELIOS.AIHub.Cli/bin/Release/net10.0/helios-ai"
# or, without an alias:
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- status
```

## First look: `helios-ai status`

```bash
helios-ai status
```

Every provider reports `Unconfigured` on a fresh clone, each with the exact variable to set.
That is the expected first state, not an error. `Ready` means *configured* (the variable or
CLI login is present); the first `ask` is what proves the wire.

## Path A: GitHub only (five minutes)

The GitHub Models lane needs nothing but your GitHub login with the `models:read` scope.

```bash
gh auth login --hostname github.com --git-protocol https --web --scopes models:read
source scripts/bootstrap/connect-github.sh     # exports GITHUB_MODELS_TOKEN from that login
helios-ai status                               # github-models: Ready
helios-ai ask "Say hello in five words" --provider github-models
```

Why `--provider`: the default routing chain is `azure-openai → openai → anthropic →
anthropic-foundry → github-models → ollama` (`config/aihub.json`, `routing.defaultChain`).
A plain `helios-ai ask` walks that chain and fails over past the unconfigured entries, which
works but is slower and noisier; naming the provider is deterministic.

Sanity check of the token itself, outside the hub: `gh models run openai/gpt-5-mini "hi"`.

## Path B: ChatGPT / Codex and GitHub

A ChatGPT login authenticates the **Codex CLI**, which the hub drives as the `codex` agent:

```bash
codex login                                    # or: codex login --device-auth
helios-ai ask "Reply with READY" --provider codex
helios-ai route code_generation "Write a C# extension method that trims a suffix"
```

`route code_generation` starts with `codex` (`config/aihub.json`, `taskRouting`). What a
CLI login does **not** do: light the `openai` and `openai-codex` API providers. Those read
`OPENAI_API_KEY` only (`scripts/bootstrap/connect-all.ps1` spells out the rule), so add a
platform key by name in your shell, or store it in Key Vault on Path C, if you want them.
Combine with Path A and `helios-ai compare "…" --providers codex,github-models` answers from
both lanes side by side.

Give Codex the hub's tools as well: `pwsh scripts/bootstrap/write-codex-config.ps1 -Apply`
registers the `helios` MCP server and the Playwright browser server in
`~/.codex/config.toml` (`codex mcp list` shows both) —
[`docs/mcp/CLIENT_SETUP.md`](mcp/CLIENT_SETUP.md).

## Path C: the owner with Azure

Two device codes in one sitting, then everything else without another prompt:

```bash
pwsh scripts/bootstrap/connect-devices.ps1 -VerifyOnly   # read-only: which lanes still need you
pwsh scripts/bootstrap/connect-devices.ps1               # gh + az codes on one screen, then the chain
```

The script starts the `gh` and `az` device flows together, prints both codes, waits for
both, and then chains: the GitHub Models export (when dot-sourced), the **HELIOS GitHub
App** (`connect-github-app.ps1`: two browser clicks, *Create GitHub App* and *Install*, and
the repository's admin writes run on a per-run installation token from then on), the Azure
ops identity (`connect-admin.ps1 -SkipGitHub`), the vault keys (`auto-login.ps1`), the
doctor, and a read-only `first-run` for the remaining checklist. Every lane is verify-first,
so a login you already hold is never asked for again; `-SkipChain` stops after the codes.

The longer form is `bash scripts/bootstrap/first-run.sh --connect` (or `--verify-only`
first): `cloud-shell-setup` → `auto-login` → `rest-connect` → `auth-doctor` →
`setup-everything` → a dry run of `provision-github-secrets`, ending with the numbered
checklist of human steps (Key Vault values, the connector secrets, the board PAT). The
Azure lane itself is `az login --use-device-code --tenant <tenant>` followed by
`bash scripts/bootstrap/azure-up.sh`, which writes `.helios/azure.env` with
`AZURE_KEY_VAULT_URI`, `AZURE_OPENAI_ENDPOINT` and `ANTHROPIC_FOUNDRY_RESOURCE`;
`source scripts/bootstrap/load-env-from-keyvault.sh` then pulls the provider keys into the
shell, and `azure-openai` / `anthropic-foundry` authenticate with your Entra login even
without a key. The owner runbook continues in
[`docs/OWNER_START_HERE.md`](OWNER_START_HERE.md).

## Free and offline: Ollama

```bash
ollama pull llama3.2                                  # the model config/aihub.json names
helios-ai ask "Say hello in five words" --provider ollama
export OLLAMA_BASE_URL=http://other-host:11434        # only if it is not on localhost
```

The hub reaches Ollama at `http://localhost:11434` by default; nothing leaves your machine.

## Routing knobs

- `--provider <name>` pins one provider; `helios-ai providers` lists the names.
- `helios-ai route <task-type> "<prompt>"` uses the per-task chains; `helios-ai routing`
  prints them.
- `helios-ai tandem <task-type> "<prompt>"` runs the whole chain at once and keeps the
  winner; `helios-ai compare "<prompt>" --providers a,b,c` shows every answer.
- `AIHUB_CONFIG=config/aihub.cloud.json` (or `--config`) swaps the profile; the cloud
  profile leads with the Azure lanes.
- Outcomes are recorded under `.helios/learning/` (gitignored); `helios-ai-api` serves
  `/v1/learning`, `/v1/insights` and `/v1/metrics` from them. Recording is on, adaptive
  routing is off by default: the learners advise, they never change the chain by themselves.

## Agents and the MCP server

The same hub is a tool surface for every assistant: `.mcp.json` registers the `helios`
server for Claude Code, `.vscode/mcp.json` for GitHub Copilot, and
`write-codex-config.ps1` for the Codex CLI, each next to a Playwright browser server so all
three can drive a browser the same way. `helios_ai_route`, `helios_ai_status`,
`helios_auth_status_get` and the rest are listed in
[`docs/mcp/CLIENT_SETUP.md`](mcp/CLIENT_SETUP.md); the Claude plugin under
`plugins/helios-operator` adds the operator skill and agent on top of the same server.

## Your first contribution

Look for `good first issue` under the **Getting started** milestone, or the sub-issues of
the onboarding epic. File bugs and features through the issue forms (`[BUG]`, `[FEATURE]`);
blank issues are off. Open the pull request with the template's four sections and paste real
gate output into **Verification**. Two reviewers read every PR (Copilot, and Codex when its
quota allows); fix or refute each finding with evidence, and nothing merges on a red or
skipped required check — the full rule is
[`docs/architecture/REVIEW_LOOP.md`](architecture/REVIEW_LOOP.md).

The local gates, from `CLAUDE.md`:

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release
cd src/ai/python && python3 -m pytest tests
bicep build infra/main.bicep --stdout
python3 scripts/validation/validate_yolkster_cutover.py
```

## What not to expect without Azure or keys

- `azure-openai`, `anthropic-foundry` and `azure-foundry` stay `Unconfigured`; nothing pulls
  from Key Vault.
- The deploy workflows are owner-dispatched and skip cleanly without the OIDC variables.
- `helios_azure_inventory_get` and the Foundry agent tools answer empty.
- The WinUI shell (`src/gui/HELIOS.Shell.sln`) builds on Windows only.
- The agent fleet runs its local stub workers until the `hermes` CLI is installed
  (`pwsh scripts/setup/setup-ai-clis.ps1 -VerifyOnly` prints the installer).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `helios-ai: command not found` | build first, then the alias above (Codespaces create the symlink for you) |
| `You must install .NET to run this application` | `dotnet` on `PATH` is not the SDK the repo pins; check `dotnet --version` against `global.json` |
| `github-models` answers 403 | the token lacks `models:read`: `gh auth refresh --scopes models:read`, then re-source `connect-github.sh` |
| `Unknown provider type` | a typo in `--provider`; `helios-ai providers` lists the valid names |
| `pwsh: command not found` | install PowerShell 7; every `scripts/**/*.ps1` needs it |
| `first-run.sh` prints an empty checklist | `python3` is missing; the raw reports are still under `.helios/bootstrap/` |
| `ask` returns "provider reported failure … (exhausted)" | every provider in the chain is unconfigured; use `--provider` for the lane you set up |
| `connect-devices` reports `transport-injected` | you ran it inside an agent container; run it from your own machine, Cloud Shell or a Codespace |

## How HELIOS got here

The buildable slice landed in one pull request on 2026-08-10 (#4: the hub, CLI, REST, MCP,
the F#, C++ and Python spokes, and all three infrastructure surfaces). Everything since is
refinement of that spine: the absorption ledger that turns the upstream history into
benchmarked epics (#13), one-command readiness (#94), the Copilot coding agent executing its
first epics (#95, #96, #97), Claude's governed OIDC lane into the repository (#100 → #152),
the knowledge packs and forward plan (#99), real dashboards and the automated
review-to-merge pipeline (#108), theme packs with computed contrast (#111), the cutover
contract and the WinUI 3 decision (#154), deploy custody (#191, #199), authentication closed
end to end (#113) with the control fabric in seven lane commits (#208), Claude in
Microsoft Foundry as a hub provider (#215), and the GitHub App that replaced the admin PAT
together with both device codes in one sitting (#241). The lanes of the onboarding epic
(#223) are the current chapter.

## Lessons the reviews kept teaching

These came back on pull request after pull request, so they are the house rules:

1. Secrets by name, never by value. Config carries environment-variable names; values
   travel over stdin or a mode-600 file, never argv, never a commit.
2. A hint names the literal variable to set. "Unconfigured" alone helps nobody.
3. Unconfigured is a state, not a crash. Startup never throws for a missing key.
4. Entra first, client secrets never: environment variable, then Key Vault, then
   Unconfigured; OIDC federation for workflows; `DefaultAzureCredential` everywhere.
5. A device code is a human step. Automation prepares and verifies around it.
6. Least privilege per job: `permissions: {}` at the top of a workflow, the narrowest grant
   per job, read-only validation split from write-capable publishing.
7. Truthful reporting beats green: a skipped check is not a pass, a proxy 403 is `unknown`,
   an unverifiable transport says "verify from your own machine".
8. Never engineer around a proxy denial; record it and print the exact owner command.

Read one merged pull request per task before you write code: adding a provider → #215
(with `.claude/skills/api-creator/SKILL.md`); adding an MCP tool → #216; a verify-first
bootstrap script → #241 (`connect-github-app.ps1`) and #113 (`rest-connect.ps1`); a
least-privilege workflow → #208's `governance-apply.yml` and #104's split authority.

## Where next

- [`docs/PROJECT_SETUP.md`](PROJECT_SETUP.md) — the contributor guide: toolchain, tests,
  the CLI tour, MCP registration.
- [`docs/TEST_RUN_PLAYBOOK.md`](TEST_RUN_PLAYBOOK.md) — every surface end to end with
  expected output.
- [`docs/mcp/CLIENT_SETUP.md`](mcp/CLIENT_SETUP.md) — the MCP server in Claude Code,
  VS Code, Codex and Cursor, plus the Playwright browser server.
- [`scripts/bootstrap/README.md`](../scripts/bootstrap/README.md) — every bring-up script and
  its contract.
- [`docs/OWNER_START_HERE.md`](OWNER_START_HERE.md) — the owner's day one.
- [`.github/CODESPACES_GUIDE.md`](../.github/CODESPACES_GUIDE.md) — the zero-install path.
