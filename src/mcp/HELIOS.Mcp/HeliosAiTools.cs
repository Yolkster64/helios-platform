using System.ComponentModel;
using System.Diagnostics;
using System.Text.Json;
using HELIOS.AIHub.Configuration;
using ModelContextProtocol;
using ModelContextProtocol.Server;
using HELIOS.AIHub;

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

    [McpServerTool(Name = "helios_task_routing_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("The task-type → provider-chain routing table (LLM strengths playbook as machine-readable config).")]
    public static string GetTaskRouting(AIHubService hub) =>
        JsonSerializer.Serialize(
            new { defaultChain = hub.RoutingTable.DefaultChain, taskRouting = hub.RoutingTable.TaskRouting },
            JsonOptions);

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

        var startInfo = new ProcessStartInfo
        {
            FileName = "bicep",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        startInfo.ArgumentList.Add("build");
        startInfo.ArgumentList.Add(bicepFile);
        startInfo.ArgumentList.Add("--stdout");

        using var process = Process.Start(startInfo)
            ?? throw new McpException("Failed to start the Bicep CLI — is 'bicep' (or 'az bicep') installed?");
        _ = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        return process.ExitCode == 0
            ? $"infra/main.bicep compiles clean.{(string.IsNullOrWhiteSpace(stderr) ? "" : $"\nLinter output:\n{stderr}")}"
            : $"Bicep build FAILED (exit {process.ExitCode}):\n{stderr}";
    }
}
