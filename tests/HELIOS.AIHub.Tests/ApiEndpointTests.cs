using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using HELIOS.AIHub.Api;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// HTTP-level tests for the REST orchestration surface. The factory boots the real app
/// against a private copy of the shipped config/aihub.json (<see cref="IsolatedApiFactory"/>),
/// where every provider is Unconfigured and the learning store is empty — so these run
/// keyless and offline, like CI, and independently of the checkout's own
/// <c>.helios/learning</c> store.
/// </summary>
public sealed class ApiEndpointTests : IClassFixture<IsolatedApiFactory>
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly bool RequirePythonSpoke =
        Environment.GetEnvironmentVariable("HELIOS_REQUIRE_PYTHON_SPOKE") == "1";

    private readonly HttpClient _client;

    public ApiEndpointTests(IsolatedApiFactory factory)
    {
        _client = factory.CreateClient();
        if (Environment.GetEnvironmentVariable("HELIOS_API_ACCESS_KEY") is { Length: > 0 } key)
        {
            _client.DefaultRequestHeaders.Add("X-HELIOS-Api-Key", key);
        }
    }

    [Fact]
    public async Task Healthz_ReturnsOk()
    {
        var response = await _client.GetAsync("/healthz");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Status_ListsEveryConfiguredProvider()
    {
        var providers = await _client.GetFromJsonAsync<List<ProviderStatusResponse>>("/v1/status", Json);

        Assert.NotNull(providers);
        Assert.NotEmpty(providers);
        Assert.Contains(providers, p => p.Name == "openai");
        Assert.Contains(providers, p => p.Name == "anthropic");
        Assert.All(providers, p => Assert.False(string.IsNullOrWhiteSpace(p.Readiness)));
    }

    [Fact]
    public async Task Routing_ExposesDefaultChainAndTaskTable()
    {
        var routing = await _client.GetFromJsonAsync<RoutingTableResponse>("/v1/routing", Json);

        Assert.NotNull(routing);
        Assert.NotEmpty(routing.DefaultChain);
        Assert.True(routing.TaskRouting.ContainsKey("code_generation"));
    }

    [Fact]
    public async Task Learning_RequiresTaskType()
    {
        var response = await _client.GetAsync("/v1/learning");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Insights_RequiresTaskType()
    {
        var response = await _client.GetAsync("/v1/insights");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Insights_ReportsSummaryOrStatesUnavailability()
    {
        var response = await _client.GetAsync("/v1/insights?taskType=code_generation");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var insights = await response.Content.ReadFromJsonAsync<InsightsResponse>(Json);
        Assert.NotNull(insights);
        Assert.Equal("code_generation", insights.TaskType);
        if (insights.Available)
        {
            Assert.NotNull(insights.Summary);
            Assert.Equal(0, insights.Summary.Value.GetProperty("totalOutcomes").GetInt32());
            Assert.NotNull(insights.Drift);
            Assert.Equal(0, insights.Drift.Value.GetProperty("checked").GetInt32());
        }
        else
        {
            Assert.False(RequirePythonSpoke, insights.Hint);
            Assert.False(string.IsNullOrWhiteSpace(insights.Hint));
        }
    }

    [Fact]
    public async Task Engines_ReturnImplementedCatalogWithRuntimeAvailability()
    {
        var response = await _client.GetAsync("/v1/engines?includeCandidates=false");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var advisory = await response.Content.ReadFromJsonAsync<EngineAdvisoryResponse>(Json);
        Assert.NotNull(advisory);
        if (!advisory.Available)
        {
            Assert.False(RequirePythonSpoke, advisory.Hint);
            Assert.False(string.IsNullOrWhiteSpace(advisory.Hint));
            return;
        }
        Assert.NotNull(advisory.Result);
        Assert.Equal(0, advisory.Result.Value.GetProperty("candidate_count").GetInt32());
        Assert.True(advisory.Result.Value.GetProperty("implemented_count").GetInt32() > 0);
        var routingPolicy = Assert.Single(
            advisory.Result.Value.GetProperty("engines").EnumerateArray(),
            engine => engine.GetProperty("name").GetString() == "routing-policy");
        Assert.True(routingPolicy.GetProperty("runtime_available").GetBoolean());
    }

    [Fact]
    public async Task EngineRecommendation_RejectsOutOfRangePressure()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/engines/recommend",
            new EngineRecommendationRequest(OptimizationPressure: 1.1),
            Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task EngineRecommendation_RejectsInvalidSecurityProfile()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/engines/recommend",
            new EngineRecommendationRequest(SecurityProfile: "invalid-profile"),
            Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task EngineRecommendation_RejectsOutOfRangeFleetSize()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/engines/recommend",
            new EngineRecommendationRequest(FleetSize: 100_001),
            Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task EngineRecommendation_IsAdvisoryAndSeparatesCandidates()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/engines/recommend",
            new EngineRecommendationRequest(
                CudaEnabled: false,
                SecurityProfile: "hardened",
                OptimizationPressure: 0.8,
                FleetSize: 36,
                IncludeCandidates: true),
            Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var advisory = await response.Content.ReadFromJsonAsync<EngineAdvisoryResponse>(Json);
        Assert.NotNull(advisory);
        if (!advisory.Available)
        {
            Assert.False(RequirePythonSpoke, advisory.Hint);
            Assert.False(string.IsNullOrWhiteSpace(advisory.Hint));
            return;
        }
        Assert.NotNull(advisory.Result);
        Assert.True(advisory.Result.Value.GetProperty("selected_count").GetInt32() > 0);
        Assert.True(advisory.Result.Value.GetProperty("candidate_count").GetInt32() > 0);
    }

    [Fact]
    public async Task Learning_ReturnsRecentOutcomes()
    {
        var response = await _client.GetAsync("/v1/learning?taskType=code_generation&limit=10");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task PostLearning_RejectsMissingSource()
    {
        // Advisory-only ingestion: without provenance the record would be
        // indistinguishable from a live provider outcome.
        var response = await _client.PostAsJsonAsync("/v1/learning",
            new AdvisoryOutcomeRequest(TaskType: "absorption", Source: null,
                Provider: "M0nado/helios-platform#222", Model: "abc", Success: true), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task PostLearning_RejectsMissingTaskType()
    {
        var response = await _client.PostAsJsonAsync("/v1/learning",
            new AdvisoryOutcomeRequest(TaskType: null, Source: "absorption-benchmark",
                Provider: "M0nado/helios-platform#222", Model: "abc", Success: true), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task PostLearning_RejectsOutOfRangeQuality()
    {
        // Quality is a [0,1] rating; a finite-but-invalid value (e.g. 100) would
        // silently poison /v1/metrics' AverageQuality.
        var response = await _client.PostAsJsonAsync("/v1/learning",
            new AdvisoryOutcomeRequest(TaskType: "absorption", Source: "absorption-benchmark",
                Provider: "M0nado/helios-platform#222", Model: "abc", Success: true,
                Quality: 100), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task PostLearning_RejectsNegativeLatency()
    {
        // A negative latency is physically impossible and would publish an
        // impossible /v1/metrics average.
        var response = await _client.PostAsJsonAsync("/v1/learning",
            new AdvisoryOutcomeRequest(TaskType: "absorption", Source: "absorption-benchmark",
                Provider: "M0nado/helios-platform#222", Model: "abc", Success: true,
                LatencyMs: -100), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task PostLearning_AcceptsAdvisoryOutcome_AndReportsStoreState()
    {
        var response = await _client.PostAsJsonAsync("/v1/learning",
            new AdvisoryOutcomeRequest(TaskType: "absorption", Source: "absorption-benchmark",
                Provider: "M0nado/helios-platform#222", Model: "abc", Success: true), Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.True(body.RootElement.TryGetProperty("recorded", out _));
        Assert.True(body.RootElement.TryGetProperty("learningEnabled", out _));
    }

    [Fact]
    public async Task Ask_RejectsMissingPrompt()
    {
        var response = await _client.PostAsJsonAsync("/v1/ask", new AskRequest(Prompt: null), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Ask_ReportsUnknownProviderAsPayloadFailure()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/ask", new AskRequest("hello", Provider: "no-such-provider"), Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<ChatResponse>(Json);
        Assert.NotNull(result);
        Assert.False(result.Success);
        Assert.Contains("Unknown provider", result.Error);
    }

    [Fact]
    public async Task Route_RejectsMissingTaskType()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/route", new RouteRequest(TaskType: null, Prompt: "hello"), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Tandem_RejectsMissingTaskType()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/tandem", new RouteRequest(TaskType: null, Prompt: "hello"), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Compare_RejectsMissingPrompt()
    {
        var response = await _client.PostAsJsonAsync("/v1/compare", new CompareRequest(Prompt: null), Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Compare_ReportsUnknownProvidersPerResult()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/compare", new CompareRequest("hello", Providers: new[] { "no-such-provider" }), Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var results = await response.Content.ReadFromJsonAsync<List<ChatResponse>>(Json);
        Assert.NotNull(results);
        var single = Assert.Single(results);
        Assert.False(single.Success);
    }
}
