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
    public async Task ChatAsync_ClosesChildStdin_SoStdinDrainingClisDoNotHang()
    {
        if (!File.Exists("/bin/sh"))
        {
            return; // POSIX-only fixture script.
        }

        // Mirrors `codex exec` under a non-interactive host: it drains stdin to EOF before
        // answering. With the hub's stdin inherited that read blocks for the whole
        // timeout; with stdin redirected and closed it sees EOF at once.
        var scriptDir = Directory.CreateTempSubdirectory("helios-cli-stdin-");
        var script = Path.Combine(scriptDir.FullName, "drain-stdin.sh");
        await File.WriteAllTextAsync(script, "#!/bin/sh\ncat >/dev/null\necho stdin-eof\n");
        try
        {
            var agent = new CliProcessAgent(new CliAgentOptions
            {
                Name = "stdin-agent",
                Command = "sh",
                ArgsTemplate = "{prompt}",
                TimeoutSeconds = 20,
            });

            var result = await agent.ChatAsync(new ChatRequest(script));

            Assert.True(result.Success, result.Error);
            Assert.Equal("stdin-eof", result.Text);
            Assert.True(result.Latency < TimeSpan.FromSeconds(10), $"blocked on stdin for {result.Latency}");
        }
        finally
        {
            scriptDir.Delete(recursive: true);
        }
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
