using System.Diagnostics;
using Anthropic.SDK;
using Anthropic.SDK.Messaging;
using HELIOS.AIHub.Abstractions;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// Claude via the community Anthropic.SDK, using its native Messages API rather than its
/// IChatClient adapter — this pins us to compile-time-checked types instead of an
/// abstractions-version handshake between two packages. Swapping to a raw-REST client is
/// documented in docs/architecture/MULTI_LLM_INTEGRATION.md if the SDK ever blocks us.
/// </summary>
public sealed class AnthropicAgent : ProviderAgentBase
{
    private readonly string? _apiKey;
    private readonly Lazy<AnthropicClient>? _client;

    public AnthropicAgent(string provider, string displayName, string? defaultModel, string? apiKey)
        : base(provider, displayName, defaultModel)
    {
        _apiKey = apiKey;
        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            _client = new Lazy<AnthropicClient>(() => new AnthropicClient(apiKey));
        }
    }

    public override ProviderReadiness Readiness =>
        _client is null ? ProviderReadiness.Unconfigured : ProviderReadiness.Ready;

    public override string? ConfigurationHint =>
        _client is null ? "Set ANTHROPIC_API_KEY (or configure the Key Vault secret 'anthropic-api-key')." : null;

    protected override async Task<ChatResult> ChatCoreAsync(ChatRequest request, CancellationToken cancellationToken)
    {
        var model = request.Model ?? DefaultModel ?? "claude-sonnet-4-5";
        var parameters = new MessageParameters
        {
            Model = model,
            MaxTokens = request.MaxTokens ?? 4096,
            Messages = new List<Message> { new(RoleType.User, request.Prompt) },
        };
        if (!string.IsNullOrWhiteSpace(request.System))
        {
            parameters.System = new List<SystemMessage> { new(request.System) };
        }
        if (request.Temperature is { } temperature)
        {
            parameters.Temperature = (decimal)temperature;
        }

        var stopwatch = Stopwatch.StartNew();
        var response = await _client!.Value.Messages
            .GetClaudeMessageAsync(parameters, cancellationToken)
            .ConfigureAwait(false);

        var text = string.Concat(
            response.Content.OfType<TextContent>().Select(content => content.Text));

        return new ChatResult(
            Success: true,
            Text: text,
            Provider: Provider,
            Model: response.Model ?? model,
            Latency: stopwatch.Elapsed,
            InputTokens: response.Usage?.InputTokens,
            OutputTokens: response.Usage?.OutputTokens);
    }
}
