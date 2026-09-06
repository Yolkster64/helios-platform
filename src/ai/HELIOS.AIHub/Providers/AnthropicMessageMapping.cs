using Anthropic.SDK.Messaging;
using HELIOS.AIHub.Abstractions;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// The hub ↔ Anthropic Messages API mapping shared by <see cref="AnthropicAgent"/>
/// (api.anthropic.com) and <see cref="AnthropicFoundryAgent"/> (Claude in Microsoft
/// Foundry). Kept in one place so both providers send and read exactly the same shape:
/// one user turn, optional system prompt, max tokens, temperature; text blocks
/// concatenated, usage tokens copied through.
/// </summary>
internal static class AnthropicMessageMapping
{
    /// <summary>The Messages API requires max_tokens; this is the hub-wide default.</summary>
    public const int DefaultMaxTokens = 4096;

    public static MessageParameters ToParameters(ChatRequest request, string model)
    {
        var parameters = new MessageParameters
        {
            Model = model,
            MaxTokens = request.MaxTokens ?? DefaultMaxTokens,
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
        return parameters;
    }

    public static ChatResult ToResult(MessageResponse response, string provider, string requestedModel, TimeSpan latency)
    {
        var text = string.Concat(
            response.Content.OfType<TextContent>().Select(content => content.Text));

        return new ChatResult(
            Success: true,
            Text: text,
            Provider: provider,
            Model: response.Model ?? requestedModel,
            Latency: latency,
            InputTokens: response.Usage?.InputTokens,
            OutputTokens: response.Usage?.OutputTokens);
    }
}
