using HELIOS.AIHub.Fleet;
using Xunit;

namespace HELIOS.AIHub.Tests.Cli;

public sealed class FleetReadinessCommandTests : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());

    public void Dispose() => File.Delete(_path);

    [Fact]
    public async Task FleetReadiness_BypassesHubConfiguration()
    {
        // A nonexistent hub config must never be opened by this offline command.
        var original = await File.ReadAllTextAsync(FleetTopology.FindTopologyFile(AppContext.BaseDirectory)!);
        await File.WriteAllTextAsync(_path, original);
        Assert.Equal(0, await HELIOS.AIHub.Cli.Program.Main([
            "fleet-readiness", "--topology", _path, "--config", _path + ".missing", "--json",
        ]));
        Assert.Equal(original, await File.ReadAllTextAsync(_path));
    }

    [Fact]
    public async Task FleetReadiness_RejectsInferenceOptionsBeforeReadingFiles()
    {
        Assert.Equal(1, await HELIOS.AIHub.Cli.Program.Main([
            "fleet-readiness", "--provider", "openai", "--topology", _path,
        ]));
        Assert.False(File.Exists(_path));
    }
}
