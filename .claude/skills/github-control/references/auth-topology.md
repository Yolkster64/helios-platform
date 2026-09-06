# GitHub auth topology — the five surfaces and the Azure federation

*Versions and API claims mirror the cited repo files; update this file in the same
PR that changes them.*

Every GitHub credential decision in this repo reduces to five surfaces. Pick by
capability, not convenience — several capabilities are exclusive to one surface.

| # | Surface | Use when | Cannot do |
|---|---|---|---|
| 1 | Actions `GITHUB_TOKEN` | A workflow acts on its own repo (contents, issues, PRs, wiki) | Trigger other workflows; manage Projects v2 |
| 2 | Classic PAT, `project` scope | Anything Projects v2 (fields, items, field values) | Be stored repo-side (it is a run-time parameter) |
| 3 | Fine-grained PAT | A narrow write the `GITHUB_TOKEN` is refused for (Copilot coding-agent assignment) | Projects v2 (classic-only) |
| 4 | GitHub App `helios-control-<owner>` | The governance admin items (rulesets, settings) in `governance-run.yml`; anything that must fire `on: push` (cascades) | Projects v2 (classic PAT only); approve production; be registered from an agent container |
| 5 | `gh` CLI device flow | A human's interactive session | Export its token into another process's env |

## 1. Actions `GITHUB_TOKEN`: deny-all default, per-job opt-ins

The exemplar is the claude-foundry pair — `.github/workflows/claude-foundry.yml`
(owner-dispatched lanes) and `.github/workflows/claude-foundry-comment-review.yml`
(the owner-comment review lane): workflow-level `permissions: {}` in both files
(`claude-foundry.yml:22`, `claude-foundry-comment-review.yml:7`), then each job
opts into exactly what it needs — `contents: read` + `issues: write` +
`pull-requests: write` + `id-token: write` for the owner-comment review job
(`claude-foundry-comment-review.yml:31-35`), `contents: read` +
`id-token: write` for manual review (`claude-foundry.yml:40-42`), and a
deliberate authority split for implementation: the Azure-authenticated job is
GitHub-read-only (`claude-foundry.yml:130-133`) while the publish job has
`contents: write` + `pull-requests: write` but **no** `id-token: write`
(`:282-284`) — the header comment at `claude-foundry.yml:19-21` states the
design.

The contrast is the backlog: **seven workflows have no `permissions:` block at
all** (verified by grep, 2026-08-13): `analysis.yml`, `code-checks.yml`,
`deploy.yml`, `phase-build.yml`, `publish-to-packagemanagers.yml`,
`quality.yml`, `verify.yml`. They run with the repository default token
permissions. (`publish-to-packagemanagers.yml` is also invalid YAML and has
never run — `docs/architecture/ROADMAP_MULTI_LLM.md:58`.) The repo rule that
every workflow needs an explicit least-privilege `permissions:` block is
already stated in `.claude/skills/pipelines-config/SKILL.md:13-14`; these seven
predate it and are cleanup candidates, not precedent.

## 2. Classic PAT with `project` scope — the only key to Projects v2

`docs/architecture/CONNECTIONS_SETUP.md:248-250`: *"Projects v2 needs a user
PAT with the `project` scope (classic token; the Actions `GITHUB_TOKEN` cannot
manage Projects v2) — pass it as `-GitHubToken` at run time from a
workstation; it is a parameter, never a stored setting."* Fine-grained PATs do
not carry the classic `project` scope either — for board automation the
classic PAT is the only surface that works.

Consumers: `scripts/board-setup/add-epics-to-board.ps1:83` and
`scripts/board-setup/validate-board.ps1:49` both default
`-GitHubToken` from `$env:GITHUB_TOKEN` (presence checked by name; the
docblocks at `add-epics-to-board.ps1:41` and `validate-board.ps1:28` state the
required scope) and degrade to a printed dry-run plan with exit 0 when no
token is available (`add-epics-to-board.ps1:36-38`).

## 3. Fine-grained PAT — the Copilot dispatch escape hatch

`.github/workflows/copilot-dispatch.yml:38` (and again at `:90`):
`GH_TOKEN: ${{ secrets.COPILOT_DISPATCH_TOKEN || secrets.GITHUB_TOKEN }}`.
The header (`copilot-dispatch.yml:12-14`) documents the contract: if
`GITHUB_TOKEN` is refused for coding-agent assignment, set
`COPILOT_DISPATCH_TOKEN` — a fine-grained PAT of a user with Copilot access,
repo issues write. The `||` fallback means the workflow works with zero setup
and upgrades transparently when the secret exists; both jobs skip green with a
`::notice::` when Copilot declines (`:66-69`, `:101-102`) — automation
degrades, it does not fail the pipeline (`:10-14`).

## 4. GitHub App — `helios-control-<owner>`, the durable admin authority

The repo's GitHub App exists: a private app named `helios-control-<owner>`
(`helios-control-Yolkster64` on the live repository), registered by
`scripts/bootstrap/connect-github-app.ps1` through the manifest flow. The
script opens the pre-filled **Create GitHub App** page, receives the one-hour
manifest code on a one-shot `127.0.0.1` listener (or pasted from the address
bar with `-CallbackPort -1`), converts it at
`POST /app-manifests/{code}/conversions` (unauthenticated by design), stores
the identifiers as repository *variables* (`HELIOS_APP_CLIENT_ID`,
`HELIOS_APP_ID`, `HELIOS_APP_SLUG`) and the PEM as the *secret*
`HELIOS_APP_PRIVATE_KEY` over stdin, discards `client_secret` and
`webhook_secret`, opens the one **Install** click
(`https://github.com/apps/<slug>/installations/new/permissions?target_id=<owner id>`),
then verifies with an in-process app JWT plus `gh api /user/installations`.
It refuses to run over an injecting transport (the agent containers), so
registration is an owner action from their own machine, Cloud Shell or a
Codespace; `connect-devices.ps1` chains it after the device-code logins.
Permissions: administration, contents, issues, pull_requests, pages, actions,
workflows = write; metadata = read; no webhook; not public. The app page is
`https://github.com/settings/apps/<slug>`; the PAT of surface 3 is now the
fallback behind it, not the plan.

**Used for:**

- **The governance admin items.** `.github/workflows/governance-run.yml` mints
  an installation token in its first step (`Mint the HELIOS GitHub App
  installation token`, `id: app`, `actions/create-github-app-token@v3`:
  `client-id` from the variable, `private-key` from the secret, `repositories`
  = this repository, the six `permission-*` inputs) when BOTH
  `vars.HELIOS_APP_CLIENT_ID` and the `HELIOS_APP_PRIVATE_KEY` secret are
  present — tested through the job-level env booleans `HAS_APP_KEY` and
  `HAS_APP_CLIENT_ID`, because the `secrets` context is not usable in `if:`.
  Precedence for `ADMIN_TOKEN`: the installation token → `HELIOS_ADMIN_TOKEN`
  (surface 3, the manual fallback) → `github.token`; the printed credential
  name is `HELIOS_APP (installation token)` / `HELIOS_ADMIN_TOKEN` /
  `GITHUB_TOKEN`. The token lives an hour, is scoped to the repository and to
  those permissions, and is revoked when the job ends; the only long-lived
  material is the key, rotated on the app page and re-stored with
  `gh secret set HELIOS_APP_PRIVATE_KEY --repo <repo> < key.pem`.
- **Workflow cascades.** A push or merge made with the installation token fires
  `on: push`, which `GITHUB_TOKEN` cannot
  (`.claude/skills/automation-wiring/references/github-actions.md:88-89`);
  the governance apply after an auto-merged PR is the first consumer, and the
  daily schedule stays as the drift net for anything still merged by
  `GITHUB_TOKEN`.
- **A broken credential is red, never silent.** A stored app credential that
  no longer mints (uninstalled, key rotated on the app page, installation
  narrowed below the requested permissions) fails the mint step and the job,
  with the repair — `pwsh scripts/bootstrap/connect-github-app.ps1` from the
  owner's machine — in the `::error`; only-the-variable or only-the-secret is
  a `::warning` and the next credential in line.

**Not used for:**

- **Projects v2.** Still surface 2 — the classic PAT with the `project` scope;
  an installation token does not carry it, so the board scripts keep taking
  `-GitHubToken` at run time.
- **Production approval.** GitHub protected environments stay the deployment
  authority (`CLAUDE.md`); the app holds no `environments` permission and no
  workflow asks it to approve anything.
- **Azure.** The GitHub → Azure section below is OIDC; the app never touches
  the cloud side.
- **ARC runner auth.** Still the docs-level aspiration in
  `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md:47,55`
  (`githubConfigSecret: helios-runners-app`); when it lands it should be a
  second, runner-scoped app — this app's key must not spread into a cluster
  secret.

## GitHub → Azure: OIDC federation, no client secret anywhere

`scripts/bootstrap/azure-oidc-setup.sh` creates the app registration and
service principal with **no client secret ever created — nothing to leak or
rotate** (`azure-oidc-setup.sh:7-8`). Two federated-credential subjects are
ensured, matched exactly against what the workflow run presents
(`azure-oidc-setup.sh:92-94`):

- `repo:<owner/repo>:ref:refs/heads/main` — push/dispatch from main (`:112`)
- `repo:<owner/repo>:environment:<env>` — jobs declaring `environment:` (`:114`)

There is deliberately **no `repo:...:pull_request` subject**: this principal
holds deploy rights, and a PR workflow can be modified by the PR itself, so
trusting the generic pull_request subject would let any PR with
`id-token: write` exchange its token for those rights
(`azure-oidc-setup.sh:117-122`). The script actively **deletes** that
credential if an earlier revision created it (`:124-130`). PR validation stays
offline in `infra-validate.yml`; a PR lane that ever needs Azure gets a
separate read-only identity (`:120-122`).

**The vars-`||`-secrets identifier idiom.** The three OIDC identifiers are
*identifiers, not secrets*, and live as repository **variables**, but legacy
setups stored them as secrets — some under the plain `AZURE_*` names, older
ones under an `AZURE_OIDC_*` alias. Consumers therefore resolve a
**three-term chain**, canonical location first and legacy alias strictly
last: `${{ vars.AZURE_CLIENT_ID || secrets.AZURE_CLIENT_ID ||
secrets.AZURE_OIDC_CLIENT_ID }}` (and tenant/subscription likewise) —
repo-wide across `helios-deploy.yml`, `claude-foundry.yml`, and
`claude-foundry-comment-review.yml`, in every env preflight and every
`azure/login` step. PR #102 (squash commit `57512b0`, verified against the
GitHub API: it touches only `claude-foundry.yml`, which then still carried
the comment lane) first brought claude-foundry in line with helios-deploy on
the two-term form; the PR #106 merge (`25e8e652`) restructured the comment
lane and appended the `AZURE_OIDC_*` alias so the canonical locations always
win when both exist. The comment-lane preflight prints the no-secret contract
explicitly: *"No client secret is used."*
(`claude-foundry-comment-review.yml:67`).

**The last anti-pattern is gone** — the known-red all-echo `deploy.yml` that
mapped `AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}` into its env
was deleted (`docs/architecture/ROADMAP_MULTI_LLM.md:53`); no workflow in
`.github/workflows/` reads a client secret. Never reintroduce that auth block.

## The absorb-pr credential guard — why auth surfaces and benchmarks collide

`scripts/absorption/absorb-pr.ps1` refuses to benchmark untrusted upstream
code on a credential-bearing host: `GH_TOKEN` and `GITHUB_TOKEN` sit on its
credential-env scrub list (`absorb-pr.ps1:53-55`, refusal message `:97`),
alongside git credential stores and helpers (`:63-88`). Consequence for this
skill: any surface above that lands a token in the shell environment (surface
2's `$env:GITHUB_TOKEN`, surface 5's exported token) makes that same shell
unusable for absorption benchmarking by design. Run board automation and
absorption runs in separate shells; never "fix" the guard.

## 5. `gh` CLI device flow — and the token-export boundary

`scripts/bootstrap/connect-github.sh:67-70` runs the browser/device-code
login with `--scopes "models:read"` (`:70`) — the extra scope feeds the
`github-models` provider; `:73-75` prints the `gh auth refresh` fix when the
scope is missing.

The boundary rule comes from `scripts/bootstrap/connect-all.ps1`: a child
script **cannot export a token back into the caller's shell**
(`connect-all.ps1:34-37`), so gh-authenticated-but-no-env-var reports
needs-attention with an export hint instead of "ready"; presence is checked by
env-var **name only** — the value is never read, printed, or exported, and
`gh auth token` is never run by the script (`:187-189`) — the human runs
`export GITHUB_MODELS_TOKEN=$(gh auth token)` in their own shell (`:194`).

## Automatic authentication

Everything above assumed someone picks a surface; the automatic lane mechanizes
the picking. `scripts/bootstrap/auth-doctor.ps1` (authored in parallel with this
section; reference by path) is the one command:

- **Report-only by default** — probes five lanes (`gh`, `az`, `codex`, `claude`,
  `copilot`) read-only; `-Json` emits the machine-readable report.
- **`-Apply` = automatic non-interactive repair only** — re-resolving env/Key
  Vault-sourced credentials and service-principal paths; never a device-code
  flow, never anything a human must watch.
- **Per-lane states**: `ready` | `repaired` (only under `-Apply`) |
  `needs-owner` | `unavailable`. Exit 0 = everything ok; exit 2 = at least one
  lane `needs-owner`.
- The consuming agent is `.claude/agents/auth-broker.md` — report first, always;
  `-Apply` only on an explicit ask. Its interactive counterpart stays
  `connect-all.ps1` (human device-code flows, verify-first).

### The automatic-first ordering — and why

Per lane, credentials are tried in this order, stopping at the first that works:
**CI OIDC federation → env token / service principal → managed identity →
device-code (owner action, never automatic)**. The why is the repo's hybrid
rule: interactive device-code logins are for *humans*; CI and fleet workers
never log in interactively — they use OIDC, Workload Identity Federation, or
managed identity, with keys arriving only via environment variables or Key Vault
(`docs/architecture/CONNECTIONS_SETUP.md:45-49`, restated in
`connect-all.ps1:16-21`). Each earlier rung carries less custody risk: the OIDC
rung has **no stored secret at all** (`azure-oidc-setup.sh:7-8`), the env rung
keeps values out of files (CLAUDE.md no-secrets rule), and the identity rung
needs no key whatsoever — an empty `AZURE_OPENAI_API_KEY` deliberately means
Entra ID via `DefaultAzureCredential` (`.env.template:60`).

### Where OIDC already covers CI — nothing for the doctor to repair

The Azure side of CI is already automatic: `scripts/bootstrap/azure-oidc-setup.sh`
federates the two subjects (`:112-115`, deliberately no `pull_request` subject —
`:117-130`), and the consumers log in with identifiers only —
`helios-deploy.yml:54-64` (azure/login, no creds JSON, no client secret), the
comment lane's review job (`claude-foundry-comment-review.yml:31-35,74-76`),
and `claude-foundry.yml`'s two dispatch Azure jobs (`:40-42,86-88`,
`:130-133,182-184`). The GitHub side of CI is surface 1 (`GITHUB_TOKEN`,
minted per run). A `needs-owner` on either in CI means the one-time bootstrap
was never run, not a broken credential.

### What stays owner-only, always

- **Device-code / browser logins** — every surface-5-style flow; they are for
  humans by rule (`CONNECTIONS_SETUP.md:45-46`).
- **MFA re-login** — `AADSTS50078` (UserStrongAuthExpired) blocked both Azure
  planes on 2026-08-13 (`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md:13-14`);
  the remediation is the owner's `az login --tenant …` sequence
  (`ENTERPRISE_AI_CONNECTIONS.md:29-35`).
- **Admin consent** — `az ad app permission admin-consent`
  (`ENTERPRISE_AI_CONNECTIONS.md:83`); tenant mutations are owner actions
  (`.claude/agents/m365-admin.md` hard rules).

The doctor reports all three as `needs-owner` with the exact command to run —
it never attempts them, and no future revision should.
