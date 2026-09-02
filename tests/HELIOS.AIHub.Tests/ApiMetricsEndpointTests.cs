using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using HELIOS.AIHub.Api;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Learning;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// HTTP-level tests for GET /v1/metrics — the dashboard telemetry seam (GUI_UPGRADE_PLAN
/// P2). Unlike <see cref="ApiEndpointTests"/>, each test builds its own factory so the
/// hub's learning store can be swapped for a deterministic <see cref="FakeLearningStore"/>
/// and so the connection's remote address and configured access key can be pinned —
/// TestServer connections otherwise carry no remote address at all, which the
/// loopback-or-key gate treats as local.
/// </summary>
public sealed class ApiMetricsEndpointTests
{
    private const string AccessKeyConfigName = "HELIOS_API_ACCESS_KEY";
    private const string AccessKeyHeader = "X-HELIOS-Api-Key";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task Metrics_EmptyStore_Returns200WithEmptyProvidersAndMessage()
    {
        using var factory = CreateFactory(new FakeLearningStore());
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/v1/metrics");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var metrics = await response.Content.ReadFromJsonAsync<MetricsResponse>(Json);
        Assert.NotNull(metrics);
        Assert.NotEqual(default, metrics.GeneratedUtc);
        Assert.Equal(0, metrics.WindowSize);
        Assert.Empty(metrics.Providers);
        Assert.False(string.IsNullOrWhiteSpace(metrics.Message));
    }

    [Fact]
    public async Task Metrics_LearningDisabled_ExplainsNullStoreInMessage()
    {
        using var factory = CreateFactory(learning: new NullLearningStore());
        using var client = factory.CreateClient();

        var metrics = await client.GetFromJsonAsync<MetricsResponse>("/v1/metrics", Json);

        Assert.NotNull(metrics);
        Assert.Empty(metrics.Providers);
        Assert.Contains("disabled", metrics.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Metrics_AggregatesPerProvider_WithHandComputedMath()
    {
        var store = new FakeLearningStore(new[]
        {
            Outcome("openai", success: true, latencyMs: 100, costUsd: 0.001),
            Outcome("openai", success: true, latencyMs: 300, costUsd: 0.002, quality: 0.5),
            Outcome("openai", success: false, latencyMs: 200, costUsd: 0.003),
            Outcome("anthropic", success: true, latencyMs: 50, costUsd: 0.010),
        });
        using var factory = CreateFactory(store);
        using var client = factory.CreateClient();

        var metrics = await client.GetFromJsonAsync<MetricsResponse>("/v1/metrics", Json);

        Assert.NotNull(metrics);
        Assert.Equal(4, metrics.WindowSize);
        Assert.Null(metrics.Message);
        Assert.Equal(2, metrics.Providers.Count);

        var openai = metrics.Providers[0]; // most attempts orders first
        Assert.Equal("openai", openai.Provider);
        Assert.Equal(3, openai.Attempts);
        Assert.Equal(2, openai.Successes);
        Assert.Equal(0, openai.AdvisoryCount);
        Assert.Equal(2.0 / 3.0, openai.SuccessRate, precision: 12);
        Assert.NotNull(openai.AverageLatencyMs);
        Assert.Equal(200.0, openai.AverageLatencyMs.Value, precision: 12);
        Assert.NotNull(openai.TotalCostUsd);
        Assert.Equal(0.006, openai.TotalCostUsd.Value, precision: 12);
        Assert.NotNull(openai.AverageCostUsd);
        Assert.Equal(0.002, openai.AverageCostUsd.Value, precision: 12);
        Assert.NotNull(openai.AverageQuality); // only the single rated outcome counts
        Assert.Equal(0.5, openai.AverageQuality.Value, precision: 12);

        var anthropic = metrics.Providers[1];
        Assert.Equal("anthropic", anthropic.Provider);
        Assert.Equal(1, anthropic.Attempts);
        Assert.Equal(1.0, anthropic.SuccessRate, precision: 12);
        Assert.NotNull(anthropic.AverageLatencyMs);
        Assert.Equal(50.0, anthropic.AverageLatencyMs.Value, precision: 12);
        Assert.NotNull(anthropic.TotalCostUsd);
        Assert.Equal(0.010, anthropic.TotalCostUsd.Value, precision: 12);
        Assert.Null(anthropic.AverageQuality); // no rated outcomes → null, never 0

        // RoutingOutcome persists no token counts, so both stay honestly null.
        Assert.All(metrics.Providers, p => Assert.Null(p.TokensUsed));
        Assert.All(metrics.Providers, p => Assert.Null(p.CostPerMillionTokens));
    }

    [Fact]
    public async Task Metrics_NonFiniteAggregates_BecomeNullInsteadOf500()
    {
        // Strict JSON cannot carry NaN/Infinity, but it CAN carry finite values whose
        // sum or average overflows (two 1e308 costs -> +Infinity) — and the default
        // serializer rejects non-finite doubles, which would turn every /v1/metrics
        // call into a 500 until the records aged out of the window (review finding).
        var store = new FakeLearningStore(new[]
        {
            Outcome("openai", success: true, latencyMs: 100, costUsd: 1e308),
            Outcome("openai", success: true, latencyMs: 200, costUsd: 1e308),
        });
        using var factory = CreateFactory(store);
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/v1/metrics");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var metrics = await response.Content.ReadFromJsonAsync<MetricsResponse>(Json);
        Assert.NotNull(metrics);
        var openai = Assert.Single(metrics.Providers);
        Assert.Equal(2, openai.Attempts);
        Assert.Null(openai.TotalCostUsd);      // 1e308 + 1e308 overflows -> null
        Assert.Null(openai.AverageCostUsd);    // Average sums first -> also overflows
        Assert.NotNull(openai.AverageLatencyMs); // sane values stay reported
        Assert.Equal(150.0, openai.AverageLatencyMs.Value, precision: 12);
    }

    [Fact]
    public async Task Metrics_NegativeLegacyLatency_ExcludedFromAverage()
    {
        // Ingestion now rejects negative latency, but rows recorded before that
        // validation can still be in the store; the average must ignore them
        // instead of publishing an impossible negative latency.
        var store = new FakeLearningStore(new[]
        {
            Outcome("openai", success: true, latencyMs: -100, costUsd: 0),
            Outcome("openai", success: true, latencyMs: 300, costUsd: 0),
        });
        using var factory = CreateFactory(store);
        using var client = factory.CreateClient();

        var metrics = await client.GetFromJsonAsync<MetricsResponse>("/v1/metrics", Json);

        Assert.NotNull(metrics);
        var openai = Assert.Single(metrics.Providers);
        Assert.NotNull(openai.AverageLatencyMs);
        Assert.Equal(300.0, openai.AverageLatencyMs.Value, precision: 12); // only the valid sample
    }

    [Fact]
    public async Task Metrics_IncludesSourceTaggedAdvisoryRecords()
    {
        // Advisory records are excluded from adaptive routing, but /v1/metrics is
        // telemetry display: a window holding ONLY advisory outcomes still aggregates.
        var store = new FakeLearningStore(new[]
        {
            Outcome("M0nado/helios-platform#222", success: true, latencyMs: 10,
                costUsd: 0, source: "absorption-benchmark"),
            Outcome("pool:xcore-9-code", success: false, latencyMs: 20,
                costUsd: 0, source: "fleet-lane"),
        });
        using var factory = CreateFactory(store);
        using var client = factory.CreateClient();

        var metrics = await client.GetFromJsonAsync<MetricsResponse>("/v1/metrics", Json);

        Assert.NotNull(metrics);
        Assert.Equal(2, metrics.WindowSize);
        Assert.Equal(2, metrics.Providers.Count);
        Assert.All(metrics.Providers, p => Assert.Equal(1, p.AdvisoryCount));
    }

    [Fact]
    public async Task Metrics_LimitCapsTheAggregationWindow()
    {
        var store = new FakeLearningStore(new[]
        {
            Outcome("openai", success: true, latencyMs: 100, costUsd: 0),
            Outcome("openai", success: true, latencyMs: 100, costUsd: 0),
            Outcome("anthropic", success: true, latencyMs: 100, costUsd: 0),
        });
        using var factory = CreateFactory(store);
        using var client = factory.CreateClient();

        var metrics = await client.GetFromJsonAsync<MetricsResponse>("/v1/metrics?limit=2", Json);

        Assert.NotNull(metrics);
        Assert.Equal(2, metrics.WindowSize); // newest two only (store hands back newest first)
        var provider = Assert.Single(metrics.Providers);
        Assert.Equal("openai", provider.Provider);
    }

    [Fact]
    public async Task Metrics_RemoteCallerWithoutConfiguredKey_IsRejected()
    {
        using var factory = CreateFactory(
            new FakeLearningStore(),
            remoteAddress: IPAddress.Parse("203.0.113.7"),
            accessKey: ""); // explicitly unconfigured, whatever the test host's env says
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/v1/metrics");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Metrics_RemoteCallerWithValidKey_IsServed()
    {
        using var factory = CreateFactory(
            new FakeLearningStore(),
            remoteAddress: IPAddress.Parse("203.0.113.7"),
            accessKey: "test-metrics-key");
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add(AccessKeyHeader, "test-metrics-key");

        var response = await client.GetAsync("/v1/metrics");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Metrics_RemoteCallerWithWrongKey_IsRejected()
    {
        using var factory = CreateFactory(
            new FakeLearningStore(),
            remoteAddress: IPAddress.Parse("203.0.113.7"),
            accessKey: "test-metrics-key");
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add(AccessKeyHeader, "not-the-key");

        var response = await client.GetAsync("/v1/metrics");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Metrics_LoopbackCaller_NeedsNoKey()
    {
        using var factory = CreateFactory(
            new FakeLearningStore(),
            remoteAddress: IPAddress.Loopback,
            accessKey: ""); // no key configured — loopback must still be served
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/v1/metrics");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    /// <summary>
    /// Boots the real app with the hub swapped for a keyless echo-free one over
    /// <paramref name="learning"/>. <paramref name="accessKey"/> lands in configuration
    /// via an in-memory source appended LAST, so it beats any ambient environment
    /// variable either way ("" = deterministically unconfigured).
    /// <paramref name="remoteAddress"/> is stamped onto every connection by a startup
    /// filter, whose middleware runs before the pipeline Program.cs builds — i.e.
    /// before the /v1 access gate reads it.
    /// </summary>
    private static WebApplicationFactory<Program> CreateFactory(
        ILearningStore learning, IPAddress? remoteAddress = null, string? accessKey = null)
    {
        return new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            if (accessKey is not null)
            {
                builder.ConfigureAppConfiguration((_, configuration) =>
                    configuration.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        [AccessKeyConfigName] = accessKey,
                    }));
            }
            builder.ConfigureServices(services =>
            {
                // Replaces Program.cs's registration (last one wins): a minimal
                // provider-less options object keeps the hub keyless and offline.
                services.AddSingleton(_ => new AIHubService(new AIHubOptions(), learning: learning));
                if (remoteAddress is not null)
                {
                    services.AddSingleton<IStartupFilter>(
                        new RemoteAddressStartupFilter(remoteAddress));
                }
            });
        });
    }

    /// <summary>Deterministic outcome for hand-computed aggregate assertions.</summary>
    private static RoutingOutcome Outcome(
        string provider, bool success, double latencyMs, double costUsd,
        double? quality = null, string? source = null) =>
        new()
        {
            Timestamp = DateTimeOffset.UnixEpoch,
            TaskType = "code_review",
            Provider = provider,
            Model = "fake-model",
            Success = success,
            LatencyMs = latencyMs,
            CostUsd = costUsd,
            Quality = quality,
            Source = source,
        };

    private sealed class RemoteAddressStartupFilter : IStartupFilter
    {
        private readonly IPAddress _address;

        public RemoteAddressStartupFilter(IPAddress address)
        {
            _address = address;
        }

        public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) =>
            app =>
            {
                app.Use(async (context, nextMiddleware) =>
                {
                    context.Connection.RemoteIpAddress = _address;
                    await nextMiddleware(context);
                });
                next(app);
            };
    }
}
