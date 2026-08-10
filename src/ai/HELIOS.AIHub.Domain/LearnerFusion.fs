namespace HELIOS.AIHub.Domain

open System

/// Deep-learning fusion for routing: turn outcome history into MLP training data and
/// blend the MLP's per-provider predictions with the linear RoutingPolicy score.
///
/// The linear policy (RoutingPolicy.fs) weighs four averaged signals. Averages cannot
/// express interactions — "fast but only when cheap", "reliable until quality drops" —
/// which is exactly what the C++ MLP spoke (helios_mlp_*) exists to capture. This module
/// owns everything about that learner that is pure math: which features describe a
/// provider, how outcomes become soft training targets, and how much the network's
/// opinion counts against the linear prior. The C# orchestrator owns the actual native
/// calls — spokes never call each other, so no P/Invoke appears here.
///
/// F# earns its place the same way as in Pricing.fs: units of measure make it a compile
/// error to normalize a latency against the cost range (both end up as bare floats in
/// the feature vector, so a swap would otherwise be silent and permanent), and pure
/// functions over immutable records keep every step replayable in tests.
module LearnerFusion =

    /// A millisecond of wall-clock latency.
    [<Measure>]
    type ms

    /// United States dollars (module-scoped, like Pricing's).
    [<Measure>]
    type usd

    /// Inputs per provider snapshot fed to the native MLP. Keep in sync with featuresOf;
    /// the native side validates buffer sizes against whatever dim the caller passes, so
    /// a mismatch here fails fast rather than corrupting.
    let featureDim = 6

    /// How many trailing outcomes feed the drift feature. Small on purpose: its whole
    /// job is to notice "this provider changed recently", which a long tail would smooth
    /// away into the overall success rate.
    let private recentWindow = 3

    /// Evidence accumulated for one provider as history is replayed in order.
    type private Running =
        { Attempts: int
          Successes: int
          LatencySum: float<ms>
          CostSum: float<usd>
          QualitySum: float
          QualityCount: int
          /// Newest first, capped at recentWindow.
          Recent: bool list }

    let private emptyRunning =
        { Attempts = 0
          Successes = 0
          LatencySum = 0.0<ms>
          CostSum = 0.0<usd>
          QualitySum = 0.0
          QualityCount = 0
          Recent = [] }

    let private observe (r: Running) (o: RoutingPolicy.Outcome) =
        { Attempts = r.Attempts + 1
          Successes = r.Successes + (if o.Success then 1 else 0)
          LatencySum = r.LatencySum + o.LatencyMs * 1.0<ms>
          CostSum = r.CostSum + o.CostUsd * 1.0<usd>
          QualitySum = r.QualitySum + defaultArg o.Quality 0.0
          QualityCount = r.QualityCount + (if o.Quality.IsSome then 1 else 0)
          Recent = o.Success :: List.truncate (recentWindow - 1) r.Recent }

    /// Global normalization ranges for the window. Measured fields mean the latency
    /// range cannot be applied to a cost (or vice versa) without a compile error.
    type NormalizationContext =
        { LatencyLo: float<ms>
          LatencyHi: float<ms>
          CostLo: float<usd>
          CostHi: float<usd> }

    let contextOf (outcomes: RoutingPolicy.Outcome list) : NormalizationContext =
        match outcomes with
        | [] ->
            { LatencyLo = 0.0<ms>; LatencyHi = 0.0<ms>; CostLo = 0.0<usd>; CostHi = 0.0<usd> }
        | _ ->
            let lats = outcomes |> List.map (fun o -> o.LatencyMs * 1.0<ms>)
            let costs = outcomes |> List.map (fun o -> o.CostUsd * 1.0<usd>)
            { LatencyLo = List.min lats
              LatencyHi = List.max lats
              CostLo = List.min costs
              CostHi = List.max costs }

    /// 1.0 at the best (lowest) observed value, 0.0 at the worst — the same "lower is
    /// better" reading RoutingPolicy uses, generic over the measure so each range only
    /// accepts its own quantity.
    let private inverseNormalized (lo: float<'u>) (hi: float<'u>) (v: float<'u>) : float =
        let span = float (hi - lo)
        if span < 1e-9 then 1.0
        else max 0.0 (min 1.0 (1.0 - float (v - lo) / span))

    let private featuresOf (ctx: NormalizationContext) (r: Running) : float32[] =
        let attempts = float r.Attempts
        let successRate = float r.Successes / attempts
        let quality =
            if r.QualityCount > 0 then r.QualitySum / float r.QualityCount else successRate
        let recentRate =
            match r.Recent with
            | [] -> successRate
            | xs -> float (xs |> List.filter id |> List.length) / float xs.Length
        [| float32 successRate
           float32 (inverseNormalized ctx.LatencyLo ctx.LatencyHi (r.LatencySum / attempts))
           float32 (inverseNormalized ctx.CostLo ctx.CostHi (r.CostSum / attempts))
           float32 quality
           // Evidence mass, saturating: lets the network learn to discount thin records
           // the way minAttemptsForConfidence does for the linear policy, but smoothly.
           float32 (attempts / (attempts + 5.0))
           float32 recentRate |]

    /// Soft target in [0,1]. Success is the primary signal; a quality rating, when one
    /// exists, refines it — a sloppy success should score below a clean one. Unrated
    /// stays pure 0/1 so "never judged" is not punished, mirroring RoutingPolicy.score.
    let target (success: bool) (quality: float option) : float =
        let s = if success then 1.0 else 0.0
        match quality with
        | Some q -> 0.5 * s + 0.5 * (max 0.0 (min 1.0 q))
        | None -> s

    /// Flat row-major training data, shaped for helios_mlp_train.
    type TrainingSet =
        { Features: float32[]
          Targets: float32[]
          SampleCount: int }

    /// Build training pairs prequentially: each outcome is predicted from the provider's
    /// state *before* that outcome, exactly the question routing asks at decision time
    /// ("given what I know now, will this call succeed?"). A provider's first outcome
    /// yields no sample — there is no prior state to predict from.
    ///
    /// Outcomes must be in chronological order (oldest first); the caller flips the
    /// store's newest-first reads. Normalization uses the whole window's latency/cost
    /// range — deterministic and honest enough, since ranges move far slower than means.
    let buildTrainingSet (taskType: string) (outcomes: RoutingPolicy.Outcome list) : TrainingSet =
        let relevant = outcomes |> List.filter (fun o -> o.TaskType = taskType)
        let ctx = contextOf relevant
        let features = ResizeArray<float32>()
        let targets = ResizeArray<float32>()
        let mutable state = Map.empty<string, Running>
        for o in relevant do
            let running = state |> Map.tryFind o.Provider |> Option.defaultValue emptyRunning
            if running.Attempts > 0 then
                features.AddRange(featuresOf ctx running)
                targets.Add(float32 (target o.Success o.Quality))
            state <- state |> Map.add o.Provider (observe running o)
        { Features = features.ToArray()
          Targets = targets.ToArray()
          SampleCount = targets.Count }

    /// Per-candidate prediction inputs: one feature row per chain provider that has any
    /// recorded history, in chain order.
    type CandidateSet =
        { Providers: string[]
          Features: float32[]
          Attempts: int[] }

    let buildCandidates
        (taskType: string)
        (configuredChain: string list)
        (outcomes: RoutingPolicy.Outcome list)
        : CandidateSet =
        let relevant = outcomes |> List.filter (fun o -> o.TaskType = taskType)
        let ctx = contextOf relevant
        let finalState =
            relevant
            |> List.fold
                (fun (m: Map<string, Running>) o ->
                    let r = m |> Map.tryFind o.Provider |> Option.defaultValue emptyRunning
                    Map.add o.Provider (observe r o) m)
                Map.empty
        let candidates =
            configuredChain
            |> List.filter (fun p ->
                match Map.tryFind p finalState with
                | Some r -> r.Attempts > 0
                | None -> false)
        { Providers = Array.ofList candidates
          Features =
            candidates
            |> List.collect (fun p -> List.ofArray (featuresOf ctx finalState.[p]))
            |> Array.ofList
          Attempts = candidates |> List.map (fun p -> finalState.[p].Attempts) |> Array.ofList }

    /// How much the MLP's opinion counts, by evidence mass. Zero below the same
    /// confidence floor the linear policy uses; grows with attempts but never past one
    /// half, so the interpretable linear score always keeps at least equal say. The
    /// network refines routing — it is never allowed to own it.
    let mlpWeight (attempts: int) : float =
        if attempts < RoutingPolicy.minAttemptsForConfidence then 0.0
        else 0.5 * float attempts / (float attempts + 10.0)

    /// Reorder the configured chain by the confidence-gated blend of linear score and
    /// MLP prediction. Same contract as RoutingPolicy.reorderChain: thin-evidence
    /// providers keep their configured slots, fewer than two confident providers means
    /// no reorder, and only operator-configured providers ever appear.
    let fuseChain
        (weights: RoutingPolicy.Weights)
        (configuredChain: string list)
        (stats: RoutingPolicy.ProviderStats list)
        (mlpScores: Map<string, float>)
        : string list =
        let byProvider = stats |> List.map (fun s -> s.Provider, s) |> Map.ofList
        let confident =
            configuredChain
            |> List.filter (fun p ->
                match Map.tryFind p byProvider with
                | Some s -> s.Attempts >= RoutingPolicy.minAttemptsForConfidence
                | None -> false)
        if confident.Length < 2 then
            configuredChain
        else
            let confidentStats = confident |> List.map (fun p -> byProvider.[p])
            let fusedScore p =
                let s = byProvider.[p]
                let linear = RoutingPolicy.score weights confidentStats s
                match Map.tryFind p mlpScores with
                | Some prediction ->
                    let w = mlpWeight s.Attempts
                    (1.0 - w) * linear + w * prediction
                | None -> linear
            let ranked = confident |> List.sortByDescending fusedScore
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

/// Interop surface for the C# orchestrator: plain arrays and primitives only.
///
/// All outcome arrays are parallel and must be in chronological order (oldest first) —
/// prequential training replays history forward. Quality is NaN where no rating exists.
/// The C# side owns every native MLP call; this type only builds the MLP's inputs and
/// fuses its outputs.
type LearnerFusionInterop =

    static member FeatureDim = LearnerFusion.featureDim

    static member private ToOutcomes
        (taskType: string,
         providers: string[],
         successes: bool[],
         latenciesMs: float[],
         costsUsd: float[],
         qualities: float[]) : RoutingPolicy.Outcome list =
        [ for i in 0 .. providers.Length - 1 ->
            { RoutingPolicy.Provider = providers.[i]
              RoutingPolicy.TaskType = taskType
              RoutingPolicy.Success = successes.[i]
              RoutingPolicy.LatencyMs = latenciesMs.[i]
              RoutingPolicy.CostUsd = costsUsd.[i]
              RoutingPolicy.Quality =
                if Double.IsNaN qualities.[i] then None else Some qualities.[i] } ]

    /// Flat prequential training data for helios_mlp_train.
    static member BuildTrainingSet
        (taskType: string,
         providers: string[],
         successes: bool[],
         latenciesMs: float[],
         costsUsd: float[],
         qualities: float[]) : LearnerFusion.TrainingSet =
        LearnerFusionInterop.ToOutcomes(taskType, providers, successes, latenciesMs, costsUsd, qualities)
        |> LearnerFusion.buildTrainingSet taskType

    /// One feature row per chain provider with history, in chain order, for
    /// helios_mlp_predict.
    static member BuildCandidates
        (taskType: string,
         configuredChain: string[],
         providers: string[],
         successes: bool[],
         latenciesMs: float[],
         costsUsd: float[],
         qualities: float[]) : LearnerFusion.CandidateSet =
        LearnerFusionInterop.ToOutcomes(taskType, providers, successes, latenciesMs, costsUsd, qualities)
        |> LearnerFusion.buildCandidates taskType (List.ofArray configuredChain)

    /// Blend MLP predictions (aligned with candidateProviders) into the chain order.
    static member FuseChain
        (taskType: string,
         configuredChain: string[],
         providers: string[],
         successes: bool[],
         latenciesMs: float[],
         costsUsd: float[],
         qualities: float[],
         candidateProviders: string[],
         candidateScores: float[]) : string[] =
        let outcomes =
            LearnerFusionInterop.ToOutcomes(taskType, providers, successes, latenciesMs, costsUsd, qualities)
        let stats = RoutingPolicy.aggregate taskType outcomes
        let mlpScores =
            Seq.zip candidateProviders candidateScores |> Map.ofSeq
        LearnerFusion.fuseChain
            RoutingPolicy.defaultWeights
            (List.ofArray configuredChain)
            stats
            mlpScores
        |> Array.ofList
