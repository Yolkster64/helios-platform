# Evidence before model combinations

`combo-analyze` adds an offline view of AIHub's existing learning records. Use it
before deciding whether a model combination earns the extra calls. It complements
the existing [F#/C++ combo calculus](../../.claude/skills/aihub-unity/references/combo-calculus.md);
it does not create another router, training loop or inference service.

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli -- combo-analyze \
  --outcomes .helios/learning/outcomes.jsonl --task code_generation --language csharp --json
```

Supply the actual local JSONL file from `learning.localPath` in your reviewed
configuration, or a reviewed export of the same `RoutingOutcome` schema. The
example path is illustrative. The command requires a task type, accepts a
language and `--limit` (default 200, maximum 2000), and always emits JSON.
It reads only this file, before initializing AIHub or any cloud learning store.
Inputs are bounded to 16 MiB and 10,000 records; malformed or ambiguous rows fail
with a line number without echoing their contents. Analyze a bounded export if
the full store is larger. Keep reports and snapshots in ignored local evidence
storage unless reviewed for sharing.

## What the report establishes

- Provider, model and pool stay separate within the exact task/language scope.
  There is no fallback from language-specific evidence to unqualified history.
- Success counts carry a two-sided 95% Wilson interval. With `p = successes/n`
  and `z = 1.959963984540054`, the center is
  `(p + z²/(2n))/(1 + z²/n)` and the half-width is
  `z * sqrt(p(1-p)/n + z²/(4n²))/(1 + z²/n)`.
  Zero observations means `[0,1]`, not zero success probability.
  This follows the [NIST Wilson method](https://itl.nist.gov/div898/handbook/prc/section2/prc241.htm).
  Routing records may be dependent and selected by earlier decisions; the
  binomial assumptions are disclosed, not certified by the command.
- Quality, positive latency and positive cost have independent sample counts.
  Missing quality is not replaced by success. Zero cost remains ambiguous
  because existing telemetry uses it both for unknown usage and zero estimates.
  Positive costs remain reported estimates, not billing reconciliation.
- An observed Pareto frontier is reported only when at least two candidates
  have complete quality, positive latency and positive cost coverage. A candidate
  dominates another only if no dimension is worse and at least one is better:
  higher success/quality, lower latency/cost. This compares sample means, not
  significance or causal effectiveness; it does not recommend a route.

## Retain knowledge without manufacturing confidence

The SHA-256 identifies the exact bytes analyzed, and candidate outcome IDs retain
the source trail. Repeated identical IDs count once; conflicting versions are
excluded together. Legacy records without IDs remain visible with an explicit
deduplication gap. Source-tagged records, including absorption and fleet-lane
observations, are counted separately and never enter provider comparisons.
Scoping and identity reconciliation happen before the evidence window is cut.

There is no paired request/task identifier in the current outcome schema.
Correlation, complementarity and tandem success therefore remain unknown; the
report never assumes independent provider failures. A future evaluation lane needs
matched tasks, model versions, provenance, measured usage, declared quality rubrics,
and withheld evaluation cases before estimating joint gains. OpenAI's
[agent evaluation guidance](https://developers.openai.com/api/docs/guides/agent-evals)
describes dataset and trace evaluation; this command does not call that service.

The uploaded Python prototypes contribute the ambition of retained outcomes,
registry-backed engines and repeated evaluation. Their simulated training quality,
heuristic memory-efficiency scores and catalog labels are not measured results.
They were read as source material only. This implementation calls no model,
does not execute those files, changes no route and activates no Hermes/XCore
workers. The existing [source audit](../imports/recovery/SOURCE-AUDIT-2026-09-09.md)
retains their provenance and remaining work.

The reusable C# entry is `ComboAnalysisService.AnalyzeJsonl(snapshot, taskType,
language, limit)`. Both MCP transports expose `helios_combo_analyze` with
caller-supplied `outcomesJsonl`, `taskType`, optional `language` and `limit`.
The MCP boundary accepts at most 32 KiB UTF-8 and 200 selected records; use the
local CLI for larger bounded snapshots. It reads no host files and receives no
credentials or learning-store writer.
Work remains under JOH-187/JOH-225 and the existing integration PR.
