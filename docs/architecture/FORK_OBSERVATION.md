# Fork Observation — Upstream Watch Pipeline

Weekly, read-only observation of the upstreams HELIOS forks or depends on, so drift is
noticed on a schedule instead of during an outage. Three parts:
`config/fork-watch.json` (what and why), `.github/workflows/fork-observation.yml`
(the mechanics), and a manual review step (the only path by which anything lands in git).

## What is watched

The authoritative list is `config/fork-watch.json` — schema
`{"repos":[{"repo":"owner/name","because":"...","signals":["releases","commits"]}]}`,
every entry carrying a why-watched note. Current entries:

| Upstream | Why |
|---|---|
| `actions/actions-runner-controller` | Upstream of the HELIOS ARC fork (GITHUB_ECOSYSTEM_DESIGN.md); releases drive controller/chart upgrades for the PR5 fleet bring-up |
| `Azure-Samples/azure-search-openai-demo` | RAG reference tracked for the PR3 Foundry retrieval work |
| `microsoft/WindowsAppSDK` | Gates the `src/gui` HELIOS.Shell dependency pin and the PR6 net10 upgrade |
| `modelcontextprotocol/csharp-sdk` | The SDK behind `src/mcp/HELIOS.Mcp` |

## How it runs

- **Trigger**: weekly cron (Mondays 06:17 UTC) + `workflow_dispatch`.
- **Access**: plain `curl` against `api.github.com` with the workflow `GITHUB_TOKEN`
  (`permissions: contents: read`). All watched repos are public — no gh CLI, no PATs, no
  extra secrets.
- **Signals**: latest release (`/releases/latest`, 404 = "none published") and commit
  activity over a 14-day window (`/commits?since=…`, first 100).
- **Output**: one markdown digest, named for the ISO week (`<year>-w<week>.md`),
  uploaded as a workflow artifact (90-day retention) and appended to the job step
  summary. **CI never pushes and never opens PRs** — no PR spam, no bot commits, and the
  workflow needs no write permission.
- **Determinism**: rate limits, outages, and 404s degrade to "unavailable" lines inside
  the digest; the job goes red only if `config/fork-watch.json` itself is malformed.

## Manual review

A human (weekly, or when a run is dispatched) opens the run's step summary or downloads
the artifact, then:

1. Commits digests worth keeping to `docs/observations/<year>-w<week>.md` via a normal
   PR — the digest header names its intended path. Noise is simply not committed.
2. Turns anything actionable into an issue or roadmap entry (bump the ARC chart pin, new
   Windows App SDK servicing release for `src/gui`, MCP SDK breaking change, a retrieval
   pattern worth porting from the RAG demo).

## Feeding the AIHub learning loop (roadmap)

Today the hub's learning store records `RoutingOutcome`s from real provider calls, read
back via `GET /v1/learning` and analyzed by the Python spoke via `/v1/insights`. The
fork digests are the same shape of signal — dated observations that should bias future
decisions — so the roadmap step (after PR3's cost wiring enables `learning.enabled` by
default) is:

- Add a **POST** ingestion surface to `/v1/learning` accepting *advisory* outcomes with
  a provenance field (`source: fork-observation`), so digest summaries sit alongside
  provider outcomes without polluting routing statistics — advisory records inform
  `/v1/insights` narratives, never the routing chains directly.
- Post each reviewed digest's per-repo summary lines through that endpoint (a follow-up
  step in the workflow, gated on the API being reachable — still no git writes).
- Keep the manual review in the loop: only human-committed digests get posted, so the
  learning store never ingests unreviewed upstream text.

Non-goals: automated dependency bumps, CI commits of any kind, and watching private
repos (that would need real secret handling and a different threat model).
