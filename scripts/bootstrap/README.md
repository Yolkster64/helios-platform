# Bootstrap: browser auth + cross-LLM environment bring-up

One command stands up the whole cross-LLM shell in **Azure Cloud Shell** (the reference
environment), **GitHub Codespaces**, or a **local** Linux/macOS shell:

```bash
bash scripts/bootstrap/first-run.sh --repository Yolkster64/helios-platform --verify-only  # no installs or logins
bash scripts/bootstrap/first-run.sh --repository Yolkster64/helios-platform  # normal automatic bring-up
# PowerShell twin: pwsh scripts/bootstrap/first-run.ps1 -Repository Yolkster64/helios-platform
```

`first-run` is an orchestrator over the scripts below, run as an ordered chain where
every step is soft (a lane that needs the owner is a checklist item, not a failure):
`cloud-shell-setup.sh --skip-smoke` as step 1 (CLI fleet `az`, `gh`, `claude`,
`codex`, `copilot`, optionally `ollama`; device-code logins for GitHub and Azure;
Cloud Shell persistence) → `auto-login.ps1` → `scripts/verify/rest-connect.ps1` →
`auth-doctor.ps1` → `setup-everything.ps1` → `provision-github-secrets.ps1` (dry run,
repo secrets by name). Every report is captured into `.helios/bootstrap-state.json`
(gitignored) and the run ends with ONE numbered checklist of the steps only a human
can do, with the exact command for each. `--verify-only` skips `auto-login.ps1`
because it delegates to `auth-doctor.ps1 -Apply`, which can log in non-interactively.

An explicit, validated `--repository owner/repo` (`-Repository owner/repo` in
PowerShell) automatically adds label/milestone dry-run readiness to the setup
chain and targets the repository-secret **name-only** probe at that same repository.
Existing credentials are used automatically; normal installation/login behavior
is retained. Omit the target for compatibility: no issue probes, and the existing
repository-secret default remains unchanged. `--skip-setup` / `-SkipSetup` skips
issue readiness with the setup step, but still forwards the target to the secret probe.

## The pieces (each usable on its own)

| Script | What it does |
| --- | --- |
| `connect-github.sh` | `gh auth login --web` device-code flow. **Source it** to also export `GITHUB_MODELS_TOKEN` from the gh token, which flips the `github-models` provider in `config/aihub.json` to Ready with no manually-handled key. |
| `connect-azure.sh` | `az login --use-device-code` (URL + one-time code, works from any browser on any device). Detects Cloud Shell's implicit login and skips. `--subscription <id>` selects a subscription. |
| `connect-azure.ps1` | Azure PowerShell twin: `Connect-AzAccount -UseDeviceAuthentication`, same Cloud Shell detection and `-Subscription` selection, for shells where Az cmdlets are the native tool. |
| `connect-all.ps1` | One command, every interactive login lane, **verify-first**: skips providers already authenticated, then runs the device-code / no-browser flows for the rest — `gh` (device-code), `az` (device-code; Cloud Shell implicit login skipped), `ant` (`ant auth login --no-browser`, per the CLI authentication docs); codex stays env-var-driven (`OPENAI_API_KEY`). Humans only — CI/fleet use OIDC/WIF/managed identity. Lanes table: `docs/architecture/CONNECTIONS_SETUP.md` § One-command login. |
| `connect-account.ps1` | **Identity-pinning** sibling of the auth doctor: verifies each surface is authenticated *as the intended account* (Azure/M365 → `JMore@Heli0s.onmicrosoft.com`, GitHub → `Yolkster64` — overridable parameters), reports the key-custody and workload-identity bridge lanes, and gates hard (exit 2) on any identity MISMATCH even in report mode. `-Apply` delegates non-interactive repair to `auth-doctor.ps1`; `-Json` one report object. |
| `auth-doctor.ps1` | Report-first authentication doctor for the `gh` / `az` / `openai-codex` / `claude` / `copilot` lanes plus verify-only connector lanes (`linear`, `slack`, `sharepoint`, `azure-devops` — wiring reports that never gate the exit code); `-Apply` adds automatic **non-interactive** repair (az service principal / managed identity only), `-Json` one machine-readable report object. MFA/device-code fixes are only ever *printed* as exact owner-action commands. |
| `setup-everything.ps1` | **The whole chain, in order, existing scripts only**: `verify-readiness.ps1` (toolchain) → `connect-account.ps1` (**identity gate** — any mismatch aborts the chain, exit 2) → `auth-doctor.ps1` (`-Apply` passed through; report-only by default) → `setup-all.ps1` (inventory) → `scripts/verify/stack-smoke.ps1` and `scripts/verify/rest-connect.ps1` (both soft — a missing script or failure is recorded, never aborts). Each step runs `-Json` and is captured; invalid JSON = failed step, not a crash. Ends with one consolidated, deduped owner-action list (every `ownerAction`/`nextCommand` across the reports); `-Json` one rollup object. |
| `auto-login.ps1` | **Dot-source it** (`. scripts/bootstrap/auto-login.ps1`): the non-interactive ACQUIRE-and-EXPORT companion — az repair delegated to `auth-doctor.ps1 -Apply`, then Key Vault → env exports (`openai-api-key`→`OPENAI_API_KEY`, `anthropic-api-key`→`ANTHROPIC_API_KEY`, `github-models-token`→`GITHUB_MODELS_TOKEN`; never clobbers existing values), then `gh auth token` fallback for the models token. Zero prompts ever — anything needing a human is printed as an owner action; secret values live only in process memory. `-Json` one rollup; `-UseManagedIdentity` is forwarded to the doctor for classic IMDS-only VMs (no `IDENTITY_ENDPOINT` / `MSI_ENDPOINT`). |
| `load-env-from-keyvault.sh` | **Source it** after Azure login. Pulls `openai-api-key`, `anthropic-api-key`, `github-models-token` from the Key Vault at `AZURE_KEY_VAULT_URI` (provisioned by `infra/main.bicep`) into the matching env vars from `config/aihub.json`. |
| `azure-up.sh` | End-to-end cloud bring-up: device-code login → resource group → `infra/main.bicep` deployment (with your objectId for the RBAC grants) → writes endpoint wiring to `.helios/azure.env` and points `AIHUB_CONFIG` at the cloud profile. |
| `azure-up.ps1` | Azure PowerShell twin of `azure-up.sh` (`New-AzResourceGroupDeployment`); writes `.helios/azure.env.ps1` for dot-sourcing. |
| `setup-ai-clis.ps1` | Installs/verifies the AI agent CLIs behind `config/aihub.json`'s `cliAgents`: `claude`, `codex`, `copilot` (all npm), and verifies `gh` for gh-models. Idempotent; prints headless-auth guidance per CLI; never prompts, never stores secrets. `-ProbeAuth` adds a read-only, informational auth column (never changes the exit code). |
| `cloud-shell-setup.sh` | Orchestrates the CLI fleet + both auth flows, the env wiring, the AIHub smoke test and the readiness inventory. `--skip-auth` / `--skip-smoke` narrow it; `--verify-only` is read-only (CLI presence + auth state, exit 0 when both auths are ready, 1 otherwise; no installs, no logins, no persistence). **Cloud Shell persistence** (Cloud Shell with `$HOME/clouddrive` mounted): points the npm prefix at `$HOME/clouddrive/helios/npm` so the CLIs survive session resets, and writes ONE marker-delimited block to `~/.bashrc` (PATH + `.helios/azure.env` + a lazy `helios-env` function wrapping `load-env-from-keyvault.sh` (options saved/restored)) and a `profile.ps1` with `Enter-HeliosEnv` dot-sourced from pwsh's `$PROFILE`; the block is refreshed in place, never duplicated. `--no-persist` opts out. |
| `cloud-shell-setup.ps1` | Thin twin: runs the SAME bash script (Git Bash preferred on Windows; the System32 WSL launcher is never used silently), translating `-SkipAuth` / `-SkipSmoke` / `-VerifyOnly` / `-NoPersist` to the bash flags and forwarding its exit code. Without a usable bash it prints the exact steps and exits 2. |
| `first-run.sh` | **The ONE command** (see the top of this page): the ordered soft chain over the scripts in this table, `.helios/bootstrap-state.json` (`steps`, `lanes`, `repoSecrets`, `ownerActions`, `reports`) and the numbered owner checklist. `--verify-only` (read-only; `auto-login` skipped), `--json` (state object only on stdout), `--skip-setup` (skip `setup-everything.ps1`), `--managed-identity` (forward `-UseManagedIdentity`). Exit 0 when the chain ran (needs-owner lanes never gate), 1 = internal failure (no pwsh, or the state could not be written). `python3` does the merge; without it a steps-only state is written and the raw reports are named. |
| `first-run.ps1` | PowerShell twin of `first-run.sh` with the same chain, flags (`-VerifyOnly` / `-Json` / `-SkipSetup` / `-UseManagedIdentity`), state shape and exit contract; step 1 goes through `cloud-shell-setup.ps1` (which owns bash resolution) with the console inherited so device codes stay visible. |
| `connect-github.ps1` | Twin of `connect-github.sh`: `-VerifyOnly` (read-only), `-FromEnv` (an anonymous `/rate_limit` probe first: an injecting transport is reported transport-ready and nothing is persisted; otherwise the env token is fed to `gh auth login --with-token` via stdin, env-cleared), default device-code `gh auth login --web --scopes models:read`. Exit 0 ready / 1 not ready / 2 precondition. |
| `set-provider-secrets.ps1` | The printed-never-scripted owner step made safe: stores `openai-api-key` / `anthropic-api-key` / `github-models-token` (names from `config/aihub.json` `apiKeySecretName`/`apiKeyEnv`, built-in fallback) in the Key Vault at `-VaultUri` / `AZURE_KEY_VAULT_URI`. Dry run by default (existence by NAME; a missing precondition degrades the vault column to `unknown (<why>)`, exit 0); `-Apply` writes from a masked prompt or `-FromEnv`, value through a mode-600 temp file with `--file` (never argv, output discarded), verified by name only; `-Only` narrows. Exit 0 / 1 (failed targets, replay list; unknown `-Only`) / 2 (`-Apply` with no vault URI, az missing, or az not logged in). |
| `provision-github-secrets.ps1` | Repository Actions variables (`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID`) and secrets (`LINEAR_API_KEY` / `SLACK_WEBHOOK_URL` / `COPILOT_DISPATCH_TOKEN` / `HELIOS_ADMIN_TOKEN`) from env vars of the SAME NAME. Wire-truth precondition (`gh api repos/{repo}` `.permissions.push`); dry run prints target / kind / source presence (name only) / current repo state by name (`unknown (<reason>)` when the listing is refused); `-Apply` feeds each value to `gh secret\|variable set` via stdin (never argv), prints the command first, replay list on failure; `-Json` one object (also on a failed precondition). Exit 0 / 1 / 2 (`-Apply` only). |
| `connect-admin.ps1` | **The one-command admin bring-up**: automates everything around the two irreducible human clicks — minting the fine-grained `HELIOS_ADMIN_TOKEN` PAT and completing the Azure MFA device-code sign-in. GitHub lane: prints the PAT creation URL with the exact permission checklist (Administration/Contents/Issues/Pull requests/Pages RW, Metadata R, this repo only), reads the value from a masked prompt or `-FromEnv <NAME>` (never argv), runs the anonymous `/rate_limit` control first (an injecting transport is reported "verify from your own machine", never a false pass), verifies it live with `gh api repos/{repo} --jq .permissions` with `GH_TOKEN` scoped to that one child process (`.admin` must be true), stores it with `gh secret set` over stdin; `-ApplyGovernance` then runs the four `scripts/github/apply-*.ps1 -Apply` with the token scoped per child and reports each exit code, the ruleset refused unless `dotnet-build.yml` on `main` (read via the contents API) carries the no-path-filter trigger. Azure lane: `az account show` + a live refresh; the interactive `az login --use-device-code --tenant` only when the session is missing/MFA-expired; then `setup-tenant.ps1 -OpsIdentity -Apply` and the three names to export (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_CERTIFICATE_PATH`). `-VerifyOnly` / `-SkipGitHub` / `-SkipAzure` / `-Json` (one object). Exit 0 / 1 (an item failed, replay list) / 2 (precondition missing or a lane needs the owner). |
| `write-codex-config.ps1` | Renders the Codex CLI's MCP registration for THIS checkout into `~/.codex/config.toml` (`[mcp_servers.helios]` with the server project path resolved to an absolute path, because Codex launches MCP servers from its own working directory). Dry run prints the TOML; `-Apply` writes; an existing file is refused unless `-Force`, which then replaces only the helios table and preserves the operator's other keys; `-Path` / `-RepoRoot` / `-Json`. Exit 0 (written, up to date, or clean dry run) / 1 (refused without `-Force`, or the write failed) / 2 (`src/mcp/HELIOS.Mcp` absent). Companion of `docs/mcp/CLIENT_SETUP.md`. |

**Contract shared by every script added with the Control fabric** (`first-run`,
`set-provider-secrets`, `provision-github-secrets`, `write-codex-config`, `connect-github.ps1`,
`cloud-shell-setup.ps1`): dry run or report by default, `-Apply` is the only thing that
mutates, `-Json` (on the scripts that offer it: `first-run`, `provision-github-secrets`,
`write-codex-config`) emits ONE object and nothing else on stdout, exit 0 = success or clean
dry run, 1 = an item failed (replay list printed) or internal failure, 2 = a precondition
or credential is missing (the exact fix is printed). No script reads, stores or prints a
secret value: env vars by NAME, values over stdin or a mode-600 `--file`, never argv.
The GitHub-side siblings (rulesets, settings, labels, milestones, branch prune, duplicate
issues) live in `scripts/github/` — see `scripts/github/README.md` and
`docs/architecture/CONNECTIONS_SETUP.md` § Control fabric.

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
pwsh scripts/bootstrap/setup-ai-clis.ps1 -VerifyOnly -ProbeAuth   # + informational auth column
pwsh scripts/bootstrap/setup-ai-clis.ps1 -Skip codex,copilot
```

**`-ProbeAuth`** (opt-in) probes each *present* CLI read-only: `codex login status`;
`gh auth status --hostname github.com --active` (automatic fallback when an older
gh lacks `--active`); env-var *presence* for claude/copilot (`ANTHROPIC_API_KEY`,
`GH_TOKEN`/`GITHUB_TOKEN` — names only, values never read or printed); and, when
the `ant` CLI is already on PATH, a grep of `ant auth status` stdout (its exit
status is documented as not scriptable, per the CLI authentication docs). Results
are informational — `authenticated | not-authenticated | unknown` — and never
change the exit code; an older CLI without the status subcommand reports `unknown`
instead of failing setup. The contract stands: no login flow is ever run, nothing
is prompted for, nothing is stored.

Idempotent (present CLIs are skipped with their version printed) and secret-free: it
prints per-CLI headless-auth guidance — `ANTHROPIC_API_KEY` / `claude setup-token`,
`OPENAI_API_KEY` / `codex login`, `gh auth login --web` device-code for copilot/gh,
`az login --use-device-code` (skipped advice in pre-authed Cloud Shell) — but never
runs a login flow itself. Exit 0 = all present, 2 = something missing (npm absent when
installs are needed is a clear error).

## Auth doctor: `auth-doctor.ps1`

The automatic-repair sibling of `setup-ai-clis.ps1 -ProbeAuth`: diagnoses every auth
lane — `gh`, `az`, `openai-codex`, `claude` (env-var name read from
`config/aihub.json` `providers.anthropic.apiKeyEnv`, never hardcoded), `copilot`
(rides the gh lane), plus four verify-only connector lanes that never gate the exit
code: `linear` (LINEAR_API_KEY — `linear-sync.yml` skips green without the repo
secret), `slack` (SLACK_WEBHOOK_URL — `notify-slack.yml` likewise; SLACK_BOT_TOKEN is
reported honestly as declared-but-unconsumed), `sharepoint` (owner-gated admin
consent, no headless probe), and `azure-devops` (informational — no ADO org is
configured in this repo today) — and, only with `-Apply`, repairs what can be repaired
**without a human**: `az login --service-principal` from `AZURE_CLIENT_ID` /
`AZURE_TENANT_ID` plus `AZURE_CLIENT_SECRET` or `AZURE_CLIENT_CERTIFICATE_PATH`
(values flow env → argv, never through a logged string), or `az login --identity`
when a managed-identity endpoint is present (or `-UseManagedIdentity`).
Automatic-first, interactive-last: CI OIDC (reported — `azure/login` owns it) →
env token / service principal → managed identity → device-code, which is only ever
*printed* as the lane's `ownerAction`; `-Apply` never falls back to anything
interactive. The az lane probes past `az account show` with a live token refresh,
so the cached-profile-but-`AADSTS50078` (MFA expired) state measured in
`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md` is caught and reported with the
exact tenant-scoped re-login command. Env vars are checked by NAME only and raw
CLI auth output is never echoed.

```powershell
pwsh scripts/bootstrap/auth-doctor.ps1          # report-only: mutates nothing, exit 0
pwsh scripts/bootstrap/auth-doctor.ps1 -Apply   # + automatic non-interactive repair
pwsh scripts/bootstrap/auth-doctor.ps1 -Json    # one machine-readable report object
```

Exit 0 = report-only run, or `-Apply` with every lane ready/repaired (unavailable =
tool missing — reported, never gates); 2 = `-Apply` left at least one lane
needs-owner; 1 = internal failure.

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

### Automatic issue setup readiness (labels and milestones only)

```powershell
pwsh scripts/setup/setup-all.ps1 -Repository Yolkster64/helios-platform -Json
pwsh scripts/bootstrap/setup-everything.ps1 -Repository Yolkster64/helios-platform -Json
```

The explicit, validated `owner/repo` triggers these checks automatically, including
through either first-run twin; there is no additional enable switch. No issue target
is inferred, and omitting `-Repository` preserves existing behavior. This adds two
gating inventory rows by calling `scripts/github/apply-labels.ps1` and
`scripts/github/apply-milestones.ps1` with `-Repository ... -Json`, **dry-run only**.
Neither `-Fix` nor `-Apply` reaches those scripts (existing CLI installation/auth
repair switches retain their separate behavior).

`gh` automatically reuses its inherited credentials (`GH_TOKEN`/`GITHUB_TOKEN` or
its existing credential store). This integration does not read/export token values,
create tokens, grant permissions, or bypass access controls. Successful reads and
in-sync readiness **do not verify Issues or Projects write scope**; only effective
required access is relevant, not unrestricted “full access.”

**Dry-run is not offline:** with a credential, the producers perform online GitHub
reads to compare live labels/milestones. The CI contract tests are offline: they run
both real first-run entrypoints with inert child fixtures and no inherited credentials,
and never install, log in, provision, or call live GitHub/Azure APIs.

Unknown live state is not ready even if a child exits 0. Missing/malformed reports,
pending creates/updates, closed milestones, invalid/failed rows, and unknown row
states also need attention. Output contains bounded summaries, not raw child
responses or replay commands. `nextCommand` and the consolidated owner checklist
only suggest another dry run. Inventory exits 2 for attention; `setup-everything`
retains its report-first exit 0 for a degraded inventory, with `ready: false` and
owner actions.

Review the direct dry-run reports first. Required write access and subsequent
changes remain with the existing governed `governance-apply.yml` /
`governance-run.yml` workflows (labels/milestones use their existing
`issues: write` grant); this integration never dispatches them or broadens
`-Apply` / `-Fix`. This increment is **not Azure, Projects, or AI provisioning**:
creating issues, configuring Projects, and granting GitHub/Azure access are not wired.

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
