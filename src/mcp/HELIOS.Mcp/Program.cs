using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using HELIOS.AIHub;
using HELIOS.AIHub.Learning;
using HELIOS.AIHub.Providers;

namespace HELIOS.Mcp;

/// <summary>
/// HELIOS MCP server (stdio). Exposes the multi-LLM hub to any MCP client — Claude Code,
/// GitHub Copilot, Codex CLI, Cursor — so every agent shares one tool surface.
/// Registration: .mcp.json at the repo root; per-client snippets in docs/mcp/CLIENT_SETUP.md.
/// </summary>
public static class Program
{
    public static async Task Main(string[] args)
    {
        var builder = Host.CreateApplicationBuilder(args);

        // stdio transport: the protocol owns stdout, so all logging must go to stderr.
        // CreateApplicationBuilder pre-registers a stdout console logger; clear it or
        // hosting log lines interleave with the JSON-RPC stream and break clients.
        builder.Logging.ClearProviders();
        builder.Logging.AddConsole(options => options.LogToStandardErrorThreshold = LogLevel.Trace);

        builder.Services.AddSingleton(_ => AIHubService.CreateFromConfig());
        builder.Services.AddSingleton<PythonInsightsSpoke>();
        // Foundry agent administration (helios_foundry_agent_*): reads
        // AZURE_FOUNDRY_PROJECT_ENDPOINT; unset is the standard Unconfigured
        // state, never a startup failure.
        builder.Services.AddSingleton(_ => new FoundryAgentService());
        // Azure management-plane inventory (helios_azure_inventory_get):
        // DefaultAzureCredential resolves lazily at first use; missing credentials
        // are the Unauthenticated state, never a startup failure.
        builder.Services.AddSingleton(_ => new AzureResourceService());
        builder.Services
            .AddMcpServer()
            .WithStdioServerTransport()
            .WithToolsFromAssembly();

        await builder.Build().RunAsync();
    }
}
