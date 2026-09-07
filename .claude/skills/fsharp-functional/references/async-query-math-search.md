# Async, queries, numerics, and search in the F# domain spoke

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Companion: `analytics-patterns.md` (units of measure in `Pricing.fs`,
the fold/scan shapes, every C# call site, FsCheck candidates) — not repeated here.
System view: `docs/architecture/AIHUB_LANGUAGE_ROLES.md`; the full optimization
write-up with worked numbers: `.claude/skills/aihub-unity/references/combo-calculus.md`.

Ground truth is the five modules of `src/ai/HELIOS.AIHub.Domain/`, compiled in order
`Pricing.fs`, `ContextBudget.fs`, `ModelSelection.fs`, `RoutingPolicy.fs`,
`LearnerFusion.fs` (`HELIOS.AIHub.Domain.fsproj:22-28`, `net10.0`, FSharp.Core pinned
centrally at 10.1.400 — `Directory.Packages.props:26`).

## Pattern 1 — async and task: the spoke computes, the hub awaits

Grep-verified: no `task { }`, `async { }`, `Async.`, or `Task<` appears in any of the
five modules. Every entry point is a synchronous pure function over snapshots the C#
hub already read (`Pricing.fs:13-14`, `ContextBudget.fs:13-15`,
`RoutingPolicy.fs:15-17`). That is the design: the hub owns the awaits
(`AIHub.cs:265-273` reads the store, then calls `_reorderEngine.Reorder` synchronously
at `:298`), so the F# side has nothing to await and nothing to cancel.

When a future entry point genuinely needs to be awaited by C#, SKILL.md's sketch applies:
`task { }` (not `async { }`) returns a real `Task<'T>` with no adapter — but it still
takes its inputs as parameters and opens no socket. Do not introduce `Async.StartAsTask`
bridges or `Async.RunSynchronously` at the interop edge; if a function needs live data,
the hub fetches it.

Trap: a `task { }` that captures a `CancellationToken` must thread it through explicitly;
the interop surfaces today take none, which is correct for pure math and would be a
review finding for anything that blocks.

## Pattern 2 — queries: pipelines over lists, not `query { }`

Grep-verified: no `query { }` expressions exist; every aggregation is a `Seq`/`List`
pipeline that ends in a plain array or record for C#:

| Question | Pipeline | Where |
|---|---|---|
| Per-provider stats for one task type | `Seq.filter` → `Seq.groupBy` → `Seq.map` into `ProviderStats` → `List.ofSeq` | `RoutingPolicy.aggregate` (`RoutingPolicy.fs:60-73`) |
| Which providers are confident | `List.filter` over the configured chain with a `Map.tryFind` lookup | `RoutingPolicy.fs:111-116`; `LearnerFusion.fs:207-212` |
| Catalog candidates for a task | `List.filter (fun m -> List.contains taskType m.Strengths)` | `ModelSelection.candidatesFor` (`ModelSelection.fs:68-69`) |
| Chain entries whose window fits | `List.filter` with unknown windows passing through, falling back to the full chain | `ContextBudget.filterFits` (`ContextBudget.fs:50-58`) |
| Running state per provider, chronological | `List.fold` of `observe` into `Map<string, Running>` | `LearnerFusion.buildCandidates` (`LearnerFusion.fs:168-174`) |

Why not `query { }`: the interop takes parallel primitive arrays and returns arrays
(`RoutingPolicy.fs:152-181`), so LINQ-style query syntax buys nothing and would pull
`System.Linq` semantics into a module whose value is being obviously pure. Keep the
`Map.ofList` idiom in mind — it keeps the *last* value for a duplicate key, which is
safe here only because `aggregate` has already grouped by provider
(`RoutingPolicy.fs:110`).

## Pattern 3 — numerics: the formulas as written

The linear routing score (`RoutingPolicy.fs:87-97`), with `defaultWeights`
`{ Success = 0.55; Quality = 0.25; Latency = 0.10; Cost = 0.10 }` (`:48-49`):

```text
score(stats) = 0.55 · successRate
             + 0.25 · (MeanQuality, or successRate when unrated)
             + 0.10 · inverseNormalized(all mean latencies, MeanLatencyMs)
             + 0.10 · inverseNormalized(all mean costs,     MeanCostUsd)
```

`inverseNormalized` maps the best (lowest) observed value to 1.0 and the worst to 0.0; an
empty list or a zero range reads 1.0 — "no evidence of being slow" is neutral, not
punitive (`RoutingPolicy.fs:75-83`). Evidence below `minAttemptsForConfidence = 5`
attempts keeps the configured slot (`:51-52`).

The fusion module (`LearnerFusion.fs`) adds:

- six features per provider — success rate, inverse-normalized mean latency,
  inverse-normalized mean cost, quality (or success rate), saturating evidence mass
  `attempts / (attempts + 5)`, and the success rate over the last three outcomes
  (`featuresOf`, `:97-113`; `recentWindow = 3`, `:38`);
- a soft target `t = s` when unrated, `t = 0.5·s + 0.5·clamp(q)` when rated
  (`target`, `:118-122`);
- the MLP weight `w(a) = 0` below five attempts, else `0.5 · a / (a + 10)` — never past
  one half, so the interpretable linear score always keeps at least equal say
  (`mlpWeight`, `:192-194`);
- the blend `(1 - w)·linear + w·prediction` per confident provider (`fuseChain`, `:217-224`).

Numeric conventions that matter at the boundary:

- `float32` leaves the spoke only where the native ABI demands it (`featuresOf` returns
  `float32[]`; `TrainingSet.Features/Targets` are `float32[]`, `:124-128`); everything
  else is `float`.
- `NaN` is the "unrated" sentinel for quality across interop — it becomes `None`, which
  is *different from zero* (`RoutingPolicy.fs:27-29,177-178`).
- The generic `inverseNormalized (lo: float<'u>) (hi: float<'u>)` clamps to `[0,1]` and
  is parametric over the measure, so a latency range cannot normalize a cost
  (`LearnerFusion.fs:89-95`); `RoutingPolicy`'s unclamped version relies on the value
  being drawn from the same list it normalizes against (`RoutingPolicy.fs:91-97`).
- Sorting uses `List.sortBy` / `List.sortByDescending`, which are stable, so ties keep
  the configured order (`RoutingPolicy.fs:121-123`, `LearnerFusion.fs:225`).

Honest gap: the weights are a compile-time constant. `RoutingPolicy.fs:40-41` says
"tune per deployment", but no config knob reaches `defaultWeights`; the C# interop
always passes it (`RoutingPolicy.fs:180`, `LearnerFusion.fs:304`). Changing the weights
is a code change with tests, not a config edit.

## Pattern 4 — search: lexicographic keys and constrained permutations

Three search shapes ship, all deterministic:

1. **Rank by a tuple key** — `ModelSelection.rank` sorts by
   `(estimatedCost, speedRank, classRank)` for cost, `(speedRank, estimatedCost)` for
   latency, `(classRank, -ContextTokens)` for quality, and a normalized blend
   `0.4·normCost + 0.3·speedRank/2 + 0.3·classRank/2` for balanced
   (`ModelSelection.fs:75-97`). `selectBest` is `candidatesFor >> rank >> List.tryHead`
   (`:101-102`); `None` means "no catalog opinion", and the C# side falls back to the
   configured chain (`:108-109`; `ModelCatalog.cs:81-85`).
2. **Cheapest rate that fits** — `Pricing.cheapestFor` sorts by `costOf rate expected`
   and takes the head; an empty candidate list is `None`, never `$0`
   (`Pricing.fs:55-61`). `rankByHeadroom` keeps only windows with non-negative headroom
   and sorts descending (`ContextBudget.fs:60-68`).
3. **Reorder within the operator's slots** — `reorderChain` ranks only the confident
   providers, then walks the configured chain refilling confident positions from that
   ranked queue, leaving thin-evidence providers exactly where the operator put them
   (`RoutingPolicy.fs:120-135`). The result is always a permutation of the input and never
   introduces a provider (`:101-104`); `fuseChain` reuses the identical splice
   (`LearnerFusion.fs:225-235`). The local `let mutable queue` is confined to the
   function, so the function stays pure and replayable.

`explain` renders the decision as `Reordered a→b→c -> b→a→c (a 4/6 ok, b 5/5 ok)` or the
"not enough evidence" sentence (`RoutingPolicy.fs:139-150`) — routing that cannot
explain itself is routing nobody leaves switched on.

## Pattern 5 — units of measure at the seams (what `analytics-patterns.md` does not say)

- Measures are declared per module on purpose: `Pricing.usd` and `LearnerFusion.usd`
  are different types, as are `ContextBudget.token` and `ContextBudget.windowToken`
  (`Pricing.fs:18-27`, `LearnerFusion.fs:23-28`, `ContextBudget.fs:19-24`). Cross-module
  arithmetic must strip and re-attach explicitly.
- Integer measures work: `int64<token>` for usage (`Pricing.fs:39-41`) and
  `int<windowToken>` for capacities (`ContextBudget.fs:31-33`); the only cross-unit
  comparison is the deliberate `int` cast in `fits` (`ContextBudget.fs:41-44`).
- Attach at the boundary by multiplication (`inputTokens * 1L<Pricing.token>`,
  `x * 1.0<Pricing.usd/Pricing.Mtoken>`), strip with `float`/`int`
  (`Pricing.fs:83-93`, `ContextBudget.fs:76-83`).

## Worked example (the numbers)

Fixture: task `code_generation`, chain `codex → openai-codex → openai → azure-openai →
anthropic`, twelve organic outcomes — codex 4/6 successes at mean 47 667 ms and
recorded cost 0 (CLI agents report no tokens), openai-codex 5/5 at mean 10 000 ms and
mean cost 0.0163 USD, openai 1/1 (thin).

- Confident set: `codex`, `openai-codex` (openai has 1 attempt).
- `score(codex) = 0.55·0.6667 + 0.25·0.6667 + 0.10·0 + 0.10·1 = 0.6333`.
- `score(openai-codex) = 0.55·1 + 0.25·1 + 0.10·1 + 0.10·0 = 0.9000`.
- Reordered chain: `openai-codex → codex → openai → azure-openai → anthropic`.
- `mlpWeight(6) = 0.1875`, `mlpWeight(5) = 0.1667`; with predictions 0.55 and 0.92 the
  fused scores are 0.6177 and 0.9033 — the same order.
- The neural path abstains here: prequential training yields 12 − 3 = 9 samples, below
  `MinTrainingSamples = 12` (`NeuralRoutingLearner.cs:29-30`), so the engine reports
  `linear`.

The full derivation, including the context-budget and cost arithmetic, is in
`.claude/skills/aihub-unity/references/combo-calculus.md`.

## Traps the reviews have caught, in prose

- Generated `float`s produce `NaN`/infinities, which at the interop edge silently mean
  "unrated" and poison normalization ranges — generate domain records, not raw arrays
  (`analytics-patterns.md` "Generator pitfall").
- The store returns newest-first; prequential replay needs oldest-first, and the C# side
  flips (`NeuralRoutingLearner.cs:53-56`). An F# function that assumes either order must
  say so in its doc comment (`LearnerFusion.fs:135-137`).
- A provider named in history but not in the configured chain is never invented into
  the result (`RoutingPolicy.fs:101-104`); a provider in the chain with no history keeps
  its slot. Both are properties worth a test.
- `ContextBudget.filterFits` returning the full chain when nothing fits is the point:
  losing a result is worse than a truncation warning (`ContextBudget.fs:46-49`).

## When to route this work to which model or provider

Chains are `config/aihub.json:97-215`.

| F# work | Task type → chain | Why |
|---|---|---|
| Domain model design, DU state machines, property invariants | `architecture_design` → `anthropic`, `anthropic-foundry`, `openai` | Reasoning about state spaces (SKILL.md "Which LLM") |
| Mechanical C# ↔ F# conversions, interop mirror members | `code_refactoring` → `codex`, `openai-codex`, `anthropic`, `openai` | Describable transformation |
| Property-test scaffolds for the contracts above | `test_creation` → `codex`, `openai-codex`, `openai`, `anthropic` | Scaffolding from a stated invariant |
| Review of a scoring change | `code_review` → `anthropic`, `anthropic-foundry`, `claude-cli`, `openai` | Must reason about every branch of `reorderChain` |
| Offline pipeline experiments | `offline` → `ollama` | No network |

The language dimension landed in PR #248 (`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`).
`helios-ai route <task-type> "<prompt>" --language fsharp` tries
`taskRouting["<task-type>:fsharp"]` before the bare task type
(`TaskTypeRoutingStrategy.GetChain(taskType, language)`,
`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs:168-196`; `F#` and `fs` fold to
`fsharp` in `NormalizeLanguage`, `:67-80`). The shipped F# key is `code_generation:fsharp`
(`config/aihub.json:112-118`: `anthropic`, `anthropic-foundry`, then `codex`,
`openai-codex`, `openai` — the reasoning lane first for DU and state-machine work);
`code_review:fsharp` is not configured, so a review with `--language fsharp` runs the bare
`code_review` chain above and records `language: fsharp` on the outcome
(`RoutingOutcome.Language`, `src/ai/HELIOS.AIHub/Learning/LearningStore.cs:27-37`), which
scopes adaptive learning to `(code_review, fsharp)` (`ChainReorderEngine.ForLanguage`,
`src/ai/HELIOS.AIHub/Learning/ChainReorderEngine.cs:49-62`). The `fsharp-reviewer` agent is
under `.claude/agents/fsharp-reviewer.md` and rostered in `config/fleet/fleet-topology.json`
(`xcore-9-code`, line 42; `xcore-9-review`, line 74).
