# Owner Start Here

The day-one checklist for the repository owner: everything that must be clicked
or configured by a human before the automation in this repo can do its job.
Contributor setup (toolchain, build, CLI) is in
[`PROJECT_SETUP.md`](PROJECT_SETUP.md) — this page is only the owner-side
switches.

Ground rule for everything below: **no secrets in the repo, ever.** Config
files (`config/aihub.json`, `config/connectors.json`) carry env-var *names*;
values live in your shell, GitHub Actions secrets, or Azure Key Vault.

## Day-one checklist

Run **`bash scripts/bootstrap/first-run.sh`** first (twin:
`pwsh scripts/bootstrap/first-run.ps1`). It installs the CLIs, runs the logins it
can (device codes you type), probes every lane and every repository secret by
name, writes `.helios/bootstrap-state.json`, and ends by printing this list as a
numbered checklist with the exact command per item. `--verify-only` is the
read-only pass. Then:

1. [Wire secrets through env vars / Key Vault](#1-secrets-env-vars-and-key-vault) — nothing works without provider credentials.
2. [Flip the GitHub repository settings](#2-github-repository-settings) — Issues is already on; what remains is the variables, secrets, and the protected `azure-dev` environment.
3. [Set the connector secrets (Slack, Linear)](#3-connectors-slack-and-linear) per `config/connectors.json`.
4. [Create the Azure OIDC deploy identity](#4-azure-oidc-for-deploys) with `scripts/bootstrap/azure-oidc-setup.sh`.
5. [Decide on the fleet VMSS](#5-fleet-vmss-opt-in) — it is OFF by default and stays off until you opt in.
6. [Connect the GitHub App (two clicks) and let the control fabric apply the rest](#6-control-fabric-the-github-app) — ruleset (mind the PR #113 ordering rule), Pages source, auto-merge, labels, milestones, from `main`; then the wiki, Pages and Projects clicks the fabric cannot make.
7. [Flip the Linear switch, then run the hygiene passes](#7-branch-prune-and-issue-hygiene) — close the loop duplicates #54–#92 and prune the stale branches; both reversible.

## 1. Secrets: env vars and Key Vault

- Copy `.env.template` (tracked, placeholders only) to `.env` (git-ignored) and
  fill in real values there. The env-var names it documents are the same ones
  `config/aihub.json` resolves per provider: `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`, `AZURE_OPENAI_ENDPOINT`/`AZURE_OPENAI_API_KEY`,
  `GITHUB_MODELS_TOKEN`, `OLLAMA_BASE_URL`, `AZURE_FOUNDRY_PROJECT_ENDPOINT`.
- Prefer Key Vault over long-lived local keys: after
  `infra/main.bicep` is deployed (`scripts/bootstrap/azure-up.sh`), set
  `AZURE_KEY_VAULT_URI` and `source scripts/bootstrap/load-env-from-keyvault.sh`
  to pull `openai-api-key`, `anthropic-api-key`, and `github-models-token` into
  the matching env vars. Resolution order per provider is env var → Key Vault →
  Unconfigured.
- The GitHub Models key needs no manual handling at all:
  `source scripts/bootstrap/connect-github.sh` exports `GITHUB_MODELS_TOKEN`
  from your gh login (scope `models:read`).
- `HELIOS_API_ACCESS_KEY` gates non-loopback access to the REST API
  (`helios-ai-api`); hosted use still needs identity-aware ingress in front.

## 2. GitHub repository settings

All under `https://github.com/Yolkster64/helios-platform` → **Settings**.

- **Issues** are enabled (measured 2026-09-03: `has_issues=true`); the 40
  absorption epics from `docs/architecture/ABSORPTION_LEDGER.md` are issues
  #14–#53. Issues #54–#92 are Linear-loop duplicates awaiting closure (step 7).
- **Actions variables** (Settings → Secrets and variables → Actions →
  Variables) and **Environment variables** for deployment — these are identifiers, not secrets,
  which is why they are variables:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` — printed
    (with ready-made `gh variable set` one-liners) by
    `scripts/bootstrap/azure-oidc-setup.sh` (step 4 below).
  - `AZURE_RESOURCE_GROUP` and `AZURE_LOCATION` are also required. Set all five
    in **Settings → Environments → azure-dev → Environment variables**, using
    the reviewed bootstrap output. Deployment has no subscription, group or region defaults.
- **Actions secrets** (Settings → Secrets and variables → Actions → Secrets):
  - `SLACK_WEBHOOK_URL` — used by `.github/workflows/notify-slack.yml`.
  - `LINEAR_API_KEY` — used by `.github/workflows/linear-sync.yml`.
  - `HELIOS_ADMIN_TOKEN` — the fine-grained PAT that is the admin fallback for
    `.github/workflows/governance-apply.yml`, used only when no GitHub App
    token is minted (step 6).
  - `COPILOT_DISPATCH_TOKEN` — optional, for `copilot-dispatch.yml`
    (`docs/architecture/CONNECTIONS_SETUP.md` § GitHub ↔ Copilot).
  - Connector secrets can be set from env vars of the same name with
    `pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply` (dry run by
    default; values travel over stdin). This existing helper writes repository
    scope and only three Azure identifier variables; use the five environment
    commands from the OIDC bootstrap for `azure-dev`.
  - `HELIOS_APP_PRIVATE_KEY` — the HELIOS GitHub App's private key, the
    durable admin credential of `governance-apply.yml`; stored together with
    the identifier variables `HELIOS_APP_CLIENT_ID`, `HELIOS_APP_ID` and
    `HELIOS_APP_SLUG` by `scripts/bootstrap/connect-github-app.ps1` (step 6);
    rotation is the key swap described there.
- **Environment `azure-dev`** (Settings → Environments): configure required
  reviewers and restrict deployment branches to `main`. The only new deploy
  federation subject is `repo:Yolkster64/helios-platform:environment:azure-dev`.
  This repository change does not configure those live protections. Production
  remains disabled.

## 3. Connectors: Slack and Linear

`config/connectors.json` is the single place that says where notifications go.
It carries env-var names and routing choices only — the owner supplies the
values:

| Env var (name in connectors.json) | Where to set it | Used for |
| --- | --- | --- |
| `SLACK_WEBHOOK_URL` | Actions secret (and locally if testing) | CI/deploy/fleet notifications to `#helios-ci`, `#helios-deploys`, `#helios-fleet` |
| `SLACK_BOT_TOKEN` | Env / Actions secret | Bot-token Slack calls (future `HELIOS.Connectors` service) |
| `LINEAR_API_KEY` | Actions secret | Mirroring labeled GitHub issues into Linear team `JOH` (the workspace's team key — `config/connectors.json` `linear.teamKey` must match your Linear team or the sync exits with a warning) |

Routing choices (which workflows notify on failure vs. always, which labels
sync) are edited in `config/connectors.json` itself, not in the workflows.

## 4. Azure OIDC for deploys

The Bash and PowerShell `azure-oidc-setup` twins start with a **read-only plan**.
They require an explicit tenant, subscription, resource group and provider-key
vault. Before any write they verify the active Azure account matches that tenant
and subscription and is Enabled, the group and vault IDs match those targets,
and the vault belongs to that tenant with RBAC enabled. Reusing federation checks
the issuer and the exact single audience as well as the subject; conflicts stop
Apply instead of being silently overwritten. The scripts never
change the selected account, sign in, create a resource group or deploy a template.

From your own terminal or Azure Cloud Shell, inspect `az account list -o table`.
If needed, complete `az login --tenant <tenant-id>` and explicitly select
`az account set --subscription <subscription-id>` yourself. Cloud Shell can
already be signed in; its currently selected subscription still needs checking.
Then run either plan:

```bash
bash scripts/bootstrap/azure-oidc-setup.sh --tenant <tenant-id> \
  --subscription <subscription-id> --resource-group <group> --key-vault <vault>
```

```powershell
pwsh scripts/bootstrap/azure-oidc-setup.ps1 -Tenant <tenant-id> `
  -Subscription <subscription-id> -ResourceGroup <group> -KeyVault <vault>
```

The existing group and RBAC vault are prerequisites. Review their provisioning
separately if missing. After reviewing the target and permissions, an authorized
owner may repeat the same command with `--apply` / `-Apply` to create or reuse:

- App registration `helios-github-deploy` and service principal, without a client secret.
- One GitHub federation subject: `repo:Yolkster64/helios-platform:environment:azure-dev`.
- Contributor on the selected group and Key Vault Secrets Officer on that vault.

Apply also removes the legacy named credentials `github-main`,
`github-pull-request` and `github-env-production` if present. A plan only describes
these removals. Other environments, including production, are refused before
Azure is called. The script prints the five `gh variable set --env azure-dev`
commands; it does not execute them or create GitHub environment protections.

Once those protections and variables are configured, dispatch **Helios Platform
Deploy** from `main` with `what_if=true`. A push never deploys. The workflow checks
the authenticated tenant/subscription and existing group/location, then retains
sanitized plan results. Applying a reviewed plan requires a separate manual
run with `what_if=false` and `deploy_confirmed=true`, plus the protected environment's
approval. This checkbox is an explicit operator assertion, not automated proof that
a specific earlier plan was reviewed.

### Provider keys, Cloud Shell and coding tools

The existing provider scripts share `config/aihub.json` names. They do not create
OpenAI or Anthropic platform credentials from a ChatGPT or Claude web sign-in.

| Purpose | Existing entry point | What changes |
| --- | --- | --- |
| Inspect provider-key targets | `pwsh scripts/bootstrap/set-provider-secrets.ps1 -VaultUri https://<vault>.vault.azure.net/` | Dry run; reports names and source presence |
| Store an existing key | Same command with `-Only openai-api-key -Apply` or `-Only anthropic-api-key -Apply` | Masked input; writes only the selected vault secret |
| Store already supplied environment values | Same command with `-FromEnv -Apply` | Values travel through restricted temporary files, not command-line arguments |
| Load keys into the current Bash shell | Set `AZURE_KEY_VAULT_URI`, then `source scripts/bootstrap/load-env-from-keyvault.sh` | Fetches keys into process environment; existing values remain unchanged |
| Load/repair from PowerShell | `. scripts/bootstrap/auto-login.ps1` | Explicit invocation can repair cached auth and load configured vault keys into the shell |
| Inspect GitHub connector credential names | `pwsh scripts/bootstrap/provision-github-secrets.ps1 -Json` | Reports source presence and accessible metadata |
| Store supplied Slack/Linear credentials | Same helper with `-Apply` | Writes available values to Actions secrets over stdin; no API key creation |

Run key-loading scripts only in a trusted shell on the reviewed checkout. Start
Claude Code, Codex or Copilot from that same shell when they should inherit its
provider environment. Native coding-tool account sign-ins and runtime API keys
remain separate. The launcher and offline checks work without provider keys;
missing keys leave those providers Unconfigured.

The target-preflight portion was selectively recovered from PR #148
(`5a8379174073071d87cdad46754f023e9d8565f3` against
`b4486a03a3aeaa681fa88abfdcc188dfebf6c388`), then aligned with the current
`azure-dev` deployment authority. No identity or cloud change is implied by this
source integration.

## 5. Fleet VMSS opt-in

The Hermes fleet's Azure burst capacity (a VM scale set) is **off by default**
and doubly gated in `infra/main.bicep`: it deploys only when
`deployFleetVmss=true` **and** `vmssAdminPublicKey` is a non-empty SSH public
key (password auth is disabled). Leaving either gate closed keeps the VMSS off
— a plain `azure-up.sh` run never creates fleet VMs.

```bash
az deployment group create ... --parameters deployFleetVmss=true \
  vmssAdminPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
```

Details: `infra/README.md` ("Fleet burst capacity (VMSS)") and
`docs/architecture/HERMES_FLEET_AND_XCORE.md`.

## 6. Control fabric: the GitHub App

**One command**: `pwsh scripts/bootstrap/connect-devices.ps1` (from your own
machine, Cloud Shell or a Codespace — never an agent container, whose transport
rewrites GitHub credentials) starts the `gh` and `az` device-code flows
together, prints both codes in one table, waits, then chains everything this
section needs: the GitHub Models token export,
`connect-github-app.ps1 -DispatchGovernance` (the two clicks below and the
first governance apply; `-SkipGitHubApp` skips it),
`connect-admin.ps1 -SkipGitHub` (the Azure ops identity via
`setup-tenant.ps1 -OpsIdentity -Apply` and the three `AZURE_*` names to export;
`-SkipOpsIdentity` skips it), `auto-login.ps1`, `auth-doctor.ps1 -Json` and
`first-run.sh --verify-only`. `-VerifyOnly` reports and changes nothing,
`-Json` emits one object, `-Retry` re-runs what did not finish; `-Tenant`,
`-Repository` and `-TimeoutMinutes` are the knobs. Twin: `connect-devices.sh`.

Repository admin writes — the `main` ruleset, Pages source = GitHub Actions,
"Allow auto-merge", delete-branch-on-merge, the `automerge` label — and the
label/milestone manifests under `config/github/` are applied by
`.github/workflows/governance-apply.yml` from `main`, never from an agent
session: the proxy those sessions sit behind rewrites GitHub credentials
(`.permissions.admin` reads false, `/pages` is blocked), so admin mutations
there are refused by design and only the dry runs are possible. The workflow's
admin credential is a private GitHub App, `helios-control-Yolkster64`, and the
only human part of it is two clicks.
`pwsh scripts/bootstrap/connect-github-app.ps1` (what `connect-devices.ps1`
calls; it runs on its own too) does the rest:

1. **Create.** It opens the GitHub App manifest flow pre-filled (name
   `helios-control-<owner>`, or `-AppName`; repository permissions
   Administration, Contents, Issues, Pull requests, Pages, Actions, Workflows
   write, Metadata read; no webhook; not public); you click **Create GitHub
   App**. The one-hour code comes back on a one-shot listener on a free
   `127.0.0.1` port (`-CallbackPort 0`, the default) or you paste it from the
   address bar (`-CallbackPort -1`; `-FromCode <env var NAME>` for a code you
   already hold); the script converts it at
   `POST /app-manifests/{code}/conversions` and stores the *variables*
   `HELIOS_APP_CLIENT_ID`, `HELIOS_APP_ID`, `HELIOS_APP_SLUG` (identifiers)
   and the *secret* `HELIOS_APP_PRIVATE_KEY` (the PEM, over stdin to
   `gh secret set`). The client and webhook secrets it also receives are
   discarded; they stay on the app page, where you can delete them.
2. **Install.** It opens
   `https://github.com/apps/<slug>/installations/new/permissions?target_id=<owner id>`;
   you click **Install** for this repository. It waits up to `-TimeoutMinutes`
   (15; `-SkipInstallWait` returns at once) and verifies the installation the
   way the workflow will: an in-process app JWT, then
   `gh api /user/installations`.
3. With `-DispatchGovernance` it runs
   `gh workflow run governance-apply.yml -f apply=true -f scope=all`; read the
   job summary: `app token: minted` on the header line, one row per item (an
   exit-2 row names the owner step, an exit-1 row carries a replay list).
   Verify: `gh ruleset list` (a ruleset named `main`), `gh label list` (the 21
   manifest labels), `gh api repos/Yolkster64/helios-platform/milestones` (the
   4 manifest milestones). Interim, while the workflow is not yet on `main`:
   `pwsh scripts/github/apply-rulesets.ps1` (dry run), then `-Apply` under an
   owner `gh auth login` on a workstation.
4. **Ordering rule for the ruleset**: apply it only after PR #113's
   no-path-filter triggers (`dotnet-build.yml`, `infra-validate.yml`) are on
   `main`. Until then `Build solution & run tests`, `bicep-validate`,
   `arm-freshness` and `terraform-validate` — 4 of the 8 required contexts —
   never start on a PR that touches none of their paths and strand as
   **Expected**, blocking every such merge.

Why an app rather than a PAT: the workflow mints an installation token per run
(`actions/create-github-app-token@v3`, scoped to this repository and to
exactly the permissions the four scripts need, revoked when the job ends), so
nothing long-lived sits in a password manager; rotation is a key swap on the
app page (`https://github.com/settings/apps/<slug>`: generate a new private
key, delete the old one, then
`gh secret set HELIOS_APP_PRIVATE_KEY --repo Yolkster64/helios-platform < key.pem`
from a shell and delete `key.pem`); and a push or merge made with it fires
`on: push`, which the cascade `GITHUB_TOKEN` cannot. A stored app credential
that stops working (uninstalled at `https://github.com/settings/installations`,
key rotated without re-storing) turns the run red with the repair named —
never a silent fallback to a weaker token.

**Fallback: the fine-grained PAT.** The runner takes `HELIOS_ADMIN_TOKEN` only
when no app token was minted. `pwsh scripts/bootstrap/connect-admin.ps1`
automates this lane around the one click only you can make (prints the PAT
creation URL with the exact permission checklist, masked prompt or
`-FromEnv HELIOS_ADMIN_TOKEN`, verifies `.permissions.admin` live, stores the
secret over stdin; `-ApplyGovernance` once PR #113 is on `main` — it reads
`dotnet-build.yml` on `main` and refuses the ruleset otherwise, item 4 above;
`-VerifyOnly` reports only) — or by hand:

- GitHub → **Settings** (profile menu) → **Developer settings** → **Personal
  access tokens** → **Fine-grained tokens** → **Generate new token**: resource
  owner **Yolkster64**, repository access **Yolkster64/helios-platform** only,
  repository permissions **Administration RW, Contents RW, Issues RW, Pull
  requests RW, Pages RW, Metadata R**; nothing else.
- `gh secret set HELIOS_ADMIN_TOKEN --repo Yolkster64/helios-platform` and
  paste when prompted — or, with the value held in an env var of the same
  name, `pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply` (it feeds
  `gh secret set` over stdin). The value goes into that prompt or that env var
  and nowhere else.

The clicks the fabric cannot make (or makes only with an admin credential),
each with the command that follows it:

- **Pages**: the `pages` item of `apply-repo-settings.ps1` sets the source with
  the app token or the PAT; by hand it is Settings → **Pages** → Source: **GitHub Actions**.
  Either way, then `gh workflow run pages-dashboard.yml` publishes the first
  dashboard instead of waiting for the next **Status Dashboard** completion.
- **"Allow auto-merge"**: already on (Settings → General → Pull Requests;
  measured 2026-09-03) — nothing to click.
- **Projects board**: needs a *classic* PAT with the `project` scope (plus
  `repo` read), passed at run time and never stored:
  `pwsh scripts/board-setup/setup-custom-fields.ps1 -GitHubToken <PAT>`, then
  `pwsh scripts/board-setup/add-epics-to-board.ps1 -GitHubToken <PAT>`;
  `pwsh scripts/board-setup/validate-board.ps1` is the read-only check.
- **Wiki**: Wiki tab → **Create the first page**, once by hand (that is what
  creates the wiki git repo), then `gh workflow run wiki-generator.yml` pushes
  `docs/GETTING_STARTED.md` (as `Getting-Started`), `docs/architecture/**` and
  `docs/mcp/**` — nothing else under `docs/` reaches the wiki.
- **Branch prune**: step 7 below — `gh workflow run branch-prune.yml` (plan),
  then `-f apply=true`.

Without either credential the workflow still applies labels and milestones
with `GITHUB_TOKEN` and reports the ruleset and settings as "needs an admin
credential", the app path first. It also applies on every push to `main` touching
`.github/rulesets/**`, `config/github/**` or `scripts/github/**` and once a day
(06:17 UTC) as a drift net; every PR touching those paths gets a read-only plan
in its checks. Full detail:
`docs/architecture/CONNECTIONS_SETUP.md` § Control fabric.

## 7. Branch prune and issue hygiene

- **Linear switch first**: Linear → Settings → Integrations → GitHub → team
  John → issue sync OFF for `Yolkster64/helios-platform`. Linear's own
  integration re-imports this repo's `[GH-n]` mirrors as new GitHub issues; that
  loop produced #54–#93 and reopened #54–#92 after they were closed once.
- **Close the duplicates**: `pwsh scripts/github/close-duplicate-issues.ps1`
  (dry run; measured 36 candidates, 3 skipped because their originals are
  closed), then `-Apply` from your own `gh` login (needs push). Per issue: the
  `duplicate` label, one comment naming the original, `state_reason=duplicate`.
- **Prune branches**: `gh workflow run branch-prune.yml` (plan: read the job
  summary or the `branch-prune-report` artifact), then
  `gh workflow run branch-prune.yml -f apply=true -f keep=<a,b>` (add
  `-f max_delete=<n>` when the plan deletes more than 200). Merged branches are
  deleted; stale ones are tagged `archive/<branch>` first, so
  `git push origin refs/tags/archive/<branch>:refs/heads/<branch>` brings any
  of them back. Measured plan: 101 branches, 8 merged, 87 stale, 5 kept
  (`main`, `develop`, `master` and two open-PR heads, one of them a PR in the
  upstream parent), 1 unclassified (a `#` in its name the proxy cannot encode).

## What is automated vs. what stays manual

| Concern | Automated | Manual (owner) |
| --- | --- | --- |
| Azure resources | `scripts/bootstrap/azure-up.sh` deploys `infra/main.bicep`; CI deploys via `helios-deploy.yml` | `az login`, choosing subscription/region, approving `production` deploys |
| Deploy identity | `azure-oidc-setup.sh` creates app/SP/federated creds/roles idempotently | Running it once as a privileged user; pasting the three variables into GitHub |
| Provider keys | Key Vault → env wiring via `load-env-from-keyvault.sh`; gh token reuse via `connect-github.sh` | Putting the keys into Key Vault (or `.env`) in the first place |
| Issues | Issues are on; epics are #14–#53; `linear-sync.yml` skips `[GH-` titles on every event and the `duplicate` label on `opened`/`labeled` | Flipping Linear's GitHub issue sync OFF for team John |
| Slack/Linear | Workflows notify/sync using the secrets | Creating the webhook/API key and adding them as Actions secrets |
| Fleet VMSS | Bicep module deploys it when gated on | Opting in (`deployFleetVmss` + SSH key) and paying for it |
| One-command bring-up | `scripts/bootstrap/first-run.sh` / `.ps1`: the soft chain over every bootstrap script, `.helios/bootstrap-state.json`, the numbered checklist (exit 0 = chain ran, 1 = internal failure) | Typing the device codes; every item the checklist prints |
| Provider keys → Key Vault | `scripts/bootstrap/set-provider-secrets.ps1`: dry run lists targets by name; `-Apply` writes through a mode-600 `--file`, verifies by name (exit 0/1/2) | Running it `-Apply` with the values in a masked prompt or `-FromEnv` |
| Repo secrets and variables | `scripts/bootstrap/provision-github-secrets.ps1`: dry run in every first-run (state by name); `-Apply` sets from same-name env vars over stdin (exit 0/1/2) | Holding the values in the environment when applying; minting the PATs |
| GitHub App (admin authority) | `scripts/bootstrap/connect-github-app.ps1`: manifest flow, code conversion, the three `HELIOS_APP_*` variables + `HELIOS_APP_PRIVATE_KEY` over stdin, install wait, JWT verify, `-DispatchGovernance`; `connect-devices.ps1` runs it after the two device-code logins, then `connect-admin.ps1 -SkipGitHub`, `auto-login.ps1`, `auth-doctor.ps1 -Json`, `first-run.sh --verify-only` | Two clicks in the browser, **Create GitHub App** then **Install** (plus typing the two device codes); a key rotation on the app page when you choose to |
| Ruleset, settings, labels, milestones | `.github/workflows/governance-apply.yml`: plan on every PR, apply on push to `main`, the daily schedule, or dispatch, with a per-run app installation token (then `HELIOS_ADMIN_TOKEN`, then `GITHUB_TOKEN` for labels/milestones only); manifests `config/github/labels.json`, `milestones.json`, `.github/rulesets/main.json` | The first dispatch, after PR #113's no-path-filter triggers are on `main`; PAT fallback only: minting `HELIOS_ADMIN_TOKEN` and `gh secret set` it once |
| Pages, wiki, Projects board | `pages-dashboard.yml` publishes on every **Status Dashboard** completion; `wiki-generator.yml` pushes `docs/` on every push to `main` touching them | Pages source (the PAT item or the Settings → Pages click) and the first `pages-dashboard.yml` dispatch; the wiki's first page, then the first `wiki-generator.yml` dispatch; the classic `project` PAT and the two board commands |
| Branch prune | `.github/workflows/branch-prune.yml` + `scripts/github/prune-branches.ps1`: classify, archive-tag, delete; JSON report artifact | Dispatching it (plan, then `apply=true`); choosing `keep` and, above 200 deletions, `max_delete` |
| Duplicate issues | `scripts/github/close-duplicate-issues.ps1`: classify #54–#92, label, comment, close as duplicate (dry run default, exit 0/1/2) | Linear switch OFF first, then running `-Apply` |
| Codex MCP config | `scripts/bootstrap/write-codex-config.ps1` renders `~/.codex/config.toml` with the absolute server path (dry run prints; `-Apply` writes; `-Force` for an existing file, helios table only; exit 0/1/2) | Running it per workstation; `codex login --device-auth` |

## Links

- [`PROJECT_SETUP.md`](PROJECT_SETUP.md) — contributor setup: toolchain, build, CLI, MCP.
- `CLAUDE.md` (repo root) — build commands and hard rules; the no-secrets rule lives here.
- `docs/CONSOLIDATION_BLUEPRINT.md` and `docs/architecture/` — the trustworthy architecture docs.
- `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md` — runners, Projects, wiki, connectors design.
- `docs/architecture/CONNECTIONS_SETUP.md` — every connection, the Control fabric, the GitHub App and PAT click paths.
- `docs/architecture/ABSORPTION_LEDGER.md` — the 40 absorption epics (issues #14–#53).
- `scripts/github/README.md` — the governance and hygiene scripts and their dry-run/apply/exit contract.
- `infra/README.md` — deploy dialects (Bicep/ARM/Terraform), VMSS gates, OIDC identity details.
- `scripts/bootstrap/README.md` — the auth + bring-up scripts referenced above.
