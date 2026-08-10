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

1. [Wire secrets through env vars / Key Vault](#1-secrets-env-vars-and-key-vault) — nothing works without provider credentials.
2. [Flip the GitHub repository settings](#2-github-repository-settings) — including enabling Issues on this fork.
3. [Set the connector secrets (Slack, Linear)](#3-connectors-slack-and-linear) per `config/connectors.json`.
4. [Create the Azure OIDC deploy identity](#4-azure-oidc-for-deploys) with `scripts/bootstrap/azure-oidc-setup.sh`.
5. [Decide on the fleet VMSS](#5-fleet-vmss-opt-in) — it is OFF by default and stays off until you opt in.

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

- **Enable Issues** (Settings → General → Features → **Issues**). This fork has
  Issues disabled (fork default), and the API write to flip it is blocked from
  the automation environment — it must be clicked by a human. Until then,
  `docs/architecture/ABSORPTION_LEDGER.md` is the system of record for the
  absorption epics; once Issues is on, each epic there becomes one GitHub issue
  verbatim.
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
| `LINEAR_API_KEY` | Actions secret | Mirroring labeled GitHub issues into Linear team `HEL` |

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

## What is automated vs. what stays manual

| Concern | Automated | Manual (owner) |
| --- | --- | --- |
| Azure resources | `scripts/bootstrap/azure-up.sh` deploys `infra/main.bicep`; CI deploys via `helios-deploy.yml` | `az login`, choosing subscription/region, approving `production` deploys |
| Deploy identity | `azure-oidc-setup.sh` creates app/SP/federated creds/roles idempotently | Running it once as a privileged user; pasting the three variables into GitHub |
| Provider keys | Key Vault → env wiring via `load-env-from-keyvault.sh`; gh token reuse via `connect-github.sh` | Putting the keys into Key Vault (or `.env`) in the first place |
| Issues | Once enabled, absorption epics/wiki sync flow through workflows | Enabling Issues in Settings (API write is blocked from automation) |
| Slack/Linear | Workflows notify/sync using the secrets | Creating the webhook/API key and adding them as Actions secrets |
| Fleet VMSS | Bicep module deploys it when gated on | Opting in (`deployFleetVmss` + SSH key) and paying for it |

## Links

- [`PROJECT_SETUP.md`](PROJECT_SETUP.md) — contributor setup: toolchain, build, CLI, MCP.
- `CLAUDE.md` (repo root) — build commands and hard rules; the no-secrets rule lives here.
- `docs/CONSOLIDATION_BLUEPRINT.md` and `docs/architecture/` — the trustworthy architecture docs.
- `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md` — runners, Projects, wiki, connectors design.
- `docs/architecture/ABSORPTION_LEDGER.md` — the epics waiting on Issues being enabled.
- `infra/README.md` — deploy dialects (Bicep/ARM/Terraform), VMSS gates, OIDC identity details.
- `scripts/bootstrap/README.md` — the auth + bring-up scripts referenced above.
