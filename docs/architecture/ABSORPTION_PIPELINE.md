# Absorption pipeline — benchmarking the original repo's best PRs

The fork's upstream (`M0nado/helios-platform`) carries ~30 open PRs of prior
work — XCore9 evaluators, Hermes federation contracts, governance gates. Some of
it is worth having; none of it is worth merging blind. This pipeline turns
"absorb the best of upstream" into an evidence-driven loop that also feeds the
AIHub learning store.

## The loop

1. **Curate** — `config/absorption/pr-watchlist.json` lists candidate PRs with
   why-absorb notes, expected extracts, and risks. Humans add candidates;
   `status` moves `candidate → benchmarked → absorbed | rejected`.
2. **Benchmark** — `pwsh scripts/absorption/absorb-pr.ps1 -PrNumber <N>` fetches
   `refs/pull/N/head`, trial-merges it onto our branch in a disposable worktree,
   and runs the exact local gate CI runs (solution build, .NET tests, Python
   tests). The scored report lands in `.helios/absorption/pr-<N>.json`:
   conflicts, per-step results, verdict.
3. **Decide** — a human reads the report. `-Apply` keeps the staged worktree so
   the good parts can be cherry-picked and committed deliberately; nothing ever
   merges automatically. Update the watchlist status either way, with the reason.
4. **Learn** — every benchmark records an ADVISORY outcome via
   `POST /v1/learning` (`source: "absorption-benchmark"`, task type
   `absorption`, success = gate verdict). Advisory records:
   - carry a required `source` field (`RoutingOutcome.Source`);
   - surface in `/v1/learning` reads and `/v1/insights` narratives;
   - are **excluded from adaptive routing** (`ApplyLearningAsync` filters
     `Source != null`), so external signals can never steer provider chains.
   `docs/architecture/FORK_OBSERVATION.md`'s digest ingestion uses the same
   contract with `source: "fork-observation"`.

## Fleet integration

Absorption benchmarks are ordinary kanban work: seed tasks on the
`xcore-infra` board (lane `infrastructure`) whose prompt is the absorb-pr
command for one PR, and the Hermes/Xcore workers run the benchmarks in
parallel — locally, or on burst capacity once the fleet VMSS
(`infra/modules/fleet-vmss.bicep`) is enabled. Review of the reports belongs on
the read-only `xcore-review` board.

## Boundaries

- **No auto-merge.** The pipeline produces evidence and staged worktrees;
  committing absorbed code is always a deliberate human (or explicitly tasked
  agent) action with normal review.
- **Advisory ≠ training data for routing.** The routing chains learn only from
  the hub's own provider outcomes; absorption/fork signals inform insights.
- **Upstream is read-only.** We fetch PR heads; we never push to the upstream.
