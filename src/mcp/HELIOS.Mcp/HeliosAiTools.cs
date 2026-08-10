using System.ComponentModel;
using System.Diagnostics;
using System.Text.Json;
using HELIOS.AIHub.Configuration;
using ModelContextProtocol;
using ModelContextProtocol.Server;
using HELIOS.AIHub;
using HELIOS.AIHub.Learning;

namespace HELIOS.Mcp;

[McpServerToolType]
public static class HeliosAiTools
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    [McpServerTool(Name = "helios_ai_ask", Idempotent = false, OpenWorld = true)]
    [Description("Ask a single LLM provider through the HELIOS hub. Omit 'provider' to use the default routed chain. Returns the reply plus provider/model/latency/token metadata as JSON.")]
    public static async Task<string> Ask(
        AIHubService hub,
        [Description("The prompt to send.")] string prompt,
        [Description("Provider key from config/aihub.json (e.g. openai, anthropic, azure-openai, github-models, ollama, azure-foundry). Omit to route.")] string? provider = null,
        [Description("Model or Azure deployment override for this request.")] string? model = null,
        [Description("Optional system prompt.")] string? system = null,
        CancellationToken cancellationToken = default)
    {
        var result = await hub.AskAsync(prompt, provider, model, system, cancellationToken);
        return JsonSerializer.Serialize(result, JsonOptions);
    }

    [McpServerTool(Name = "helios_ai_route", Idempotent = false, OpenWorld = true)]
    [Description("Route a prompt by task type through the strengths-based provider chain with circuit-broken fallback (e.g. code_review→Claude, code_generation→Codex/OpenAI, enterprise_data→Azure Foundry). Use helios_task_routing_get for the full table.")]
    public static async Task<string> Route(
        AIHubService hub,
        [Description("Task type key, e.g. code_generation, code_review, long_context_analysis, security_analysis, enterprise_data, offline.")] string taskType,
        [Description("The prompt to send.")] string prompt,
        [Description("Optional system prompt.")] string? system = null,
        CancellationToken cancellationToken = default)
    {
        var result = await hub.RouteAsync(taskType, prompt, system, cancellationToken);
        return JsonSerializer.Serialize(result, JsonOptions);
    }

    [McpServerTool(Name = "helios_ai_tandem", Idempotent = false, OpenWorld = true)]
    [Description("Runs a task type's whole provider chain concurrently instead of sequential fallback -- e.g. ChatGPT (API) and Codex (CLI) racing on the same code_generation prompt -- and reports which the learned policy currently favors among the successes. Every result feeds the learning store when enabled, so tandem runs improve future single-shot routing.")]
    public static async Task<string> Tandem(
        AIHubService hub,
        [Description("Task type key, e.g. code_generation, code_review.")] string taskType,
        [Description("The prompt to send to every provider in the chain.")] string prompt,
        [Description("Optional system prompt.")] string? system = null,
        CancellationToken cancellationToken = default)
    {
        var result = await hub.TandemAsync(taskType, prompt, system, cancellationToken);
        return JsonSerializer.Serialize(result, JsonOptions);
    }

    [McpServerTool(Name = "helios_ai_compare", Idempotent = false, OpenWorld = true)]
    [Description("Fan the same prompt out to several providers in parallel and return every reply — useful for consensus checks and model comparison. Defaults to all ready providers.")]
    public static async Task<string> Compare(
        AIHubService hub,
        [Description("The prompt to send to every provider.")] string prompt,
        [Description("Comma-separated provider keys; omit for all ready providers.")] string? providers = null,
        CancellationToken cancellationToken = default)
    {
        var list = providers?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var results = await hub.CompareAsync(prompt, list, system: null, cancellationToken);
        return JsonSerializer.Serialize(results, JsonOptions);
    }

    [McpServerTool(Name = "helios_ai_status", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Readiness of every configured provider (Ready / Unconfigured with a fix hint / Degraded when its circuit breaker is open). No network calls.")]
    public static string Status(AIHubService hub) =>
        JsonSerializer.Serialize(hub.GetStatus(), JsonOptions);

    [McpServerTool(Name = "helios_providers_list", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("List all provider keys registered in the hub, with kind (api/cli) and default model.")]
    public static string ListProviders(AIHubService hub) =>
        JsonSerializer.Serialize(
            hub.GetStatus().Select(p => new { p.Name, p.Kind, p.Model }), JsonOptions);

    [McpServerTool(Name = "helios_optimal_provider_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Best provider AND model for a task type under a cost/latency/quality/balanced preference, from the static model catalog (config/model-catalog.json) — not the learned routing chain. Pass both to helios_ai_ask: the ranking scored that specific pair. Returns null when the catalog has no entry for the task type; fall back to helios_ai_route.")]
    public static string? SelectOptimalProvider(
        AIHubService hub,
        [Description("Task type key, e.g. code_generation, code_review, architecture_design.")] string taskType,
        [Description("cost | latency | quality | balanced (default).")] string preference = "balanced") =>
        hub.SelectOptimalProfile(taskType, preference) is { } profile
            ? JsonSerializer.Serialize(new { profile.Provider, profile.Model }, JsonOptions)
            : null;

    [McpServerTool(Name = "helios_task_routing_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("The task-type → provider-chain routing table (LLM strengths playbook as machine-readable config).")]
    public static string GetTaskRouting(AIHubService hub) =>
        JsonSerializer.Serialize(
            new { defaultChain = hub.RoutingTable.DefaultChain, taskRouting = hub.RoutingTable.TaskRouting },
            JsonOptions);

    [McpServerTool(Name = "helios_engine_catalog_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the HELIOS engine capability catalog. By default it returns only implemented capabilities, with runtime availability reported separately. Set includeCandidates=true to include recovered prototype/concept vocabulary. This tool does not install or run an engine.")]
    public static async Task<string> GetEngineCatalog(
        PythonInsightsSpoke spoke,
        [Description("Whether CUDA-required candidates are eligible for display. Defaults false; this does not probe or enable a GPU.")] bool cudaEnabled = false,
        [Description("Include explicitly labeled prototype/concept candidates.")] bool includeCandidates = false,
        CancellationToken cancellationToken = default)
    {
        var result = await spoke.GetEngineCatalogAsync(
            cudaEnabled, includeCandidates, cancellationToken);
        return result is { } catalog
            ? catalog.GetRawText()
            : JsonSerializer.Serialize(new
            {
                available = false,
                hint = "Python spoke unavailable; no engine was installed or run.",
            }, JsonOptions);
    }

    [McpServerTool(Name = "helios_engine_mix_recommend", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Create a local, deterministic engine plan for a security/performance/fleet profile. Runtime-available implementations and non-runnable build candidates are returned separately. The tool never installs, trains, or executes candidates.")]
    public static async Task<string> RecommendEngineMix(
        PythonInsightsSpoke spoke,
        [Description("Whether the target runtime has CUDA available. This is an input, not a hardware probe.")] bool cudaEnabled = false,
        [Description("balanced | hardened | paranoid | performance")] string? securityProfile = "balanced",
        [Description("Optimization pressure from 0.0 to 1.0.")] double optimizationPressure = 0.5,
        [Description("Expected concurrent Hermes/XCore fleet size, 0 to 100000.")] int fleetSize = 0,
        [Description("Include non-runnable prototype/concept build candidates in a separate list.")] bool includeCandidates = false,
        CancellationToken cancellationToken = default)
    {
        var normalizedProfile = (securityProfile ?? "balanced").Trim().ToLowerInvariant();
        if (normalizedProfile is not ("balanced" or "hardened" or "paranoid" or "performance"))
        {
            throw new McpException(
                "securityProfile must be balanced, hardened, paranoid, or performance.");
        }
        if (!double.IsFinite(optimizationPressure) || optimizationPressure is < 0 or > 1)
        {
            throw new McpException("optimizationPressure must be between 0 and 1.");
        }
        if (fleetSize is < 0 or > 100_000)
        {
            throw new McpException("fleetSize must be between 0 and 100000.");
        }

        var result = await spoke.RecommendEnginesAsync(
            cudaEnabled,
            normalizedProfile,
            optimizationPressure,
            fleetSize,
            includeCandidates,
            cancellationToken);
        return result is { } recommendation
            ? recommendation.GetRawText()
            : JsonSerializer.Serialize(new
            {
                available = false,
                hint = "Python spoke unavailable or rejected the request; no engine was selected or run.",
            }, JsonOptions);
    }

    [McpServerTool(Name = "helios_infra_validate", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Compile and lint the Azure infra (infra/main.bicep) with the Bicep CLI. Read-only: no deployment, no subscription access.")]
    public static async Task<string> ValidateInfra(CancellationToken cancellationToken = default)
    {
        var configPath = AIHubOptions.FindConfigFile()
            ?? throw new McpException("Repo root not found (no config/aihub.json in any parent directory).");
        var repoRoot = Directory.GetParent(Path.GetDirectoryName(configPath)!)!.FullName;
        var bicepFile = Path.Combine(repoRoot, "infra", "main.bicep");
        if (!File.Exists(bicepFile))
        {
            throw new McpException($"'{bicepFile}' does not exist.");
        }

        // Standalone `bicep` first; fall back to `az bicep` — the repo explicitly
        // supports either frontend and only one may be installed.
        Process? process = null;
        foreach (var (fileName, leadingArgs) in new[]
        {
            ("bicep", Array.Empty<string>()),
            ("az", new[] { "bicep" }),
        })
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = fileName,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            foreach (var arg in leadingArgs)
            {
                startInfo.ArgumentList.Add(arg);
            }
            startInfo.ArgumentList.Add("build");
            if (fileName == "az")
            {
                startInfo.ArgumentList.Add("--file");
            }
            startInfo.ArgumentList.Add(bicepFile);
            startInfo.ArgumentList.Add("--stdout");

            try
            {
                process = Process.Start(startInfo);
                if (process is not null)
                {
                    break;
                }
            }
            catch (System.ComponentModel.Win32Exception)
            {
                // This frontend isn't installed — try the next one.
            }
        }

        if (process is null)
        {
            throw new McpException("Neither 'bicep' nor 'az' is on PATH — install the Bicep CLI or Azure CLI.");
        }
        using var _proc = process;
        _ = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        return process.ExitCode == 0
            ? $"infra/main.bicep compiles clean.{(string.IsNullOrWhiteSpace(stderr) ? "" : $"\nLinter output:\n{stderr}")}"
            : $"Bicep build FAILED (exit {process.ExitCode}):\n{stderr}";
    }
}
