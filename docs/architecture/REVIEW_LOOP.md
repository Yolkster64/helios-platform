# Multi-LLM Review Loop — Runbook

The operating protocol for getting a PR through the three-reviewer loop
(Copilot, Codex, Claude) to a defensible merge. `FORWARD_PLAN.md:11-17`
declares the loop "proven, keep"; this document is the missing protocol
write-up — how each reviewer is triggered, how waves work, what failure looks
like, and when to stop. Governance follow-ons (rulesets, CODEOWNERS,
merge-queue) are tranche T9 (`FORWARD_PLAN.md:54-62`); the credential and
control-plane mechanics live in the `github-control` skill
(`.claude/skills/github-control/`).

## Trigger surface per reviewer

| Reviewer | Trigger | Repo config | Ground truth |
|---|---|---|---|
| **Copilot code review** | Automatic on every PR `opened` / `ready_for_review` when not draft — the `request-review` job POSTs `copilot-pull-request-reviewer[bot]` to `requested_reviewers` | `copilot-dispatch.yml` (plus optional `COPILOT_DISPATCH_TOKEN` secret) | `.github/workflows/copilot-dispatch.yml:19-20,83-103` |
| **Codex** | Cloud-side: reviews when a PR opens for review / a draft is marked ready, and on `@codex review`; `@codex address that feedback` has it push fixes | **Zero repo config** — the connection lives in Codex settings at chatgpt.com; Codex reads `AGENTS.md` | `docs/architecture/CONNECTIONS_SETUP.md:101-119,260` |
| **Claude** | `@claude <ask>` PR comments, **owner-only** (`github.actor == github.repository_owner`); plus owner-dispatched review/implement lanes | `claude-foundry-comment-review.yml` (comment lane) + `claude-foundry.yml` (dispatch lanes) + Azure OIDC variables | `.github/workflows/claude-foundry-comment-review.yml:26-29` |

Notes that bite in practice:

- Copilot's request is **draft-filtered** (`copilot-dispatch.yml:85`): a draft
  PR gets no Copilot review until marked ready — that event also fires the
  workflow (`:20`).
- Codex reacts 👍 instead of commenting when it has no findings — a 👍 wave is
  a *converged* wave, not a skipped one.
- The `@claude` gate rejects non-owner comments by design; a silent `@claude`
  from anyone else is the gate working, not a failure.

## The wave protocol

A **wave** = one reviewer pass over one head commit. The loop as practiced:

1. Open the PR (or mark ready). Copilot and Codex review the head commit —
   wave 1.
2. Fix or refute every finding. Push. The push produces a **new wave on the
   new commit** (Codex reviews pushes; re-request Copilot or comment
   `@codex review` where needed).
3. Repeat until a wave ends in 👍 or no findings.

Wave counts vary wildly and that is normal — the loop terminates on
convergence, never on a count. Verified against the PR review timelines via
the GitHub API (2026-08-13): **PR #94 took 18 Codex waves** before merging,
**PR #10 took 6+**, **PR #99 converged in 2–3**.
`ENTERPRISE_AI_CONNECTIONS.md:17` records the same pattern ("Codex review
waves on PRs #94–#99"). Do not merge mid-wave: a fix pushed after a review
starts means the posted findings describe a stale commit — wait for the wave
on your actual head.

## Quota failure mode and escalation

Codex work counts against the ChatGPT plan's usage limits; when the limit is
hit, reviews and commands **quietly stop** until the window resets — so a
*missing* Codex review usually means quota, not breakage
(`CONNECTIONS_SETUP.md:112-114`).

- Codex comments about hitting **usage limits for security reviews** are
  noise: the experimental security-review lane rides alongside the regular
  review (it appeared exactly once in PR #94's 18-wave run) and its quota
  message does not indicate the regular review failed. Ignore them.
- A missing **regular** review is the real signal. Escalation procedure:
  1. Comment `@codex review` to retrigger (`CONNECTIONS_SETUP.md:110`).
  2. If still silent, retrigger once more on the current head.
  3. If Codex stays silent after **two retriggers**, proceed on green
     required checks plus all previously raised findings resolved — and say
     so in the PR ("Codex silent after two retriggers, presumed quota;
     proceeding on green checks").

## Stopping rule

Merge when **all three** hold:

1. `mergeable_state` is `clean` (`gh pr view <n> --json mergeable,mergeStateStatus`) —
   no conflicts, no pending required checks;
2. every raised finding is **fixed, or refuted with evidence in a reply**
   (a file/line or test demonstrating the reviewer was wrong — never a bare
   "disagree"); a 👍/no-findings wave on the final head commit counts as
   Codex's sign-off;
3. required checks are green — never merge an agent-authored PR on a red or
   skipped check (`GITHUB_ECOSYSTEM_DESIGN.md:74-75`).

Scope boundaries from the control plane apply on top: absorption-pipeline
candidates never auto-merge (`ABSORPTION_PIPELINE.md:50`), and claude-foundry
implementation patches enter this loop as **drafts**
(`claude-foundry.yml:339-344`) — marking one ready is the human decision that
starts wave 1.

## Automated pipeline

`.github/workflows/pr-pipeline.yml` mechanizes the stopping rule for a fixed
trusted author set — the repo owner, the Copilot coding agent (PR author login
`Copilot`, verified on PRs #95–#97), and dependabot's grouped minor/patch
update branches:

- **Auto-ready**: the Copilot agent's draft PRs (its PRs open as drafts by
  design) are marked ready once every check run on the head SHA has completed
  green. Drafts by humans — including the owner's and claude-foundry
  implementation drafts — are never auto-readied: a human draft means
  not-ready by intent.
- **Auto-enable merge**: for non-draft trusted PRs, it arms native squash
  auto-merge only when `reviewDecision` is not `CHANGES_REQUESTED`, there are
  **zero unresolved review threads** (unresolved threads = outstanding
  findings — rule 2 of the stopping rule, mechanized), and every check run on
  the head is green. When GitHub refuses to arm because the PR is already
  clean, the run completes the squash merge directly; the `main` ruleset's
  required checks are enforced server-side on that call either way.

What stays manual: **resolving or refuting review threads is the steward's
judgment** — the pipeline only reads `isResolved`, so bot findings still get
fixed or refuted-with-evidence exactly as above; the `automerge` label lane
(`auto-merge.yml`) remains the manual override for anything outside the
trusted set; and absorption-lane branches (`absorb*`/`absorption*` in any
path segment, including the agent's `copilot/absorption-*`) are always
excluded per `ABSORPTION_PIPELINE.md:50`. Event gap worth knowing: resolving
a thread and the completion of Actions-created check suites emit no
re-evaluation event — when a converged PR sits unarmed, nudge it with
`workflow_dispatch` (`pr_number`) or the next push/review event.

## External-push reconciliation

Other actors push to loop branches: `@codex address that feedback` has Codex
push fixes (`CONNECTIONS_SETUP.md:110-111`), and the Copilot coding agent
authors whole branches (`copilot-dispatch.yml:3-6`). Before any
`git push --force-with-lease` on a branch you steward:

1. `git fetch` and diff your local head against the remote head;
2. **read the content** of any commit pushed by another actor — verify what
   it changed, do not assume it matches its message;
3. fold acceptable external commits into your history (rebase onto them or
   keep them), then push; `--force-with-lease` then fails closed if yet
   another push landed meanwhile — that failure means go back to step 1.

Never plain `--force` on a shared loop branch: it silently discards reviewer
work and desynchronizes the wave history the stopping rule depends on.

## Cross-references

- `FORWARD_PLAN.md` — operating model (`:11-17`) and T9 governance lane (`:54-62`).
- `.claude/skills/github-control/` — auth surfaces, rulesets/required checks,
  auto-merge boundaries, Projects v2, wiki/Pages.
- `CONNECTIONS_SETUP.md` — per-connection wiring, owner actions, verification.
- `LLM_STRENGTHS_PLAYBOOK.md` — which model to route which review task to.
