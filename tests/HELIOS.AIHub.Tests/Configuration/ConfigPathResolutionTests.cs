using HELIOS.AIHub;
using HELIOS.AIHub.Configuration;
using Xunit;

namespace HELIOS.AIHub.Tests.Configuration;

/// <summary>
/// Pins the config resolution order the bootstrap scripts rely on: an explicit
/// --config path wins, then AIHUB_CONFIG (how .helios/azure.env selects the
/// cloud-only profile), then walking up from the current directory.
/// </summary>
public class ConfigPathResolutionTests : IDisposable
{
    private readonly string? _savedEnv = Environment.GetEnvironmentVariable("AIHUB_CONFIG");

    public void Dispose() => Environment.SetEnvironmentVariable("AIHUB_CONFIG", _savedEnv);

    [Fact]
    public void ExplicitPath_BeatsEnvironmentVariable()
    {
        Environment.SetEnvironmentVariable("AIHUB_CONFIG", "/nonexistent/env.json");
        Assert.Equal("/explicit/path.json", AIHubService.ResolveConfigPath("/explicit/path.json"));
    }

    [Fact]
    public void EnvironmentVariable_BeatsDirectoryWalk()
    {
        var cloudPath = CloudProfilePath();
        Environment.SetEnvironmentVariable("AIHUB_CONFIG", cloudPath);
        Assert.Equal(cloudPath, AIHubService.ResolveConfigPath());
    }

    [Fact]
    public void BlankEnvironmentVariable_FallsThroughToDirectoryWalk()
    {
        Environment.SetEnvironmentVariable("AIHUB_CONFIG", "  ");
        var resolved = AIHubService.ResolveConfigPath();
        Assert.EndsWith("aihub.json", resolved);
    }

    [Fact]
    public void EnvironmentVariable_SelectsCloudProfile_EndToEnd()
    {
        Environment.SetEnvironmentVariable("AIHUB_CONFIG", CloudProfilePath());
        var options = AIHubOptions.Load(AIHubService.ResolveConfigPath());
        Assert.Empty(options.CliAgents);
        Assert.False(options.Providers.ContainsKey("ollama"));
    }

    private static string CloudProfilePath()
    {
        var basePath = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.False(basePath is null, "config/aihub.json not found walking up from test output directory");
        return Path.Combine(Path.GetDirectoryName(basePath!)!, "aihub.cloud.json");
    }
}
