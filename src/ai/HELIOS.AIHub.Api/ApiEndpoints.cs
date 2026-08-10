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
}
