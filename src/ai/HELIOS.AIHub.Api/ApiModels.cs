using HELIOS.AIHub.Abstractions;

namespace HELIOS.AIHub.Api;

public sealed record AskRequest(
    string? Prompt, string? Provider = null, string? Model = null, string? System = null);

public sealed record RouteRequest(string? TaskType, string? Prompt, string? System = null);

public sealed record CompareRequest(
    string? Prompt, IReadOnlyList<string>? Providers = null, string? System = null);

public sealed record ApiError(string Error);

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
