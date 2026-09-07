using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Routing;
using HELIOS.Platform.Core.AI.Interfaces;
using HELIOS.Platform.Core.AI.Router;
using Xunit;

namespace HELIOS.AIHub.Tests.Routing;

public class TaskTypeRoutingStrategyTests
{
    private static RoutingOptions Routing => new()
    {
        DefaultChain = new List<string> { "fallback-provider" },
        TaskRouting = new Dictionary<string, List<string>>
        {
            ["code_review"] = new() { "anthropic", "openai" },
        },
    };

    [Fact]
    public void SelectAgent_FollowsTaskChain_SkippingUnconfigured()
    {
        var strategy = new TaskTypeRoutingStrategy(Routing);
        var agents = new IAgent[]
        {
            new FakeProviderAgent("anthropic", ProviderReadiness.Unconfigured),
            new FakeProviderAgent("openai", ProviderReadiness.Ready),
            new FakeProviderAgent("fallback-provider", ProviderReadiness.Ready),
        };
        var request = new AgentRoutingRequest
        {
            RoutingHints = { [TaskTypeRoutingStrategy.TaskTypeHint] = "code_review" },
        };

        var selected = strategy.SelectAgent(request, agents);

        Assert.Equal("openai", ((IChatProviderAgent)selected!).Provider);
    }

    [Fact]
    public void SelectAgent_UsesDefaultChain_ForUnknownTaskType()
    {
        var strategy = new TaskTypeRoutingStrategy(Routing);
        var agents = new IAgent[]
        {
            new FakeProviderAgent("fallback-provider", ProviderReadiness.Ready),
        };
        var request = new AgentRoutingRequest
        {
            RoutingHints = { [TaskTypeRoutingStrategy.TaskTypeHint] = "no_such_task" },
        };

        var selected = strategy.SelectAgent(request, agents);

        Assert.Equal("fallback-provider", ((IChatProviderAgent)selected!).Provider);
    }

    [Fact]
    public void SelectAgents_AppendsRemainingReadyProviders_AfterChain()
    {
        var strategy = new TaskTypeRoutingStrategy(Routing);
        var agents = new IAgent[]
        {
            new FakeProviderAgent("anthropic", ProviderReadiness.Ready),
            new FakeProviderAgent("openai", ProviderReadiness.Ready),
            new FakeProviderAgent("extra", ProviderReadiness.Ready),
        };
        var request = new AgentRoutingRequest
        {
            RoutingHints = { [TaskTypeRoutingStrategy.TaskTypeHint] = "code_review" },
        };

        var selected = strategy.SelectAgents(request, agents, maxAgents: 3);

        Assert.Equal(
            new[] { "anthropic", "openai", "extra" },
            selected.Cast<IChatProviderAgent>().Select(a => a.Provider).ToArray());
    }

    [Fact]
    public void GetChain_ReturnsDefaultChain_WhenTaskTypeIsNull()
    {
        var strategy = new TaskTypeRoutingStrategy(Routing);
        Assert.Equal(new[] { "fallback-provider" }, strategy.GetChain(null));
    }

    /// <summary>A bare chain plus one language-qualified override that reverses it.</summary>
    private static RoutingOptions LanguageRouting => new()
    {
        DefaultChain = new List<string> { "fallback-provider" },
        TaskRouting = new Dictionary<string, List<string>>
        {
            ["code_generation"] = new() { "openai", "anthropic" },
            ["code_generation:fsharp"] = new() { "anthropic", "openai" },
            ["code_review"] = new() { "anthropic" },
        },
    };

    [Fact]
    public void GetChain_TriesQualifiedKey_ThenBareTaskType_ThenDefault()
    {
        var strategy = new TaskTypeRoutingStrategy(LanguageRouting);

        // 1. "{taskType}:{language}" exists → the qualified chain.
        Assert.Equal(new[] { "anthropic", "openai" }, strategy.GetChain("code_generation", "fsharp"));
        // 2. Language given but no qualified key → the bare task type.
        Assert.Equal(new[] { "openai", "anthropic" }, strategy.GetChain("code_generation", "python"));
        Assert.Equal(new[] { "anthropic" }, strategy.GetChain("code_review", "fsharp"));
        // No language → identical to the pre-language behavior.
        Assert.Equal(new[] { "openai", "anthropic" }, strategy.GetChain("code_generation"));
        // 3. Neither key → the default chain.
        Assert.Equal(new[] { "fallback-provider" }, strategy.GetChain("no_such_task", "fsharp"));
    }

    [Fact]
    public void GetChain_NormalizesTheLanguageBeforeLookup()
    {
        var strategy = new TaskTypeRoutingStrategy(LanguageRouting);

        Assert.Equal(new[] { "anthropic", "openai" }, strategy.GetChain("code_generation", " F# "));
        Assert.Equal(new[] { "anthropic", "openai" }, strategy.GetChain("code_generation", ".FS"));
        // Blank is "no language", never a lookup of "code_generation:".
        Assert.Equal(new[] { "openai", "anthropic" }, strategy.GetChain("code_generation", "   "));
    }

    [Theory]
    [InlineData("fsharp", "fsharp")]
    [InlineData("F#", "fsharp")]
    [InlineData("  FSharp  ", "fsharp")]
    [InlineData(".fs", "fsharp")]
    [InlineData("C#", "csharp")]
    [InlineData("c++", "cpp")]
    [InlineData("CXX", "cpp")]
    [InlineData("ps1", "powershell")]
    [InlineData("pwsh", "powershell")]
    [InlineData("py", "python")]
    [InlineData("yml", "yaml")]
    [InlineData("Bicep", "bicep")]
    [InlineData("json", "json")]
    public void NormalizeLanguage_FoldsCaseWhitespaceDotsAndAliases(string input, string expected) =>
        Assert.Equal(expected, TaskTypeRoutingStrategy.NormalizeLanguage(input));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(".")]
    public void NormalizeLanguage_BlankMeansNoLanguage(string? input) =>
        Assert.Null(TaskTypeRoutingStrategy.NormalizeLanguage(input));

    [Fact]
    public void SelectAgent_HonorsTheLanguageHint()
    {
        var strategy = new TaskTypeRoutingStrategy(LanguageRouting);
        var agents = new IAgent[]
        {
            new FakeProviderAgent("openai", ProviderReadiness.Ready),
            new FakeProviderAgent("anthropic", ProviderReadiness.Ready),
        };
        var request = new AgentRoutingRequest
        {
            RoutingHints =
            {
                [TaskTypeRoutingStrategy.TaskTypeHint] = "code_generation",
                [TaskTypeRoutingStrategy.LanguageHint] = "fsharp",
            },
        };

        var selected = strategy.SelectAgent(request, agents);

        Assert.Equal("anthropic", ((IChatProviderAgent)selected!).Provider);
    }

    [Fact]
    public void RoutingKey_And_SplitRoutingKey_RoundTrip()
    {
        Assert.Equal("code_review:bicep", TaskTypeRoutingStrategy.RoutingKey("code_review", "bicep"));

        var (taskType, language) = TaskTypeRoutingStrategy.SplitRoutingKey("code_generation:fsharp");
        Assert.Equal("code_generation", taskType);
        Assert.Equal("fsharp", language);

        var (bareTask, noLanguage) = TaskTypeRoutingStrategy.SplitRoutingKey("code_generation");
        Assert.Equal("code_generation", bareTask);
        Assert.Null(noLanguage);
    }
}
