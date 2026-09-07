# Absorption and learning program — start here

This is the beginner's guide to the part of HELIOS that watches other repositories,
benchmarks their best pull requests in isolation, scores the results, learns from the
outcomes, and then **proposes** what is worth taking — never merging anything by itself.

It is written for someone who has cloned `Yolkster64/helios-platform` and wants to run
the program end to end in about ten minutes, understand what every file is for, and know
which upstream ideas are worth taking first. Everything here is grounded in the
repository tree at the time of writing and in the GitHub issues and pull requests of
`Yolkster64/helios-platform` as read on 2026-09-06. Where something is planned rather
than present, it says **planned, not yet in the repo**.

Reading time: about 25 minutes for the whole page; the ten-minute path is section 4.

## Contents

- [1. What the program is](#1-what-the-program-is)
- [2. Why it exists](#2-why-it-exists)
- [3. The pieces and where they live](#3-the-pieces-and-where-they-live)
- [4. The easy path in 10 minutes](#4-the-easy-path-in-10-minutes)
- [5. Automatic setup when ready](#5-automatic-setup-when-ready)
- [6. The dashboard](#6-the-dashboard)
- [7. How the fleet joins in](#7-how-the-fleet-joins-in)
- [8. How scoring works](#8-how-scoring-works)
- [9. The best parts to take first](#9-the-best-parts-to-take-first)
- [10. What not to expect](#10-what-not-to-expect)
- [11. Troubleshooting](#11-troubleshooting)
- [12. Glossary](#12-glossary)
- [13. Where next](#13-where-next)

## 1. What the program is

In plain words, the absorption and learning program does five things, in a loop:

1. **Watch.** It keeps a curated list of upstream and sibling repositories and of
   specific pull requests in them that look worth having. The upstream that matters
   most is the historical parent, `M0nado/helios-platform`, whose 195 pull requests
   were distilled into 40 theme "epics". A second, lighter watch covers six
   dependency upstreams (the Windows App SDK, the MCP C# SDK, the actions-runner
   controller, the Hermes agent CLI, Linear's SDK monorepo, and an Azure RAG
   reference) for releases and commit activity.
2. **Benchmark in isolation.** For one candidate pull request at a time, it fetches
   the PR head, trial-merges it onto our branch inside a throw-away git worktree, and
   runs exactly the gate that CI runs: native C++ build, solution build, Bicep compile
   (template and parameters), .NET tests, Python tests. Nothing touches the real
   working tree.
3. **Score.** Each benchmark writes a small JSON report: whether the trial merge was
   clean, which files conflicted, which gate steps passed or failed and how long they
   took, and a one-line verdict.
4. **Learn from outcomes.** The verdict is recorded in the hub's learning store as an
   **advisory** outcome, tagged with where it came from. Advisory outcomes show up in
   the hub's learning reads, insights, and metrics — and are deliberately **excluded**
   from the adaptive routing that picks which model answers which task, so an outside
   signal can never steer provider chains.
5. **Propose, never merge.** A human (or an explicitly tasked agent) reads the report,
   decides, and updates the watchlist status with the reason. Committing absorbed
   code is always a deliberate change through a normal pull request. Two workflows
   (`auto-merge.yml` and `pr-pipeline.yml`) explicitly refuse to auto-merge any
   branch in the absorption lane.

That last point is the program's one unbreakable rule, and it is written down in
`docs/architecture/ABSORPTION_PIPELINE.md` under "Boundaries": **no auto-merge**.

The word "learning" covers two related things. The narrow one is the advisory outcome
each benchmark records. The wider one is the hub's tandem-learning loop, where the
Hermes/Xcore fleet works kanban boards, its finished tasks become learning records, and
the hub reports which provider chains it *would* prefer — again advisory, never
applied on its own. Section 7 covers how the fleet joins in.

## 2. Why it exists

The short history, with the issue and pull request numbers you can open to check:

- **2026-08-10 — PR #4 lands the hub.** The multi-LLM AIHub, CLI, REST API, MCP server,
  the F#/C++/Python spokes, and the Azure Foundry infrastructure arrive in one pull
  request. At that point the upstream `M0nado/helios-platform` still carries months of
  prior work — evaluators, federation contracts, governance gates — that this fork does
  not have, and nobody wants to merge any of it blind.
- **2026-08-10 — PR #13 turns "absorb the best of upstream" into a program.** It adds
  the absorption ledger (then 18 epics, later 40), the curated watchlist, the benchmark
  script and its keyless GitHub Actions twin, the `helios-ai absorb-status` read-only
  view, and the first tranche of ports with benchmark evidence. Its own description
  records the lesson that shaped everything after: **every tranche-1 trial merge
  conflicted**, so tranche 1 ported ideas rather than code.
- **2026-08-10 — issues #14 to #53 are created**, one per epic, so that E-n is issue
  number 13+n (E1 is #14, E40 is #53), all labelled `absorption`. A Linear integration
  loop then created duplicate copies as #54–#93, which is why some later pull requests
  say "Fixes #54" or "Fixes #93" when they mean E1 or E40.
- **2026-08-11 — PR #94** adds the unified `setup-all` readiness entrypoint (epic E1's
  command surface), the `absorption-analyst` agent, two read-only MCP status tools, and
  — after a security review — makes the **keyless hosted benchmark the default lane**
  because the gate executes the candidate PR's own build code.
- **2026-08-12 — the Copilot coding agent executes its first epics.** PR #95 (E34,
  central NuGet versions), PR #96 (E24, CI preflight and action pins), and PR #97 (E32,
  a platform scorecard artifact) each close their epic issue (#47, #37, #45). Small,
  well-bounded epics worked.
- **2026-08-13 — PR #105** ports the E40 developer helper family into PowerShell
  (`scripts/dev/helios.ps1`), and the forward plan (`docs/architecture/FORWARD_PLAN.md`,
  tranche T8) names the next absorption batch as an owner lane run through Copilot and
  the fleet.
- **2026-09-03 — issues #115, #131, #132** write down the missing automation: a weekly
  **absorption cadence workflow** that benchmarks the next candidates and posts verdicts
  on the epics, and **learning + absorption sections on the dashboard**. The milestone
  "Absorption tranche 5" (due 2026-09-27) tracks it.
- **2026-09-06 — PR #191** closes epic E5 (#18): the deploy workflow pins its OIDC
  audience and seals plan/deploy custody records, enforced by a validator and a contract
  workflow. Follow-ups #198 and #199 merge the same day; #197, #196, #190 and #148 stay
  open awaiting owner decisions (issue #229 has the triage table).
- **2026-09-06 — the "Getting started" epic #223** re-sequences the program around
  onboarding. Its sub-issue #231 carries the cadence as "Step 4", #235 asks for the
  cross-LLM learning loop to run with real outcomes, and #242's addendum 4 records the
  owner's ask in his words: absorption-specific setup, smart ranking, feeding the AI
  hub, code-specific tests per candidate with scores.

So the program exists because there is a large body of prior work worth mining, because
blind merges were tried and rejected, and because the owner keeps asking for the same
thing: an easy, evidence-driven way to take the best parts of everything and learn from
it, with the safety rules intact.

## 3. The pieces and where they live

| Piece | Path | What it is for | Who runs it |
| --- | --- | --- | --- |
| Watchlist | `config/absorption/pr-watchlist.json` | The curated upstream PRs (52 entries at the time of writing: 37 `candidate`, 11 `benchmarked`, 4 `absorbed`), each with `epic`, `why`, `absorb` (what to extract) and `risks`. Humans edit the `status`. | You, by hand, in a PR |
| Ledger | `docs/architecture/ABSORPTION_LEDGER.md` | The 40 epics E1–E40 with their upstream PRs, extracts, risks, and status (`open`, `tranche-1`, `audit-first`, `absorbed`). Published to the wiki. | You, by hand, in a PR |
| Pipeline design | `docs/architecture/ABSORPTION_PIPELINE.md` | The four-step loop (curate, benchmark, decide, learn) and the boundaries. | Read only |
| Benchmark script | `scripts/absorption/absorb-pr.ps1` | Fetches `refs/pull/<N>/head`, trial-merges in a disposable worktree, runs the full gate, writes `.helios/absorption/pr-<N>.json`, POSTs an advisory outcome. | You, locally, only on a credential-free host |
| Hosted benchmark | `.github/workflows/absorption-benchmark.yml` | The same script on a keyless runner (`contents: read`, no secrets); report uploaded as the `absorption-report-pr-<N>` artifact (90 days) and written to the job summary. | `gh workflow run absorption-benchmark.yml -f pr_number=<N>` |
| Status view (CLI) | `helios-ai absorb-status` (`src/ai/HELIOS.AIHub.Cli/AbsorptionStatus.cs`) | Read-only JSON: the watchlist merged with any local reports (`verdict`, `benchmarked`). | Anyone; no network |
| Status view (MCP) | `helios_absorb_status_get` (`src/mcp/HELIOS.Mcp/HeliosStatusTools.cs`) | Same view for MCP clients, plus `gatePassed` per candidate and a `warnings` array. | Any MCP client |
| Analyst agent | `.claude/agents/absorption-analyst.md` | The agent definition that runs the loop: curate, benchmark (hosted lane by default), read, record. | An agent session, on request |
| Fleet seeding | `scripts/fleet/seed-absorption-tasks.ps1` | Turns watchlist candidates into kanban tasks (`absorb-pr-<N>`) on a running fleet's `xcore-infra` board. | You, against a real Hermes fleet |
| Tandem learning | `scripts/fleet/learn-fleet.ps1` and `.github/workflows/fleet-learning.yml` | One fleet learning cycle: start, seed, drain, stop, collect outcomes, summarize, advisory plan; the workflow runs a stub cycle weekly (Mondays 04:41 UTC). | You locally; CI weekly |
| Learning store | `.helios/learning/outcomes.jsonl` (config in `config/aihub.json` → `learning`) | Every outcome the hub records, organic and advisory. `adaptiveRouting` is `false`: record-only. | The hub, automatically |
| Learning API | `helios-ai-api`: `GET /v1/learning`, `POST /v1/learning`, `GET /v1/insights`, `GET /v1/metrics` | Read outcomes, ingest advisory outcomes (a `source` is required), analytics, telemetry. Loopback-only unless `HELIOS_API_ACCESS_KEY` is presented as `X-HELIOS-Api-Key`. | The benchmark script and the fleet lane |
| Fork watch | `config/fork-watch.json` and `.github/workflows/fork-observation.yml` | Weekly (Mondays 06:17 UTC) read-only digest of six dependency upstreams; artifact `fork-observation-digest`; a human commits kept digests to `docs/observations/`. | CI weekly; you review |
| Fork inventory | `docs/repository/FORK-INVENTORY-2026-09-05.md` | The sibling repositories and their import rules (hash and license plan, no generated output, no CI machinery). | Read only |
| Status dashboard | `.github/workflows/status-dashboard.yml` → `dashboard.json`; `.github/workflows/pages-dashboard.yml` + `.github/pages/index.html` | Hourly workflow-health table published to GitHub Pages. Learning and absorption sections are **planned** (#132). | CI hourly; owner enables Pages once |
| Cadence workflow | `.github/workflows/absorption-cadence.yml` | **Planned, not yet in the repo** (#131): weekly benchmarks of the next candidates with verdicts posted on the epics. | — |
| Labels and milestone | `config/github/labels.json` (`absorption`, `absorption-candidate`, `copilot`), `config/github/milestones.json` ("Absorption tranche 5") | Applied by `governance-apply.yml`; the `copilot` label on an epic hands it to the Copilot coding agent via `copilot-dispatch.yml`. | Owner |
| Auto-merge guards | `.github/workflows/auto-merge.yml`, `.github/workflows/pr-pipeline.yml` | Refuse to auto-merge any `absorb/*`, `absorb-*`, `absorption/*`, `absorption-*` branch in any path segment. | CI, automatically |

Everything under `.helios/` is git-ignored: reports, worktrees, learning records, fleet
run state. That is by design — the report artifact from the hosted workflow is the
durable copy, and verdicts travel into git by editing the watchlist.

## 4. The easy path in 10 minutes

The path has four steps: verify only, benchmark one entry, read the report, record the
verdict. It needs no Azure login and no provider API key. The only network access is to
`github.com` (public, read-only) for the PR head.

### Step 0 — what you need on the box

| Need | Why | Required? |
| --- | --- | --- |
| Git and a clone of the repository | The trial merge needs real history, not a shallow tip | Yes |
| PowerShell 7 (`pwsh`) | Every automation script | Yes |
| .NET SDK 10 (`dotnet`) | Solution build, tests, `helios-ai absorb-status` | Yes for the local lane and the status view |
| Python 3 with `pytest` | The Python spoke tests in the gate | Yes for the local lane |
| `bash`, `cmake`, `g++` | The native C++ build step of the gate | Yes for the local lane |
| Azure CLI (`az`) with the Bicep extension | `az bicep build` compiles `infra/main.bicep` offline — **no login needed** | Yes for the local lane |
| GitHub CLI (`gh`) logged in | Dispatching the hosted workflow and downloading its artifact | Yes for the hosted lane |

If you only have `gh`, use the hosted lane for step 2; the runner brings its own .NET,
Python, and Bicep. The readiness script in step 1 tells you which of these you have.

### Step 1 — verify only (about 2 minutes)

Run the read-only checks. None of them logs in, installs, or changes anything.

```bash
pwsh scripts/build/verify-readiness.ps1
```

Expected: a table of tools split into required (`dotnet`, `pwsh`, `python3`) and
optional (`bicep`/`az`, `terraform`, `cmake`, `g++`, `docker`), each with version and
path. Exit 0 when every required tool is present, 2 otherwise. Add `-Json` for a
machine-readable object.

```bash
pwsh scripts/setup/setup-all.ps1
```

Expected: one inventory table — toolchain, GitHub and Azure auth state (verify-only
probes, never a login), the AI CLI fleet, fleet topology, MCP registration — with a
next-command per gap. Exit 0 ready, 2 attention needed. This is the E1 command surface
the program itself absorbed.

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- absorb-status
```

Expected: JSON shaped `{ "upstream", "total", "by_status", "candidates": [...] }`. On a
fresh clone `by_status` counts the watchlist statuses and every candidate's `verdict`
is absent, because no report exists yet under `.helios/absorption/`. The first build
takes a minute; later runs are instant.

Optional, if you are the owner: `pwsh scripts/bootstrap/first-run.ps1 -VerifyOnly`
runs the whole bring-up chain read-only and ends with the numbered checklist of the
steps only a human can take (repository secrets are probed **by name**, never by value).

### Step 2 — benchmark one watchlist entry (about 5 minutes of waiting)

Pick a small candidate for your first run. `#117` ("Update wiki sync workflow", epic
E17) is a good teaching example: it is small, touches a workflow rather than product
code, and the watchlist already expects "likely reject after review", so you will see a
complete verdict cheaply. `#220` (E11, the reliability evidence harness) and `#294`
(E2, the runtime matrix) are good second and third runs.

**Hosted lane (default, keyless):**

```bash
gh workflow run absorption-benchmark.yml -f pr_number=117
gh run list --workflow absorption-benchmark.yml --limit 1
gh run watch <run-id>
gh run download <run-id> -n absorption-report-pr-117 -D .helios/absorption
```

The workflow checks out full history, sets up .NET 10, Python 3.12 and Bicep, sets
`HELIOS_REQUIRE_PYTHON_SPOKE=1` (so a candidate that breaks the C#-to-Python contract
cannot score green) and `HELIOS_ABSORB_ACCEPT_CREDENTIALS=1` (the runner has no
secrets, so the script's credential guard is satisfied by design), runs the script,
and treats **exit 2 as a valid outcome** — conflicts or a red gate are results, not
workflow failures. The job summary shows the verdict; the artifact holds the report.

**Local lane (only on a credential-free host):**

```bash
pwsh scripts/absorption/absorb-pr.ps1 -PrNumber 117
```

The gate executes the merged tree's own build code — the candidate's `build-native.sh`,
its MSBuild targets, its pytest configuration — with your environment and your home
directory. So the script **refuses with exit 3** when it finds any of the well-known
credential env vars set (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GITHUB_MODELS_TOKEN`,
`AZURE_OPENAI_API_KEY`, `HELIOS_API_ACCESS_KEY`, `GH_TOKEN`, `GITHUB_TOKEN`), any
credential store on disk (the `gh` config directory, `~/.azure`, `~/.ssh`, `~/.aws`,
Docker or kube configs, git credential files), or a configured git credential helper.
It prints the names, never the values, and points you at the hosted lane. Override
flags exist (`-AcceptCredentialExposure`, or `HELIOS_ABSORB_ACCEPT_CREDENTIALS=1`) and
mean exactly what they say; do not set them on a workstation with live keys.

Useful switches: `-SkipTests` gives at most a partial verdict (a fast conflict scan);
`-Apply` keeps the staged worktree at `.helios/absorption/wt-pr-117` so you can inspect
and cherry-pick deliberately; `-Upstream owner/repo` benchmarks a different upstream.

### Step 3 — read the report (about 2 minutes)

```bash
python3 -m json.tool .helios/absorption/pr-117.json
```

You are looking at nine fields. Section 8 explains each; the short version:

- `verdict` — one sentence, one of four shapes: absorbable, conflicts, partial, or
  gate failed.
- `gatePassed` — `true` only when the trial merge was clean, every step passed, and
  tests were not skipped.
- `steps[]` — `trial-merge` (with `conflicts[]` and `diffstat`), then `native-build`,
  `dotnet-build`, `bicep-build`, `bicep-build-params`, `dotnet-test`, `pytest`, each
  with `ok`, `seconds`, and `error` (the last lines of output) when it failed.
- `prHead` and `ourHead` — the two commits that were combined, so the result is
  reproducible.

A conflict list is not a failure of the program; it is the most common and most useful
result. It tells you which files upstream and this fork both changed, which is exactly
where "port the idea, not the code" applies.

### Step 4 — record the verdict (about 1 minute)

1. Open `config/absorption/pr-watchlist.json`, find the entry for `"pr": 117`, and move
   `"status"` from `candidate` to `benchmarked` — or straight to `rejected` if the
   report and your reading settle it. Add a `"reason"` field in one sentence (the
   `#101` entry shows the precedent), or `"absorbedInto"` when something was ported.
2. Run `dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- absorb-status` again
   and confirm the candidate now shows its `verdict` and `benchmarked` timestamp (the
   report file was read from `.helios/absorption/`).
3. If a whole epic changed state, update its status line in
   `docs/architecture/ABSORPTION_LEDGER.md` too, and say so on the epic issue.
4. Open a pull request with the watchlist (and ledger) change. Paste the verdict line
   and the conflict list into the PR body — the report file itself is git-ignored, and
   the hosted artifact expires after 90 days.

That is the whole loop. Repeat per candidate; batch it through the fleet (section 7) or,
once it exists, the cadence workflow (section 5).

### What needs Azure and what does not

| Activity | Azure login | Provider API keys | GitHub |
| --- | --- | --- | --- |
| Verify-only checks (step 1) | No | No | `gh` optional (the auth probe reports "not logged in" honestly) |
| Hosted benchmark (step 2) | No | No | `gh` login to dispatch and download |
| Local benchmark (step 2) | No — `az bicep build` compiles offline | No — and the script refuses if it finds any | No — the PR head is fetched anonymously |
| Reading and recording (steps 3–4) | No | No | A PR to land the watchlist change |
| Advisory POST to `/v1/learning` | No | No | No — needs only a running `helios-ai-api` on loopback; skipped silently otherwise |
| Fleet batch benchmarking | No | No (credential-free host required) | No |
| Azure learning backend (optional) | Yes — `deployLearningStorage=true` on `infra/main.bicep`, then `AZURE_LEARNING_TABLE_ENDPOINT` | No | No |
| Cross-LLM outcomes for the learners (issue #235) | Only for the Azure providers | Yes, by env-var name or Key Vault | `gh` for the `github-models` lane |

## 5. Automatic setup when ready

"Automatic" here means two different things, and it is worth keeping them apart:

- **What runs on its own today**: the hosted benchmark on dispatch, the fleet learning
  cycle weekly, the fork observation digest weekly, the status dashboard hourly, the
  Pages publish after each dashboard run, the Slack notification on each Absorption
  Benchmark completion (when the webhook secret exists), the Copilot coding agent when
  the owner labels an epic `copilot`, and the auto-merge guards on every PR.
- **What is planned**: `absorption-cadence.yml` (#131) picking the next N `candidate`
  watchlist entries each week, running the benchmark, posting the verdict on the owning
  E-epic issue, flipping the watchlist status, and labelling promising ones
  `absorption-candidate`; plus learning and absorption sections in `dashboard.json`
  (#132). Both are tracked under #115 and by the "Absorption tranche 5" milestone (due
  2026-09-27), and restated in #231 as "Step 4". **Planned, not yet in the repo.**

### What "ready" means

Nothing below is a secret value in the repository; the table names identities, labels,
and switches, and where they are checked.

| Readiness item | Needed for | Where it is set | How to check without changing anything |
| --- | --- | --- | --- |
| The workflow files on `main` | Hosted benchmark, fleet learning, fork watch, dashboard | Already in `.github/workflows/` | `gh workflow list` |
| Actions enabled with `contents: read` | Every lane above; none needs write | Repository default | `gh workflow view absorption-benchmark.yml` |
| Labels `absorption`, `absorption-candidate`, `copilot` | Epic tracking; the planned cadence's "promising" label; Copilot delegation | `config/github/labels.json`, applied by `governance-apply.yml` with the workflow token | `gh label list` |
| Milestone "Absorption tranche 5" | Grouping the cadence work | `config/github/milestones.json`, applied by `governance-apply.yml` | `gh api repos/Yolkster64/helios-platform/milestones` |
| Secret `SLACK_WEBHOOK_URL` (name only) | Verdict notifications from `notify-slack.yml` | Actions secret, set by the owner | `pwsh scripts/bootstrap/first-run.ps1 -VerifyOnly` reports repository secrets by name |
| Secret `HELIOS_ADMIN_TOKEN` (name only) | Rulesets, Pages source, and repository settings via `governance-apply.yml`; labels and milestones work without it | Actions secret, set by the owner (`docs/OWNER_START_HERE.md` § 6) | Same as above |
| Copilot coding agent enabled | Handing an epic to Copilot with the `copilot` label | Settings → Copilot; optional `COPILOT_DISPATCH_TOKEN` | `copilot-dispatch.yml` green-skips with a notice when unavailable |
| Pages source = GitHub Actions | The public dashboard | Settings → Pages (one click) or the `pages` item of the governance apply | `pages-dashboard.yml` green-skips with the exact click path until then |
| A running `helios-ai-api` on loopback | Recording advisory outcomes from local benchmarks | `dotnet run --project src/ai/HELIOS.AIHub.Api` | `pwsh scripts/verify/rest-connect.ps1 -Json` |
| A real Hermes fleet (`workerKind: hermes`) on a credential-free host | Batch benchmarking through the fleet | The Hermes CLI on PATH before `start-fleet.ps1` | `pwsh scripts/fleet/fleet-status.ps1` and the run manifest |
| `AZURE_LEARNING_TABLE_ENDPOINT` (optional) | `learning.mode=azure` or `hybrid` | Output of the `learning-storage` Bicep module | `helios-ai status` |

The two lane doctors are `pwsh scripts/bootstrap/auth-doctor.ps1` (report-only by
default; one row per auth lane with the exact owner action) and
`pwsh scripts/bootstrap/first-run.ps1 -VerifyOnly` (the full read-only chain, writing
`.helios/bootstrap-state.json` and printing the owner checklist). Neither prints a
credential value.

### Turning the cadence on

Today the cadence is manual and per PR. The commands that "turn it on" are:

```bash
# one benchmark, hosted and keyless
gh workflow run absorption-benchmark.yml -f pr_number=<N>

# a fast conflict scan only (partial verdict)
gh workflow run absorption-benchmark.yml -f pr_number=<N> -f skip_tests=true

# hand an epic to the Copilot coding agent (the label IS the decision)
gh issue edit <epic-number> --add-label copilot

# the weekly fleet learning cycle, on demand
gh workflow run fleet-learning.yml -f task_count=12

# the weekly fork digest, on demand
gh workflow run fork-observation.yml
```

When `absorption-cadence.yml` lands (planned), the intended dispatch is
`gh workflow run absorption-cadence.yml -f count=<N> -f epic=<E-n>` with the same
never-auto-merge rule: it posts verdicts and flips statuses; a human still decides what
to port, and Copilot only takes an epic the owner labelled. Its job summary is meant to
list the PRs benchmarked and their verdicts.

## 6. The dashboard

### What is published today

`status-dashboard.yml` runs hourly (at :23 UTC, off the :00 spike) and on dispatch. It
never checks out or commits anything: it queries the GitHub Actions REST API for the
repository's workflows and the 100 most recent runs, and computes one `dashboard.json`:

```json
{
  "generated_at": "…",
  "repository": "Yolkster64/helios-platform",
  "runs_sampled": 100,
  "source": "GitHub Actions REST API; success rate covers only the sampled window",
  "workflows": [
    { "name": "Absorption Benchmark", "path": ".github/workflows/absorption-benchmark.yml",
      "state": "active", "latest_status": "completed", "latest_conclusion": "success",
      "last_run_at": "…", "runs_in_window": 1, "completed_in_window": 1,
      "success_rate_pct": 100, "html_url": "https://github.com/…" }
  ]
}
```

The same table lands in the job's step summary, so you can read it without Pages.
`pages-dashboard.yml` runs after every successful Status Dashboard run (or on dispatch,
reusing the newest successful run's artifact), copies `.github/pages/index.html` next
to `dashboard.json`, and deploys both to GitHub Pages. The page is one table:

| Column | Meaning |
| --- | --- |
| Workflow | Name, linked to the workflow's page |
| State | `active` or `disabled_manually` |
| Latest run | Conclusion of the most recent run: `success`, `failure`, `in_progress`, or "no recent runs" |
| Success rate (window) | Successful completed runs over completed runs, in the sampled window only |
| Completed / seen | Runs that finished versus runs seen in the window |
| Last run (UTC) | Start time of the latest run |

Where to click: the repository's **Actions** tab → **Status Dashboard** → latest run →
the step summary; or, once Pages is enabled, the Pages URL printed by the
`github-pages` environment on the **Pages Dashboard** run. Enabling Pages is a one-time
owner click (Settings → Pages → Build and deployment → Source: GitHub Actions), after
which `gh workflow run pages-dashboard.yml` publishes the first page instead of waiting
for the next hourly cycle. Until then the deploy green-skips with a notice.

For the absorption program specifically, the rows that matter today are **Absorption
Benchmark** (was the last benchmark green — remember exit 2 is reported as a successful
workflow run with the verdict in the summary), **Fleet Learning (informational)**,
**Fork Observation**, and **Deploy Hardening Contract** (the E5 validator).

### What the absorption and learning sections will show

**Planned, not yet in the repo** (#132, under #115): two more sections in
`dashboard.json`, rendered by the same page.

| Section | Intended content | Data source that exists today |
| --- | --- | --- |
| `absorption` | Watchlist counts by status; the last verdicts with PR number, epic, and `gatePassed`; the candidates labelled `absorption-candidate` | `helios-ai absorb-status` / `helios_absorb_status_get` (the same JSON shape), plus the hosted report artifacts |
| `learning` | Outcome counts per provider and task type with the advisory share; the top insights narrative; per-provider success and latency | `GET /v1/learning`, `GET /v1/insights`, `GET /v1/metrics` (`AdvisoryCount` per provider is already computed) |

Two honest constraints shape the design. The dashboard collector runs in CI with no
`helios-ai-api` and no learning store, so the `learning` section will need either an
exported outcomes artifact or an API reachable through identity-aware ingress; and the
`absorption` section can be built from the watchlist in git plus artifacts alone, which
is why it is the easier half.

## 7. How the fleet joins in

The Hermes/Xcore fleet (design: `docs/architecture/HERMES_FLEET_AND_XCORE.md`) is four
specialized pools, each with its own kanban board, tool grant, and provider chain:

| Pool | Board | Task types | Tools | Role in this program |
| --- | --- | --- | --- | --- |
| `xcore-9-code` | `xcore-code` | code generation, refactoring, test creation | read/write | Porting an accepted extract, when explicitly tasked |
| `xcore-9-infra` | `xcore-infra` | infrastructure, pipeline and config authoring | read/write | **Runs the absorption benchmarks** (seeded tasks) |
| `xcore-9-review` | `xcore-review` | code review, security, long-context analysis | **read-only** | Reviews the benchmark reports; judges, never authors |
| `xcore-9-native` | `xcore-native` | native optimization, rendering, GUI | read/write, local only | Not used by the program |

### Seeded absorption tasks

`scripts/fleet/seed-absorption-tasks.ps1` turns watchlist candidates into board tasks
whose prompt is the benchmark command for one PR. Task ids are deterministic
(`absorb-pr-<N>`), so re-seeding after you add watchlist entries is safe: existing ids
are skipped. It enqueues through the lock-aware enqueue against a **running** fleet
run's board (the latest `running` run, or `-RunId`), never by editing a board file.

```bash
pwsh scripts/fleet/start-fleet.ps1 -Fleet xcore-9-infra -PoolSize 1
pwsh scripts/fleet/seed-absorption-tasks.ps1 -DryRun -Max 2        # plan only
pwsh scripts/fleet/seed-absorption-tasks.ps1 -Epic E14 -Max 3      # enqueue 3 E14 candidates
pwsh scripts/fleet/fleet-status.ps1                                 # workers and board tallies
pwsh scripts/fleet/stop-fleet.ps1
```

Filters: `-Epic E<n>` (one ledger epic), `-Status benchmarked` (re-queue after a base
change), `-Max` (cap — each benchmark is a full build-and-test gate, and uncapped
seeding starves the infra pool's other lanes), `-Board` (default `xcore-infra`).

**The stub caveat, stated plainly.** When the Hermes CLI is not on PATH, `start-fleet`
falls back to a Python stub worker that claims tasks and marks them `done` as
`stub-completed` **without executing anything**. Seeding absorption tasks onto a stub
fleet consumes them with no gate run and no report, and their deterministic ids then
block re-seeding into that run. Seed only when the run manifest says
`workerKind: hermes`; on a stub fleet, dispatch the hosted benchmark once per PR
instead. Real Hermes workers execute benchmarks locally on the fleet host, so the fleet
inherits the same credential rule as the local lane.

### Tandem learning

The fleet feeds the hub's learning store without ever steering it. One cycle:

1. A fleet run works its boards; every task ends `done` or `blocked`.
2. `python3 -m helios_agents fleet-collect --run-dir <runDir> --outcomes .helios/learning/outcomes.jsonl`
   turns finished tasks into learning records tagged `source: "fleet-lane"` with
   provider `pool:<name>`; a sidecar ledger keeps re-collection idempotent.
3. `python3 -m helios_agents fleet-summary` reports per-pool tasks, blocked count, and
   block rate, correlated with scaling decisions in `.helios/fleet/scale-log.jsonl`.
4. `helios-ai fleet-plan --json` (MCP twin `helios_fleet_plan_get`) scores each pool's
   configured provider chain against the order the hub's learned routing would prefer
   — from organic hub history only — and reports it. Nothing is applied.

`pwsh scripts/fleet/learn-fleet.ps1` runs the whole cycle (`-DryRun` to see the plan,
`-SeedSynthetic 12` by default, `-RunId` to attach) and writes
`.helios/fleet/learning-report.json` shaped `{at, runId, seeded, drained, collected,
summary, fleetPlan}`. The weekly `fleet-learning.yml` lane runs a **stub** cycle: a
green run proves the wiring — boards, claims, terminations, the collection contract —
never model quality. It is informational by contract and must never become a required
check.

### Scores the fleet produces

From a stub fleet: none that mean anything (every task is `done` by construction). From
a real Hermes fleet: one advisory record per task with `success` = the task finished
rather than blocked, `latencyMs` = claim-to-resolve wall time, `model` empty, `costUsd`
0, `quality` null. Absorption tasks on the fleet also produce the ordinary benchmark
report per PR, because the task prompt is the benchmark command itself.

## 8. How scoring works

There are three scoring surfaces. They use different words on purpose, so it is worth
seeing them side by side.

### The benchmark report

Written by `absorb-pr.ps1` to `.helios/absorption/pr-<N>.json`:

| Field | Type | Meaning |
| --- | --- | --- |
| `upstream` | string | The repository the PR came from (default `M0nado/helios-platform`) |
| `pr` | number | The upstream PR number |
| `prHead` | sha | The PR head commit that was fetched |
| `ourHead` | sha | Our `HEAD` at benchmark time |
| `benchmarked` | ISO-8601 UTC | When the run started |
| `gatePassed` | boolean | `true` only when every step passed **and** tests were not skipped |
| `steps[]` | array | One entry per step: `step`, `ok`, `seconds`; `trial-merge` adds `conflicts[]` and `diffstat`; a failed step adds `error` (the last lines of its output) |
| `verdict` | string | One of the four shapes below |
| `worktree` | path or null | The kept worktree when `-Apply` was used |

The four verdict shapes, and what to do with each:

| Verdict | Means | Next |
| --- | --- | --- |
| `absorbable: trial merge clean and full gate green` | Nothing conflicted and the whole gate passed on the merged tree | Read the diff anyway; decide what to port; `-Apply` to stage |
| `conflicts in <k> file(s): manual reconciliation required` | Upstream and this fork both changed those files; nothing else ran | Read the conflict list; port the idea, not the code |
| `partial: merge and build clean, but -SkipTests ran — rerun without it for a full verdict` | Fast scan only | Re-run without `-SkipTests` before recording |
| `gate failed on the merged tree: see steps` | Merge was clean but a build or test step went red | Read the failing step's `error`; often a layout mismatch, not a bad idea |

Exit codes: 0 gate passed; 2 gate not fully green (a valid outcome); 3 refused because
the host carries credentials; 1 the PR head could not be fetched.

An illustrative report (not a recorded run — the numbers are made up to show the shape):

```json
{
  "upstream": "M0nado/helios-platform",
  "pr": 220,
  "prHead": "0123456789abcdef0123456789abcdef01234567",
  "ourHead": "82d4c55f0000000000000000000000000000abcd",
  "benchmarked": "2026-09-06T15:04:05.0000000Z",
  "gatePassed": false,
  "steps": [
    { "step": "trial-merge", "ok": false,
      "conflicts": [ "README.md", ".github/workflows/dotnet-build.yml" ],
      "diffstat": "41 files changed, 2210 insertions(+), 18 deletions(-)" }
  ],
  "verdict": "conflicts in 2 file(s): manual reconciliation required",
  "worktree": null
}
```

Reading it: the two conflicting files are the README and the build workflow — both
places this fork rewrote heavily — so the harness itself (the 39 other files) is very
likely portable. That is a "port the idea" result, and a good one.

### The advisory learning record

After writing the report, the script POSTs one outcome to `/v1/learning`:

```json
{
  "taskType": "absorption",
  "source": "absorption-benchmark",
  "provider": "M0nado/helios-platform#220",
  "model": "0123456789ab",
  "success": false,
  "latencyMs": 412000
}
```

The record lands in the store as a `RoutingOutcome` (`src/ai/HELIOS.AIHub/Learning/LearningStore.cs`)
whose fields are `outcomeId`, `timestamp`, `taskType`, `language` (optional — the
routing language dimension, omitted when null; `docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`),
`provider`, `model`, `success`, `latencyMs`, `costUsd`, `quality` (0 to 1, or null),
`pool`, and `source`. Three rules follow from `source`:

- A `source` is **required** for anything posted from outside the hub; a missing
  `source` is a rejected request, not a silently organic record.
- Any record with a non-null `source` is **excluded from adaptive routing**
  (`ChainReorderEngine.OrganicOnly` filters the history the reorder engines see), so
  absorption, fork-digest, and fleet-lane signals inform people and never steer
  provider chains. Adaptive routing is off anyway (`config/aihub.json` →
  `learning.adaptiveRouting: false`); this rule holds even when it is turned on.
- Advisory records **are** included in `GET /v1/metrics` (each provider row reports
  `advisoryCount`) and in `/v1/insights` narratives, because a dashboard should show
  everything the store recorded.

Today the benchmark sets no `quality`. The owner's ask on #242 (addendum 4) is a
per-language rubric — C#, F#, C++, Python, PowerShell, Bicep — as a
`config/absorption/scoring.json` that the benchmark applies, so a C++ candidate is
judged on sanitizer and interop results and a Bicep one on what-if and lint. **Planned,
not yet in the repo.**

### The ledger and watchlist statuses

| Level | Values | Who moves it |
| --- | --- | --- |
| Watchlist entry (`status`) | `candidate` → `benchmarked` → `absorbed` or `rejected` | A human, after reading the report, with a `reason` |
| Ledger epic (status line) | `open`, `tranche-1` (a first pass landed), `audit-first` (documentation before any code), `absorbed` | A human, when a tranche completes; mirrored on the issue |
| GitHub issue | open / closed as completed | The owner, or the PR that says "Fixes #n" |

A port is marked landed only when its files exist at the branch head with the benchmark
report as evidence and CI validates them — the ledger's own rule in its "Coverage"
section.

## 9. The best parts to take first

Ranked by value against risk, with the evidence for each. "Landed" means the files are
on `main`; "candidate" means a watchlist entry with no report yet.

| Rank | What | Epic / candidates | Value | Risk | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | **Keep the evidence loop itself as the way work enters the repo** — watchlist, hosted benchmark, status view, never-auto-merge | Program (PR #13, #94) | Everything else depends on it; it is what turned 195 upstream PRs into a decidable list | None — landed and enforced by `auto-merge.yml` and `pr-pipeline.yml` | PR #13 description; `.github/workflows/absorption-benchmark.yml`; the credential guard in `absorb-pr.ps1` |
| 2 | **Small, bounded epics through the Copilot coding agent** — the pattern of #95/#96/#97 and #191 | E34 (#47), E24 (#37), E32 (#45), E5 (#18) | Four epics closed with real files: `Directory.Packages.props`, the `preflight` job in `ci-validation.yml`, `scripts/build/minimal-platform-scorecard.py`, `scripts/validation/validate_deploy_custody.py` | Low when scoped; the counter-example is #197's 686-file churn and the ten zero-diff shells #229 found | PRs #95, #96, #97, #191 (merged); issue #229's triage table |
| 3 | **Readiness and developer helpers** — `verify-readiness.ps1`, `setup-all.ps1`, `helios.ps1 verify/pr-update/prune-generated`, the model-catalog schema | E14 (#27), E1 (#14), E40 (#53), E15 (#28) | The "easy setup" the owner keeps asking for; every port was benchmarked first | Low — landed; the open PR #209 adds a board-setup inventory row and needs a rebase | Watchlist entries `#136 #138 #137 #130 #123 #124 #131 #110` (`benchmarked`); PRs #13, #94, #105; #14 closed 2026-09-06 |
| 4 | **Schema validation for the config files** — the validator and JSON-Schema harness ideas | E4 (#17): `#292`, `#295`, `#285` | #242 measured that `config/aihub.json`, `fleet-topology.json` and `connectors.json` have no schema and that the repo's own `validate_all.py` was never called by a workflow (PR #248 wires it into `quality.yml`; the schemas are still missing); E15's `model-catalog.schema.json` is the precedent that worked | Low — validators only, never the upstream runtime or security model | Watchlist E4 `why`/`absorb` fields; #242 gap list; `config/schemas/model-catalog.schema.json` |
| 5 | **The reliability evidence harness** | E11 (#24): `#220` | An evidence-report shape that matches the absorption reports, plus a development-only failure injector to exercise fallback chains and circuit breakers deliberately | Low if the injector stays dev-only and fails closed | Watchlist `#220`; ledger E11 |
| 6 | **Per-candidate scoring** — runtime matrix and scoring telemetry | E2 (#15): `#294`, `#253` | Directly answers the owner's "tests each candidate for code-specific things and gives scores" (#242 addendum 4); feeds the `quality` field | Medium — pre-consolidation layout; expect path conflicts under `src/ai` | Watchlist E2 entries; #242 addendum 4; the empty `quality` today |
| 7 | **Dashboard data shapes and report cadence** | E16 (#29) `#145`, E39 (#52) `#128` | Feeds the planned `absorption`/`learning` sections (#132) | Medium — very large PRs; absorb shapes, never the parallel implementation | Ledger E16/E39 risks; #132 |
| 8 | **Remote-redaction rules** | E31 (#44): `#91` | Security-adjacent and small; the rules outlive the automation they guarded | Low | Watchlist `#91` |
| 9 | **Read-only enforcement guarantees** | E10 (#23): `#221` | Complements the loopback-guarded API and the read-only review pool; guarantees, not a second CLI | Low | Watchlist `#221`; `helios-ai absorb-status` already read-only |
| 10 | **Branch-intelligence scoring** — "which upstream work next" | E13 (#26): `#141`, `#140` | The owner's "ranking that is smart and automated"; a priority model over the watchlist | Medium — depends on the upstream analytics layout; new projects must join `HELIOS.sln` | Ledger E13; #242 addendum 4 |

Deliberately **not** first: E18 (audit-first by recorded safety disposition — no code
without a signing and consent story), E19/E20/E23 (era-specific, superseded by the live
topology), E28 (`ltrain`; training runtimes are advisory catalog entries only), E7
(dormant until a real submodule exists), E6 (Container Apps versus our Foundry + VMSS),
E35/E37 (tied to reviving the excluded legacy core), and E17's `#117` (our wiki sync
is newer; the watchlist already says "likely reject").

`docs/absorption/EPICS_AND_LEARNINGS.md` has one row per epic and the full ranked
candidate table.

## 10. What not to expect

- **No automatic merges, ever.** The benchmark stages evidence and, with `-Apply`, a
  worktree. Committing absorbed code is a human decision through a normal PR, and the
  two automation lanes refuse absorption branches by pattern. The planned cadence keeps
  this rule; so does Copilot dispatch, which needs an owner-applied label.
- **The token rule.** Any credential in the environment or on disk makes the local
  benchmark refuse untrusted code (exit 3). This is a tripwire over known names and
  locations, not isolation; the keyless hosted runner is the only sanctioned lane for a
  PR you have not read. In an agent container that carries a `GH_TOKEN`, the local lane
  will refuse — that is correct behaviour, use the hosted lane.
- **Advisory means advisory.** No benchmark, fork digest, fleet record, `fleet-plan`,
  or engine recommendation changes routing, topology, or configuration. Adaptive
  routing is off by default, and even when on it sees organic outcomes only.
- **Upstream is read-only.** PR heads are fetched from `M0nado/helios-platform`; nothing
  is pushed, commented, or labelled there.
- **A conflict is a result, not a bug.** Most tranche-1 benchmarks conflicted, and the
  ports still happened — as ideas.
- **The stub fleet proves wiring, not learning.** A green weekly fleet cycle says the
  boards, claims and collection contract work. It says nothing about model quality.
- **No scores beyond pass/fail today.** `quality` is null on absorption records; the
  per-language rubric is planned.
- **No cadence workflow and no dashboard sections yet.** Both are written down (#131,
  #132) and milestoned; neither file exists in the repository at the time of writing.
- **No committed fork digests yet.** `docs/observations/` does not exist; the weekly
  digest has only ever lived as a workflow artifact. Committing one is a human step
  that has not been exercised.
- **Ledger and issues can drift.** The ledger said E1 was `open` after issue #14 closed
  as completed on 2026-09-06, its E24 and E32 headings said `open` for three weeks
  after PRs #96 and #97 closed #37 and #45, and E5 read `tranche-1` after PR #191
  closed #18 — corrected alongside this guide. Trust the issue for status and the
  ledger for narrative, and fix drift in the same PR as your next watchlist change.
- **Secrets never appear in these files.** Every credential is referred to by its
  environment-variable or secret name.

## 11. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `absorb-pr.ps1` prints `REFUSED: benchmarking untrusted upstream code in a credential-bearing environment` and exits 3 | One of the well-known credential env vars is set, a credential store exists, or a git credential helper is configured | Use `gh workflow run absorption-benchmark.yml -f pr_number=<N>`; or run on a credential-free host; the override flags mean accepting exposure |
| `Could not fetch refs/pull/<N>/head` (exit 1) | No network to `github.com`, a wrong `-Upstream`, or a PR number that does not exist upstream | Check `git ls-remote https://github.com/M0nado/helios-platform refs/pull/<N>/head`; confirm the number in the watchlist |
| Verdict says `conflicts in k file(s)` | Upstream and this fork both changed those files | Expected; read the list, port the idea, record `benchmarked` with the reason |
| `native-build` fails with `bash is required` or a cmake/g++ error | The native C++ spoke needs `bash`, `cmake`, `g++` locally | Install them or use the hosted lane, which has them |
| `bicep-build` fails with `Azure CLI is required` | `az` or its Bicep extension is missing | `az bicep install` (no login needed) or use the hosted lane |
| `dotnet-build` fails with `Native library did not reach test output` | The candidate broke the native build or its test output copy | A real gate failure on the merged tree; it is the verdict |
| `helios-ai-api unavailable or access denied … advisory outcome not recorded` | No API on loopback, or a remote `HELIOS_API_URL` without HTTPS or without `HELIOS_API_ACCESS_KEY` | Fine to ignore — the report file is authoritative; to record, run the API locally |
| `absorb-status` says `pr-watchlist.json not found` | Run from outside the repository | Run from any directory inside the clone |
| `absorb-status` shows no `verdict` for a PR you benchmarked in CI | The report is an artifact, not in your clone | `gh run download <run-id> -n absorption-report-pr-<N> -D .helios/absorption` |
| `seed-absorption-tasks.ps1` fails with a pointer to `start-fleet.ps1` | No fleet run with status `running` | Start one first; this error is the designed guidance |
| Seeded tasks are `done` within seconds and no report appears | The fleet is the stub (`workerKind` is not `hermes`) | Do not seed on a stub fleet; dispatch the hosted benchmark per PR |
| Pages Dashboard run says `GitHub Pages is not enabled` | The one-time owner click is missing | Settings → Pages → Source: GitHub Actions, then `gh workflow run pages-dashboard.yml` |
| Pages Dashboard says `No successful Status Dashboard run exists yet` | The collector has not run | `gh workflow run status-dashboard.yml`, wait, re-run Pages |
| `copilot-dispatch.yml` green-skips with a notice after labelling an epic `copilot` | Copilot coding agent unavailable, or the token was refused | Enable the agent under Settings → Copilot; optionally set `COPILOT_DISPATCH_TOKEN` (name only here) |
| A `[GH-nn]` twin of an epic reopens or a PR says "Fixes #54" | The Linear-side issue sync loop | Flip the Linear GitHub issue sync off, then `pwsh scripts/github/close-duplicate-issues.ps1 -Apply` (`docs/OWNER_START_HERE.md` § 7) |
| `fleet-learning.yml` is red | The wiring exercise failed (enqueue, drain, or stop) — not a model problem | Read the uploaded `learning-report.json`; the lane is informational and never a required check |

## 12. Glossary

| Term | Meaning here |
| --- | --- |
| Absorption | Taking an idea, contract, or file from an upstream PR into this repository deliberately, with benchmark evidence |
| Advisory | A record or recommendation that informs people and dashboards but is never applied automatically and never steers routing |
| Benchmark | One run of `absorb-pr.ps1` (locally or hosted): trial merge plus the full gate, producing a report |
| Candidate | A watchlist entry with `status: candidate` — curated, not yet benchmarked |
| Epic (E1–E40) | One of the 40 themes in the ledger; each is a GitHub issue, E-n = issue 13+n |
| Gate | The exact checks CI runs: native build, solution build, Bicep compile, .NET tests, Python tests |
| Hosted lane | The `Absorption Benchmark` workflow on a keyless runner — the default for untrusted code |
| Learning store | `.helios/learning/outcomes.jsonl` (local) or the optional Azure table; every outcome the hub records |
| Ledger | `docs/architecture/ABSORPTION_LEDGER.md`, the narrative map of the epics |
| Organic outcome | A learning record with no `source`: the hub's own provider call results; the only input to adaptive routing |
| Report | `.helios/absorption/pr-<N>.json` |
| Source (field) | The provenance tag on an advisory record: `absorption-benchmark`, `fork-observation`, `fleet-lane` |
| Stub fleet | The Python worker used when the Hermes CLI is absent; claims and completes tasks without executing them |
| Tandem learning | The fleet-to-hub loop: run, collect, summarize, advisory plan |
| Tranche | A batch of ports; `tranche-1` on an epic means a first pass landed |
| Trial merge | `git merge --no-commit --no-ff` of the PR head inside a disposable worktree |
| Upstream | `M0nado/helios-platform` (read-only) for PRs; the six `config/fork-watch.json` repos for release and commit signals |
| Verdict | The one-line summary in the report; also the exit code 0/2 |
| Watchlist | `config/absorption/pr-watchlist.json` |

## 13. Where next

- `docs/absorption/EPICS_AND_LEARNINGS.md` — every epic with what it wanted, what
  landed, and what we learned; the themes; the ranked candidate table.
- `docs/absorption/README.md` — the index of this folder and the related scripts.
- `docs/architecture/ABSORPTION_PIPELINE.md` — the loop and the boundaries, in the
  architecture's words.
- `docs/architecture/ABSORPTION_LEDGER.md` — the 40 epics in full.
- `docs/architecture/FORK_OBSERVATION.md` — the weekly dependency-upstream digest.
- `docs/architecture/HERMES_FLEET_AND_XCORE.md` — the fleet and tandem learning.
- `docs/architecture/LLM_STRENGTHS_PLAYBOOK.md` — which model for which task, the
  reasoning behind the routing table the learners score against.
- `docs/architecture/MULTI_LLM_INTEGRATION.md` — the hub, the API endpoints, the
  learning contract.
- `docs/TEST_RUN_PLAYBOOK.md` — sections 7 and 8 are the fleet and absorption lanes
  with expected outcomes.
- `docs/OWNER_START_HERE.md` — the owner-only switches (secrets by name, Pages, labels,
  the Linear switch).
- `docs/PROJECT_SETUP.md` — contributor toolchain, build, CLI, MCP.
- `.claude/agents/absorption-analyst.md` — what an agent session does when you say
  "benchmark PR N".
- On GitHub: epic issues #14–#53 (label `absorption`), the cadence parent #115 with
  #131 and #132, the Getting started epic #223 with #231, #235 and #242, and the
  merged program PRs #13, #94, #95, #96, #97, #105, #191.
