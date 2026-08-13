# GitHub control plane — Projects v2, rulesets, merge policy, wiki/Pages, issues

*Versions and API claims mirror the cited repo files; update this file in the same
PR that changes them.*

## Projects v2 GraphQL: what is automatable — and what is not

Auth first: everything in this section requires a **classic PAT with the
`project` scope** (`docs/architecture/CONNECTIONS_SETUP.md:248-250`); see
`auth-topology.md` surface 2.

### Automatable (working scripts prove it)

| Operation | Mutation/query | Working script |
|---|---|---|
| Create custom fields | `createProjectV2Field` | `scripts/board-setup/setup-custom-fields.ps1:359` |
| Add an issue/PR to the board | `addProjectV2ItemById` | `scripts/board-setup/add-epics-to-board.ps1:179-183` |
| Stamp single-select field values | `updateProjectV2ItemFieldValue` | `add-epics-to-board.ps1:187-194` |
| Resolve the project + fields | `repositoryOwner(login){ projectV2(number) }` | `add-epics-to-board.ps1:124-146`, `validate-board.ps1:82` |

The idioms in `add-epics-to-board.ps1` are the house style for any new
Projects v2 automation:

- **Aliased batch node-id resolution** — one aliased query resolves every
  issue node id in a single round trip (`add-epics-to-board.ps1:199`,
  consumed via alias probing at `:440-442`; gaps in the number range are
  expected and tolerated, `:219`).
- **Paged presence checks to completion** — items are paged 100/page with
  `pageInfo { hasNextPage endCursor }` (`:149-155`, loop at `:360-405`).
- **Abort-before-mutate on incomplete paging** — if item paging cannot be
  completed, exit 1 **before any mutation** (`:15`, enforced at `:358`);
  a partial presence map would cause duplicate adds.
- **Repair only EMPTY fields** — on items already on the board, only empty
  Status/Priority get stamped; existing values are never overwritten
  (`:32`, repair plan at `:466`, skip message at `:497`).

### Not automatable — no API exists

Views, item/phase templates, and the built-in board workflows **cannot be
created or configured via the ProjectV2 GraphQL API**. The three simulation
scripts say so explicitly, make **no** API calls, and instead generate the
manual click-path documentation:

- `scripts/board-setup/setup-views.ps1:3-11` — "LOCAL SIMULATION … GitHub's
  ProjectV2 GraphQL API cannot create or configure [views] … generates the
  manual click-path".
- `scripts/board-setup/setup-automation-rules.ps1:3-14` — built-in workflows;
  click path is Project → menu → "Workflows".
- `scripts/board-setup/setup-templates.ps1:3-7` — item/phase templates.

`docs/architecture/FORWARD_PLAN.md:55-57` (T9) restates the boundary: "board
custom fields + item wiring are real GraphQL; views/templates/automation are
API-impossible and documented as manual click-paths." Any PR claiming to
automate these is wrong by construction — review accordingly.

## Rulesets & branch protection

REST surface: `POST /repos/{owner}/{repo}/rulesets` creates a ruleset,
`PUT /repos/{owner}/{repo}/rulesets/{ruleset_id}` updates one; branch targeting
uses `conditions.ref_name` patterns (e.g. `~DEFAULT_BRANCH`) and required
checks go in a `required_status_checks` rule listing check-run contexts.
Ruleset *enablement* is an owner decision (`FORWARD_PLAN.md:61-62`: "ruleset
enablement is an owner click").

**The job-level check-name rule.** A required status check matches a
*check-run name*, which is the job's `name:` (or the job id when `name:` is
absent — `infra-validate.yml:14` exposes `bicep-validate` that way). Pin the
specific truthful gates:

- `Build solution & run tests` — `.github/workflows/dotnet-build.yml:44`
- `bicep-validate` — `.github/workflows/infra-validate.yml:14`

Never require "everything from the workflow": `dotnet-build.yml` also carries
`.NET 11 preview build (informational, allowed to fail)` — `continue-on-error:
true`, with the comment "keeps it out of the required-checks path, and nothing
may ever `needs:` this job. Never gate required CI on a preview SDK"
(`dotnet-build.yml:228-236`) — and `Legacy core build (informational)`
(`:207`). Requiring either blocks every merge.

**Known-red exclusion list — nothing here may become required**
(`docs/architecture/ROADMAP_MULTI_LLM.md:50-66`): `deploy.yml` (all-echo fake
deploy), `ai-code-review.yml` (regex "AI review"), `nuget.yml` (main/tag lane
builds the broken core), `build-variant-test.yml` (Node matrix in a .NET
repo), the nested `microsoft-ecosystem/.github/workflows/azure-deploy.yml`
(never runs), `publish-to-packagemanagers.yml` and
`documentation-update.yml` (invalid YAML — cannot even parse),
`build-all-modules.yml` / `multi-repo-sync.yml` (reference structures that
don't exist), the `ci-validation.yml` markdownlint step (missing config), and
`azure-pipelines.yml` (git-ignored starter). The standing rule: "nothing new
may depend on a known-red item" (`ROADMAP_MULTI_LLM.md:66-67`).

`docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md:23-26` sets the new-repo
convention (protect `main`, require the build/infra gates from day one, no
repo goes live with a red default-branch check).

## Auto-merge & merge queue

`gh pr merge --auto` arms GitHub's native auto-merge: the PR merges when all
required checks and reviews pass. Prerequisite: the repository setting
**"Allow auto-merge"** (Settings → General) — an owner click; without it the
command errors. With no required checks configured, `--auto` degrades to an
immediate merge, which is why rulesets (above) come first.

The scope boundary this repo draws:

- **Session-stewarded PRs may auto-merge** once the review loop converges —
  see `docs/architecture/REVIEW_LOOP.md` for the stopping rule.
- **Absorption-pipeline candidates NEVER auto-merge**: "the pipeline produces
  evidence and staged worktrees" — a human merges
  (`docs/architecture/ABSORPTION_PIPELINE.md:50`).
- **claude-foundry implementation patches open as drafts**
  (`gh pr create --draft`, `.github/workflows/claude-foundry.yml:303-308`);
  the PR body states "No automatic merge or Azure deployment is requested by
  this workflow" (`:300`).
- **Never let an agent-authored PR merge on a red or skipped check**
  (`GITHUB_ECOSYSTEM_DESIGN.md:74-75`).

Merge queue: deliberately deferred — "merge-queue evaluation once required
checks stabilize" (`FORWARD_PLAN.md:59`). Do not enable it while required
checks are still being trued up; a queue amplifies a flaky gate into a stalled
main.

## Wiki automation — real, with one manual prerequisite

`.github/workflows/wiki-generator.yml` is a working publisher, not an
aspiration:

- Clones the wiki repo with the Actions token:
  `git clone https://x-access-token:${GH_TOKEN}@github.com/${REPO}.wiki.git`
  (`wiki-generator.yml:50`) — `contents: write` is what authorizes pushes to
  `<repo>.wiki.git`, since the wiki is part of the repository for permission
  purposes (`:26-29`).
- Flattens `docs/architecture/*.md` → `Architecture-<NAME>.md` and
  `docs/mcp/*.md` → `Mcp-<NAME>.md`, removing previously synced pages first so
  renames don't strand stale wiki pages (`:63-75`).
- Generates `_Sidebar.md` from the synced page set (`:77-94`) and
  commits-if-changed so re-runs are no-ops (`:98-113`).

**One-time materialization prerequisite**: GitHub only creates
`<repo>.wiki.git` when the first wiki page is created in the UI. The workflow
detects the missing repo and exits green with the `::notice::` naming that one
manual step (`wiki-generator.yml:54`, design note `:14-16`). Until the owner
clicks once, every sync is a green no-op — a "successful" run is not proof
the wiki exists.

The wiki is a mirror: `docs/architecture/` is the source of truth, no
hand-edited wiki pages (`GITHUB_ECOSYSTEM_DESIGN.md:65-66`).

## GitHub Pages — being added in this tranche

The Pages publication job is T9 work (`FORWARD_PLAN.md:60-61` names "the
wiki/Pages publication job") and is **being added in this tranche** — do not
cite a Pages workflow as existing until it lands. The Actions-based Pages
contract to hold it to: `actions/configure-pages` +
`actions/upload-pages-artifact` + `actions/deploy-pages`, with the deploy job
declaring `permissions: pages: write` and `id-token: write` and an
`environment: github-pages`; the repo's Pages setting must be set to
"GitHub Actions" as the source (owner click, same class as wiki
materialization above).

## Issues automation surfaces

- **`copilot-dispatch.yml`** — two directions, both degrade-not-fail
  (`copilot-dispatch.yml:10-14`):
  - Issues: adding the `copilot` label IS the delegation decision (`:3-6`,
    gate at `:33`). The job resolves `suggestedActors(capabilities:
    [CAN_BE_ASSIGNED])` and proceeds only if `copilot-swe-agent` is
    assignable (`:52-69`), then assigns via the
    `replaceActorsForAssignable` mutation (`:71-75`). Remove the label /
    unassign to take the work back (`:6`).
  - PRs: every non-draft PR gets a Copilot review requested — the job filters
    `github.event.pull_request.draft == false` (`:85`) and POSTs
    `{"reviewers":["copilot-pull-request-reviewer[bot]"]}` to
    `/repos/{repo}/pulls/{n}/requested_reviewers` via curl (`:94-98`),
    treating anything but HTTP 201 as a skip-notice (`:99-103`).
- **`linear-sync.yml`** — one-directional by design: GitHub is the source of
  truth, Linear-side edits are not synced back (`linear-sync.yml:3-6`);
  without `LINEAR_API_KEY` every run skips green (`:6`); per-issue
  concurrency queues rather than cancels so racing label events cannot
  double-create Linear issues (`:15-22`).
- The multi-LLM review choreography on top of these surfaces:
  `docs/architecture/REVIEW_LOOP.md`.
