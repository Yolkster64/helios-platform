using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using HELIOS.AIHub.Api;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// HTTP-level tests for the REST orchestration surface. The factory boots the real app
/// against the shipped config/aihub.json (found by walking up from the test directory),
/// where every provider is Unconfigured — so these run keyless and offline, like CI.
/// </summary>
public sealed class ApiEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly HttpClient _client;

    public ApiEndpointTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
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
            Assert.False(string.IsNullOrWhiteSpace(insights.Hint));
        }
    }

    [Fact]
    public async Task Learning_ReturnsRecentOutcomes()
    {
        var response = await _client.GetAsync("/v1/learning?taskType=code_generation&limit=10");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
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
