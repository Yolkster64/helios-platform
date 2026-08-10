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
}
