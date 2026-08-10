namespace HELIOS.AIHub.Domain

open System
open System.Runtime.CompilerServices

/// Learning-informed routing: turn observed outcomes into the provider order the hub
/// should try next, instead of trusting a hand-written chain forever.
///
/// The static chains in config/aihub.json encode a prior — a considered guess about which
/// model suits which task. This module lets evidence update that prior: if Codex keeps
/// failing on `code_generation` in this codebase while Claude succeeds, the order should
/// change without a human editing JSON. The config chain stays the tie-breaker and the
/// cold-start answer, so behavior is never mysterious on day one.
///
/// F# earns its place here because the scoring is pure arithmetic over immutable records
/// — easy to test exhaustively, impossible to accidentally couple to I/O. The C#
/// orchestrator owns persistence (local JSONL, Azure Table) and calls in with snapshots.
module RoutingPolicy =

    /// One recorded call outcome. The hub appends these; nothing here reads them from disk.
    type Outcome =
        { Provider: string
          TaskType: string
          Success: bool
          LatencyMs: float
          CostUsd: float
          /// Optional human or judge signal in [0,1]. None means "no opinion", which is
          /// different from zero — an unrated success must not look like a bad one.
          Quality: float option }

    /// Aggregated evidence for one provider on one task type.
    type ProviderStats =
        { Provider: string
          Attempts: int
          Successes: int
          MeanLatencyMs: float
          MeanCostUsd: float
          MeanQuality: float option }

    /// How much each signal matters. Tune per deployment; defaults favor correctness,
    /// because a cheap wrong answer costs more than an expensive right one.
    type Weights =
        { Success: float
          Quality: float
          Latency: float
          Cost: float }

    let defaultWeights =
        { Success = 0.55; Quality = 0.25; Latency = 0.10; Cost = 0.10 }

    /// Evidence below this many attempts is too thin to reorder on — keep the config order.
    let minAttemptsForConfidence = 5

    let private mean (xs: float list) =
        match xs with
        | [] -> 0.0
        | _ -> List.average xs

    /// Fold raw outcomes into per-provider stats for a single task type.
    let aggregate (taskType: string) (outcomes: Outcome seq) : ProviderStats list =
        outcomes
        |> Seq.filter (fun o -> o.TaskType = taskType)
        |> Seq.groupBy (fun o -> o.Provider)
        |> Seq.map (fun (provider, calls) ->
            let calls = List.ofSeq calls
            let rated = calls |> List.choose (fun c -> c.Quality)
            { Provider = provider
              Attempts = calls.Length
              Successes = calls |> List.filter (fun c -> c.Success) |> List.length
              MeanLatencyMs = calls |> List.map (fun c -> c.LatencyMs) |> mean
              MeanCostUsd = calls |> List.map (fun c -> c.CostUsd) |> mean
              MeanQuality = if rated.IsEmpty then None else Some(mean rated) })
        |> List.ofSeq

    /// Normalize so that lower is better for latency and cost: 1.0 is the best observed,
    /// 0.0 the worst. A single sample scores 1.0 — with nothing to compare against, the
    /// neutral reading is "no evidence of being slow", not "assume the worst".
    let private inverseNormalized (values: float list) (value: float) =
        match values with
        | [] -> 1.0
        | _ ->
            let lo, hi = List.min values, List.max values
            if hi - lo < 1e-9 then 1.0 else 1.0 - ((value - lo) / (hi - lo))

    /// Score in [0,1]. Unrated providers fall back to their success rate for the quality
    /// term so that "never judged" is not silently punished relative to "judged poorly".
    let score (weights: Weights) (all: ProviderStats list) (stats: ProviderStats) : float =
        let successRate =
            if stats.Attempts = 0 then 0.0
            else float stats.Successes / float stats.Attempts
        let latencies = all |> List.map (fun s -> s.MeanLatencyMs)
        let costs = all |> List.map (fun s -> s.MeanCostUsd)
        let quality = defaultArg stats.MeanQuality successRate
        weights.Success * successRate
        + weights.Quality * quality
        + weights.Latency * inverseNormalized latencies stats.MeanLatencyMs
        + weights.Cost * inverseNormalized costs stats.MeanCostUsd

    /// Reorder the configured chain using evidence.
    ///
    /// Providers with thin evidence keep their configured position — this is what stops a
    /// single unlucky failure from demoting a good provider. Providers never named in the
    /// config are not invented here; routing only ever picks from what the operator
    /// allowed.
    let reorderChain
        (weights: Weights)
        (configuredChain: string list)
        (stats: ProviderStats list)
        : string list =
        let byProvider = stats |> List.map (fun s -> s.Provider, s) |> Map.ofList
        let confident =
            configuredChain
            |> List.filter (fun p ->
                match Map.tryFind p byProvider with
                | Some s -> s.Attempts >= minAttemptsForConfidence
                | None -> false)
        if confident.Length < 2 then
            configuredChain
        else
            let confidentStats = confident |> List.map (fun p -> byProvider.[p])
            let ranked =
                confident
                |> List.sortByDescending (fun p -> score weights confidentStats byProvider.[p])
            // Splice the reordered confident providers back into their original slots,
            // leaving low-evidence providers exactly where the operator put them.
            let mutable queue = ranked
            configuredChain
            |> List.map (fun p ->
                if List.contains p confident then
                    match queue with
                    | head :: tail ->
                        queue <- tail
                        head
                    | [] -> p
                else p)

    /// A short, human-readable justification. Routing that cannot explain itself is
    /// routing nobody will trust enough to leave switched on.
    let explain (configuredChain: string list) (reordered: string list) (stats: ProviderStats list) : string =
        if configuredChain = reordered then
            "Using the configured chain: not enough evidence to reorder."
        else
            let summary =
                stats
                |> List.filter (fun s -> s.Attempts >= minAttemptsForConfidence)
                |> List.map (fun s ->
                    sprintf "%s %d/%d ok" s.Provider s.Successes s.Attempts)
                |> String.concat ", "
            sprintf "Reordered %s -> %s (%s)"
                (String.concat "→" configuredChain) (String.concat "→" reordered) summary

/// Interop surface for the C# orchestrator: plain arrays and primitives only.
[<Extension>]
type RoutingPolicyInterop =

    /// Reorder a configured provider chain from recorded outcomes.
    /// Quality is passed as NaN where no rating exists — NaN means "unrated", which the
    /// policy treats differently from a zero score.
    static member ReorderChain
        (taskType: string,
         configuredChain: string[],
         providers: string[],
         successes: bool[],
         latenciesMs: float[],
         costsUsd: float[],
         qualities: float[]) : string[] =
        let n = providers.Length
        if n = 0 || configuredChain.Length = 0 then configuredChain
        else
            let outcomes =
                [ for i in 0 .. n - 1 ->
                    { RoutingPolicy.Provider = providers.[i]
                      RoutingPolicy.TaskType = taskType
                      RoutingPolicy.Success = successes.[i]
                      RoutingPolicy.LatencyMs = latenciesMs.[i]
                      RoutingPolicy.CostUsd = costsUsd.[i]
                      RoutingPolicy.Quality =
                        if Double.IsNaN qualities.[i] then None else Some qualities.[i] } ]
            let stats = RoutingPolicy.aggregate taskType outcomes
            RoutingPolicy.reorderChain RoutingPolicy.defaultWeights (List.ofArray configuredChain) stats
            |> Array.ofList
