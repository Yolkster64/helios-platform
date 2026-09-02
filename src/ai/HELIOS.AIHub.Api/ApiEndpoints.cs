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
    private const string ApiKeyEnvironment = "HELIOS_API_ACCESS_KEY";
    private const string ApiKeyHeader = "X-HELIOS-Api-Key";

    private static readonly HashSet<string> EngineSecurityProfiles = new(StringComparer.OrdinalIgnoreCase)
    {
        "balanced",
        "hardened",
        "paranoid",
        "performance",
    };

    public static IEndpointRouteBuilder MapAIHubApi(this WebApplication app)
    {
        // Authorization must run before endpoint selection/binding. Endpoint filters in
        // .NET 8 run after handler arguments are bound, so a malformed remote POST could
        // otherwise receive a binding response without ever reaching the access check.
        app.Use(async (context, next) =>
        {
            if (context.Request.Path.StartsWithSegments("/v1")
                && AuthorizeApiRequest(
                    context, app.Configuration[ApiKeyEnvironment]) is { } denied)
            {
                await denied.ExecuteAsync(context);
                return;
            }
            await next(context);
        });

        app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

        var api = app.MapGroup("/v1");

        api.MapGet("/status", (AIHubService hub) =>
            Results.Ok(hub.GetStatus().Select(ProviderStatusResponse.From).ToList()));

        api.MapGet("/routing", (AIHubService hub) =>
            Results.Ok(new RoutingTableResponse(
                hub.RoutingTable.DefaultChain, hub.RoutingTable.TaskRouting)));

        api.MapGet("/learning", async (
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

        api.MapPost("/learning", async (
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
            if (request.Quality is { } quality && !(double.IsFinite(quality) && quality is >= 0 and <= 1))
            {
                // Quality is a [0,1] rating; a finite-but-invalid value (e.g. 100)
                // would silently poison /v1/metrics' AverageQuality (review finding).
                return Results.BadRequest(new ApiError(
                    "quality must be between 0 and 1 when provided."));
            }
            if (!(double.IsFinite(request.LatencyMs) && request.LatencyMs >= 0))
            {
                // A negative or non-finite latency is physically impossible and
                // would publish an impossible /v1/metrics average (review finding).
                return Results.BadRequest(new ApiError(
                    "latencyMs must be a nonnegative finite number."));
            }
            if (!(double.IsFinite(request.CostUsd) && request.CostUsd >= 0))
            {
                return Results.BadRequest(new ApiError(
                    "costUsd must be a nonnegative finite number."));
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

        api.MapGet("/insights", async (
            AIHubService hub, PythonInsightsSpoke spoke, string? taskType, int? limit,
            CancellationToken ct) =>
        {
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

        api.MapGet("/metrics", async (AIHubService hub, int? limit, CancellationToken ct) =>
        {
            // Telemetry, not routing: the window deliberately INCLUDES source-tagged
            // advisory records — the same records adaptive routing and fleet-plan
            // exclude — because a dashboard should show everything the store recorded.
            var window = await hub.Learning.GetRecentAllAsync(
                Math.Clamp(limit ?? 200, 1, 500), ct);

            var providers = window
                .GroupBy(o => o.Provider, StringComparer.OrdinalIgnoreCase)
                .Select(group =>
                {
                    var outcomes = group.ToList();
                    var successes = outcomes.Count(o => o.Success);
                    return new ProviderMetricsResponse(
                        group.Key,
                        Attempts: outcomes.Count,
                        Successes: successes,
                        AdvisoryCount: outcomes.Count(o => o.Source is not null),
                        SuccessRate: (double)successes / outcomes.Count,
                        // FiniteOrNull: strict JSON cannot carry NaN/Infinity, but it
                        // CAN carry finite values whose sum or average overflows (two
                        // 1e308 costs) — and the serializer then rejects the whole
                        // response with a 500 until those records age out of the
                        // window (review finding). A non-finite aggregate becomes
                        // null instead.
                        // The >= 0 filter is defense-in-depth for impossible negative
                        // latencies recorded before ingestion validated them; the
                        // nullable selector makes an all-invalid window null, not a
                        // throw (review finding).
                        AverageLatencyMs: FiniteOrNull(outcomes.Average(
                            o => o.LatencyMs >= 0 ? o.LatencyMs : (double?)null)),
                        TotalCostUsd: FiniteOrNull(outcomes.Sum(o => o.CostUsd)),
                        AverageCostUsd: FiniteOrNull(outcomes.Average(o => o.CostUsd)),
                        // Average(double?) ignores unrated outcomes and is null when
                        // none are rated — never a fabricated 0. The [0,1] filter is
                        // defense-in-depth for out-of-range ratings recorded before
                        // POST /v1/learning validated the range.
                        AverageQuality: FiniteOrNull(outcomes.Average(
                            o => o.Quality is >= 0 and <= 1 ? o.Quality : null)),
                        // RoutingOutcome persists no token counts, so these cannot be
                        // derived honestly — see ProviderMetricsResponse.
                        TokensUsed: null,
                        CostPerMillionTokens: null);
                })
                .OrderByDescending(p => p.Attempts)
                .ThenBy(p => p.Provider, StringComparer.OrdinalIgnoreCase)
                .ToList();

            var message = window.Count > 0
                ? null
                : hub.Learning is NullLearningStore
                    ? "Learning is disabled (or its store failed to initialize), so no "
                      + "outcomes are recorded; enable learning in config/aihub.json."
                    : "No routing outcomes recorded yet: route traffic through the hub "
                      + "or POST advisory outcomes to /v1/learning.";

            return Results.Ok(new MetricsResponse(
                DateTimeOffset.UtcNow, window.Count, providers, message));
        });

        api.MapGet("/engines", async (
            PythonInsightsSpoke spoke,
            bool? cudaEnabled,
            bool? includeCandidates,
            CancellationToken ct) =>
        {
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

        api.MapPost("/engines/recommend", async (
            EngineRecommendationRequest request,
            PythonInsightsSpoke spoke,
            CancellationToken ct) =>
        {
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

        api.MapPost("/ask", async (AskRequest request, AIHubService hub, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Prompt))
            {
                return Results.BadRequest(new ApiError("prompt is required."));
            }
            var result = await hub.AskAsync(
                request.Prompt, request.Provider, request.Model, request.System, ct);
            return Results.Ok(ChatResponse.From(result));
        });

        api.MapPost("/route", async (RouteRequest request, AIHubService hub, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.TaskType) || string.IsNullOrWhiteSpace(request.Prompt))
            {
                return Results.BadRequest(new ApiError("taskType and prompt are required."));
            }
            var result = await hub.RouteAsync(request.TaskType, request.Prompt, request.System, ct);
            return Results.Ok(ChatResponse.From(result));
        });

        api.MapPost("/tandem", async (RouteRequest request, AIHubService hub, CancellationToken ct) =>
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

        api.MapPost("/compare", async (CompareRequest request, AIHubService hub, CancellationToken ct) =>
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
    /// All API operations are local by default. A directly remote caller must use the
    /// configured access key; hosted deployments should additionally enforce their normal
    /// identity-aware ingress before traffic reaches Kestrel.
    /// </summary>
    /// <summary>Null when the aggregate is not representable as a finite double.</summary>
    private static double? FiniteOrNull(double? value) =>
        value is { } finite && double.IsFinite(finite) ? finite : null;

    private static IResult? AuthorizeApiRequest(HttpContext context, string? configuredKey)
    {
        var remoteAddress = context.Connection.RemoteIpAddress;
        if (remoteAddress is null || IPAddress.IsLoopback(remoteAddress))
        {
            return null;
        }
        if (string.IsNullOrWhiteSpace(configuredKey))
        {
            return Results.Json(
                new ApiError(
                    $"Remote API access is disabled. Configure {ApiKeyEnvironment} "
                    + $"and send {ApiKeyHeader}."),
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var suppliedKey = context.Request.Headers[ApiKeyHeader].ToString();
        var expectedBytes = Encoding.UTF8.GetBytes(configuredKey);
        var suppliedBytes = Encoding.UTF8.GetBytes(suppliedKey);
        return CryptographicOperations.FixedTimeEquals(expectedBytes, suppliedBytes)
            ? null
            : Results.Json(
                new ApiError($"Missing or invalid {ApiKeyHeader}."),
                statusCode: StatusCodes.Status401Unauthorized);
    }
}
