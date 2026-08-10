using System.Net;
using System.Security.Cryptography;
using System.Text;
using HELIOS.AIHub.Learning;

namespace HELIOS.AIHub.Api;

/// <summary>
/// The C# orchestration surface as REST. Every endpoint delegates to
/// <see cref="AIHubService"/> — the same hub the CLI and MCP server share — so the API,
/// shell, and MCP clients always agree on routing, learning, and provider state.
///
/// Provider failures are payload, not transport: a completed orchestration call returns
/// 200 with <c>success=false</c> and the provider's error, because the orchestration
/// itself worked. 4xx is reserved for requests the hub was never asked to run.
/// </summary>
public static class ApiEndpoints
{
    private const string SpokeApiKeyEnvironment = "HELIOS_PYTHON_SPOKE_API_KEY";
    private const string SpokeApiKeyHeader = "X-HELIOS-Spoke-Key";

    private static readonly HashSet<string> EngineSecurityProfiles = new(StringComparer.OrdinalIgnoreCase)
    {
        "balanced",
        "hardened",
        "paranoid",
        "performance",
    };

    public static IEndpointRouteBuilder MapAIHubApi(this IEndpointRouteBuilder app)
    {
        app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

        app.MapGet("/v1/status", (AIHubService hub) =>
            Results.Ok(hub.GetStatus().Select(ProviderStatusResponse.From).ToList()));

        app.MapGet("/v1/routing", (AIHubService hub) =>
            Results.Ok(new RoutingTableResponse(
                hub.RoutingTable.DefaultChain, hub.RoutingTable.TaskRouting)));

        app.MapGet("/v1/learning", async (
            AIHubService hub, string? taskType, int? limit, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(taskType))
            {
                return Results.BadRequest(new ApiError("taskType query parameter is required."));
            }
            var outcomes = await hub.Learning.GetRecentAsync(
                taskType, Math.Clamp(limit ?? 50, 1, 500), ct);
            return Results.Ok(outcomes);
        });

        app.MapPost("/v1/learning", async (
            AIHubService hub, AdvisoryOutcomeRequest request, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.TaskType))
            {
                return Results.BadRequest(new ApiError("taskType is required."));
            }
            if (string.IsNullOrWhiteSpace(request.Source))
            {
                return Results.BadRequest(new ApiError(
                    "source is required: this endpoint ingests ADVISORY outcomes only "
                    + "(e.g. 'absorption-benchmark', 'fork-observation'); live provider "
                    + "outcomes are recorded by the hub itself."));
            }

            await hub.Learning.RecordAsync(
                new RoutingOutcome
                {
                    Timestamp = DateTimeOffset.UtcNow,
                    TaskType = request.TaskType,
                    Provider = request.Provider ?? request.Source,
                    Model = request.Model ?? "",
                    Success = request.Success,
                    LatencyMs = request.LatencyMs,
                    CostUsd = request.CostUsd,
                    Quality = request.Quality,
                    Pool = request.Pool,
                    Source = request.Source,
                },
                ct);

            // A disabled learning config routes to NullLearningStore — accepted but
            // dropped; tell the caller which happened.
            var enabled = hub.Learning is not NullLearningStore;
            return Results.Ok(new { recorded = enabled, learningEnabled = enabled });
        });

        app.MapGet("/v1/insights", async (
            HttpContext httpContext, AIHubService hub, PythonInsightsSpoke spoke,
            string? taskType, int? limit,
            CancellationToken ct) =>
        {
            if (AuthorizePythonSpokeRequest(httpContext) is { } denied)
            {
                return denied;
            }
            if (string.IsNullOrWhiteSpace(taskType))
            {
                return Results.BadRequest(new ApiError("taskType query parameter is required."));
            }
            var recent = await hub.Learning.GetRecentAsync(
                taskType, Math.Clamp(limit ?? 200, 1, 500), ct);
            // The store hands back newest first; the spoke's window math wants oldest first.
            var chronological = recent.Reverse().ToList();
            var summary = await spoke.SummarizeAsync(chronological, ct);
            if (summary is null)
            {
                return Results.Ok(new InsightsResponse(
                    taskType, false,
                    "Python spoke unavailable: needs python3 on PATH and src/ai/python "
                    + "(or HELIOS_PYTHON_SPOKE pointing at it).",
                    null, null));
            }
            var drift = await spoke.DetectDriftAsync(chronological, ct);
            return Results.Ok(new InsightsResponse(taskType, true, null, summary, drift));
        });

        app.MapGet("/v1/engines", async (
            HttpContext httpContext,
            PythonInsightsSpoke spoke,
            bool? cudaEnabled,
            bool? includeCandidates,
            CancellationToken ct) =>
        {
            if (AuthorizePythonSpokeRequest(httpContext) is { } denied)
            {
                return denied;
            }
            var catalog = await spoke.GetEngineCatalogAsync(
                cudaEnabled ?? false, includeCandidates ?? false, ct);
            return catalog is null
                ? Results.Ok(new EngineAdvisoryResponse(
                    false,
                    "Python spoke unavailable: install Python 3 and keep src/ai/python "
                    + "beside the HELIOS runtime (or set HELIOS_PYTHON_SPOKE).",
                    null))
                : Results.Ok(new EngineAdvisoryResponse(true, null, catalog));
        });

        app.MapPost("/v1/engines/recommend", async (
            HttpContext httpContext,
            EngineRecommendationRequest request,
            PythonInsightsSpoke spoke,
            CancellationToken ct) =>
        {
            if (AuthorizePythonSpokeRequest(httpContext) is { } denied)
            {
                return denied;
            }
            var profile = request.SecurityProfile?.Trim().ToLowerInvariant() ?? "balanced";
            if (!EngineSecurityProfiles.Contains(profile))
            {
                return Results.BadRequest(new ApiError(
                    "securityProfile must be balanced, hardened, paranoid, or performance."));
            }
            if (!double.IsFinite(request.OptimizationPressure)
                || request.OptimizationPressure < 0
                || request.OptimizationPressure > 1)
            {
                return Results.BadRequest(new ApiError(
                    "optimizationPressure must be a finite number between 0 and 1."));
            }
            if (request.FleetSize is < 0 or > 100_000)
            {
                return Results.BadRequest(new ApiError(
                    "fleetSize must be between 0 and 100000."));
            }

            var recommendation = await spoke.RecommendEnginesAsync(
                request.CudaEnabled,
                profile,
                request.OptimizationPressure,
                request.FleetSize,
                request.IncludeCandidates,
                ct);
            return recommendation is null
                ? Results.Ok(new EngineAdvisoryResponse(
                    false,
                    "Python spoke unavailable or rejected the request; no engine was selected or run.",
                    null))
                : Results.Ok(new EngineAdvisoryResponse(true, null, recommendation));
        });

        app.MapPost("/v1/ask", async (AskRequest request, AIHubService hub, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Prompt))
            {
                return Results.BadRequest(new ApiError("prompt is required."));
            }
            var result = await hub.AskAsync(
                request.Prompt, request.Provider, request.Model, request.System, ct);
            return Results.Ok(ChatResponse.From(result));
        });

        app.MapPost("/v1/route", async (RouteRequest request, AIHubService hub, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.TaskType) || string.IsNullOrWhiteSpace(request.Prompt))
            {
                return Results.BadRequest(new ApiError("taskType and prompt are required."));
            }
            var result = await hub.RouteAsync(request.TaskType, request.Prompt, request.System, ct);
            return Results.Ok(ChatResponse.From(result));
        });

        app.MapPost("/v1/tandem", async (RouteRequest request, AIHubService hub, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.TaskType) || string.IsNullOrWhiteSpace(request.Prompt))
            {
                return Results.BadRequest(new ApiError("taskType and prompt are required."));
            }
            var tandem = await hub.TandemAsync(request.TaskType, request.Prompt, request.System, ct);
            return Results.Ok(new TandemResponse(
                tandem.TaskType,
                tandem.Results.Select(ChatResponse.From).ToList(),
                tandem.Winner?.Provider));
        });

        app.MapPost("/v1/compare", async (CompareRequest request, AIHubService hub, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Prompt))
            {
                return Results.BadRequest(new ApiError("prompt is required."));
            }
            var results = await hub.CompareAsync(request.Prompt, request.Providers, request.System, ct);
            return Results.Ok(results.Select(ChatResponse.From).ToList());
        });

        return app;
    }

    /// <summary>
    /// Python-spawning endpoints are local by default. A directly remote caller must use
    /// the configured spoke key; hosted deployments should additionally enforce their
    /// normal identity-aware ingress before traffic reaches Kestrel.
    /// </summary>
    private static IResult? AuthorizePythonSpokeRequest(HttpContext context)
    {
        var configuredKey = Environment.GetEnvironmentVariable(SpokeApiKeyEnvironment);
        var remoteAddress = context.Connection.RemoteIpAddress;
        if (remoteAddress is null || IPAddress.IsLoopback(remoteAddress))
        {
            return null;
        }
        if (string.IsNullOrEmpty(configuredKey))
        {
            return Results.Json(
                new ApiError(
                    $"Remote Python-spoke access is disabled. Configure {SpokeApiKeyEnvironment} "
                    + $"and send {SpokeApiKeyHeader}."),
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var suppliedKey = context.Request.Headers[SpokeApiKeyHeader].ToString();
        var expectedBytes = Encoding.UTF8.GetBytes(configuredKey);
        var suppliedBytes = Encoding.UTF8.GetBytes(suppliedKey);
        return CryptographicOperations.FixedTimeEquals(expectedBytes, suppliedBytes)
            ? null
            : Results.Json(
                new ApiError($"Missing or invalid {SpokeApiKeyHeader}."),
                statusCode: StatusCodes.Status401Unauthorized);
    }
}
