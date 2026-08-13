using System.Reflection;
using System.Text.Json;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The read-only `helios-ai absorb-status` command: watchlist parsing, benchmark-report
/// merging by PR number, and the missing-watchlist error path. The CLI exe project is not
/// referenced by this test project, so the command engine
/// (HELIOS.AIHub.Cli.AbsorptionStatus.Execute) is loaded by reflection from the CLI build
/// output that the HELIOS.sln build CI runs before the tests already produced.
/// </summary>
public sealed class AbsorbStatusTests : IDisposable
{
    private const string SampleWatchlist = """
        {
          "$comment": "test fixture",
          "upstream": "M0nado/helios-platform",
          "candidates": [
            {
              "pr": 222,
              "title": "Add bounded XCore-9 evaluation service",
              "status": "candidate",
              "why": "F# analytics service",
              "absorb": ["service contracts"],
              "risks": ["path conflicts with src/ai"]
            },
            {
              "pr": 294,
              "title": "Add governed XCore9 runtime matrix",
              "status": "benchmarked",
              "why": "runtime matrix maps onto fleet runtime",
              "absorb": ["runtime matrix definition"],
              "risks": [],
              "epic": "fleet-runtime"
            },
            {
              "pr": 250,
              "title": "Define Hermes/XCore v1 contracts",
              "status": "candidate",
              "why": "federation contracts",
              "absorb": [],
              "risks": ["contract divergence"]
            }
          ]
        }
        """;

    private static readonly Lazy<MethodInfo> ExecuteMethod = new(LocateExecute);

    private readonly List<string> _roots = new();

    public void Dispose()
    {
        foreach (var root in _roots)
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    [Fact]
    public void SummarizesWatchlist_WithStatusCounts()
    {
        var root = CreateRepoRoot(SampleWatchlist);

        var (exitCode, stdout, stderr) = RunAbsorbStatus(root);

        Assert.Equal(0, exitCode);
        Assert.Equal("", stderr);
        using var doc = JsonDocument.Parse(stdout);
        var summary = doc.RootElement;
        Assert.Equal("M0nado/helios-platform", summary.GetProperty("upstream").GetString());
        Assert.Equal(3, summary.GetProperty("total").GetInt32());
        var byStatus = summary.GetProperty("by_status");
        Assert.Equal(2, byStatus.GetProperty("candidate").GetInt32());
        Assert.Equal(1, byStatus.GetProperty("benchmarked").GetInt32());

        var candidates = summary.GetProperty("candidates");
        Assert.Equal(3, candidates.GetArrayLength());
        var first = candidates[0];
        Assert.Equal(222, first.GetProperty("pr").GetInt32());
        Assert.Equal("Add bounded XCore-9 evaluation service", first.GetProperty("title").GetString());
        Assert.Equal("candidate", first.GetProperty("status").GetString());
        // No benchmark report and no epic: the optional fields are omitted, not null.
        Assert.False(first.TryGetProperty("verdict", out _));
        Assert.False(first.TryGetProperty("benchmarked", out _));
        Assert.False(first.TryGetProperty("epic", out _));
        Assert.Equal("fleet-runtime", candidates[1].GetProperty("epic").GetString());
    }

    [Fact]
    public void MergesBenchmarkReports_ByPrNumber()
    {
        var root = CreateRepoRoot(SampleWatchlist);
        WriteReport(root, 222, """
            {
              "pr": 222,
              "gatePassed": true,
              "verdict": "clean merge; gate passed",
              "benchmarked": "2026-08-10T08:48:39Z"
            }
            """);
        WriteReport(root, 999, """
            {
              "pr": 999,
              "gatePassed": false,
              "verdict": "not on the watchlist",
              "benchmarked": "2026-08-09T00:00:00Z"
            }
            """);

        var (exitCode, stdout, _) = RunAbsorbStatus(root);

        Assert.Equal(0, exitCode);
        using var doc = JsonDocument.Parse(stdout);
        // The unmatched pr-999 report must not invent a watchlist row.
        Assert.Equal(3, doc.RootElement.GetProperty("total").GetInt32());
        var merged = FindCandidate(doc.RootElement, 222);
        Assert.Equal("clean merge; gate passed", merged.GetProperty("verdict").GetString());
        Assert.Equal("2026-08-10T08:48:39Z", merged.GetProperty("benchmarked").GetString());
        var untouched = FindCandidate(doc.RootElement, 294);
        Assert.False(untouched.TryGetProperty("verdict", out _));
        Assert.False(untouched.TryGetProperty("benchmarked", out _));
    }

    [Fact]
    public void MissingWatchlist_FailsWithOneLineError()
    {
        var root = CreateRepoRoot(watchlistJson: null);

        var (exitCode, stdout, stderr) = RunAbsorbStatus(root);

        Assert.Equal(1, exitCode);
        Assert.Equal("", stdout);
        Assert.Contains("config/absorption/pr-watchlist.json", stderr);
        Assert.Single(stderr.Trim().Split('\n'));
    }

    [Fact]
    public void ResolvesWatchlist_WalkingUpFromSubdirectory()
    {
        var root = CreateRepoRoot(SampleWatchlist);
        var nested = Directory.CreateDirectory(Path.Combine(root, "src", "ai")).FullName;

        var (exitCode, stdout, _) = RunAbsorbStatus(nested);

        Assert.Equal(0, exitCode);
        using var doc = JsonDocument.Parse(stdout);
        Assert.Equal(3, doc.RootElement.GetProperty("total").GetInt32());
    }

    [Fact]
    public void SkipsMalformedReport_WithWarning_AndStillSucceeds()
    {
        var root = CreateRepoRoot(SampleWatchlist);
        WriteReport(root, 222, "{ this is not json");

        var (exitCode, stdout, stderr) = RunAbsorbStatus(root);

        Assert.Equal(0, exitCode);
        Assert.Contains("pr-222.json", stderr);
        using var doc = JsonDocument.Parse(stdout);
        var row = FindCandidate(doc.RootElement, 222);
        Assert.False(row.TryGetProperty("verdict", out _));
    }

    private string CreateRepoRoot(string? watchlistJson)
    {
        var root = Path.Combine(Path.GetTempPath(), $"helios-absorb-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        _roots.Add(root);
        if (watchlistJson is not null)
        {
            var configDir = Path.Combine(root, "config", "absorption");
            Directory.CreateDirectory(configDir);
            File.WriteAllText(Path.Combine(configDir, "pr-watchlist.json"), watchlistJson);
        }
        return root;
    }

    private static void WriteReport(string root, int pr, string json)
    {
        var reportsDir = Path.Combine(root, ".helios", "absorption");
        Directory.CreateDirectory(reportsDir);
        File.WriteAllText(Path.Combine(reportsDir, $"pr-{pr}.json"), json);
    }

    private static (int ExitCode, string Stdout, string Stderr) RunAbsorbStatus(string startDirectory)
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var exitCode = (int)ExecuteMethod.Value.Invoke(
            null, new object?[] { startDirectory, stdout, stderr })!;
        return (exitCode, stdout.ToString(), stderr.ToString());
    }

    private static JsonElement FindCandidate(JsonElement summary, int pr) =>
        summary.GetProperty("candidates").EnumerateArray()
            .Single(candidate => candidate.GetProperty("pr").GetInt32() == pr);

    private static MethodInfo LocateExecute()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "HELIOS.sln")))
        {
            dir = dir.Parent;
        }
        Assert.False(dir is null, "HELIOS.sln not found above the test output directory.");

        var binRoot = Path.Combine(dir!.FullName, "src", "ai", "HELIOS.AIHub.Cli", "bin");
        var preferred = AppContext.BaseDirectory.Contains(
            $"{Path.DirectorySeparatorChar}Release{Path.DirectorySeparatorChar}",
            StringComparison.OrdinalIgnoreCase)
            ? "Release"
            : "Debug";
        // The CLI and this test project are built together by HELIOS.sln at the same
        // TFM, so derive it from our own output directory instead of hardcoding one -
        // a hardcoded TFM survives locally on stale bin output and only fails on CI's
        // clean checkout.
        var targetFramework = new DirectoryInfo(
            AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar)).Name;
        var dllPath = new[] { preferred, preferred == "Release" ? "Debug" : "Release" }
            .Select(configuration => Path.Combine(binRoot, configuration, targetFramework, "helios-ai.dll"))
            .FirstOrDefault(File.Exists);
        Assert.False(
            dllPath is null,
            "helios-ai.dll not found in the CLI build output; run `dotnet build HELIOS.sln` first (CI does).");

        var type = Assembly.LoadFrom(dllPath!).GetType("HELIOS.AIHub.Cli.AbsorptionStatus");
        Assert.False(type is null, "HELIOS.AIHub.Cli.AbsorptionStatus not found in helios-ai.dll.");
        var method = type!.GetMethod(
            "Execute", new[] { typeof(string), typeof(TextWriter), typeof(TextWriter) });
        Assert.False(method is null, "AbsorptionStatus.Execute(string?, TextWriter, TextWriter) not found.");
        return method!;
    }
}
