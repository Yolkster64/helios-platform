# Connections Setup — GitHub ↔ Everything

The one-page wiring guide: every external connection this repo has, what carries it,
what the owner must click, and how to prove it works. Design rationale lives in
[`GITHUB_ECOSYSTEM_DESIGN.md`](GITHUB_ECOSYSTEM_DESIGN.md); the owner's day-one
checklist (including the GitHub settings pages) is
[`../OWNER_START_HERE.md`](../OWNER_START_HERE.md). Hard rule everywhere below:
**no secrets in the repo** — config files carry env-var *names* only.

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
| OpenAI (`codex`) | `codex` cliAgent (`codex exec {prompt}`) | Local browser: `codex login`; headless interactive session: `codex login --device-auth` when device login is enabled; approved API credentials remain a separate usage-based option |

### One command, everything

`pwsh scripts/bootstrap/setup-everything.ps1` chains the whole bring-up in order,
calling only the existing scripts: `verify-readiness.ps1` (toolchain) →
`connect-account.ps1` (identity) → `auth-doctor.ps1` (auth; `-Apply` passes
through) → `setup-all.ps1` (inventory) → `scripts/verify/stack-smoke.ps1` (soft
smoke), ending in one consolidated, deduped owner-action list (`-Json` for the
machine rollup). The identity gate is hard: any `connect-account` mismatch aborts
the chain immediately with exit 2 — acting as the wrong account is worse than
acting unauthenticated. Report-first by default: nothing is mutated without
`-Apply`, and even then repair is auth-doctor's non-interactive lane only.

Read `ready` separately from `executionSucceeded`: an exit-zero report can still
contain `needs-owner`, `build-missing`, unavailable checks, or unknown states.
`readinessIssues` preserves these gaps, and `ownerActions` includes both top-level
actions and per-lane/component commands. To make incomplete readiness fail an
automation gate without repairing accounts:

```powershell
pwsh scripts/bootstrap/setup-everything.ps1 -Json -RequireReady
```

`-RequireReady` returns 2 for incomplete readiness; internal failures still return
1 and identity mismatches still return 2. Without it, the existing report-first
exit contract is retained. Readiness covers the checks performed by child scripts;
it does not certify provider inference, remote MCP authentication, or deployment.

For Codex, ChatGPT subscription login and OpenAI API authentication are distinct.
A connector session also does not authenticate a workstation CLI. Verify the local
CLI with `codex login status`; device login requires the corresponding account or
workspace setting. See the [official Codex authentication guide](https://learn.chatgpt.com/docs/auth).

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
only — never values). Each `enabled` flag controls its workflow. Disabled
connectors skip; enabled connectors with missing credentials or failed delivery
fail their own workflow so an unconnected integration cannot look ready.

| Connection | Secret | Workflow | Fires when |
|---|---|---|---|
| Linear | `LINEAR_API_KEY` | `.github/workflows/linear-sync.yml` | Issue `opened`/`edited`/`labeled`/`unlabeled`/`closed`/`reopened` **and** the issue carries a `linear.syncLabels` label (`bug`, `enhancement`, `infra`, `ai-hub`, `absorption`, `build-ci`); `unlabeled` also proceeds when the *last* sync label was just removed, so the mirror's labels empty instead of freezing |
| Slack | `SLACK_WEBHOOK_URL` | `.github/workflows/notify-slack.yml` | `workflow_run` completion of the six workflows listed in it, filtered by `slack.notifyOn` (`always` vs `failures-and-recovery`) |

Linear sync is one-directional (GitHub is the source of truth): mirrored issues
get a `[GH-<n>]` title prefix into team `JOH` (`linear.teamKey` — must match
your Linear workspace's team key or the sync fails), label mapping
per `githubLabelToLinear`, and close/reopen moves the Linear state. Enable
with `gh secret set LINEAR_API_KEY` / `gh secret set SLACK_WEBHOOK_URL`;
notification policy and label mappings live in `config/connectors.json`.
The configured env names must match the fixed Actions secret bindings.

The incoming webhook posts to its Slack installation channel; the `channels`
names and `SLACK_BOT_TOKEN` are reserved service metadata and do not redirect
this webhook. `failures-and-recovery` compares the preceding run on the same
workflow, branch, event, and source repository (or the previous rerun attempt).
Routine successes stay quiet; a success following a failure sends a recovery.

Linear reads current issue data before mutation, stops on GraphQL errors even
with HTTP 200, and detects ambiguous mirrors in the configured team. Title and
label changes update the existing mirror; state changes use current GitHub
state. Repeated state events do not append duplicate comments. Full production
worker idempotency and incident threading remain separate work in JOH-52.
See [activation and verification](CONNECTOR_ACTIVATION.md).

> **Owner action — disable Linear's own GitHub sync for team John.** Linear's
> built-in GitHub integration must NOT also be linked to this repository for
> team `JOH`, or the two syncs loop: Linear re-creates its mirrored issues back
> on GitHub as new issues (this produced duplicates #54–#93, closed 2026-08-12,
> and closing the GitHub twins then cancelled the Linear mirrors, which had to
> be restored). Click path: Linear → **Settings → Integrations → GitHub** →
> under the team `John` link, disable issue sync for `Yolkster64/helios-platform`
> (leave PR-link previews on if desired). One direction only: this repo's
> `linear-sync.yml` is the writer; Linear stays the mirror.

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

**Projects v2 needs a user PAT with the `project` scope** (classic token; the
Actions `GITHUB_TOKEN` cannot manage Projects v2) — pass it as `-GitHubToken`
at run time from a workstation; it is a parameter, never a stored setting.
`validate-board.ps1` and `add-epics-to-board.ps1` also fall back to the
`GITHUB_TOKEN` environment variable (name only — the value is never stored or
printed) and print a dry-run plan and exit 0 when it is absent.

## GitHub governance (rulesets, Pages, auto-merge)

The governance artifacts live in the repo — `.github/rulesets/main.json`,
`.github/CODEOWNERS`, `.github/dependabot.yml`, and the PR/issue templates — and
three owner clicks turn them on:

1. **Apply the branch ruleset** — `pwsh scripts/github/apply-rulesets.ps1` first
   (dry run: prints the exact `gh api` POST/PUT calls, changes nothing), then re-run
   with `-Apply` under a `gh` login or PAT with the `admin:repo` scope. Idempotent:
   it GETs existing rulesets and updates by name instead of duplicating; exits 2
   with an explanation when `gh` or auth is missing. The check-name provenance and
   exclusion rationale are in the script's header comment.
2. **Enable GitHub Pages** — Settings → Pages → Source: **GitHub Actions**, so
   `pages-dashboard.yml` can publish the status dashboard that
   `status-dashboard.yml` collects from the real Actions API.
3. **Enable "Allow auto-merge"** — Settings → General → Pull Requests, so
   `auto-merge.yml` can arm merges.

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

## Connection checklist

| Connection | Owner action required | Secret or setting | Verified by |
|---|---|---|---|
| Actions ↔ Azure | Run `scripts/bootstrap/azure-up.sh`, then `azure-oidc-setup.sh`; paste the 3 variables | Vars `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (optional `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`) | Dispatch **Helios Platform Deploy** from `main` with `what_if=true`; `az role assignment list --assignee <appId> --all` |
| ChatGPT/Codex | Connect the repo in Codex settings at chatgpt.com | None in this repo | Open a PR (auto-review) or comment `@codex review` |
| Copilot reviews + coding agent | Have Copilot enabled for the repo; optionally mint the PAT | Optional secret `COPILOT_DISPATCH_TOKEN` | Open a non-draft PR (review request appears); label an issue `copilot` (agent assigned) |
| Claude | None | None (dev's own `claude` login; `ANTHROPIC_API_KEY` via aihub flow) | `/mcp` in Claude Code; `helios-ai providers` |
| Self-hosted runners | Run `scripts/runners/register-runner.sh` (or `.ps1`) as repo admin, start the runner | Labels `helios,xcore` (+ pool extras, e.g. `xcore-native`) | `gh workflow run runner-smoke.yml`; runner listed in Settings → Actions → Runners |
| Linear | Create a Linear personal API key | Secret `LINEAR_API_KEY` (+ `linear.teamKey` in `config/connectors.json`) | Label an issue `bug` (or another sync label) → `[GH-n]` issue appears in Linear |
| Slack | Create an incoming webhook | Secret `SLACK_WEBHOOK_URL` (+ `slack.notifyOn` routing) | Re-run any listed workflow; failure/`always` outcomes post to the channel |
| Project board | Run `setup-board.ps1` with a `project`-scope user PAT (custom fields via API; views/templates/automation are manual UI steps — the scripts only simulate locally); add epics with `add-epics-to-board.ps1` | PAT passed as `-GitHubToken` or via `GITHUB_TOKEN` (never stored) | `scripts/board-setup/validate-board.ps1` (real GraphQL read of fields/items); board visible under the org's Projects |
