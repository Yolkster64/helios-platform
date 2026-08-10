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
    }
}
