using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using Xunit;

namespace HELIOS.AIHub.Tests;

public class AIHubServiceTests
{
    private static AIHubOptions EchoOnlyOptions() => new()
    {
        CliAgents = new List<CliAgentOptions>
        {
            new() { Name = "echo-agent", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
            new() { Name = "ghost-agent", Command = "no-such-cmd-xyz", ArgsTemplate = "{prompt}" },
        },
        Routing = new RoutingOptions
        {
            DefaultChain = new List<string> { "ghost-agent", "echo-agent" },
            TaskRouting = new Dictionary<string, List<string>>
            {
                ["echo_task"] = new() { "echo-agent" },
            },
        },
    };

    [Fact]
    public async Task AskAsync_UnknownProvider_ListsKnownOnes()
    {
        var hub = new AIHubService(EchoOnlyOptions());

        var result = await hub.AskAsync("q", provider: "nope");

        Assert.False(result.Success);
        Assert.Contains("Unknown provider 'nope'", result.Error);
        Assert.Contains("echo-agent", result.Error);
    }

    [Fact]
    public async Task RouteAsync_FallsThroughUnconfigured_ToWorkingProvider()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var hub = new AIHubService(EchoOnlyOptions());

        // Default chain: ghost-agent (unconfigured → soft failure) then echo-agent.
        var result = await hub.RouteAsync(taskType: null, "ping");

        Assert.True(result.Success, result.Error);
        Assert.Equal("echo-agent", result.Provider);
        Assert.Equal("ping", result.Text);
    }

    [Fact]
    public async Task RouteAsync_UnknownTaskTypeWithEmptyDefault_ReturnsActionableError()
    {
        var options = EchoOnlyOptions();
        options.Routing.DefaultChain = new List<string> { "not-registered" };
        var hub = new AIHubService(options);

        var result = await hub.RouteAsync(taskType: null, "q");

        Assert.False(result.Success);
        Assert.Contains("defaultChain", result.Error);
    }

    [Fact]
    public async Task CompareAsync_ReturnsOneResultPerProvider()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var hub = new AIHubService(EchoOnlyOptions());

        var results = await hub.CompareAsync("ping", new[] { "echo-agent", "unknown-x" });

        Assert.Equal(2, results.Count);
        Assert.True(results.Single(r => r.Provider == "echo-agent").Success);
        Assert.False(results.Single(r => r.Provider == "unknown-x").Success);
    }

    [Fact]
    public void GetStatus_ReportsReadinessAndHints()
    {
        var hub = new AIHubService(EchoOnlyOptions());

        var status = hub.GetStatus();

        var ghost = status.Single(p => p.Name == "ghost-agent");
        Assert.Equal(ProviderReadiness.Unconfigured, ghost.Readiness);
        Assert.Contains("not found on PATH", ghost.Detail);
        Assert.All(status, p => Assert.Equal("cli", p.Kind));
    }

    [Fact]
    public void ShippedConfig_BuildsHub_WithAllProvidersRegistered()
    {
        var path = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.NotNull(path);

        var hub = new AIHubService(AIHubOptions.Load(path!));
        var status = hub.GetStatus();

        // 6 API providers + 5 CLI agents from config/aihub.json.
        Assert.Equal(11, status.Count);
        // Nothing requiring secrets should be Ready in a keyless environment.
        Assert.Equal(ProviderReadiness.Unconfigured,
            status.Single(p => p.Name == "anthropic").Readiness);
    }
}
