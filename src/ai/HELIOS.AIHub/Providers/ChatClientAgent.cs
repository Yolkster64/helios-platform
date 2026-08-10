using System.Collections.Concurrent;
using System.Diagnostics;
using HELIOS.AIHub.Abstractions;
using Microsoft.Extensions.AI;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// One provider agent over Microsoft.Extensions.AI's IChatClient — covers OpenAI,
/// GitHub Models, Azure OpenAI, and Ollama with a single implementation. The factory is
/// keyed by model name so per-request model overrides get their own cached client.
/// </summary>
public sealed class ChatClientAgent : ProviderAgentBase
{
    private readonly Func<string, IChatClient>? _clientFactory;
    private readonly ConcurrentDictionary<string, IChatClient> _clients = new(StringComparer.Ordinal);
    private readonly string? _configurationHint;

    /// <param name="clientFactory">Model name → client. Null means the provider is unconfigured.</param>
    /// <param name="configurationHint">Shown in status output when unconfigured (e.g. "set OPENAI_API_KEY").</param>
    public ChatClientAgent(
        string provider,
        string displayName,
        string? defaultModel,
        Func<string, IChatClient>? clientFactory,
        string? configurationHint = null)
        : base(provider, displayName, defaultModel)
    {
        _clientFactory = clientFactory;
        _configurationHint = configurationHint;
    }

    public override ProviderReadiness Readiness =>
        _clientFactory is null ? ProviderReadiness.Unconfigured : ProviderReadiness.Ready;

    public override string? ConfigurationHint => _configurationHint;

    protected override async Task<ChatResult> ChatCoreAsync(ChatRequest request, CancellationToken cancellationToken)
    {
        var model = request.Model ?? DefaultModel
            ?? throw new InvalidOperationException($"Provider '{Provider}' has no model configured; pass one explicitly.");
        var client = _clients.GetOrAdd(model, _clientFactory!);

        var messages = new List<ChatMessage>();
        if (!string.IsNullOrWhiteSpace(request.System))
        {
            messages.Add(new ChatMessage(ChatRole.System, request.System));
        }
        messages.Add(new ChatMessage(ChatRole.User, request.Prompt));

        var options = new ChatOptions
        {
            ModelId = model,
            MaxOutputTokens = request.MaxTokens,
            Temperature = (float?)request.Temperature,
        };

        var stopwatch = Stopwatch.StartNew();
        var response = await client.GetResponseAsync(messages, options, cancellationToken).ConfigureAwait(false);
        return new ChatResult(
            Success: true,
            Text: response.Text,
            Provider: Provider,
            Model: response.ModelId ?? model,
            Latency: stopwatch.Elapsed,
            InputTokens: response.Usage?.InputTokenCount,
            OutputTokens: response.Usage?.OutputTokenCount);
    }
}
