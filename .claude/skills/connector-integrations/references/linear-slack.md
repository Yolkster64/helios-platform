# Linear & Slack connectors — behavior reference

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.*

## `config/connectors.json` — the routing table

One file, env-var NAMES and routing choices only, never values — its own
`$comment` (`config/connectors.json:2`) states this and names both readers: the
GitHub Actions workflows today, and the `HELIOS.Connectors` service only when it
lands (`docs/architecture/ROADMAP_MULTI_LLM.md:31-34` — PR4; nothing under
`src/` implements it yet).

### `slack` block (`config/connectors.json:3-21`)

| Key | Value | Consumed by |
|---|---|---|
| `enabled` | `true` | (declarative — the workflow gates on the secret, not this flag) |
| `webhookUrlEnv` | `SLACK_WEBHOOK_URL` | `notify-slack.yml:38` maps the secret of that name into the job env |
| `botTokenEnv` | `SLACK_BOT_TOKEN` | **Nothing.** See "Declared but unconsumed" below |
| `channels` | `ci` → `#helios-ci`, `deploys` → `#helios-deploys`, `fleet` → `#helios-fleet`, `controlPlane` → `#helios-control-plane` (`connectors.json:7-12`) | Routing intent; an incoming webhook posts to the channel it was created for, so channel choice is made at webhook-creation time |
| `notifyOn` | Six workflow-name → policy rows (`connectors.json:13-20`): `Helios Platform Deploy` and `Absorption Benchmark` are `always`; `.NET Build & Test`, `Infra Validation`, `Python Spoke`, `Docker Validation` are `failures-and-recovery` | `notify-slack.yml:50` (`jq` lookup, default `failures-and-recovery`) |

### `linear` block (`config/connectors.json:22-36`)

| Key | Value | Consumed by |
|---|---|---|
| `apiKeyEnv` | `LINEAR_API_KEY` | `linear-sync.yml:40` maps the secret of that name into the job env |
| `teamKey` | `JOH` | Team lookup, `linear-sync.yml:55,88-93` |
| `titlePrefix` | `[GH-{number}] ` | Mirror title + identity lookup, `linear-sync.yml:56-57,101-104` |
| `syncLabels` | `bug`, `enhancement`, `infra`, `ai-hub`, `absorption`, `build-ci` (`connectors.json:27`) | Crossing gate, `linear-sync.yml:66-79` |
| `githubLabelToLinear` | `bug`→`Bug`, `enhancement`→`Feature`, `infra`→`Infra`, `ai-hub`→`AIHub`, `absorption`→`Absorption`, `build-ci`→`BuildCI` (`connectors.json:28-35`) | Label mapping, `linear-sync.yml:120-135` |

## `.github/workflows/linear-sync.yml` — issue mirror

- **Trigger**: `issues` events `opened, labeled, unlabeled, closed, reopened`
  (`linear-sync.yml:11-13`). One-directional by design — GitHub is the source of
  truth; Linear-side edits are never synced back (header, lines 3-6).
- **Concurrency**: one run at a time per issue
  (`group: linear-sync-${{ github.event.issue.number }}`,
  `cancel-in-progress: false`, lines 20-22) — queued, not cancelled, so a
  running mutation always finishes; two racing label events on an unmirrored
  issue would otherwise both miss the `existing_id` lookup and each create a
  Linear issue (comment, lines 15-19).
- **Checkout**: sparse, `config/` only (lines 33-36).
- **Skip-green gate**: `LINEAR_API_KEY` empty → log a pointer to
  `config/connectors.json` and `exit 0` (lines 50-53).
- **Sync-label gate**: only issues carrying at least one `syncLabels` label cross
  over; `unlabeled`, `closed`, and `reopened` are exempt so removing the last
  sync label empties the mirror's labels instead of freezing them, and an
  existing mirror keeps following GitHub state (lines 59-79).
- **Mirror identity**: server-side GraphQL filter on title `startsWith` the
  rendered prefix AND description `contains` this repo's issue URL — the
  `[GH-N]` prefix alone is ambiguous across repos syncing into one workspace; a
  client-side re-check remains as a belt (lines 95-104).
- **Label semantics**: labels are re-read live via
  `gh api repos/$REPO/issues/$N` at mutation time (payload snapshot is only the
  fallback), mapped through `githubLabelToLinear`, missing Linear labels are
  created in the team, and the mapped set REPLACES the mirror's labels — empty
  set included (lines 106-151).
- **Close/reopen**: resolves the issue's LIVE state (not the event's), then maps
  by state TYPE — `closed` → the team's first `completed` state by position,
  `reopened` → its first `unstarted` state — via `issueUpdate`, plus a
  `commentCreate` noting the transition (lines 169-202).
- **Comment-back**: on create, `gh issue comment` posts
  "Tracked in Linear as [IDENT](url)" on the GitHub issue (lines 163-167;
  needs `permissions: issues: write`, lines 24-26).

### Linear GraphQL surface used (all via `curl` to `https://api.linear.app/graphql`, `Authorization: $LINEAR_API_KEY` — `linear-sync.yml:81-86`)

- Queries: `teams(filter:{key})` (88-89), `issues(filter:{title.startsWith,
  description.contains})` (101-102), `issueLabels(filter:{team,name})` (128-129),
  `team(id){states{nodes{id type position}}}` (188-189).
- Mutations: `issueLabelCreate` (131-132), `issueUpdate` with `labelIds` (144-145)
  or `stateId` (193-194), `issueCreate` (156-160), `commentCreate` (198-200).

### Failure/skip modes (all end green — read the log)

| Log line | Meaning |
|---|---|
| `LINEAR_API_KEY is not configured — skipping` | Secret unset; owner runs `gh secret set LINEAR_API_KEY` (`CONNECTIONS_SETUP.md:200`) |
| `No sync label on #N` | Working as designed — add a `syncLabels` label to cross over |
| `::warning::Linear team with key 'JOH' not found` | `linear.teamKey` doesn't match the workspace (`linear-sync.yml:90-93`; `CONNECTIONS_SETUP.md:197-198`) |
| `No Linear counterpart for #N` | close/reopen/unlabel on an issue that was never mirrored — no-op by design (lines 152-155, 170-173) |
| `::warning::Team has no '<type>' workflow state` | State left unchanged; the comment still posts (lines 195-197) |

## `.github/workflows/notify-slack.yml` — CI/deploy outcomes

- **Trigger**: `workflow_run` `completed` on exactly six workflows
  (`notify-slack.yml:12-21`): `.NET Build & Test`, `Infra Validation`,
  `Python Spoke`, `Helios Platform Deploy`, `Absorption Benchmark`,
  `Docker Validation` — the same six names keyed in `slack.notifyOn`
  (`config/connectors.json:14-19`). A deliberate separate listener: pipelines
  stay notification-agnostic, and adding a channel means editing exactly one
  file (header, lines 3-7). **Subscribing a new workflow means adding it to
  this list** — a `notifyOn` row alone does nothing (the lookup only filters
  events that already arrived, line 50).
- **Skip-green gate**: `SLACK_WEBHOOK_URL` empty → pointer + `exit 0`
  (lines 45-48); "the workflow must never be the red check" (line 7).
- **Policy**: `notifyOn` lookup with default `failures-and-recovery`; that
  policy skips routine successes (recovery detection would need run history the
  payload doesn't carry) — flip a row to `always` to hear every outcome
  (lines 50-58).
- **Formatting**: icon per conclusion (lines 60-65); the branch name is
  mrkdwn-escaped because it is the one attacker-influenced field — an external
  PR's branch can embed tokens like `<!channel>` (lines 67-71).
- **Absorption Benchmark caveat**: on success the message says the benchmark
  RAN, not that the candidate passed — that workflow reports success for every
  completed benchmark, rejected candidates included; the verdict is in the run
  summary/report artifact (lines 74-81).
- **Delivery**: single `{text}` JSON POST to the webhook (lines 82-83).

## Declared but unconsumed: `SLACK_BOT_TOKEN`

`config/connectors.json:6` declares `botTokenEnv: SLACK_BOT_TOKEN`, and
`docs/OWNER_START_HERE.md:76` reserves it for bot-token Slack calls in the
future `HELIOS.Connectors` service — but no workflow, script, or `src/` code
reads it today. Say so when asked; do not invent bot-token features
(threads, reactions, channel lookup) that the webhook-only integration lacks.

## Team-John sync loop — history and the owner click-path

Linear's built-in GitHub integration must NOT also be linked to this repo for
team `JOH`, or the two syncs loop: Linear re-created its mirrored issues back on
GitHub as new issues, producing duplicates #54–#93 (closed 2026-08-12), and
closing the GitHub twins then cancelled the Linear mirrors, which had to be
restored (`docs/architecture/CONNECTIONS_SETUP.md:203-211`). Owner click-path
(not delegable): Linear → **Settings → Integrations → GitHub** → under the team
`John` link, disable issue sync for `Yolkster64/helios-platform` (PR-link
previews may stay on). One writer only: this repo's `linear-sync.yml` writes;
Linear stays the mirror.

## Verification recipes (owner checklist, `CONNECTIONS_SETUP.md:300-301`)

- **Linear**: label an issue `bug` (or any other `syncLabels` label) → a
  `[GH-n]` issue appears in Linear team `JOH`, and the GitHub issue gets the
  "Tracked in Linear as …" comment.
- **Slack**: re-run any of the six listed workflows → failure or `always`
  outcomes post to the channel (a `failures-and-recovery` success stays quiet
  on purpose — check the notify run's log for "staying quiet", not the channel).
- **Either connector "did nothing"**: read the skipped run's log first
  (`gh run list --workflow <file>` then `gh run view <id> --log`) — the
  skip-green gates and the label/policy gates all log exactly why they exited 0.
- **Auth wiring doubts**: `pwsh scripts/bootstrap/auth-doctor.ps1` — its
  connector lanes (linear, slack) verify by env-var NAME only, report-only,
  and never print a value.
