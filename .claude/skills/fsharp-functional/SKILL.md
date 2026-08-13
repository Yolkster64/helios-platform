---
name: fsharp-functional
description: F# for HELIOS domain modeling and data pipelines — DU/record modeling, railway-oriented Result handling, units of measure for token pricing, FsCheck, and clean C# interop. Use when writing or reviewing F# code, or when modeling domain rules the C# orchestrator will consume.
---

Hub-and-spoke rule: F# is a spoke compiled to a plain .NET assembly loaded IN-PROCESS by the C# orchestrator — pure domain logic and transformations only; the C# hub owns all I/O (HTTP, DB, files, LLM providers).

## Domain modeling: make illegal states unrepresentable

Discriminated unions + records instead of flag/nullable soup. A provider request cannot be both routed and failed:

```fsharp
type ProviderId = ProviderId of string        // single-case DU = zero-cost domain type

type RouteDecision =
    | Routed of provider: ProviderId * reason: string
    | Rejected of RejectReason
    | Deferred of retryAfter: TimeSpan

and RejectReason =
    | OverBudget of limitUsd: decimal
    | ProviderDown of ProviderId
    | NoCapableProvider of requiredCapability: string
```

`match` on `RouteDecision` and the compiler enforces every case is handled — no forgotten `else` branch when a new state is added. Model states, not booleans: `IsRetrying: bool` + `RetryCount: int` becomes `Status = Pending | Retrying of attempt: int | Done of Result<_,_>`.

Records are immutable by default; use `{ req with MaxTokens = 4096 }` copy-and-update rather than mutation.

## Railway-oriented error handling

`Result<'ok,'err>` for expected failures, exceptions only for bugs. Chain with `Result.bind` / `Result.map`:

```fsharp
let route (cfg: HubConfig) (req: LlmRequest) : Result<RoutePlan, RejectReason> =
    validate req
    |> Result.bind (pickProvider cfg)
    |> Result.bind (checkBudget cfg)
    |> Result.map buildPlan
```

Use `Option` for "absent", `Result` for "failed with a reason" — never `null` inside F# code. Collapse at the hub boundary once, not at every step.

## Async interop: task {} CE

Use `task { }` (not `async { }`) for anything the C# orchestrator awaits — it returns a real `Task<'T>` with no `Async.StartAsTask` adapter and correct `ConfigureAwait` semantics on net8.0 (unchanged through .NET 10 LTS):

```fsharp
let scorePlansAsync (plans: RoutePlan seq) : Task<IReadOnlyList<ScoredPlan>> =
    task {
        let scored = plans |> Seq.map score |> Seq.sortByDescending (fun p -> p.Score)
        return upcast ResizeArray scored
    }
```

Reminder: even inside `task`, this spoke computes — it does not open sockets. If a function needs live data, take it as a parameter and let the hub fetch it.

## Type providers: caution

JSON/SQL type providers hard-bind schemas at compile time and drag design-time dependencies into CI. For HELIOS, prefer plain records + `System.Text.Json` deserialization done by the C# hub, with the F# side receiving typed records. If a provider is used (e.g. `FSharp.Data.JsonProvider` for `aihub.json` shape checks in tests), pin the sample file in-repo and keep it out of the shipping assembly.

## Units of measure: capacity and cost

Token pricing bugs are unit bugs. Encode them:

```fsharp
[<Measure>] type token
[<Measure>] type ktoken            // 1000 tokens
[<Measure>] type usd

let perK = 1000.0<token/ktoken>

let inputPrice  : float<usd/ktoken> = 0.003<usd/ktoken>
let cost (n: float<token>) (rate: float<usd/ktoken>) : float<usd> =
    (n / perK) * rate

// cost 12_500.0<token> inputPrice  →  0.0375<usd>
// cost 12_500.0<token> 0.003        →  compile error: missing measure
```

Mixing per-token and per-1k-token rates now fails at compile time. Measures erase at runtime — zero cost, and C# just sees `double`.

## Property-based testing with FsCheck

Test invariants, not examples. Routing must be total and budget-respecting for all inputs:

```fsharp
open FsCheck.Xunit

[<Property>]
let ``routing never exceeds budget`` (req: LlmRequest) (cfg: HubConfig) =
    match route cfg req with
    | Ok plan -> plan.EstimatedCost <= cfg.BudgetPerRequest
    | Error _ -> true

[<Property>]
let ``cost is monotone in token count`` (a: PositiveInt) (b: PositiveInt) =
    a.Get <= b.Get ==> lazy (costOf a.Get <= costOf b.Get)
```

Write custom `Arbitrary` instances for domain types so generated values satisfy construction invariants; shrinkers then hand you minimal counterexamples.

## Spoke packaging and C# interop

The project is a plain `net8.0` class library (`HELIOS.Domain.fsproj`) referenced directly by the orchestrator — no process boundary, no serialization. Public surface rules:

- Never expose `FSharpList`, `FSharpOption`, `FSharpFunc`, or tuples in public APIs. Return `IReadOnlyList<'T>`, `'T` + `TryX` patterns or nullable, and `Task<'T>`.
- `[<CLIMutable>]` on records that C# serializers/binders must materialize (parameterless ctor + settable props, F# still sees them as immutable):

```fsharp
[<CLIMutable>]
type ProviderMetrics = { Name: string; LatencyMs: float; SuccessRate: float }
```

- `[<CompiledName "GetRoutePlan">]` to give C# PascalCase names for camelCase F# functions; group entry points in a module the hub calls like a static class.
- DUs surface to C# as awkward nested classes — wrap decision results in a small record or expose `TryGetRouted(out ...)`-style helpers at the boundary.

## Which LLM to use (via helios-ai / aihub.json)

| Task | Provider | Why |
|---|---|---|
| Domain model design, DU state machines, property-test invariants | anthropic (Claude) | Architecture-level reasoning about state spaces |
| Mechanical C#↔F# conversions, record/DTO mirroring | openai+codex | High-volume mechanical translation |
| Line-level completion inside modules | copilot | Inline completion |
| Offline pipeline experiments | ollama | No network |

## Reference material

`references/analytics-patterns.md` — the domain as shipped in
`src/ai/HELIOS.AIHub.Domain/` (five modules): the Mtoken-based pricing measures actually
in `Pricing.fs`, the `Running`/`observe` fold-and-prequential-replay patterns in
`LearnerFusion.fs`, every C# call site of the interop surface, FsCheck property
candidates (FsCheck itself is not in the repo), and the E38 growth path (GitHub issue
#51). The `ktoken` and FsCheck snippets above are teaching sketches — when they disagree
with the reference file, the reference file mirrors the real code and wins.
