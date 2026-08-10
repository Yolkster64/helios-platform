namespace HELIOS.AIHub.Domain

open System
open System.Runtime.CompilerServices

/// Token accounting and cost estimation for the multi-LLM hub.
///
/// This lives in F# because units of measure make a whole class of bug unrepresentable:
/// provider pricing is quoted per *million* tokens while usage arrives as *single*
/// tokens, and mixing the two silently produces costs off by 10^6. The compiler now
/// rejects that instead of the invoice discovering it.
///
/// Hub-and-spoke: pure functions only. No HTTP, no files, no clock — the C# orchestrator
/// gathers inputs and decides what to do with the answers.
module Pricing =

    /// A single token.
    [<Measure>]
    type token

    /// United States dollars.
    [<Measure>]
    type usd

    /// One million tokens — the unit providers actually publish prices in.
    [<Measure>]
    type Mtoken

    let private tokensPerMillion = 1_000_000.0<token/Mtoken>

    /// Published price for one provider/model pair.
    type ModelRate =
        { Provider: string
          Model: string
          InputPerMillion: float<usd/Mtoken>
          OutputPerMillion: float<usd/Mtoken> }

    /// Observed usage for a single completed call.
    type Usage =
        { InputTokens: int64<token>
          OutputTokens: int64<token> }

    let private toMillions (t: int64<token>) : float<Mtoken> =
        float t * 1.0<token> / tokensPerMillion

    /// Cost of one call at the given rate.
    let costOf (rate: ModelRate) (usage: Usage) : float<usd> =
        toMillions usage.InputTokens * rate.InputPerMillion
        + toMillions usage.OutputTokens * rate.OutputPerMillion

    /// Total cost across many calls that may span different models.
    let totalCost (priced: (ModelRate * Usage) seq) : float<usd> =
        priced |> Seq.sumBy (fun (rate, usage) -> costOf rate usage)

    /// Cheapest rate that can serve a call of the given expected shape.
    /// Returns None when no candidates were supplied, which the caller must handle —
    /// an empty provider list is a configuration problem, not a zero-cost answer.
    let cheapestFor (expected: Usage) (candidates: ModelRate list) : ModelRate option =
        candidates
        |> List.sortBy (fun rate -> float (costOf rate expected))
        |> List.tryHead

    /// Does this call fit in what's left of the budget?
    let withinBudget (remaining: float<usd>) (rate: ModelRate) (expected: Usage) : bool =
        costOf rate expected <= remaining

    /// Split a budget across providers by weight, dropping non-positive weights.
    /// Weights need not sum to one; they are normalized.
    let allocateBudget (total: float<usd>) (weights: (string * float) list) : (string * float<usd>) list =
        let positive = weights |> List.filter (fun (_, w) -> w > 0.0)
        let sum = positive |> List.sumBy snd
        if sum <= 0.0 then []
        else positive |> List.map (fun (name, w) -> name, total * (w / sum))

/// Interop surface for the C# orchestrator.
///
/// F#-only types (options, units of measure, F# lists) never cross this boundary — the
/// csharp-orchestrator skill's rule. C# sees plain doubles, longs, and nullables.
[<Extension>]
type PricingInterop =

    /// Cost in USD for a call. Rates are per million tokens, as providers publish them.
    static member EstimateCostUsd
        (inputPerMillionUsd: float, outputPerMillionUsd: float, inputTokens: int64, outputTokens: int64) : float =
        let rate =
            { Pricing.Provider = ""
              Pricing.Model = ""
              Pricing.InputPerMillion = inputPerMillionUsd * 1.0<Pricing.usd/Pricing.Mtoken>
              Pricing.OutputPerMillion = outputPerMillionUsd * 1.0<Pricing.usd/Pricing.Mtoken> }
        let usage =
            { Pricing.InputTokens = inputTokens * 1L<Pricing.token>
              Pricing.OutputTokens = outputTokens * 1L<Pricing.token> }
        float (Pricing.costOf rate usage)

    /// True when the call fits the remaining budget.
    static member FitsBudget
        (remainingUsd: float, inputPerMillionUsd: float, outputPerMillionUsd: float,
         inputTokens: int64, outputTokens: int64) : bool =
        PricingInterop.EstimateCostUsd(inputPerMillionUsd, outputPerMillionUsd, inputTokens, outputTokens)
        <= remainingUsd
