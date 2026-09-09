using System.Text.Json;
using HELIOS.AIHub.Cli;
using HELIOS.AIHub.Tests.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests.Cli;

public sealed class ComboAnalysisCommandTests : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());

    public void Dispose() => File.Delete(_path);

    [Fact]
    public async Task ValidSnapshot_ProducesReport_AndPreservesFile()
    {
        var original = ComboAnalysisTests.Bytes(ComboAnalysisTests.Row("offline"));
        await File.WriteAllBytesAsync(_path, original);
        var options = new Dictionary<string, string?> { ["outcomes"] = _path, ["task"] = "code_generation" };
        using var output = new StringWriter();
        using var error = new StringWriter();
        Assert.Equal(0, await ComboAnalysisCommand.ExecuteAsync([], options, output, error));
        Assert.Empty(error.ToString());
        using var document = JsonDocument.Parse(output.ToString());
        Assert.Equal("offline-advisory", document.RootElement.GetProperty("mode").GetString());
        Assert.Equal(original, await File.ReadAllBytesAsync(_path));
    }

    [Fact]
    public async Task RealEntryPoint_BypassesInvalidConfigAndAllProviderInitialization()
    {
        await File.WriteAllBytesAsync(_path, ComboAnalysisTests.Bytes(ComboAnalysisTests.Row("offline")));
        // A nonexistent explicit config makes normal AIHub initialization fail. This
        // succeeds only when the real CLI dispatches before constructing any hub.
        var result = await HELIOS.AIHub.Cli.Program.Main([
            "combo-analyze", "--outcomes", _path, "--task", "code_generation",
            "--config", _path + ".no-such-config", "--json",
        ]);
        Assert.Equal(0, result);
    }

    [Theory]
    [InlineData("task", null)]
    [InlineData("outcomes", null)]
    [InlineData("limit", "2001")]
    [InlineData("limit", null)]
    [InlineData("language", "")]
    [InlineData("provider", "openai")]
    public async Task InvalidOptionsNeverProduceReport(string key, string? value)
    {
        var options = new Dictionary<string, string?> { ["outcomes"] = _path, ["task"] = "code_generation" };
        options[key] = value;
        using var output = new StringWriter();
        using var error = new StringWriter();
        Assert.Equal(1, await ComboAnalysisCommand.ExecuteAsync([], options, output, error));
        Assert.Empty(output.ToString());
        Assert.NotEmpty(error.ToString());
        Assert.False(File.Exists(_path));
    }
}
