using HELIOS.Platform.Core.AI.Interfaces;

namespace HELIOS.AIHub.Abstractions;

/// <summary>A single chat-style request routed to any provider.</summary>
public sealed record ChatRequest(
    string Prompt,
    string? System = null,
    string? Model = null,
    string? TaskType = null,
    int? MaxTokens = null,
    double? Temperature = null);

/// <summary>Normalized result from any provider.</summary>
/// <param name="DuplicateOfProvider">
/// Set by <c>CompareAsync</c>'s dedup pass when this result's text is a near-duplicate of
/// another provider's response (native cosine-similarity check). Names the earliest provider
/// it duplicates; null when the result is unique or dedup didn't run.
/// </param>
public sealed record ChatResult(
    bool Success,
    string? Text,
    string Provider,
    string Model,
    TimeSpan Latency,
    long? InputTokens = null,
    long? OutputTokens = null,
    string? Error = null,
    string? DuplicateOfProvider = null);

/// <summary>Configuration/readiness state of a provider.</summary>
public enum ProviderReadiness
{
    /// <summary>Required secret or endpoint is missing; the provider is registered but inert.</summary>
    Unconfigured,

    /// <summary>Provider has everything it needs to accept requests.</summary>
    Ready,

    /// <summary>Provider is configured but its circuit breaker is open after repeated failures.</summary>
    Degraded,
}

/// <summary>Point-in-time provider status for `helios-ai status` and MCP.</summary>
public sealed record ProviderStatusInfo(
    string Name,
    string Kind,
    string? Model,
    ProviderReadiness Readiness,
    string? Detail);

/// <summary>
/// An IAgent that fronts an LLM provider. Everything the hub registers — API SDK
/// providers, the Foundry agent service, and external CLI processes — implements this.
/// </summary>
public interface IChatProviderAgent : IAgent
{
    /// <summary>Stable provider key used in config, routing tables, and CLI flags.</summary>
    string Provider { get; }

    /// <summary>Readiness derived from configuration, never from a network call.</summary>
    ProviderReadiness Readiness { get; }

    Task<ChatResult> ChatAsync(ChatRequest request, CancellationToken cancellationToken = default);
}
