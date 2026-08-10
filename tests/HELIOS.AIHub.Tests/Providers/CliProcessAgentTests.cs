using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Providers;
using Xunit;

namespace HELIOS.AIHub.Tests.Providers;

public class CliProcessAgentTests
{
    [Fact]
    public async Task ChatAsync_RunsCommand_AndCapturesStdout()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return; // POSIX-only fixture commands.
        }

        var agent = new CliProcessAgent(new CliAgentOptions
        {
            Name = "echo-agent",
            Command = "echo",
            ArgsTemplate = "{prompt}",
            TimeoutSeconds = 10,
        });

        Assert.Equal(ProviderReadiness.Ready, agent.Readiness);
        var result = await agent.ChatAsync(new ChatRequest("hello world"));

        Assert.True(result.Success, result.Error);
        Assert.Equal("hello world", result.Text);
    }

    [Fact]
    public async Task ChatAsync_TimesOut_AndReportsCleanFailure()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var agent = new CliProcessAgent(new CliAgentOptions
        {
            Name = "sleep-agent",
            Command = "sleep",
            ArgsTemplate = "30",
            TimeoutSeconds = 1,
        });

        var result = await agent.ChatAsync(new ChatRequest("unused"));

        Assert.False(result.Success);
        Assert.Contains("timed out", result.Error);
    }

    [Fact]
    public void MissingCommand_IsUnconfigured_NotAnError()
    {
        var agent = new CliProcessAgent(new CliAgentOptions
        {
            Name = "ghost",
            Command = "definitely-not-a-real-command-xyz",
            ArgsTemplate = "{prompt}",
        });

        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
        Assert.Contains("not found on PATH", agent.ConfigurationHint);
    }

    [Fact]
    public async Task ChatAsync_NonZeroExit_ReturnsFailureWithDetail()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var agent = new CliProcessAgent(new CliAgentOptions
        {
            Name = "false-agent",
            Command = "false",
            ArgsTemplate = "",
            TimeoutSeconds = 5,
        });

        var result = await agent.ChatAsync(new ChatRequest("unused"));

        Assert.False(result.Success);
        Assert.Contains("exited 1", result.Error);
    }
}
