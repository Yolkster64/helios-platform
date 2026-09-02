using System.Text.Json;
using HELIOS.AIHub.Abstractions;

namespace HELIOS.AIHub.Api;

public sealed record AskRequest(
    string? Prompt, string? Provider = null, string? Model = null, string? System = null);

public sealed record RouteRequest(string? TaskType, string? Prompt, string? System = null);

public sealed record CompareRequest(
    string? Prompt, IReadOnlyList<string>? Providers = null, string? System = null);

public sealed record ApiError(string Error);

/// <summary>
/// Advisory outcome ingested from outside the hub (absorption benchmarks, fork
/// digests). Source is REQUIRED: live provider outcomes are recorded only by the
/// hub itself, and adaptive routing ignores everything that carries a Source.
/// </summary>
public sealed record AdvisoryOutcomeRequest(
    string? TaskType,
    string? Source,
    string? Provider,
    string? Model,
    bool Success,
    double LatencyMs = 0,
    double CostUsd = 0,
    double? Quality = null,
    string? Pool = null);

/// <summary>
/// <see cref="ChatResult"/> shaped for the wire: latency as plain milliseconds instead of
/// a serialized TimeSpan, so any HTTP client reads it without .NET conventions.
/// </summary>
public sealed record ChatResponse(
    bool Success,
    string? Text,
    string Provider,
    string Model,
    double LatencyMs,
    long? InputTokens,
    long? OutputTokens,
    string? Error,
    string? DuplicateOfProvider)
{
    public static ChatResponse From(ChatResult result) => new(
        result.Success, result.Text, result.Provider, result.Model,
        result.Latency.TotalMilliseconds, result.InputTokens, result.OutputTokens,
        result.Error, result.DuplicateOfProvider);
}

public sealed record TandemResponse(
    string TaskType, IReadOnlyList<ChatResponse> Results, string? Winner);

public sealed record ProviderStatusResponse(
    string Name, string Kind, string? Model, string Readiness, string? Detail)
{
    public static ProviderStatusResponse From(ProviderStatusInfo info) => new(
        info.Name, info.Kind, info.Model, info.Readiness.ToString(), info.Detail);
}

public sealed record RoutingTableResponse(
    IReadOnlyList<string> DefaultChain,
    IReadOnlyDictionary<string, IReadOnlyList<string>> TaskRouting);

/// <summary>
/// Python-spoke analytics over recorded routing outcomes. <c>Available=false</c> with a
/// hint (rather than an error status) when the spoke isn't runnable here — insights are
/// advisory and their absence is a state, not a failure.
/// </summary>
public sealed record InsightsResponse(
    string TaskType,
    bool Available,
    string? Hint,
    JsonElement? Summary,
    JsonElement? Drift);

/// <summary>
/// Per-provider telemetry over the recent learning window (the dashboard seam —
/// GUI_UPGRADE_PLAN P2). <c>WindowSize</c> is the number of outcomes actually
/// aggregated, which can be smaller than the requested limit. Providers are ordered by
/// attempts descending, then name, so the busiest lane renders first and the order is
/// deterministic. A null <c>Message</c> means data was aggregated; an empty window
/// explains itself through <c>Message</c> instead of a non-200 status — like
/// /v1/insights, absence of telemetry is a state, not a failure.
/// </summary>
public sealed record MetricsResponse(
    DateTimeOffset GeneratedUtc,
    int WindowSize,
    IReadOnlyList<ProviderMetricsResponse> Providers,
    string? Message);

/// <summary>
/// Aggregates for one provider. Like /v1/insights (and unlike adaptive routing and
/// fleet-plan, which exclude every source-tagged record), the window deliberately
/// INCLUDES advisory outcomes — this is telemetry display, not routing input — and
/// <c>AdvisoryCount</c> says how many of <c>Attempts</c> carry a source tag.
/// <c>AverageQuality</c> averages only rated outcomes and is null when none are rated.
/// <c>TokensUsed</c> and <c>CostPerMillionTokens</c> are always null today:
/// <see cref="HELIOS.AIHub.Learning.RoutingOutcome"/> does not persist token counts, so
/// neither value can be derived honestly. They stay in the contract, explicitly null,
/// so dashboard cards keep a stable shape if token capture lands later; cost is instead
/// reported as recorded — <c>TotalCostUsd</c> and per-call <c>AverageCostUsd</c>.
/// </summary>
public sealed record ProviderMetricsResponse(
    string Provider,
    int Attempts,
    int Successes,
    int AdvisoryCount,
    double SuccessRate,
    double AverageLatencyMs,
    double TotalCostUsd,
    double AverageCostUsd,
    double? AverageQuality,
    long? TokensUsed,
    double? CostPerMillionTokens);

public sealed record EngineRecommendationRequest(
    bool CudaEnabled = false,
    string? SecurityProfile = "balanced",
    double OptimizationPressure = 0.5,
    int FleetSize = 0,
    bool IncludeCandidates = false);

/// <summary>
/// A local, read-only Python-spoke answer. Candidate engines are architecture proposals,
/// never an instruction to install or execute arbitrary code.
/// </summary>
public sealed record EngineAdvisoryResponse(
    bool Available,
    string? Hint,
    JsonElement? Result);
