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
2. [Flip the GitHub repository settings](#2-github-repository-settings) — Issues is already on; what remains is the variables, secrets, and the `production` environment.
3. [Set the connector secrets (Slack, Linear)](#3-connectors-slack-and-linear) per `config/connectors.json`.
4. [Create the Azure OIDC deploy identity](#4-azure-oidc-for-deploys) with `scripts/bootstrap/azure-oidc-setup.sh`.
5. [Decide on the fleet VMSS](#5-fleet-vmss-opt-in) — it is OFF by default and stays off until you opt in.
6. [Store the admin PAT and let the control fabric apply the rest](#6-control-fabric-the-admin-pat) — ruleset (mind the PR #113 ordering rule), Pages source, auto-merge, labels, milestones, from `main`; then the wiki, Pages and Projects clicks the fabric cannot make.
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
  Variables) for the deploy workflow — these are identifiers, not secrets,
  which is why they are variables:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` — printed
    (with ready-made `gh variable set` one-liners) by
    `scripts/bootstrap/azure-oidc-setup.sh` (step 4 below).
  - Optional: `AZURE_RESOURCE_GROUP` (default `rg-helios-ai`) and
    `AZURE_LOCATION` (default `eastus2`), read by
    `.github/workflows/helios-deploy.yml`.
- **Actions secrets** (Settings → Secrets and variables → Actions → Secrets):
  - `SLACK_WEBHOOK_URL` — used by `.github/workflows/notify-slack.yml`.
  - `LINEAR_API_KEY` — used by `.github/workflows/linear-sync.yml`.
  - `HELIOS_ADMIN_TOKEN` — the one admin credential, read only by
    `.github/workflows/governance-apply.yml` (step 6).
  - `COPILOT_DISPATCH_TOKEN` — optional, for `copilot-dispatch.yml`
    (`docs/architecture/CONNECTIONS_SETUP.md` § GitHub ↔ Copilot).
  - All of the above, plus the three variables, can be set from env vars of the
    same name with `pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply`
    (dry run by default; values travel over stdin, never argv).
- **Environment `production`** (Settings → Environments): the OIDC federated
  credential is scoped to `environment:production`, so deploy jobs declaring it
  can only get Azure tokens through this environment. Add required reviewers
  here if you want a human approval gate on deploys.

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

`scripts/bootstrap/azure-oidc-setup.sh` (PowerShell twin:
`azure-oidc-setup.ps1`) creates the deploy identity with **no stored cloud
credential anywhere** — no client secret exists to leak or rotate:

- App registration `helios-github-deploy` + service principal.
- Federated credentials trusting GitHub's OIDC issuer for exactly two
  subjects: the repo's `main` branch and the `production` environment.
  Deliberately **no** `pull_request` subject — a PR can rewrite its own
  workflow, so PRs never get deploy rights (PR validation stays offline in
  `infra-validate.yml`).
- Contributor scoped to the resource group only, plus Key Vault Secrets
  Officer scoped to the provider-key vault only (least privilege).

Order matters: run `scripts/bootstrap/azure-up.sh` first (device-code login →
resource group → `infra/main.bicep` deployment), because the OIDC script
refuses to run until the resource group exists. It finishes by printing the
three GitHub Actions variables to set (step 2 above). It is safe to re-run;
every step checks for the existing object first.

Then rehearse: run "Helios Platform Deploy" via `workflow_dispatch` **from
`main`** (the federated subject is branch-scoped) with `what_if=true` for a
read-only dry run.

To check auth state at any time without changing anything:

```bash
scripts/bootstrap/cloud-shell-setup.sh --verify-only   # gh + az, read-only
```

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

## 6. Control fabric: the admin PAT

**One command**: `pwsh scripts/bootstrap/connect-admin.ps1` (from your own
machine) does everything in this section around the two clicks only you can
make. It prints the PAT creation URL with the exact permission checklist, reads
the value from a masked prompt (or `-FromEnv HELIOS_ADMIN_TOKEN`), verifies
`.permissions.admin` live and stores the secret over stdin; then, if the Azure
session is missing or MFA-expired, runs the device-code sign-in and waits, mints
the ops identity via `setup-tenant.ps1 -OpsIdentity -Apply`, and prints the
three `AZURE_*` names to export so no later session needs you. Add
`-ApplyGovernance` once PR #113 is on `main` — it reads `dotnet-build.yml` on
`main` and refuses the ruleset otherwise (item 4 below); `-VerifyOnly` reports
and changes nothing. From an agent session the transport rewrites GitHub
credentials and the script says so instead of claiming a pass. The steps below
are what it automates, for doing them by hand.

Repository admin writes — the `main` ruleset, Pages source = GitHub Actions,
"Allow auto-merge", delete-branch-on-merge, the `automerge` label — and the
label/milestone manifests under `config/github/` are applied by
`.github/workflows/governance-apply.yml` from `main`, never from an agent
session: the proxy those sessions sit behind rewrites GitHub credentials
(`.permissions.admin` reads false, `/pages` is blocked), so admin mutations
there are refused by design and only the dry runs are possible. The workflow
needs one credential from you:

1. GitHub → **Settings** (profile menu) → **Developer settings** → **Personal
   access tokens** → **Fine-grained tokens** → **Generate new token**: resource
   owner **Yolkster64**, repository access **Yolkster64/helios-platform** only,
   repository permissions **Administration RW, Contents RW, Issues RW, Pull
   requests RW, Pages RW, Metadata R**; nothing else.
2. `gh secret set HELIOS_ADMIN_TOKEN --repo Yolkster64/helios-platform` and
   paste when prompted — or, with the value held in an env var of the same
   name, `pwsh scripts/bootstrap/provision-github-secrets.ps1 -Apply` (it feeds
   `gh secret set` over stdin). The value goes into that prompt or that env var
   and nowhere else.
3. Once the workflow is on `main`:
   `gh workflow run governance-apply.yml -f apply=true -f scope=all`, then read
   the job summary: one row per item; an exit-2 row names the owner step, an
   exit-1 row carries a replay list. Verify: `gh ruleset list` (a ruleset named
   `main`), `gh label list` (the 21 manifest labels),
   `gh api repos/Yolkster64/helios-platform/milestones` (the 4 manifest
   milestones). Interim, while the workflow is not yet on `main`:
   `pwsh scripts/github/apply-rulesets.ps1` (dry run), then `-Apply` under an
   owner `gh auth login` on a workstation.
4. **Ordering rule for the ruleset**: apply it only after PR #113's
   no-path-filter triggers (`dotnet-build.yml`, `infra-validate.yml`) are on
   `main`. Until then `Build solution & run tests`, `bicep-validate`,
   `arm-freshness` and `terraform-validate` — 4 of the 8 required contexts —
   never start on a PR that touches none of their paths and strand as
   **Expected**, blocking every such merge.

The clicks the fabric cannot make (or makes only with the PAT), each with the
command that follows it:

- **Pages**: the `pages` item of `apply-repo-settings.ps1` sets the source with
  the PAT; by hand it is Settings → **Pages** → Source: **GitHub Actions**.
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
  `docs/`.
- **Branch prune**: step 7 below — `gh workflow run branch-prune.yml` (plan),
  then `-f apply=true`.

Without the secret the workflow still applies labels and milestones with
`GITHUB_TOKEN` and reports the ruleset and settings as "needs
HELIOS_ADMIN_TOKEN". It also applies on every push to `main` touching
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
| Ruleset, settings, labels, milestones | `.github/workflows/governance-apply.yml`: plan on every PR, apply on push to `main`, the daily schedule, or dispatch; manifests `config/github/labels.json`, `milestones.json`, `.github/rulesets/main.json` | Minting `HELIOS_ADMIN_TOKEN` and `gh secret set` it once; the first dispatch, after PR #113's no-path-filter triggers are on `main` |
| Pages, wiki, Projects board | `pages-dashboard.yml` publishes on every **Status Dashboard** completion; `wiki-generator.yml` pushes `docs/` on every push to `main` touching them | Pages source (the PAT item or the Settings → Pages click) and the first `pages-dashboard.yml` dispatch; the wiki's first page, then the first `wiki-generator.yml` dispatch; the classic `project` PAT and the two board commands |
| Branch prune | `.github/workflows/branch-prune.yml` + `scripts/github/prune-branches.ps1`: classify, archive-tag, delete; JSON report artifact | Dispatching it (plan, then `apply=true`); choosing `keep` and, above 200 deletions, `max_delete` |
| Duplicate issues | `scripts/github/close-duplicate-issues.ps1`: classify #54–#92, label, comment, close as duplicate (dry run default, exit 0/1/2) | Linear switch OFF first, then running `-Apply` |
| Codex MCP config | `scripts/bootstrap/write-codex-config.ps1` renders `~/.codex/config.toml` with the absolute server path (dry run prints; `-Apply` writes; `-Force` for an existing file, helios table only; exit 0/1/2) | Running it per workstation; `codex login --device-auth` |

## Links

- [`PROJECT_SETUP.md`](PROJECT_SETUP.md) — contributor setup: toolchain, build, CLI, MCP.
- `CLAUDE.md` (repo root) — build commands and hard rules; the no-secrets rule lives here.
- `docs/CONSOLIDATION_BLUEPRINT.md` and `docs/architecture/` — the trustworthy architecture docs.
- `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md` — runners, Projects, wiki, connectors design.
- `docs/architecture/CONNECTIONS_SETUP.md` — every connection, the Control fabric, the PAT click path.
- `docs/architecture/ABSORPTION_LEDGER.md` — the 40 absorption epics (issues #14–#53).
- `scripts/github/README.md` — the governance and hygiene scripts and their dry-run/apply/exit contract.
- `infra/README.md` — deploy dialects (Bicep/ARM/Terraform), VMSS gates, OIDC identity details.
- `scripts/bootstrap/README.md` — the auth + bring-up scripts referenced above.
