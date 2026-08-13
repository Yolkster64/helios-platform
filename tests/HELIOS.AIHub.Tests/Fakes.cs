using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Learning;
using HELIOS.AIHub.Providers;
using Microsoft.Extensions.AI;

namespace HELIOS.AIHub.Tests;

/// <summary>Scriptable provider agent for router/facade tests.</summary>
public sealed class FakeProviderAgent : ProviderAgentBase
{
    private readonly ProviderReadiness _readiness;
    private readonly Func<ChatRequest, ChatResult>? _handler;

    public FakeProviderAgent(string provider, ProviderReadiness readiness, Func<ChatRequest, ChatResult>? handler = null)
        : base(provider, $"fake-{provider}", "fake-model")
    {
        _readiness = readiness;
        _handler = handler;
    }

    public override ProviderReadiness Readiness => _readiness;

    public override string? ConfigurationHint =>
        _readiness == ProviderReadiness.Unconfigured ? $"configure {Provider}" : null;

    protected override Task<ChatResult> ChatCoreAsync(ChatRequest request, CancellationToken cancellationToken) =>
        Task.FromResult(_handler?.Invoke(request)
                        ?? new ChatResult(true, $"reply-from-{Provider}", Provider, "fake-model", TimeSpan.Zero));
}

/// <summary>
/// Scripted learning store: GetRecentAsync always answers from the canned history
/// (newest first, per the store contract); appends are collected into
/// <see cref="Recorded"/> and never replayed, so tests stay deterministic.
/// </summary>
public sealed class FakeLearningStore : ILearningStore
{
    private readonly IReadOnlyList<RoutingOutcome> _history;

    public FakeLearningStore(IReadOnlyList<RoutingOutcome>? history = null)
    {
        _history = history ?? Array.Empty<RoutingOutcome>();
    }

    public List<RoutingOutcome> Recorded { get; } = new();

    public Task RecordAsync(RoutingOutcome outcome, CancellationToken cancellationToken = default)
    {
        Recorded.Add(outcome);
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<RoutingOutcome>> GetRecentAsync(
        string taskType, int limit = 200, CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<RoutingOutcome>>(
            _history.Where(h => h.TaskType == taskType).Take(limit).ToList());

    /// <summary>Fixed-timestamp outcome so histories are fully deterministic and keyless.</summary>
    public static RoutingOutcome Outcome(
        string taskType, string provider, bool success, string? source = null) =>
        new()
        {
            Timestamp = DateTimeOffset.UnixEpoch,
            TaskType = taskType,
            Provider = provider,
            Model = "fake-model",
            Success = success,
            LatencyMs = 100,
            CostUsd = 0,
            Source = source,
        };
}

/// <summary>Minimal IChatClient for ChatClientAgent tests.</summary>
public sealed class FakeChatClient : IChatClient
{
    private readonly Func<IEnumerable<ChatMessage>, ChatOptions?, ChatResponse> _handler;

    public FakeChatClient(Func<IEnumerable<ChatMessage>, ChatOptions?, ChatResponse> handler)
    {
        _handler = handler;
    }

    public List<(IReadOnlyList<ChatMessage> Messages, ChatOptions? Options)> Calls { get; } = new();

    public Task<ChatResponse> GetResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null, CancellationToken cancellationToken = default)
    {
        var list = messages.ToList();
        Calls.Add((list, options));
        return Task.FromResult(_handler(list, options));
    }

    public IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null, CancellationToken cancellationToken = default) =>
        throw new NotSupportedException("Streaming is not used in these tests.");

    public object? GetService(Type serviceType, object? serviceKey = null) => null;

    public void Dispose()
    {
    }
}
