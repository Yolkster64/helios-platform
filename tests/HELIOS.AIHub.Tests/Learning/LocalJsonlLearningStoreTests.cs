using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

public class LocalJsonlLearningStoreTests : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), $"aihub-learning-{Guid.NewGuid():N}.jsonl");

    [Fact]
    public async Task RecordAndGetRecent_RoundTrips_NewestFirst()
    {
        var store = new LocalJsonlLearningStore(_path);
        await store.RecordAsync(Outcome("openai", success: true, at: 1));
        await store.RecordAsync(Outcome("anthropic", success: false, at: 2));
        await store.RecordAsync(Outcome("openai", success: true, at: 3));

        var recent = await store.GetRecentAsync("code_review");

        Assert.Equal(3, recent.Count);
        Assert.Equal("openai", recent[0].Provider); // at: 3, newest
        Assert.Equal("anthropic", recent[1].Provider);
    }

    [Fact]
    public async Task GetRecentAsync_FiltersByTaskType()
    {
        var store = new LocalJsonlLearningStore(_path);
        await store.RecordAsync(Outcome("openai", success: true, at: 1, taskType: "code_review"));
        await store.RecordAsync(Outcome("openai", success: true, at: 2, taskType: "code_generation"));

        var recent = await store.GetRecentAsync("code_review");

        Assert.Single(recent);
        Assert.Equal("code_review", recent[0].TaskType);
    }

    [Fact]
    public async Task GetRecentAsync_RespectsLimit()
    {
        var store = new LocalJsonlLearningStore(_path);
        for (var i = 0; i < 10; i++)
        {
            await store.RecordAsync(Outcome("openai", success: true, at: i));
        }

        var recent = await store.GetRecentAsync("code_review", limit: 3);

        Assert.Equal(3, recent.Count);
    }

    [Fact]
    public async Task GetRecentAsync_SkipsTornLines_WithoutThrowing()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        await File.WriteAllTextAsync(_path, "{not json}\n" + """{"taskType":"code_review","provider":"openai","success":true}""" + "\n");
        var store = new LocalJsonlLearningStore(_path);

        var recent = await store.GetRecentAsync("code_review");

        Assert.Single(recent);
        Assert.Equal("openai", recent[0].Provider);
    }

    [Fact]
    public async Task GetRecentAsync_MissingFile_ReturnsEmpty()
    {
        var store = new LocalJsonlLearningStore(_path);
        var recent = await store.GetRecentAsync("code_review");
        Assert.Empty(recent);
    }

    [Fact]
    public async Task GetRecentAllAsync_CrossesTaskTypes_NewestFirst()
    {
        var store = new LocalJsonlLearningStore(_path);
        await store.RecordAsync(Outcome("openai", success: true, at: 1, taskType: "code_review"));
        await store.RecordAsync(Outcome("anthropic", success: true, at: 2, taskType: "code_generation"));
        await store.RecordAsync(Outcome("ollama", success: false, at: 3, taskType: "debugging"));

        var recent = await store.GetRecentAllAsync();

        Assert.Equal(3, recent.Count);
        Assert.Equal("ollama", recent[0].Provider); // at: 3, newest
        Assert.Equal("anthropic", recent[1].Provider);
        Assert.Equal("openai", recent[2].Provider);
    }

    [Fact]
    public async Task GetRecentAllAsync_RespectsLimit_KeepingTheNewest()
    {
        var store = new LocalJsonlLearningStore(_path);
        await store.RecordAsync(Outcome("oldest", success: true, at: 1, taskType: "code_review"));
        await store.RecordAsync(Outcome("middle", success: true, at: 2, taskType: "code_generation"));
        await store.RecordAsync(Outcome("newest", success: true, at: 3, taskType: "debugging"));

        var recent = await store.GetRecentAllAsync(limit: 2);

        Assert.Equal(2, recent.Count);
        Assert.Equal("newest", recent[0].Provider);
        Assert.Equal("middle", recent[1].Provider);
    }

    [Fact]
    public async Task GetRecentAllAsync_MissingFile_ReturnsEmpty()
    {
        var store = new LocalJsonlLearningStore(_path);
        var recent = await store.GetRecentAllAsync();
        Assert.Empty(recent);
    }

    [Fact]
    public async Task ConcurrentAppends_FromTwoStoreInstances_LoseNoLinesAndTearNone()
    {
        // Two store instances over the SAME path have independent in-process gates, so
        // this exercises the cross-process discipline at the file-sharing level — the
        // shipped config points helios-ai-api, the MCP server, and CLI invocations at
        // one shared JSONL file.
        const int perStore = 50;
        using var storeA = new LocalJsonlLearningStore(_path);
        using var storeB = new LocalJsonlLearningStore(_path);

        var writes = new List<Task>(perStore * 2);
        for (var i = 0; i < perStore; i++)
        {
            writes.Add(Task.Run(() => storeA.RecordAsync(Outcome("store-a", success: true, at: 1))));
            writes.Add(Task.Run(() => storeB.RecordAsync(Outcome("store-b", success: true, at: 2))));
        }
        await Task.WhenAll(writes);

        var lines = await File.ReadAllLinesAsync(_path);
        Assert.Equal(perStore * 2, lines.Length);
        foreach (var line in lines)
        {
            var outcome = System.Text.Json.JsonSerializer.Deserialize<RoutingOutcome>(line);
            Assert.NotNull(outcome); // an interleaved partial line would throw or parse to garbage
            Assert.Contains(outcome!.Provider, new[] { "store-a", "store-b" });
        }

        var recent = await storeA.GetRecentAsync("code_review", limit: perStore * 2);
        Assert.Equal(perStore * 2, recent.Count);
    }

    [Fact]
    public async Task RecordAsync_LockedFile_RetriesAndSucceedsAfterRelease()
    {
        var store = new LocalJsonlLearningStore(_path);

        Task record;
        using (new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            record = store.RecordAsync(Outcome("openai", success: true, at: 1));
            // The bounded retry budget's minimum backoff (~225ms across attempts) far
            // exceeds this hold, so at least one retry lands after release.
            await Task.Delay(100);
        }
        await record;

        var recent = await store.GetRecentAsync("code_review");
        Assert.Single(recent);
        Assert.Equal("openai", recent[0].Provider);
    }

    [Fact]
    public async Task RecordAsync_LockNeverReleased_SurfacesIOExceptionForBestEffortCallers()
    {
        // The degradation contract: after bounded retries the store throws IOException,
        // which recording callers (AIHub.RecordOutcomeAsync) swallow best-effort — the
        // hub never crashes over a lost data point. This also pins that the .lock
        // exclusion actually holds on this platform.
        var store = new LocalJsonlLearningStore(_path);

        using (new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            await Assert.ThrowsAsync<IOException>(
                () => store.RecordAsync(Outcome("openai", success: true, at: 1)));
        }

        Assert.False(File.Exists(_path)); // no partial line was ever written
    }

    private static RoutingOutcome Outcome(string provider, bool success, int at, string taskType = "code_review") =>
        new()
        {
            Timestamp = DateTimeOffset.UnixEpoch.AddSeconds(at),
            TaskType = taskType,
            Provider = provider,
            Model = "test-model",
            Success = success,
            LatencyMs = 100,
            CostUsd = 0.01,
        };

    public void Dispose()
    {
        if (File.Exists(_path))
        {
            File.Delete(_path);
        }
        if (File.Exists(_path + ".lock"))
        {
            File.Delete(_path + ".lock");
        }
    }
}
