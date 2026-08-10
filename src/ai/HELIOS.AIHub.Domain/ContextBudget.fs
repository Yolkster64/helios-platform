namespace HELIOS.AIHub.Domain

open System.Runtime.CompilerServices

/// Context-window fitness checks for multi-LLM routing.
///
/// Before committing to a provider, the hub can ask: does this prompt fit?
/// A 200k-token prompt routed to gpt-4o-mini (128k window) wastes a round-trip.
/// This module makes those comparisons impossible to get wrong by keeping
/// prompt size in one unit and window limits in another — the compiler rejects
/// an accidental direct comparison.
///
/// Hub-and-spoke: pure functions, no I/O. The C# orchestrator measures the
/// prompt (via the C++ native estimator or a simple character heuristic) and
/// calls in with the estimates.
module ContextBudget =

    /// A count of tokens in a single piece of text.
    [<Measure>]
    type token

    /// A context-window capacity in tokens.
    [<Measure>]
    type windowToken

    /// Per-provider context window limit.
    type ProviderWindow =
        { Provider: string
          Model: string
          /// Total context window (prompt + expected completion).
          MaxContextTokens: int<windowToken>
          /// Tokens we expect to need for the completion. Reserve this from the window.
          ReservedOutputTokens: int<windowToken> }

    let private promptCapacity (w: ProviderWindow) : int<windowToken> =
        w.MaxContextTokens - w.ReservedOutputTokens

    /// True when the prompt (in tokens) fits in the provider's context window.
    /// Uses a conversion factor of 1 token ≈ 1 windowToken — the units are
    /// logically distinct (input vs. window), but the conversion rate is 1:1.
    let fits (promptTokens: int<token>) (window: ProviderWindow) : bool =
        let capacity = promptCapacity window
        // Cross-unit comparison via explicit cast — the compiler confirms we meant to do this.
        int promptTokens <= int capacity

    /// Filter a chain to providers whose windows can fit this prompt.
    /// When all providers are filtered out, returns the full chain unchanged so
    /// the caller always has something to try — losing a result is worse than a
    /// truncation warning.
    let filterFits (promptTokens: int<token>) (chain: string list) (windows: ProviderWindow list) : string list =
        let byProvider = windows |> List.map (fun w -> w.Provider, w) |> Map.ofList
        let fitting =
            chain
            |> List.filter (fun provider ->
                match Map.tryFind provider byProvider with
                | Some w -> fits promptTokens w
                | None -> true) // unknown window → don't filter out
        if fitting.IsEmpty then chain else fitting

    /// Rank providers by how much headroom they offer beyond the prompt.
    /// Useful for long-context task routing: prefer the roomiest window when
    /// multiple providers all fit.
    let rankByHeadroom (promptTokens: int<token>) (windows: ProviderWindow list) : (string * int<windowToken>) list =
        windows
        |> List.choose (fun w ->
            let headroom = int (promptCapacity w) - int promptTokens
            if headroom >= 0 then Some (w.Provider, headroom * 1<windowToken>) else None)
        |> List.sortByDescending snd

/// Interop surface for the C# orchestrator.
[<Extension>]
type ContextBudgetInterop =

    /// True when a prompt of the given token count fits in the given window.
    /// reservedOutputTokens is subtracted from maxContextTokens before checking.
    static member Fits
        (promptTokens: int, maxContextTokens: int, reservedOutputTokens: int) : bool =
        let window =
            { ContextBudget.Provider = ""
              ContextBudget.Model = ""
              ContextBudget.MaxContextTokens = maxContextTokens * 1<ContextBudget.windowToken>
              ContextBudget.ReservedOutputTokens = reservedOutputTokens * 1<ContextBudget.windowToken> }
        ContextBudget.fits (promptTokens * 1<ContextBudget.token>) window

    /// Filter a provider chain to those whose windows fit the prompt.
    /// Returns the full chain (as a string[]) when none fit — never returns empty.
    static member FilterFits
        (promptTokens: int,
         chain: string[],
         providerNames: string[],
         maxContextTokens: int[],
         reservedOutputTokens: int[]) : string[] =
        let windows =
            [ for i in 0 .. providerNames.Length - 1 ->
                { ContextBudget.Provider = providerNames.[i]
                  ContextBudget.Model = ""
                  ContextBudget.MaxContextTokens = maxContextTokens.[i] * 1<ContextBudget.windowToken>
                  ContextBudget.ReservedOutputTokens = reservedOutputTokens.[i] * 1<ContextBudget.windowToken> } ]
        ContextBudget.filterFits
            (promptTokens * 1<ContextBudget.token>)
            (List.ofArray chain)
            windows
        |> Array.ofList

    /// Provider → headroom pairs, sorted by most room first.
    static member RankByHeadroom
        (promptTokens: int,
         providerNames: string[],
         maxContextTokens: int[],
         reservedOutputTokens: int[]) : (string * int)[] =
        let windows =
            [ for i in 0 .. providerNames.Length - 1 ->
                { ContextBudget.Provider = providerNames.[i]
                  ContextBudget.Model = ""
                  ContextBudget.MaxContextTokens = maxContextTokens.[i] * 1<ContextBudget.windowToken>
                  ContextBudget.ReservedOutputTokens = reservedOutputTokens.[i] * 1<ContextBudget.windowToken> } ]
        ContextBudget.rankByHeadroom (promptTokens * 1<ContextBudget.token>) windows
        |> List.map (fun (provider, headroom) -> provider, int headroom)
        |> Array.ofList
