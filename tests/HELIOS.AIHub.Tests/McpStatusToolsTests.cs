using System.Reflection;
using System.Text.Json;
using HELIOS.Mcp;
using ModelContextProtocol;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The read-only MCP status tools (helios_absorb_status_get, helios_fleet_status_get):
/// discoverability annotations, absorption watchlist + benchmark-report merging, fleet
/// manifest + board tallies, and the missing-directory paths. Each test fabricates a
/// throwaway repo root (a config/aihub.json marker is all the root resolution needs)
/// and points the tools' core methods at it.
/// </summary>
public sealed class McpStatusToolsTests : IDisposable
{
    private const string SampleWatchlist = """
        {
          "$comment": "test fixture",
          "upstream": "M0nado/helios-platform",
          "candidates": [
            {
              "pr": 222,
              "title": "Add bounded XCore-9 evaluation service",
              "status": "candidate"
            },
            {
              "pr": 294,
              "title": "Add governed XCore9 runtime matrix",
              "status": "benchmarked",
              "epic": "fleet-runtime"
            },
            {
              "pr": 250,
              "title": "Define Hermes/XCore v1 contracts",
              "status": "candidate"
            }
          ]
        }
        """;

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

    [Theory]
    [InlineData(nameof(HeliosStatusTools.GetAbsorbStatus), "helios_absorb_status_get")]
    [InlineData(nameof(HeliosStatusTools.GetFleetStatus), "helios_fleet_status_get")]
    public void StatusTools_AreDiscoverable_AndReadOnly(string methodName, string expectedToolName)
    {
        var method = typeof(HeliosStatusTools).GetMethod(methodName, BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal(expectedToolName, attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(true, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
    }

    [Fact]
    public void AbsorbStatus_SummarizesWatchlist_AndMergesReports()
    {
        var root = CreateRepoRoot();
        WriteWatchlist(root, SampleWatchlist);
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

        var json = HeliosStatusTools.BuildAbsorbStatusJson(root);

        using var doc = JsonDocument.Parse(json);
        var summary = doc.RootElement;
        Assert.Equal("M0nado/helios-platform", summary.GetProperty("upstream").GetString());
        Assert.Equal(3, summary.GetProperty("total").GetInt32());
        var byStatus = summary.GetProperty("by_status");
        Assert.Equal(2, byStatus.GetProperty("candidate").GetInt32());
        Assert.Equal(1, byStatus.GetProperty("benchmarked").GetInt32());

        // The unmatched pr-999 report must not invent a watchlist row.
        Assert.Equal(3, summary.GetProperty("candidates").GetArrayLength());
        var merged = FindCandidate(summary, 222);
        Assert.Equal("Add bounded XCore-9 evaluation service", merged.GetProperty("title").GetString());
        Assert.Equal("candidate", merged.GetProperty("status").GetString());
        Assert.Equal("clean merge; gate passed", merged.GetProperty("verdict").GetString());
        Assert.True(merged.GetProperty("gatePassed").GetBoolean());
        Assert.Equal("2026-08-10T08:48:39Z", merged.GetProperty("benchmarked").GetString());

        // No report and no epic: the optional fields are omitted, not null.
        var untouched = FindCandidate(summary, 250);
        Assert.False(untouched.TryGetProperty("verdict", out _));
        Assert.False(untouched.TryGetProperty("gatePassed", out _));
        Assert.False(untouched.TryGetProperty("benchmarked", out _));
        Assert.False(untouched.TryGetProperty("epic", out _));
        Assert.Equal("fleet-runtime", FindCandidate(summary, 294).GetProperty("epic").GetString());
    }

    [Fact]
    public void AbsorbStatus_MissingWatchlist_ThrowsActionableError()
    {
        var root = CreateRepoRoot();

        var ex = Assert.Throws<McpException>(() => HeliosStatusTools.BuildAbsorbStatusJson(root));

        Assert.Contains(Path.Combine("config", "absorption", "pr-watchlist.json"), ex.Message);
    }

    [Fact]
    public void AbsorbStatus_SkipsMalformedReport_WithWarning_AndStillSucceeds()
    {
        var root = CreateRepoRoot();
        WriteWatchlist(root, SampleWatchlist);
        WriteReport(root, 222, "{ this is not json");

        var json = HeliosStatusTools.BuildAbsorbStatusJson(root);

        using var doc = JsonDocument.Parse(json);
        var row = FindCandidate(doc.RootElement, 222);
        Assert.False(row.TryGetProperty("verdict", out _));
        var warnings = doc.RootElement.GetProperty("warnings");
        Assert.Contains(
            warnings.EnumerateArray(),
            warning => warning.GetString()!.Contains("pr-222.json"));
    }

    [Fact]
    public void FleetStatus_ReportsLatestRun_WithWorkerAndBoardCounts()
    {
        var root = CreateRepoRoot();
        WriteFleetRun(root, "20260810-090000-aaaaaa", "stopped", pools: new[]
        {
            ("old-pool", "old-board", 1, """{ "tasks": [] }"""),
        });
        WriteFleetRun(root, "20260811-120000-bb12cd", "running", pools: new[]
        {
            ("xcore-9-code", "xcore-code", 2, """
                {
                  "board": "xcore-code",
                  "tasks": [
                    { "id": "T-1", "lane": "code_generation", "status": "open" },
                    { "id": "T-2", "lane": "code_generation", "status": "open" },
                    { "id": "T-3", "lane": "code_review", "status": "claimed" },
                    { "id": "T-4", "lane": "code_review", "status": "done" },
                    { "id": "T-5", "lane": "code_review", "status": "blocked" },
                    { "id": "T-6", "lane": "code_review" }
                  ]
                }
                """),
            ("xcore-9-docs", "xcore-docs", 1, """{ "board": "xcore-docs", "tasks": [] }"""),
        });

        var json = HeliosStatusTools.BuildFleetStatusJson(allRuns: false, startDirectory: root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.TryGetProperty("message", out _));
        var run = Assert.Single(doc.RootElement.GetProperty("runs").EnumerateArray());
        Assert.Equal("20260811-120000-bb12cd", run.GetProperty("runId").GetString());
        Assert.Equal("running", run.GetProperty("status").GetString());

        var pools = run.GetProperty("pools");
        Assert.Equal(2, pools.GetArrayLength());
        var codePool = pools[0];
        Assert.Equal("xcore-9-code", codePool.GetProperty("pool").GetString());
        Assert.Equal("xcore-code", codePool.GetProperty("board").GetString());
        Assert.Equal(2, codePool.GetProperty("workers").GetInt32());
        // The fixture's pids (40001+) are synthetic and their recorded start time
        // matches no real process, so none verify as live.
        Assert.Equal(0, codePool.GetProperty("workersLive").GetInt32());
        // T-6 has no status and defaults to open; blocked T-5 gets its own bucket.
        Assert.Equal(3, codePool.GetProperty("openTasks").GetInt32());
        Assert.Equal(1, codePool.GetProperty("claimedTasks").GetInt32());
        Assert.Equal(1, codePool.GetProperty("doneTasks").GetInt32());
        Assert.Equal(1, codePool.GetProperty("blockedTasks").GetInt32());

        var docsPool = pools[1];
        Assert.Equal(1, docsPool.GetProperty("workers").GetInt32());
        Assert.Equal(0, docsPool.GetProperty("openTasks").GetInt32());
    }

    [Fact]
    public void FleetStatus_AllRuns_ReturnsEveryRun_InRunIdOrder()
    {
        var root = CreateRepoRoot();
        WriteFleetRun(root, "20260810-090000-aaaaaa", "stopped", pools: new[]
        {
            ("old-pool", "old-board", 1, """{ "tasks": [] }"""),
        });
        WriteFleetRun(root, "20260811-120000-bb12cd", "running", pools: new[]
        {
            ("xcore-9-code", "xcore-code", 2, """{ "tasks": [] }"""),
        });

        var json = HeliosStatusTools.BuildFleetStatusJson(allRuns: true, startDirectory: root);

        using var doc = JsonDocument.Parse(json);
        var runs = doc.RootElement.GetProperty("runs");
        Assert.Equal(2, runs.GetArrayLength());
        Assert.Equal("20260810-090000-aaaaaa", runs[0].GetProperty("runId").GetString());
        Assert.Equal("20260811-120000-bb12cd", runs[1].GetProperty("runId").GetString());
        Assert.Equal("stopped", runs[0].GetProperty("status").GetString());
    }

    [Fact]
    public void FleetStatus_WorkersLive_CountsPidAndStartTimeVerifiedProcesses()
    {
        var root = CreateRepoRoot();
        // One genuinely live worker (this very test process, with its real start
        // time) and one dead entry (synthetic pid): live must count exactly 1.
        using var self = System.Diagnostics.Process.GetCurrentProcess();
        var runDir = Path.Combine(root, ".helios", "fleet", "20260811-130000-cc34ef");
        Directory.CreateDirectory(Path.Combine(runDir, "boards"));
        var dbPath = Path.Combine(runDir, "boards", "xcore-code.json");
        File.WriteAllText(dbPath, """{ "tasks": [] }""");
        File.WriteAllText(Path.Combine(runDir, "manifest.json"), JsonSerializer.Serialize(new
        {
            runId = "20260811-130000-cc34ef",
            status = "running",
            pools = new[]
            {
                new
                {
                    pool = "xcore-9-code",
                    board = "xcore-code",
                    db = dbPath,
                    workers = new object[]
                    {
                        new
                        {
                            assignee = "xcode-1",
                            pid = self.Id,
                            startTime = self.StartTime.ToUniversalTime().ToString("o"),
                        },
                        new { assignee = "xcode-2", pid = 40999, startTime = "2026-08-11T12:00:00.0000000Z" },
                    },
                },
            },
        }));

        var json = HeliosStatusTools.BuildFleetStatusJson(allRuns: false, startDirectory: root);

        using var doc = JsonDocument.Parse(json);
        var pool = Assert.Single(
            Assert.Single(doc.RootElement.GetProperty("runs").EnumerateArray())
                .GetProperty("pools").EnumerateArray());
        Assert.Equal(2, pool.GetProperty("workers").GetInt32());
        Assert.Equal(1, pool.GetProperty("workersLive").GetInt32());
    }

    [Fact]
    public void FleetStatus_MissingFleetDirectory_ReturnsEmptyResult_NotAnError()
    {
        var root = CreateRepoRoot();

        var json = HeliosStatusTools.BuildFleetStatusJson(allRuns: false, startDirectory: root);

        using var doc = JsonDocument.Parse(json);
        Assert.Equal(0, doc.RootElement.GetProperty("runs").GetArrayLength());
        var message = doc.RootElement.GetProperty("message").GetString()!;
        Assert.Contains(Path.Combine(".helios", "fleet"), message);
        Assert.Contains("start-fleet.ps1", message);
    }

    [Fact]
    public void FleetStatus_MissingBoardDb_YieldsZeroCounts()
    {
        var root = CreateRepoRoot();
        var runDir = Path.Combine(root, ".helios", "fleet", "20260811-130000-cc34ef");
        Directory.CreateDirectory(runDir);
        File.WriteAllText(Path.Combine(runDir, "manifest.json"), """
            {
              "runId": "20260811-130000-cc34ef",
              "status": "running",
              "stoppedAt": null,
              "pools": [
                {
                  "pool": "xcore-9-code",
                  "board": "xcore-code",
                  "lanes": "code_generation",
                  "db": "boards/does-not-exist.json",
                  "claimLock": "locks/xcore-code.lock",
                  "workers": []
                }
              ]
            }
            """);

        var json = HeliosStatusTools.BuildFleetStatusJson(allRuns: false, startDirectory: root);

        using var doc = JsonDocument.Parse(json);
        var pool = Assert.Single(
            Assert.Single(doc.RootElement.GetProperty("runs").EnumerateArray())
                .GetProperty("pools").EnumerateArray());
        Assert.Equal(0, pool.GetProperty("workers").GetInt32());
        Assert.Equal(0, pool.GetProperty("openTasks").GetInt32());
        Assert.Equal(0, pool.GetProperty("claimedTasks").GetInt32());
        Assert.Equal(0, pool.GetProperty("doneTasks").GetInt32());
    }

    private string CreateRepoRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), $"helios-mcp-status-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(root, "config"));
        // The tools resolve the repo root exactly like the other MCP tools: the
        // directory holding config/aihub.json. Content is never read here.
        File.WriteAllText(Path.Combine(root, "config", "aihub.json"), "{}");
        _roots.Add(root);
        return root;
    }

    private static void WriteWatchlist(string root, string json)
    {
        var configDir = Path.Combine(root, "config", "absorption");
        Directory.CreateDirectory(configDir);
        File.WriteAllText(Path.Combine(configDir, "pr-watchlist.json"), json);
    }

    private static void WriteReport(string root, int pr, string json)
    {
        var reportsDir = Path.Combine(root, ".helios", "absorption");
        Directory.CreateDirectory(reportsDir);
        File.WriteAllText(Path.Combine(reportsDir, $"pr-{pr}.json"), json);
    }

    /// <summary>
    /// Fabricates .helios/fleet/&lt;runId&gt;/ with a manifest shaped like the one
    /// start-fleet.ps1 writes (absolute db/claimLock paths, worker objects with
    /// assignee/pid/startTime) plus the referenced board db files.
    /// </summary>
    private static void WriteFleetRun(
        string root, string runId, string status,
        (string Pool, string Board, int Workers, string BoardJson)[] pools)
    {
        var runDir = Path.Combine(root, ".helios", "fleet", runId);
        Directory.CreateDirectory(Path.Combine(runDir, "boards"));
        Directory.CreateDirectory(Path.Combine(runDir, "locks"));

        var manifestPools = new List<object>();
        foreach (var (pool, board, workers, boardJson) in pools)
        {
            var dbPath = Path.Combine(runDir, "boards", $"{board}.json");
            File.WriteAllText(dbPath, boardJson);
            manifestPools.Add(new
            {
                pool,
                board,
                lanes = "code_generation,code_review",
                db = dbPath,
                claimLock = Path.Combine(runDir, "locks", $"{board}.lock"),
                workers = Enumerable.Range(1, workers)
                    .Select(slot => new
                    {
                        assignee = $"{pool}-{slot}",
                        pid = 40000 + slot,
                        startTime = "2026-08-11T12:00:00.0000000Z",
                    })
                    .ToArray(),
            });
        }

        File.WriteAllText(
            Path.Combine(runDir, "manifest.json"),
            JsonSerializer.Serialize(new
            {
                runId,
                startedAt = "2026-08-11T12:00:00Z",
                repoRoot = root,
                workerKind = "claude",
                status,
                stoppedAt = (string?)null,
                pools = manifestPools,
            }));
    }

    private static JsonElement FindCandidate(JsonElement summary, int pr) =>
        summary.GetProperty("candidates").EnumerateArray()
            .Single(candidate => candidate.GetProperty("pr").GetInt32() == pr);
}
