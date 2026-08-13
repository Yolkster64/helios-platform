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

    [Fact]
    public void RelativeLearningPath_ShippedLayout_ResolvesUnderConfigRoot_NotCwd()
    {
        // Recording is on by default, so a relative localPath anchored to the
        // process CWD would scatter .helios/ trees wherever helios-ai runs. In the
        // shipped layout (<root>/config/aihub.json) the anchor is the config ROOT —
        // one level above the config/ directory — never config/ itself.
        var root = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        var configDir = Path.Combine(root, "config");
        Directory.CreateDirectory(configDir);
        try
        {
            var path = Path.Combine(configDir, "aihub.json");
            File.WriteAllText(path,
                """{ "providers": {}, "learning": { "localPath": ".helios/learning/outcomes.jsonl" } }""");
            var options = AIHubOptions.Load(path);
            Assert.True(Path.IsPathRooted(options.Learning.LocalPath));
            Assert.StartsWith(
                Path.Combine(root, ".helios"), options.Learning.LocalPath);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void RelativeLearningPath_ArbitraryConfigLocation_ResolvesBesideTheFile()
    {
        // --config /tmp/aihub.json must anchor beside the file, NOT one level up:
        // stepping to the parent of an arbitrary directory anchors to an unrelated
        // (often unwritable) place — /tmp → /.helios/... — and the permission failure
        // silently degrades recording to a NullLearningStore.
        var dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(dir);
        try
        {
            var path = Path.Combine(dir, "aihub.json");
            File.WriteAllText(path,
                """{ "providers": {}, "learning": { "localPath": ".helios/learning/outcomes.jsonl" } }""");
            var options = AIHubOptions.Load(path);
            Assert.True(Path.IsPathRooted(options.Learning.LocalPath));
            Assert.StartsWith(
                Path.Combine(dir, ".helios"), options.Learning.LocalPath);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void AbsoluteLearningPath_PassesThroughUntouched()
    {
        var dir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(dir);
        try
        {
            var absolute = Path.Combine(Path.GetTempPath(), "helios-learning", "outcomes.jsonl");
            var path = Path.Combine(dir, "aihub.json");
            File.WriteAllText(path,
                $$"""{ "providers": {}, "learning": { "localPath": {{System.Text.Json.JsonSerializer.Serialize(absolute)}} } }""");
            var options = AIHubOptions.Load(path);
            Assert.Equal(absolute, options.Learning.LocalPath);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    private static string CloudProfilePath()
    {
        var basePath = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.False(basePath is null, "config/aihub.json not found walking up from test output directory");
        return Path.Combine(Path.GetDirectoryName(basePath!)!, "aihub.cloud.json");
    }
}
