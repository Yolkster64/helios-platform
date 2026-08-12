# Analytics patterns — the F# domain as it actually ships

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Ground truth is the five modules of `src/ai/HELIOS.AIHub.Domain/` (net8.0, zero package
references — `HELIOS.AIHub.Domain.fsproj` compiles them in order: `Pricing.fs`,
`ContextBudget.fs`, `ModelSelection.fs`, `RoutingPolicy.fs`, `LearnerFusion.fs`).
SKILL.md's snippets are teaching sketches; when they disagree with this file, the code wins.

## Units of measure for token pricing (Pricing.fs)

SKILL.md's example prices per thousand tokens (`ktoken`); the shipped module prices per
**million** (`Mtoken`), "the unit providers actually publish prices in" — mixing per-token
and per-million silently produces costs off by 10^6, which is the bug the module exists to
kill (Pricing.fs doc comment).

| Type / function | Shape (Pricing.fs) |
|---|---|
| `[<Measure>] token`, `usd`, `Mtoken` | the only conversion constant is `tokensPerMillion = 1_000_000.0<token/Mtoken>` (private) |
| `ModelRate` | `InputPerMillion` / `OutputPerMillion : float<usd/Mtoken>` + `Provider`/`Model` strings |
| `Usage` | `InputTokens` / `OutputTokens : int64<token>` — measures work on int64 too |
| `costOf : ModelRate -> Usage -> float<usd>` | prices input and output separately, sums |
| `totalCost : (ModelRate * Usage) seq -> float<usd>` | `Seq.sumBy costOf` across mixed models |
| `cheapestFor : Usage -> ModelRate list -> ModelRate option` | sort by cost, `tryHead`; `None` on empty — an empty catalog is a config error, not a $0 answer |
| `withinBudget : float<usd> -> ModelRate -> Usage -> bool` | `costOf ... <= remaining` |
| `allocateBudget : float<usd> -> (string * float) list -> (string * float<usd>) list` | normalizes weights, drops non-positive ones, `[]` when none remain positive |

Pitfalls, in prose. Measures are nominal per declaration site: `LearnerFusion.fs` declares
its own `usd` ("module-scoped, like Pricing's") and `ms`, and `ContextBudget.fs` splits
`token` from `windowToken` even though the rate is 1:1 — so a prompt size cannot meet a
window capacity without the deliberate `int` casts inside `ContextBudget.fits`. Do not
"unify" these; the friction is the design. Attach measures to boundary primitives by
multiplication (`inputTokens * 1L<Pricing.token>`, `x * 1.0<Pricing.usd/Pricing.Mtoken>`)
and strip with `float`/`int` — exactly what `PricingInterop.EstimateCostUsd` does. Measures
erase at runtime: C# only ever sees `double`/`long`.

## Fold/scan pipelines over outcome history (LearnerFusion.fs, RoutingPolicy.fs)

Three aggregation shapes, chosen by the question being asked:

| Question | Pattern | Where |
|---|---|---|
| Per-provider averages for one task type | `Seq.filter >> Seq.groupBy >> Seq.map` into `ProviderStats` | `RoutingPolicy.aggregate` |
| "What did we know *before* each outcome?" | prequential replay: emit a feature row from the prior `Running` state, *then* `observe` | `LearnerFusion.buildTrainingSet` |
| "What do we know *now*, per chain provider?" | `List.fold` of `observe` into `Map<string, Running>` | `LearnerFusion.buildCandidates` |

The reusable core is the private `Running` accumulator plus its step function `observe`
(attempts, successes, latency/cost sums with measures, quality sum/count, and a
newest-first `Recent` list capped at `recentWindow = 3` for the drift feature).
`buildTrainingSet` replays chronologically and skips each provider's first outcome — no
prior state, no sample — which is scan semantics written as a loop over a locally mutable
`Map` + `ResizeArray`: mutation stays inside the function, the function stays pure and
deterministic (asserted by `BuildTrainingSet_IsDeterministic` in
`tests/HELIOS.AIHub.Tests/LearnerFusionTests.cs`). Normalization ranges come from
`contextOf` over the whole window; `NormalizationContext`'s measured fields (`float<ms>`
vs `float<usd>`) make swapping the latency range onto a cost a compile error, and the
generic `inverseNormalized (lo: float<'u>) (hi: float<'u>)` reads 1.0 = best observed.
Evidence gating is smooth on the neural side (`attempts / (attempts + 5.0)` feature;
`mlpWeight` = 0 below `RoutingPolicy.minAttemptsForConfidence = 5`, saturating below 0.5
so the linear score always keeps at least equal say) and hard on the linear side
(`reorderChain` leaves any provider with < 5 attempts in its configured slot and does
nothing unless ≥ 2 providers are confident).

## Pure-function discipline and the C# call sites

Every module computes over snapshots; the C# orchestrator owns I/O, catches failures, and
falls back to the configured chain — "learning must never be able to break routing"
(`src/ai/HELIOS.AIHub/AIHub.cs`, `ApplyLearningAsync` doc).

| F# entry point | C# call site | Contract |
|---|---|---|
| `RoutingPolicyInterop.ReorderChain` | `AIHub.cs` `ApplyLearningAsync` (~line 230), as `??` fallback when `NeuralRoutingLearner.Reorder` returns null | quality `NaN` = unrated (→ `None`); C# pre-filters advisory records (`Source != null`) and re-validates the returned chain against known providers |
| `LearnerFusionInterop.BuildTrainingSet` / `BuildCandidates` / `FuseChain` / `FeatureDim` | `src/ai/HELIOS.AIHub/Learning/NeuralRoutingLearner.cs` (~lines 76–102, 134–141) | parallel arrays **chronological, oldest first** — C# flips the store's newest-first; fixed seed 42 + weight cache keyed on (taskType, count, newest timestamp) keep routing deterministic |
| `ContextBudgetInterop.FilterFits` | `AIHub.cs` `FilterChainByContext` (~line 316) | never returns empty: unknown windows pass through, all-too-small hands back the full chain |
| `PricingInterop.EstimateCostUsd` | `AIHub.cs` `EstimateCostUsd` (~line 644) | catalog rates + reported usage feed the learning loop's cost signal; C# returns 0 without a confident rate match — "a wrong price is worse than an unknown one" |
| `ModelSelectionInterop.SelectBestProvider` / `SelectBestProfile` | `src/ai/HELIOS.AIHub/Configuration/ModelCatalog.cs` (~lines 93, 126) | `""` / empty array = no catalog answer → caller falls back to the configured chain; unknown class/speed/preference strings parse to `FastClass`/`Medium`/`Balanced` |
| `PricingInterop.FitsBudget`; `ContextBudgetInterop.Fits`, `RankByHeadroom` | `FitsBudget`: tests only (`tests/HELIOS.AIHub.Tests/Learning/RoutingPolicyInteropTests.cs`); the two ContextBudget helpers: no callers yet | keep the surface — add callers, not new shapes |

Interop conventions to preserve when extending: parallel primitive arrays in, arrays or
primitives out; `NaN` as the option-none sentinel for quality; absence signalled by `""`
or `[||]`, never by throwing; every never-empty guarantee stated in the doc comment.

## FsCheck property patterns

The suite today is example-based xunit 2.9.3 + Moq (`tests/HELIOS.AIHub.Tests/*.csproj`);
`LearnerFusionTests.cs` already tests invariants (determinism, thin-evidence no-reorder)
as hand-picked cases. Properties worth generating, straight from the code's contracts:

| Property | Grounding |
|---|---|
| `reorderChain` / `fuseChain` return a permutation of the configured chain — never invent, never drop | splice logic maps over `configuredChain`, refilling confident slots from a queue of the same elements (RoutingPolicy.fs, LearnerFusion.fs) |
| fewer than two providers with ≥ 5 attempts ⇒ chain unchanged | `minAttemptsForConfidence` guard in both modules |
| `fuseChain w chain stats Map.empty = reorderChain w chain stats` | `fusedScore` falls back to the linear score when the MLP map has no entry |
| `target success quality` ∈ [0,1] and is monotone in `quality` | clamped 50/50 blend, unrated stays hard 0/1 (LearnerFusion.fs) |
| `Features.Length = SampleCount * featureDim`; `SampleCount` = relevant outcomes − providers with history | prequential first-outcome skip (asserted for one case in `LearnerFusionTests.cs`) |
| `score defaultWeights` ∈ [0,1] when ratings ∈ [0,1] | each term ∈ [0,1], default weights sum to 1.0 (RoutingPolicy.fs) |
| `filterFits` output is a non-empty subsequence of a non-empty chain | fallback-to-full-chain rule (ContextBudget.fs) |
| `allocateBudget` allocations are non-negative and sum to `total` (± ε) when any weight is positive | weight normalization (Pricing.fs) |

Generator pitfall: raw `float` generators produce `NaN`/infinities. At the interop
boundary `NaN` quality *means* "unrated", so piping generated doubles through
`ReorderChain` silently flips `Some`→`None` semantics; and non-finite latencies or costs
make `contextOf`'s min/max range meaningless, poisoning every normalized feature. Generate
domain records (`RoutingPolicy.Outcome`) with clamped `Quality: float option` in [0,1] and
finite non-negative latency/cost instead of testing through the C#-facing arrays.

### Not in the repo (candidates)

FsCheck is not referenced anywhere in the repo. If adopted (per the FsCheck 3.x release
notes and FsCheck.Xunit examples — verified via Context7, `/fscheck/fscheck`): F# code
opens `FsCheck.FSharp`; per-type generators live in immutable `ArbMap`s configured with
`Config.WithArbitrary` (the global mutable `Arb.register` map is gone in 3.x, and defaults
are looked up via `ArbMap.Default.ArbFor<'T>()`); build generator + shrinker pairs with
`Arb.fromGenShrink`; FsCheck.Xunit's `[<Property>]` supports `Replay = "seed"` to pin a
failing case. Decide FsCheck vs FsCheck.Xunit versions at adoption time — pin what CI
proves, and note that adding it to the test csproj is a `pipelines-config` concern too.

## Growth path: the E38 epic

GitHub issue #51 — **"Absorption E38: F# analytics library & platform contracts"** (open,
labels `absorption`, `ai-hub`) tracks absorbing upstream PR #120, "a HELIOS.Analytics.FSharp
library with platform contracts and unit tests — the earliest F# analytics slot, ancestor
to E13's RepositoryAnalytics and E2's scoring modules. Evaluate the contracts against our
F# domain." Same text in `docs/architecture/ABSORPTION_LEDGER.md` § E38; the watchlist row
is `config/absorption/pr-watchlist.json` (pr 120, epic E38, absorb "platform contract
shapes"). Read this as: the five modules here are the seed of a larger analytics library —
absorb *contract shapes* into this domain project rather than merging a parallel
implementation, and remember the stated risk: any new project must join `HELIOS.sln` and
the root csproj glob guards (also a CLAUDE.md hard rule). Process lives in the issue:
`pwsh scripts/absorption/absorb-pr.ps1 -PrNumber 120` or fleet-seed with `-Epic E38`;
upstream is read-only, nothing merges blind.
