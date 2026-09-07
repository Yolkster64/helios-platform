# Absorption and learning program — index

The folder for people starting with the program that watches upstream and sibling
repositories, benchmarks candidate pull requests in isolation, scores them, learns from
the outcomes, and only ever proposes. Nothing in this program auto-merges.

## In this folder

| Document | One line |
| --- | --- |
| [START_HERE.md](START_HERE.md) | The beginner's guide: what the program is, the pieces, the ten-minute path, automatic setup when ready, the dashboard, the fleet, scoring, the best parts to take first, limits, troubleshooting, glossary |
| [EPICS_AND_LEARNINGS.md](EPICS_AND_LEARNINGS.md) | One row per epic E1–E40 (issues #14–#53), the themes the issues and PRs teach, and the candidates ranked |

## Architecture documents

| Document | One line |
| --- | --- |
| [../architecture/ABSORPTION_PIPELINE.md](../architecture/ABSORPTION_PIPELINE.md) | The four-step loop (curate, benchmark, decide, learn) and its boundaries |
| [../architecture/ABSORPTION_LEDGER.md](../architecture/ABSORPTION_LEDGER.md) | The 40 theme epics distilled from the upstream's 195 PRs, with status |
| [../architecture/FORK_OBSERVATION.md](../architecture/FORK_OBSERVATION.md) | The weekly read-only digest of dependency upstreams |
| [../architecture/HERMES_FLEET_AND_XCORE.md](../architecture/HERMES_FLEET_AND_XCORE.md) | The fleet pools and tandem learning |
| [../architecture/LLM_STRENGTHS_PLAYBOOK.md](../architecture/LLM_STRENGTHS_PLAYBOOK.md) | Which model for which task — the routing reasoning the learners score against |
| [../architecture/MULTI_LLM_INTEGRATION.md](../architecture/MULTI_LLM_INTEGRATION.md) | The hub, the API endpoints, the advisory learning contract |
| [../repository/FORK-INVENTORY-2026-09-05.md](../repository/FORK-INVENTORY-2026-09-05.md) | Sibling repositories and their import rules |
| [../TEST_RUN_PLAYBOOK.md](../TEST_RUN_PLAYBOOK.md) | Sections 7 and 8: the fleet and absorption lanes with expected outcomes |

## Configuration, scripts, workflows, and agents

| Path | One line |
| --- | --- |
| `config/absorption/pr-watchlist.json` | The curated candidates with `epic`, `why`, `absorb`, `risks`, and the human-moved `status` |
| `config/fork-watch.json` | The six dependency upstreams watched weekly |
| `config/github/labels.json`, `config/github/milestones.json` | The `absorption`, `absorption-candidate`, `copilot` labels and the "Absorption tranche 5" milestone |
| `scripts/absorption/absorb-pr.ps1` | The benchmark: trial merge in a disposable worktree, full gate, scored report, advisory outcome; refuses on a credential-bearing host |
| `scripts/fleet/seed-absorption-tasks.ps1` | Watchlist candidates as fleet tasks on the `xcore-infra` board (real Hermes fleet only) |
| `scripts/fleet/learn-fleet.ps1` | One tandem learning cycle: seed, drain, stop, collect, summarize, advisory plan |
| `.github/workflows/absorption-benchmark.yml` | The keyless hosted benchmark (the default lane for untrusted code) |
| `.github/workflows/fleet-learning.yml` | The weekly informational stub learning cycle |
| `.github/workflows/fork-observation.yml` | The weekly fork digest artifact |
| `.github/workflows/status-dashboard.yml`, `.github/workflows/pages-dashboard.yml` | The workflow-health dashboard and its Pages publish |
| `.github/workflows/auto-merge.yml`, `.github/workflows/pr-pipeline.yml` | The guards that refuse to auto-merge absorption branches |
| `.claude/agents/absorption-analyst.md` | The agent that runs the loop on request |
| `helios-ai absorb-status`, MCP `helios_absorb_status_get` | The read-only status views (watchlist merged with local reports) |

Planned, not yet in the repo: `.github/workflows/absorption-cadence.yml` (issue #131),
the `absorption` and `learning` dashboard sections (issue #132), and a per-language
scoring rubric `config/absorption/scoring.json` (issue #242, addendum 4).
