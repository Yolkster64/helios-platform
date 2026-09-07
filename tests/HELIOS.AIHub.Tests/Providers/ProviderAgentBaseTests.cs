using Xunit;
using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Routing;
using HELIOS.Platform.Core.AI.Router;
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

    [Fact]
    public async Task AgentRouter_LanguageHint_SelectsTheQualifiedChain_AndTheAdapterSeesTheLanguage()
    {
        // The generic seam end to end: AgentRouter picks the agent from the
        // language-qualified chain through the "language" routing hint, and executing
        // that agent with the same key as a request parameter hands the adapter the
        // canonical language — the path the facade never takes.
        ChatRequest? seen = null;
        var alpha = new FakeProviderAgent("alpha", ProviderReadiness.Ready);
        var beta = new FakeProviderAgent("beta", ProviderReadiness.Ready, request =>
        {
            seen = request;
            return new ChatResult(true, "ok", "beta", "fake-model", TimeSpan.Zero);
        });
        var routing = new RoutingOptions
        {
            TaskRouting = new Dictionary<string, List<string>>
            {
                ["code_generation"] = new() { "alpha", "beta" },
                ["code_generation:fsharp"] = new() { "beta", "alpha" },
            },
        };
        var router = new AgentRouter(new TaskTypeRoutingStrategy(routing));
        router.RegisterAgent(alpha);
        router.RegisterAgent(beta);

        var routed = await router.RouteAsync(new AgentRoutingRequest
        {
            RoutingHints =
            {
                [TaskTypeRoutingStrategy.TaskTypeHint] = "code_generation",
                [TaskTypeRoutingStrategy.LanguageHint] = "F#",
            },
        });
        var selected = Assert.IsAssignableFrom<IChatProviderAgent>(routed.SelectedAgent);
        Assert.Equal("beta", selected.Provider);

        var result = await routed.SelectedAgent!.ExecuteAsync(new AgentRequest
        {
            Operation = "chat",
            Parameters =
            {
                ["prompt"] = "hi",
                [TaskTypeRoutingStrategy.TaskTypeHint] = "code_generation",
                [TaskTypeRoutingStrategy.LanguageHint] = "F#",
            },
        });

        Assert.True(result.Success);
        Assert.NotNull(seen);
        Assert.Equal("code_generation", seen!.TaskType);
        Assert.Equal("fsharp", seen.Language);
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
