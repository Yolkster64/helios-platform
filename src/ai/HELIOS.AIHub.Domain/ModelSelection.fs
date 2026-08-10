namespace HELIOS.AIHub.Domain

open System.Runtime.CompilerServices

/// Picks a model from the static catalog (config/model-catalog.json) by an explicit
/// preference, rather than the fixed config/aihub.json chain. This is the "optimize for
/// cost, speed, or quality across every provider" lever: the catalog says what each
/// model costs and how it's classed; this module turns a preference into an ordering.
///
/// Deliberately separate from RoutingPolicy: that module reorders a chain from *observed*
/// outcomes in this codebase; this one ranks from *published* characteristics. The hub
/// composes them — catalog picks the initial candidate set for a preference, learning
/// then reorders among providers that are actually configured and have a track record.
module ModelSelection =

    type SpeedClass =
        | Fast
        | Medium
        | Slow
        | HardwareBound

    type ModelClass =
        | Frontier
        | BalancedClass
        | Specialist
        | FastClass
        | Local

    type ModelProfile =
        { Provider: string
          Model: string
          Class: ModelClass
          ContextTokens: int
          InputPerMillionUsd: float
          OutputPerMillionUsd: float
          Speed: SpeedClass
          Strengths: string list }

    /// What the caller is optimizing for. Cost and Quality are opposing pulls by design —
    /// Balanced is the honest middle, not a fourth independent axis.
    type Preference =
        | CostSensitive
        | LatencySensitive
        | QualitySensitive
        | Balanced

    let private speedRank =
        function
        | Fast -> 0
        | Medium -> 1
        | HardwareBound -> 1
        | Slow -> 2

    let private classRank =
        function
        | Frontier -> 0
        | BalancedClass -> 1
        | Specialist -> 1
        | FastClass -> 2
        | Local -> 2

    let private estimatedCost (m: ModelProfile) =
        m.InputPerMillionUsd + m.OutputPerMillionUsd

    /// Candidates whose published strengths cover the task type. Empty when the catalog
    /// has no opinion — the caller should fall back to the configured routing chain
    /// rather than treat "no match" as "any model will do".
    let candidatesFor (taskType: string) (catalog: ModelProfile list) : ModelProfile list =
        catalog |> List.filter (fun m -> List.contains taskType m.Strengths)

    /// Order candidates by preference. Ties break toward the option that satisfies the
    /// preference most strongly on the OTHER axes too, so "cost-sensitive" among equally
    /// cheap options still prefers the faster or better-classed one rather than an
    /// arbitrary catalog order.
    let rank (preference: Preference) (candidates: ModelProfile list) : ModelProfile list =
        match preference with
        | CostSensitive ->
            candidates |> List.sortBy (fun m -> estimatedCost m, speedRank m.Speed, classRank m.Class)
        | LatencySensitive ->
            candidates |> List.sortBy (fun m -> speedRank m.Speed, estimatedCost m)
        | QualitySensitive ->
            candidates |> List.sortBy (fun m -> classRank m.Class, -m.ContextTokens)
        | Balanced ->
            // Normalize cost and speed onto comparable [0,1] scales and split the
            // difference with class — no single axis dominates by construction.
            match candidates with
            | [] -> []
            | _ ->
                let costs = candidates |> List.map estimatedCost
                let lo, hi = List.min costs, List.max costs
                let normCost m =
                    if hi - lo < 1e-9 then 0.0 else (estimatedCost m - lo) / (hi - lo)
                candidates
                |> List.sortBy (fun m ->
                    normCost m * 0.4
                    + float (speedRank m.Speed) / 2.0 * 0.3
                    + float (classRank m.Class) / 2.0 * 0.3)

    /// Best single model for a task under a preference, or None when the catalog has no
    /// entry for that task type at all.
    let selectBest (taskType: string) (preference: Preference) (catalog: ModelProfile list) : ModelProfile option =
        candidatesFor taskType catalog |> rank preference |> List.tryHead

/// Interop surface for the C# orchestrator and the helios-ai CLI's --optimize flag.
[<Extension>]
type ModelSelectionInterop =

    /// Returns "" when no catalog entry covers the task type — the caller should fall
    /// back to config/aihub.json's routing chain rather than guess.
    static member SelectBestProvider
        (taskType: string,
         preference: string,
         providers: string[], models: string[], classes: string[],
         contextTokens: int[], inputCostPerM: float[], outputCostPerM: float[],
         speeds: string[], strengthsCsv: string[]) : string =
        let n = providers.Length
        let parseClass =
            function
            | "frontier" -> ModelSelection.Frontier
            | "balanced" -> ModelSelection.BalancedClass
            | "specialist" -> ModelSelection.Specialist
            | "local" -> ModelSelection.Local
            | _ -> ModelSelection.FastClass
        let parseSpeed =
            function
            | "fast" -> ModelSelection.Fast
            | "slow" -> ModelSelection.Slow
            | "hardware-bound" -> ModelSelection.HardwareBound
            | _ -> ModelSelection.Medium
        let parsePreference =
            function
            | "cost" -> ModelSelection.CostSensitive
            | "latency" -> ModelSelection.LatencySensitive
            | "quality" -> ModelSelection.QualitySensitive
            | _ -> ModelSelection.Balanced

        let catalog =
            [ for i in 0 .. n - 1 ->
                { ModelSelection.Provider = providers.[i]
                  ModelSelection.Model = models.[i]
                  ModelSelection.Class = parseClass classes.[i]
                  ModelSelection.ContextTokens = contextTokens.[i]
                  ModelSelection.InputPerMillionUsd = inputCostPerM.[i]
                  ModelSelection.OutputPerMillionUsd = outputCostPerM.[i]
                  ModelSelection.Speed = parseSpeed speeds.[i]
                  ModelSelection.Strengths = strengthsCsv.[i].Split(',') |> Array.toList } ]

        match ModelSelection.selectBest taskType (parsePreference preference) catalog with
        | Some m -> m.Provider
        | None -> ""
