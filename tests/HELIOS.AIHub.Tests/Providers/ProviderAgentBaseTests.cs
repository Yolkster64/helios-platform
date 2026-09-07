using Xunit;
using HELIOS.AIHub.Abstractions;
using HELIOS.Platform.Core.AI.Interfaces;

namespace HELIOS.AIHub.Tests.Providers;

/// <summary>
/// The generic <see cref="IAgent"/> seam (<c>ExecuteAsync</c>) is how AgentRouter reaches an
/// adapter; the language the router selected on travels as a request parameter under the
/// same key as the routing hint, so the adapter must see it on <see cref="ChatRequest.Language"/>.
/// </summary>
public class ProviderAgentBaseTests
{
    [Theory]
    [InlineData("F#", "fsharp")]
    [InlineData("fsharp", "fsharp")]
    [InlineData(" .PS1 ", "powershell")]
    public async Task ExecuteAsync_MapsLanguageParameter_Normalized(string parameter, string expected)
    {
        ChatRequest? seen = null;
        var agent = new FakeProviderAgent("fake", ProviderReadiness.Ready, request =>
        {
            seen = request;
            return new ChatResult(true, "ok", "fake", "fake-model", TimeSpan.Zero);
        });

        var result = await agent.ExecuteAsync(new AgentRequest
        {
            Operation = "chat",
            Parameters = { ["prompt"] = "hi", ["language"] = parameter },
        });

        Assert.True(result.Success);
        Assert.NotNull(seen);
        Assert.Equal(expected, seen!.Language);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task ExecuteAsync_WithoutUsableLanguage_LeavesLanguageNull(string? parameter)
    {
        ChatRequest? seen = null;
        var agent = new FakeProviderAgent("fake", ProviderReadiness.Ready, request =>
        {
            seen = request;
            return new ChatResult(true, "ok", "fake", "fake-model", TimeSpan.Zero);
        });

        var request = new AgentRequest { Operation = "chat", Parameters = { ["prompt"] = "hi" } };
        if (parameter is not null)
        {
            request.Parameters["language"] = parameter;
        }

        var result = await agent.ExecuteAsync(request);

        Assert.True(result.Success);
        Assert.NotNull(seen);
        Assert.Null(seen!.Language);
    }
}
