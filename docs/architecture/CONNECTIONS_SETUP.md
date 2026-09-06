# Connections Setup — GitHub ↔ Everything

The one-page wiring guide: every external connection this repo has, what carries it,
what the owner must click, and how to prove it works. Design rationale lives in
[`GITHUB_ECOSYSTEM_DESIGN.md`](GITHUB_ECOSYSTEM_DESIGN.md); the owner's day-one
checklist (including the GitHub settings pages) is
[`../OWNER_START_HERE.md`](../OWNER_START_HERE.md). The single entry point for a
fresh shell is `bash scripts/bootstrap/first-run.sh` (§ Control fabric below); admin
writes to the repository run only from `main` through `governance-apply.yml`. Hard
rule everywhere below: **no secrets in the repo** — config files carry env-var
*names* only.

## One-command login (Cloud Shell and hybrid)

`pwsh scripts/bootstrap/connect-all.ps1` runs every interactive login lane in one
pass, **verify-first**: lanes already authenticated are detected and skipped, the
rest get a device-code / no-browser flow (a URL plus a one-time code you finish in
any browser). It never prompts for a key and never stores a secret; check the
result any time with `pwsh scripts/bootstrap/setup-ai-clis.ps1 -VerifyOnly
-ProbeAuth` (informational auth column, exit code unchanged).

When a lane is *broken* rather than not-yet-logged-in,
`pwsh scripts/bootstrap/auth-doctor.ps1` is the automatic diagnose/repair entry
point: report-only by default (it probes every lane, mutates nothing, exits 0),
and `-Apply` adds non-interactive repair only — whatever needs a human comes back
as an exact owner-action command. Its connector lanes (linear, slack, sharepoint,
azure-devops) are **verify-only** and never gate the exit code: their fixes are
repository secrets or tenant consent, not logins. Connector knowledge and
operations live in the `connector-integrations` skill
(`.claude/skills/connector-integrations/`) and the `connector-steward` agent
(`.claude/agents/connector-steward.md`).

| Provider | What it unlocks | Command (what the lane runs) |
|---|---|---|
| GitHub (`gh`) | `gh-models` provider, `copilot` CLI (reuses the gh login), repo/Actions operations | `gh auth login --web` device-code (`scripts/bootstrap/connect-github.sh`) |
| Azure (`az`) | Key Vault env loading (`load-env-from-keyvault.sh`), `azure-openai`/`azure-foundry` via Entra ID, Bicep deploys | `az login --use-device-code` (`connect-azure.sh` / `connect-azure.ps1`; Cloud Shell is implicitly logged in and skipped) |
| Anthropic (`ant`) | Profile credentials for the `anthropic` provider and `claude` CLI without handling a raw key | `ant auth login --no-browser` (prints the authorize URL, accepts the pasted code) |
| OpenAI (`codex`) | `codex` cliAgent (`codex exec {prompt}`) | Headless: `OPENAI_API_KEY` from Key Vault (`openai-api-key`); `codex login` only where a browser exists |

### One command, everything

`pwsh scripts/bootstrap/setup-everything.ps1` chains the whole bring-up in order,
calling only the existing scripts: `verify-readiness.ps1` (toolchain) →
`connect-account.ps1` (identity) → `auth-doctor.ps1` (auth; `-Apply` passes
through) → `setup-all.ps1` (inventory) → `scripts/verify/stack-smoke.ps1` (soft
smoke) → `scripts/verify/rest-connect.ps1` (soft control-plane REST probes),
ending in one consolidated, deduped owner-action list (`-Json` for the
machine rollup). The identity gate is hard: any `connect-account` mismatch aborts
the chain immediately with exit 2 — acting as the wrong account is worse than
acting unauthenticated. Report-first by default: nothing is mutated without
`-Apply`, and even then repair is auth-doctor's non-interactive lane only.

**Auto-login** (`. scripts/bootstrap/auto-login.ps1`, dot-sourced) is the
acquire-and-export companion: it delegates az repair to `auth-doctor -Apply`
(non-interactive only; `-UseManagedIdentity` is forwarded for classic IMDS-only
VMs that expose no managed-identity endpoint variable), pulls `openai-api-key` / `anthropic-api-key` /
`github-models-token` from the Key Vault at `AZURE_KEY_VAULT_URI` into
`OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GITHUB_MODELS_TOKEN` (the exact names
`config/aihub.json` declares — lighting the codex, claude, and gh-models lanes
plus every SDK/REST consumer of the same names), and falls back to `gh auth
token` for the models token. Zero prompts ever; values live only in process
memory; existing env values are never clobbered. The zero-human-input paths that
exist today: CI (OIDC + `GITHUB_TOKEN`), Azure Cloud Shell (implicit `az` login →
auto-login lights every provider **whose key the vault actually holds** — the
default `azure-up` deployment creates no provider-key secrets, since
`infra/main.bicep`'s key parameters default to empty strings, so storing
`openai-api-key` / `anthropic-api-key` / `github-models-token` values is a
one-time owner step), and any host holding the ops service principal minted once
by `setup-tenant.ps1 -OpsIdentity`.

**ant CLI facts** (per the CLI authentication docs):

- Interactive login is `ant auth login` (browser OAuth). On a remote or
  browserless host — Cloud Shell included — use `ant auth login --no-browser`,
  which prints the authorize URL and accepts the pasted code.
- `--profile <name>` names profiles; `--workspace-id` skips the workspace picker.
  Credentials store under `$ANTHROPIC_CONFIG_DIR`.
- `ant auth status` prints the selected credential source, but its exit status
  must not be scripted against (the docs say so) — grep its stdout instead, which
  is exactly what `setup-ai-clis.ps1 -ProbeAuth` does.
- `ANTHROPIC_API_KEY` overrides every profile — unset it when the profile
  credentials should win. `ant auth logout` clears stored credentials.
- Non-interactive workloads (CI, servers) should use **Workload Identity
  Federation**, not interactive login.

**Visual Studio**: no lane needed — Visual Studio signs into Entra ID and GitHub
itself (File → Account Settings…), and the Copilot/Azure tooling inside VS rides
those logins rather than anything a script here sets up.

**The hybrid rule**: interactive device-code / no-browser logins are for *humans*
on workstations and Cloud Shell. CI and fleet workers never log in interactively —
they use OIDC (`scripts/bootstrap/azure-oidc-setup.sh`), Workload Identity
Federation, or managed identity, with keys arriving only via environment variables
or Key Vault.

## The matrix

| Connection | What flows | Carried by (in this repo) | Repo-side config needed |
|---|---|---|---|
| GitHub Actions ↔ Azure | OIDC deploy of `infra/main.bicep`, no stored cloud secret | `.github/workflows/helios-deploy.yml` + `scripts/bootstrap/azure-oidc-setup.sh`/`.ps1` | 3 Actions **variables** (below) |
| GitHub ↔ ChatGPT/Codex | Auto PR reviews, `@codex` commands | Nothing — connection lives at chatgpt.com (Codex settings) | None (`AGENTS.md` is read by Codex) |
| GitHub ↔ Copilot | Inline/CLI agent, auto review requests, coding-agent assignment | `.github/workflows/copilot-dispatch.yml`, `config/aihub.json` `copilot` cliAgent, `.github/copilot-instructions.md` | Optional `COPILOT_DISPATCH_TOKEN` secret |
| GitHub ↔ Claude | Claude Code sessions, `claude-cli` routing, MCP tools | `CLAUDE.md`, `.claude/skills/`, `config/aihub.json` `claude-cli` cliAgent, `.mcp.json` | None |
| Self-hosted runners | `runs-on: [self-hosted, helios]` job execution | `scripts/runners/register-runner.sh`/`.ps1`, `.github/workflows/runner-smoke.yml` | Runner registration (repo admin) |
| GitHub ↔ Linear | Labeled issues mirrored to the Linear board | `.github/workflows/linear-sync.yml` + `config/connectors.json` | `LINEAR_API_KEY` secret |
| GitHub ↔ Slack | CI/deploy outcomes posted to channels | `.github/workflows/notify-slack.yml` + `config/connectors.json` | `SLACK_WEBHOOK_URL` secret |
| GitHub Project board | Epic-level tracking board (Projects v2) | `scripts/board-setup/` (custom fields, validation, and epic wiring via GraphQL; views/templates/automation are manual UI steps the scripts document) | User PAT with `project` scope (run-time param, never stored) |

## GitHub Actions ↔ Azure (OIDC, no stored credential)

`scripts/bootstrap/azure-oidc-setup.sh` (PowerShell twin `azure-oidc-setup.ps1`,
same `az` calls) creates, idempotently:

- app registration **`helios-github-deploy`** + service principal — **no client
  secret is ever created**;
- federated credentials trusting GitHub's OIDC issuer for exactly **two**
  subjects: `repo:Yolkster64/helios-platform:ref:refs/heads/main` and
  `repo:…:environment:production`. Deliberately **no `pull_request` subject**
  (a PR can rewrite its own workflow; PR validation stays offline in
  `.github/workflows/infra-validate.yml`) — the script even deletes that
  credential if an older revision created it;
- **Contributor** scoped to the resource group only, plus **Key Vault Secrets
  Officer** scoped to the provider-key vault only (data-plane RBAC for the
  vault-secret writes `infra/main.bicep` performs).

It finishes by printing the values for the exact settings
`.github/workflows/helios-deploy.yml` reads — set them as Actions
**variables** (identifiers, not secrets), with `gh variable set` one-liners
printed ready to paste:

| Setting | Kind | Read by `helios-deploy.yml` as |
|---|---|---|
| `AZURE_CLIENT_ID` | variable (required) | `vars.AZURE_CLIENT_ID` (falls back to `secrets.AZURE_CLIENT_ID`, then the older `secrets.AZURE_OIDC_CLIENT_ID` alias — legacy locations, strictly last) |
| `AZURE_TENANT_ID` | variable (required) | `vars.AZURE_TENANT_ID` (same fallback) |
| `AZURE_SUBSCRIPTION_ID` | variable (required) | `vars.AZURE_SUBSCRIPTION_ID` (same fallback) |
| `AZURE_RESOURCE_GROUP` | variable (optional) | defaults to `rg-helios-ai` |
| `AZURE_LOCATION` | variable (optional) | defaults to `eastus2` |

Graceful skip: the workflow's "Check Azure OIDC configuration" step exits green
with a `::notice::` whenever `AZURE_CLIENT_ID` is unset, so forks and
pre-bootstrap clones never see a red deploy check. Order matters: run
`scripts/bootstrap/azure-up.sh` first (the OIDC script refuses to run until the
resource group exists). Verify by dispatching **Helios Platform Deploy** *from
`main`* (the federated subject is branch-scoped) with `what_if=true`.

## GitHub ↔ ChatGPT / Codex

The connection lives on OpenAI's side, not in this repo: the **owner** connects
the GitHub account/repo in the Codex settings at **chatgpt.com** (Settings →
connectors / Codex → GitHub). There is nothing repo-side to configure or keep
in sync. Once connected:

- Codex posts an automatic review on new PRs (when auto-review is enabled for
  the repo in those same settings);
- PR comments drive it: `@codex review` requests a review, `@codex address
  that feedback` (or any `@codex <task>` follow-up) has it push fixes;
- work counts against the ChatGPT plan's Codex usage limits — when the limit
  is hit, reviews and commands quietly stop until the window resets, so a
  *missing* Codex review usually means quota, not breakage.

Repo artifacts Codex reads: `AGENTS.md` (its instruction file, mirroring
`CLAUDE.md`). The reverse direction — this repo calling Codex — is the `codex`
cliAgent in `config/aihub.json` (`codex exec {prompt}`, first in the
`code_generation`/`code_refactoring`/`test_creation` chains) and the Codex CLI
MCP wiring in [`../mcp/CLIENT_SETUP.md`](../mcp/CLIENT_SETUP.md).

## GitHub ↔ Copilot (three surfaces)

1. **Inline / CLI agent** — the `copilot` cliAgent in `config/aihub.json`
   (`copilot -p {prompt}`), routed for `inline_completion`;
   `.github/copilot-instructions.md` is its per-repo instruction file, and
   [`../mcp/CLIENT_SETUP.md`](../mcp/CLIENT_SETUP.md) wires VS Code Copilot to
   the HELIOS MCP server. Needs only each developer's Copilot login.
2. **Auto review request** — `.github/workflows/copilot-dispatch.yml`
   (`request-review` job) asks Copilot to review every non-draft PR, so the
   review happens without anyone remembering to ask.
3. **Coding-agent assignment** — adding the **`copilot` label** to an issue *is*
   the delegation decision: the `assign-coding-agent` job in the same workflow
   assigns the Copilot coding agent (`copilot-swe-agent`), which opens a draft
   PR. Remove the label / unassign to take the work back. Keep it to scoped,
   mechanical tasks, and never merge an agent PR on a red or skipped check
   (see [`GITHUB_ECOSYSTEM_DESIGN.md`](GITHUB_ECOSYSTEM_DESIGN.md)).

Both workflow paths **skip green with a `::notice::`** when Copilot isn't
available in the repo. If the default `GITHUB_TOKEN` is refused for
coding-agent assignment, set the optional **`COPILOT_DISPATCH_TOKEN`** Actions
secret (fine-grained PAT of a user with Copilot access) — the workflow prefers
it automatically **for both of its jobs**, so the PAT needs **Issues: write
AND Pull requests: write** on this repo (the request-reviewers endpoint
requires the latter; an issues-only token would silently reduce every
automatic review request to a `::notice::`).

## GitHub ↔ Claude

- **CLI agent**: `claude-cli` in `config/aihub.json` (`claude -p {prompt}`) —
  the routing table sends `code_review`, `long_context_analysis`, and
  `debugging` its way (`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md` says why).
- **Claude Code sessions**: pick up `CLAUDE.md` (build commands, hard rules)
  and the coding skills in `.claude/skills/` automatically on opening the repo.
- **MCP**: `.mcp.json` at the repo root registers the HELIOS MCP server
  (`dotnet run --project src/mcp/HELIOS.Mcp`), so Claude Code gets the
  `helios_ai_*` tool surface with zero setup — verify with `/mcp` in a session.
  Other clients: [`../mcp/CLIENT_SETUP.md`](../mcp/CLIENT_SETUP.md).

No owner action and no secrets beyond each developer's own `claude` login
(`ANTHROPIC_API_KEY` for the API provider follows the normal
`config/aihub.json` env-var/Key Vault flow).

## Self-hosted runners

- **Register one runner (hand-managed)**: `scripts/runners/register-runner.sh`
  (Linux/macOS) or `scripts/runners/register-runner.ps1` (adds Windows). They
  require an admin-authenticated `gh`, mint a single-use ~1h registration token
  (never echoed, never on disk), download the latest `actions/runner`, and
  configure with labels **`helios,xcore`** — add pool labels via the
  extra-labels parameter, e.g. `xcore-native` for the `xcore-9-native` pool's
  dedicated Windows-SDK/GPU box (`config/fleet/fleet-topology.json`). They
  print the `./run.sh` / service commands rather than auto-starting; both have
  a dry-run mode.
- **Proof of life**: dispatch `.github/workflows/runner-smoke.yml`
  (**Self-Hosted Runner Smoke**) — one job on `[self-hosted, helios]` that
  prints the runner identity and exits green. It is `workflow_dispatch`-only
  on purpose: it can never queue forever and hang CI when no runner exists.
- **Scale-out path**: runner scale sets via ARC (`gha-runner-scale-set`,
  GitHub App auth, scale-to-zero) — the design, chart values, and per-workload
  scale-set layout are in
  [`GITHUB_ECOSYSTEM_DESIGN.md` § Self-hosted runners (ARC)](GITHUB_ECOSYSTEM_DESIGN.md#self-hosted-runners-arc);
  this page deliberately doesn't duplicate them.

## GitHub ↔ Linear and Slack

`config/connectors.json` is the single routing table (env-var names and routing
only — never values). Two Actions secrets switch the connections on; without
them **both workflows skip green** and can never be the red check.

| Connection | Secret | Workflow | Fires when |
|---|---|---|---|
| Linear | `LINEAR_API_KEY` | `.github/workflows/linear-sync.yml` | Issue `opened`/`labeled`/`unlabeled`/`closed`/`reopened` **and** the issue carries a `linear.syncLabels` label (`bug`, `enhancement`, `infra`, `ai-hub`, `absorption`, `build-ci`); `unlabeled` also proceeds when the *last* sync label was just removed, so the mirror's labels empty instead of freezing |
| Slack | `SLACK_WEBHOOK_URL` | `.github/workflows/notify-slack.yml` | `workflow_run` completion of the six workflows listed in it, filtered by `slack.notifyOn` (`always` vs `failures-and-recovery`) |

Linear sync is one-directional (GitHub is the source of truth): mirrored issues
get a `[GH-<n>]` title prefix into team `JOH` (`linear.teamKey` — must match
your Linear workspace's team key or the sync warns and exits), label mapping
per `githubLabelToLinear`, and close/reopen moves the Linear state. Enable
with `gh secret set LINEAR_API_KEY` / `gh secret set SLACK_WEBHOOK_URL`;
routing changes are edits to `config/connectors.json`, never to the workflows.

> **Owner action — disable Linear's own GitHub sync for team John.** Linear's
> built-in GitHub integration must NOT also be linked to this repository for
> team `JOH`, or the two syncs loop: Linear re-creates its mirrored issues back
> on GitHub as new issues (this produced duplicates #54–#93: closed 2026-08-12,
> after which the integration **reopened #54–#92** — only #93 stayed closed — and
> closing the GitHub twins also cancelled the Linear mirrors, which had to be
> restored). Click path: Linear → **Settings → Integrations → GitHub** →
> under the team `John` link, disable issue sync for `Yolkster64/helios-platform`
> (leave PR-link previews on if desired). One direction only: this repo's
> `linear-sync.yml` is the writer; Linear stays the mirror. Only after the switch
> is off, close the twins with `scripts/github/close-duplicate-issues.ps1`
> (§ Control fabric → Issue hygiene); `linear-sync.yml` already skips `[GH-`
> titles and the `duplicate` label, so the closing never echoes back.

## GitHub Project board

`scripts/board-setup/setup-board.ps1` orchestrates the board setup steps, but
only part of the build is real API provisioning — GitHub's ProjectV2 GraphQL
API cannot create views, item templates, or built-in workflows:

- **Custom fields — real**: `setup-custom-fields.ps1` creates the 25 fields via
  GraphQL mutations against `api.github.com/graphql`.
- **Views / phase templates / automation rules — manual + local simulation**:
  `setup-views.ps1`, `setup-templates.ps1`, and `setup-automation-rules.ps1`
  make **zero API calls** (a real API limitation, not a script bug). They write
  the intended configuration to local JSON (`.views/`, `templates/`,
  `.automation/`) and generate manual click-path guides under `logs/`; those
  steps are performed by hand in the GitHub UI.
- **Validation — real**: `validate-board.ps1` does a read-only GraphQL query of
  the project's fields and items (first 100), verifies the 25 expected custom
  fields, and reports counts. Without a token it prints exactly what it would
  query and exits 0 (`NO TOKEN - DRY-RUN`).
- **Epics — real**: `add-epics-to-board.ps1` puts epic issues #14–#53 of
  `Yolkster64/helios-platform` on the board via `addProjectV2ItemById` and
  stamps Status/Priority via `updateProjectV2ItemFieldValue` where those fields
  exist. Idempotent; `-DryRun` prints the per-issue plan; degrades to the same
  no-token dry-run.

```powershell
./scripts/board-setup/setup-board.ps1 -GitHubToken $token -ProjectNumber 1 `
    -OrganizationName "Yolkster64" -BoardName "HELIOS Platform" -DryRun
```

Real parameters: `-GitHubToken` (mandatory), `-ProjectNumber` (mandatory, int),
`-OrganizationName` (mandatory), `-BoardName` (default `HELIOS Platform`),
`-DryRun` (preview), `-SkipSteps` (any of `fields,templates,automation,views`),
`-Verbose`. Run `-DryRun` first; it writes logs/report/backup JSON under
`logs/`.

**Projects v2 needs a user PAT with the `project` scope** (classic token, plus
`repo` read so the epics resolve; the Actions `GITHUB_TOKEN` cannot manage
Projects v2) — pass it as `-GitHubToken` at run time from a workstation; it is a
parameter, never a stored setting. The two commands `apply-repo-settings.ps1`
prints for its report-only `boards` item are
`pwsh scripts/board-setup/setup-custom-fields.ps1 -GitHubToken <PAT>` and
`pwsh scripts/board-setup/add-epics-to-board.ps1 -GitHubToken <PAT>`;
`validate-board.ps1` is the read-only check.
`validate-board.ps1` and `add-epics-to-board.ps1` also fall back to the
`GITHUB_TOKEN` environment variable (name only — the value is never stored or
printed) and print a dry-run plan and exit 0 when it is absent.

## GitHub governance (rulesets, Pages, auto-merge)

The governance artifacts live in the repo — `.github/rulesets/main.json`,
`.github/CODEOWNERS`, `.github/dependabot.yml`, and the PR/issue templates — and
three settings turn them on. All three are now items of the Control fabric
(§ below): `governance-apply.yml` applies them from `main` once the owner has
stored `HELIOS_ADMIN_TOKEN`, so the clicks are the fallback, not the plan.

1. **Apply the branch ruleset** — `pwsh scripts/github/apply-rulesets.ps1` first
   (dry run: prints the exact `gh api` POST/PUT calls, changes nothing), then
   `-Apply` under repository admin (the workflow's PAT, or — until
   `governance-apply.yml` is on `main` — an owner `gh auth login` on a
   workstation). Idempotent: it GETs existing rulesets and updates by name instead
   of duplicating; exits 2 with an explanation when `gh` or auth is missing. The
   check-name provenance and exclusion rationale are in the script's header
   comment. Measured 2026-09-03: no ruleset named `main` exists yet; `gh ruleset
   list` is the check. **Ordering rule**: apply the ruleset only after PR #113's
   no-path-filter triggers (`dotnet-build.yml`, `infra-validate.yml`) are on
   `main` — before that, `Build solution & run tests`, `bicep-validate`,
   `arm-freshness` and `terraform-validate` (4 of the 8 required contexts) never
   start on a PR outside their paths and strand as **Expected**, blocking every
   such merge.
2. **Enable GitHub Pages** — Settings → Pages → Source: **GitHub Actions**, so
   `pages-dashboard.yml` can publish the status dashboard that
   `status-dashboard.yml` collects from the real Actions API. Item `pages` of
   `scripts/github/apply-repo-settings.ps1` (`build_type=workflow`). Then
   `gh workflow run pages-dashboard.yml` publishes the first dashboard instead of
   waiting for the next **Status Dashboard** completion.
3. **Enable "Allow auto-merge"** — Settings → General → Pull Requests, so
   `auto-merge.yml` can arm merges. Item `auto-merge` of the same script; measured
   already on. Its sibling item `delete-branch-on-merge` (measured off) is the
   train's own hygiene and rides the same run.

**Auto-merge label contract**: adding the **`automerge` label** is the arming
decision. It is honored only when the sender has owner/write permission, and the
absorption lane is excluded (absorption PRs never auto-merge). Arming never skips
gates — the merge still waits for every required check in the `main` ruleset, and
removing the label disarms.

**Automatic lane**: `.github/workflows/pr-pipeline.yml` is the unattended
counterpart to the label lane. For trusted authors only (the repo owner, the
Copilot coding agent, and dependabot's grouped minor/patch updates) it readies the
agent's draft PRs when all checks are green, and arms — or, on an already-clean
PR, completes — a squash merge once review threads are resolved and every check on
the head SHA passes (absorption branches always excluded). The same three owner
clicks above are its prerequisites: the ruleset supplies the required checks it
defers to, and "Allow auto-merge" lets it arm. To pause the automatic lane without
touching the label lane, disable the workflow: Actions → **PR Pipeline** → "…" →
Disable workflow (or `gh workflow disable pr-pipeline.yml`); re-enabling it
resumes evaluation on the next PR event.

## Control fabric (governed writes from `main`)

Everything above that needs **repository admin** — the ruleset, the Pages source,
the wiki flag, `delete_branch_on_merge`, the `automerge` label — plus the labels
and milestones the automation relies on, is checked-in truth reconciled by one
workflow. It is a workflow rather than an agent session for a measured reason.
From the containers that author this repo's PRs (Claude Code sessions,
Codespaces behind an egress proxy) the GitHub API is reachable only through a
proxy that rewrites the credential: `gh api repos/Yolkster64/helios-platform`
reads succeed, but every `.permissions.*` field comes back `false` (no `admin`,
no `push`), mutations are refused, `repos/{repo}/pages` and the
`repos/{repo}/actions/secrets|variables` listings are blocked outright
(HTTP 403 "not permitted through this proxy" — which is why
`provision-github-secrets.ps1` reports every repository secret as `unknown` from
here), and a path carrying `%23` (`#` in a branch name) fails with HTTP 400. So
from there every script below can only run
its dry run; the exact commands it prints are ledgered, and the apply happens
where the credential is real: an Actions job on `main` (rule 5 of the train:
classifier and proxy denials are never engineered around).

### `governance-apply.yml`: four scripts, one authority split

| Item | Script | Truth it applies | Credential |
|---|---|---|---|
| `rulesets` | `scripts/github/apply-rulesets.ps1` | `.github/rulesets/*.json` (create, or PUT by name) | repo admin |
| `settings` | `scripts/github/apply-repo-settings.ps1` | Pages source = Actions, `allow_auto_merge`, `has_wiki`, `delete_branch_on_merge`, the `automerge` label; `boards` is report-only | repo admin |
| `labels` | `scripts/github/apply-labels.ps1` | `config/github/labels.json` — 21 labels: the 16 live ones (colors verbatim, blank descriptions filled) plus `automerge`, `copilot`, `dependencies`, `hygiene`, `absorption-candidate`; never deletes, never renames | `issues: write` |
| `milestones` | `scripts/github/apply-milestones.ps1` | `config/github/milestones.json` — Control fabric, GUI train T5, Absorption tranche 5, Owner setup, each with a due date; never closes or deletes | `issues: write` |

Every script is dry-run by default, prints the exact `gh api` call **before**
executing it under `-Apply`, never aborts the pass on one failed item, and exits
0 (clean), 1 (an item failed; replay list printed) or 2 (precondition or
credential missing). The workflow honors the same contract:

- **`plan` job** — `pull_request` touching `.github/rulesets/**`,
  `config/github/**`, `scripts/github/**` or the workflow itself: `GITHUB_TOKEN`,
  `contents: read` + `pages: read` (so the Pages GET is truthful, not a 403),
  every script in dry run, the diff table in the job summary. A PR can never
  mutate the repository.
- **`apply` job** — `push` to `main` on the same paths, the daily `schedule`
  (06:17 UTC: the drift net for merges that raise no push event; GitHub keeps
  scheduled runs off on forks unless enabled), or `workflow_dispatch` with `apply`
  (boolean, default false, which makes it a plan run with the real token) and
  `scope` (`all|rulesets|settings|labels|milestones`): `GH_TOKEN` is `HELIOS_ADMIN_TOKEN`
  when the owner has stored it, else `github.token` (`contents: read`,
  `issues: write`, `pages: read`). Labels and milestones apply with either token.
  Rulesets and settings apply **only** with the PAT; without it they print their
  dry run and the summary row reads "needs HELIOS_ADMIN_TOKEN" with the owner step
  spelled out. Exit 2 is reported, never red; exit 1 fails the job. Concurrency
  group `governance-apply`, never cancelled mid-pass (the plan job uses
  `governance-plan-<PR>` so a PR never queues behind an apply); every script is
  called with `-Repository $GITHUB_REPOSITORY`, so a fork reconciles itself and
  never the upstream default; every `pwsh` command line is echoed before it runs.

Measured 2026-09-03 (dry runs from this container): rulesets — none named `main`
live, 1 to create; settings — `allow_auto_merge` already true,
`delete_branch_on_merge` false, `has_wiki` true, `pages` unreadable from here;
labels — create 5, update 7, in sync 9; milestones — create 4.

### The one owner step: `HELIOS_ADMIN_TOKEN`

One fine-grained PAT is the repository's single admin credential. It lives in the
Actions secret and the owner's password manager, nowhere else.

1. GitHub → **Settings** (profile menu, not the repository) → **Developer
   settings** → **Personal access tokens** → **Fine-grained tokens** →
   **Generate new token**.
2. Resource owner **Yolkster64**; Repository access **Only select
   repositories** → **Yolkster64/helios-platform**.
3. Repository permissions: **Administration: Read and write**, **Contents: Read
   and write**, **Issues: Read and write**, **Pull requests: Read and write**,
   **Pages: Read and write**, **Metadata: Read** (GitHub adds it itself). Nothing
   else, no account permissions. Choose an expiry and calendar the renewal.
4. Store it once, from any shell whose `gh` is logged in as the owner:

   ```bash
   gh secret set HELIOS_ADMIN_TOKEN --repo Yolkster64/helios-platform   # paste when prompted
   ```

   The value goes into that prompt and nowhere else — not a file, a chat, a
   workflow input, `.env`, or a shell history line. (The first-run path is the
   same call: `scripts/bootstrap/provision-github-secrets.ps1 -Apply` feeds the
   env var of the same NAME to `gh secret set` over stdin.)
5. Apply from `main`, once the workflow is there: `gh workflow run
   governance-apply.yml -f apply=true -f scope=all`, then read the run's job
   summary — one row per item with its exit code and note. Interim, before the
   workflow is on `main`: `pwsh scripts/github/apply-rulesets.ps1 -Apply` under an
   owner `gh auth login` (and mind the ruleset ordering rule in § GitHub
   governance).
6. Verify from any shell: `gh ruleset list` (a ruleset named `main`),
   `gh label list` (the 21 manifest labels),
   `gh api repos/Yolkster64/helios-platform/milestones` (the 4 manifest
   milestones).

Rotation is the same steps 1–5; nothing in the repo references the value.
Projects v2 stays outside this token on purpose: the board scripts need a classic
PAT with the `project` scope (plus `repo` read) passed at run time (§ GitHub
Project board), which is why `apply-repo-settings.ps1` prints the board commands
instead of running them.

### Branch prune (`branch-prune.yml`)

`scripts/github/prune-branches.ps1` classifies every remote branch from live API
reads (never from a clone): `open-pr` (head of an open PR here or, because this
repository is a fork, in the upstream parent `M0nado/helios-platform` — GitHub
closes a PR the moment its head branch disappears) and `keep-list` (the
default branch, `main`, `develop`, `master`, plus `-Keep`) are kept; `merged`
(`compare/main...branch` reports `ahead_by == 0`) is deleted, nothing lost;
`stale` (unmerged commits) is **archived, then deleted** — a lightweight tag
`archive/<branch>` is created at the tip, the tip is re-read and the item refused
if it moved, then the ref is deleted; `unclassified` (the compare read failed) is
never touched and turns the exit into 1. `-MaxDelete` (default 200) refuses an
apply that would delete more (exit 2, nothing changed; the refusal prints the
raised-cap re-dispatch). A failed read of the parent's open PRs is exit 2 as well:
nothing is classified from a partial PR set. Restore any archived branch:

```bash
git push origin refs/tags/archive/<branch>:refs/heads/<branch>
```

The workflow is `workflow_dispatch` only (never scheduled — deletion is a per-run
decision), `permissions: contents: write` + `pull-requests: read`, `GITHUB_TOKEN`,
inputs `apply` (default false), `keep` and `max_delete` (default 200, maps 1:1 to
`-MaxDelete`). It prints the exact command, runs the script with
`-Repository $GITHUB_REPOSITORY -Json -MaxDelete <n>`, renders the table and the
report's `nextStep` (the exact next command) into the job summary, uploads the
`branch-prune-report` artifact (`branch-prune-report.json`, 90 days) and only
then re-raises the script's exit code, so a failed pass still publishes its
replay list. Run it twice: `gh workflow run branch-prune.yml` (plan), read the
summary, then `gh workflow run branch-prune.yml -f apply=true -f keep=<a,b>`
(add `-f max_delete=<n>` when the plan deletes more than 200).

Measured plan 2026-09-03: 101 branches — 2 open-pr
(`claude/azure-ai-deployment-params-9fjn3i`, PR #113 here;
`integration/helios-hermes-xcore`, head of an open PR in the upstream parent),
3 keep-list, 8 merged, 87 stale (4 with no common ancestor), 1 unclassified
(`codex/fix-linux-ci-coverage-issues-in-pull-request-#85`: the proxy here
rejects `%23`, so the dry run exits 1 from this container; the Actions transport
is expected to read it).

### Issue hygiene: the Linear loop and its closer

Issues **are** enabled on this fork. The 40 absorption epics are #14–#53 (E-n is
issue 13+n; `docs/architecture/ABSORPTION_LEDGER.md`). Issues #54–#93 are their
`[GH-<n>] …` twins: Linear's own GitHub integration mirrored this repo's Linear
mirrors back as new GitHub issues; they were closed on 2026-08-12 and the
integration reopened #54–#92 (#93 stayed closed). Two pieces end the loop, in
this order:

1. **Owner switch first** — the blockquote under § GitHub ↔ Linear and Slack:
   Linear → Settings → Integrations → GitHub → team John → issue sync OFF for
   `Yolkster64/helios-platform`. Until it is off, closed twins reopen again.
2. `pwsh scripts/github/close-duplicate-issues.ps1` — dry run by default;
   `-Apply` from an owner `gh` login or the PAT (needs `.permissions.push`). It
   sweeps #54–#92 (`-From`/`-To`) and closes a number only when all four hold:
   open, title starts with `[GH-<n>]` followed by a space, body carries Linear's `GitHub (system of
   record)` line, and original `#n` exists and is open. Per candidate, each
   command printed first: add `duplicate` (skipped if present), post ONE
   "Duplicate of #<n> …" comment with the footer (skipped if present), `PATCH
   state=closed state_reason=duplicate`. Exit 0/1/2 as its siblings. Optional
   `-SessionUrl https://claude.ai/code/session_<id>` appends the session link
   under the comment footer (any other shape is rejected with exit 1). Measured
   dry run: 36 candidates, 3 skipped (#77, #85, #87 — their originals #37, #45,
   #47 are closed, so they get a human look instead), 0 unreadable.

`linear-sync.yml` carries the guard on this side already: an issue whose title
starts with the configured `titlePrefix` marker (`[GH-`, read from
`config/connectors.json` so a prefix change moves the guard with it) is skipped
green with a `::notice` on every event; the `duplicate` label is checked only on
`opened` and `labeled`, the two events that can create a mirror (a hand-triaged
duplicate that already has a mirror still gets its Done/Todo update on `closed` /
`reopened`). So the closing itself never echoes back into Linear.

### `first-run`: the single entry point

`bash scripts/bootstrap/first-run.sh` (twin: `pwsh scripts/bootstrap/first-run.ps1`)
is the one command for a fresh Cloud Shell, Codespace or workstation. It chains
the existing scripts with every step soft — `cloud-shell-setup.sh --skip-smoke`
(CLI fleet, device-code logins, Cloud Shell persistence) → `auto-login.ps1` →
`scripts/verify/rest-connect.ps1` → `auth-doctor.ps1` → `setup-everything.ps1` →
`provision-github-secrets.ps1` (dry run: repository secrets and variables by
NAME) — writes `.helios/bootstrap-state.json` (gitignored: steps, lanes,
`repoSecrets`, `ownerActions`) and ends with ONE numbered checklist of the steps
only a human can do, each with its exact command: the device-code logins,
`codex login --device-auth`, `claude setup-token`, `set-provider-secrets.ps1`
for the Key Vault values, `gh secret set HELIOS_ADMIN_TOKEN`, the Linear switch.
`--verify-only` is read-only (no installs, no logins, `auto-login` skipped);
`--json` emits the state only; exit 0 when the chain ran (needs-owner lanes are
the checklist, never a failure), 1 only on internal failure.

The two secret writers it points at never take a value on argv or in a log:
`scripts/bootstrap/set-provider-secrets.ps1` (masked prompt or `-FromEnv`; the
value reaches `az keyvault secret set` through a mode-600 temp file with
`--file`, verified by name only) and `scripts/bootstrap/provision-github-secrets.ps1`
(env var of the same name → `gh secret|variable set` over stdin). Both are
dry-run by default with the `-Apply` / exit 0/1/2 contract; the per-script tables
are `scripts/bootstrap/README.md` and `scripts/github/README.md`.

## Connection checklist

| Connection | Owner action required | Secret or setting | Verified by |
|---|---|---|---|
| Actions ↔ Azure | Run `scripts/bootstrap/azure-up.sh`, then `azure-oidc-setup.sh`; set the 3 variables (`provision-github-secrets.ps1 -Apply` from env vars of the same name, or the printed `gh variable set` lines) | Vars `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (optional `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`) | Dispatch **Helios Platform Deploy** from `main` with `what_if=true`; `az role assignment list --assignee <appId> --all` |
| ChatGPT/Codex | Connect the repo in Codex settings at chatgpt.com | None in this repo | Open a PR (auto-review) or comment `@codex review` |
| Copilot reviews + coding agent | Have Copilot enabled for the repo; optionally mint the PAT | Optional secret `COPILOT_DISPATCH_TOKEN` | Open a non-draft PR (review request appears); label an issue `copilot` (agent assigned) |
| Claude | None | None (dev's own `claude` login; `ANTHROPIC_API_KEY` via aihub flow) | `/mcp` in Claude Code; `helios-ai providers` |
| Self-hosted runners | Run `scripts/runners/register-runner.sh` (or `.ps1`) as repo admin, start the runner | Labels `helios,xcore` (+ pool extras, e.g. `xcore-native`) | `gh workflow run runner-smoke.yml`; runner listed in Settings → Actions → Runners |
| Linear | **First** switch Linear's own GitHub issue sync OFF for team John (loop warning above); create a Linear personal API key | Secret `LINEAR_API_KEY` (+ `linear.teamKey` in `config/connectors.json`); `provision-github-secrets.ps1 -Apply` or `gh secret set` | Label an issue `bug` (or another sync label) → `[GH-n]` issue appears in Linear; no new `[GH-` issue appears on GitHub afterwards |
| Slack | Create an incoming webhook | Secret `SLACK_WEBHOOK_URL` (+ `slack.notifyOn` routing); `provision-github-secrets.ps1 -Apply` or `gh secret set` | Re-run any listed workflow; failure/`always` outcomes post to the channel |
| Provider keys (Key Vault) | Run `pwsh scripts/bootstrap/set-provider-secrets.ps1` (dry run), then `-Apply` (masked prompt or `-FromEnv`) after `azure-up.sh` | Vault secrets `openai-api-key`, `anthropic-api-key`, `github-models-token` at `AZURE_KEY_VAULT_URI` (names from `config/aihub.json`) | `. scripts/bootstrap/auto-login.ps1` lights the providers; `helios-ai providers` |
| Control fabric (ruleset, settings, labels, milestones) | Mint the fine-grained PAT (§ Control fabric click path), `gh secret set HELIOS_ADMIN_TOKEN` (or `provision-github-secrets.ps1 -Apply` with the env var set), then — once the workflow is on `main` — `gh workflow run governance-apply.yml -f apply=true -f scope=all`; interim `pwsh scripts/github/apply-rulesets.ps1 -Apply` under an owner `gh auth login`; ruleset only after PR #113's no-path-filter triggers are on `main` | Secret `HELIOS_ADMIN_TOKEN` (Administration/Contents/Issues/Pull requests/Pages RW, Metadata R on this repo only) | Job summary: every row `applied`/`ok`; `gh ruleset list`; `gh label list`; `gh api repos/Yolkster64/helios-platform/milestones` |
| Pages dashboard | Settings → Pages → Source: **GitHub Actions** (or the `pages` item of `apply-repo-settings.ps1` with the PAT), then `gh workflow run pages-dashboard.yml` | Pages `build_type=workflow`; "Allow auto-merge" is its sibling setting, measured already on | `gh api repos/Yolkster64/helios-platform/pages --jq .build_type` reads `workflow` from an owner login (the proxy blocks `/pages`); the dashboard URL in the run summary |
| Branch prune | `gh workflow run branch-prune.yml` (plan), read the summary, then `-f apply=true -f keep=<a,b>` (`-f max_delete=<n>` above 200 deletions) | None (`GITHUB_TOKEN`, `contents: write` + `pull-requests: read`); every stale tip kept as tag `archive/<branch>` | `branch-prune-report` artifact; `git ls-remote --tags origin 'archive/*'` |
| Issue hygiene (#54–#92) | Linear switch OFF first, then `pwsh scripts/github/close-duplicate-issues.ps1 -Apply` from an owner login or the PAT | None stored (`duplicate` label from the manifest) | Dry run reports 0 candidates; `gh issue list --label duplicate --state closed` |
| Wiki | Create the first page once by hand (Wiki → "Create the first page") so the wiki git repo exists, then `gh workflow run wiki-generator.yml` | `has_wiki` is an `apply-repo-settings.ps1` item (measured already on) | `wiki-generator.yml` stops green-skipping and pushes `docs/` |
| Project board | Run `setup-custom-fields.ps1` then `add-epics-to-board.ps1`, each `-GitHubToken <PAT>` with a classic `project`-scope (+ `repo` read) user PAT (custom fields via API; views/templates/automation are manual UI steps — the scripts only simulate locally; `setup-board.ps1` orchestrates) | PAT passed as `-GitHubToken` or via `GITHUB_TOKEN` (never stored) | `scripts/board-setup/validate-board.ps1` (real GraphQL read of fields/items); board visible under the org's Projects |
