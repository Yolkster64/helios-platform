using HELIOS.AIHub.Abstractions;
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
