using System.Text.Json;
using HELIOS.AIHub;
using HELIOS.AIHub.Abstractions;

namespace HELIOS.AIHub.Cli;

/// <summary>
/// helios-ai — the cross-LLM shell. One command surface over every configured provider:
/// API SDKs (OpenAI, Anthropic, Azure OpenAI/Foundry, GitHub Models, Ollama) and agent
/// CLIs (claude, codex, copilot, gh models, hermes).
/// </summary>
public static class Program
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static async Task<int> Main(string[] args)
    {
        try
        {
            return await RunAsync(args).ConfigureAwait(false);
        }
        catch (FileNotFoundException ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static async Task<int> RunAsync(string[] args)
    {
        var (command, positionals, options) = Parse(args);
        var hub = AIHubService.CreateFromConfig(options.GetValueOrDefault("config"));

        switch (command)
        {
            case "ask":
            {
                if (positionals.Count == 0)
                {
                    return Fail("Usage: helios-ai ask \"<prompt>\" [--provider P] [--model M] [--system S] " +
                                "[--optimize cost|latency|quality|balanced --for <task-type>]");
                }
                var provider = options.GetValueOrDefault("provider");
                var optimize = options.GetValueOrDefault("optimize");
                if (provider is null && optimize is not null)
                {
                    var forTask = options.GetValueOrDefault("for");
                    if (forTask is null)
                    {
                        return Fail("--optimize requires --for <task-type> so the catalog knows what it's optimizing.");
                    }
                    provider = hub.SelectOptimalProvider(forTask, optimize);
                    if (provider is null)
                    {
                        return Fail($"No catalog entry (config/model-catalog.json) covers task '{forTask}'; " +
                                     "falling back to `route` is your next move.");
                    }
                    Console.Error.WriteLine($"[optimize={optimize} for={forTask} -> {provider}]");
                }
                var result = await hub.AskAsync(
                    positionals[0], provider,
                    options.GetValueOrDefault("model"),
                    options.GetValueOrDefault("system"));
                return PrintResult(result);
            }

            case "route":
            {
                if (positionals.Count < 2)
                {
                    return Fail("Usage: helios-ai route <task-type> \"<prompt>\" [--system S]\n" +
                                $"Task types: {string.Join(", ", hub.RoutingTable.TaskRouting.Keys.OrderBy(k => k))}");
                }
                var result = await hub.RouteAsync(positionals[0], positionals[1], options.GetValueOrDefault("system"));
                return PrintResult(result);
            }

            case "compare":
            {
                if (positionals.Count == 0)
                {
                    return Fail("Usage: helios-ai compare \"<prompt>\" [--providers a,b,c]");
                }
                var providers = options.GetValueOrDefault("providers")?
                    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                var results = await hub.CompareAsync(positionals[0], providers);
                foreach (var result in results)
                {
                    Console.WriteLine($"────── {result.Provider} ({result.Model}) " +
                                      $"{(result.Success ? $"{result.Latency.TotalSeconds:F1}s" : "FAILED")} ──────");
                    Console.WriteLine(result.Success ? result.Text : $"  {result.Error}");
                    Console.WriteLine();
                }
                return results.Any(r => r.Success) ? 0 : 1;
            }

            case "status":
            {
                foreach (var provider in hub.GetStatus())
                {
                    var marker = provider.Readiness switch
                    {
                        ProviderReadiness.Ready => "✓",
                        ProviderReadiness.Degraded => "!",
                        _ => "·",
                    };
                    Console.WriteLine($"{marker} {provider.Name,-16} {provider.Kind,-4} " +
                                      $"{provider.Model ?? "-",-28} {provider.Readiness}" +
                                      (provider.Detail is null ? "" : $"  — {provider.Detail}"));
                }
                return 0;
            }

            case "providers":
            case "list":
                Console.WriteLine(JsonSerializer.Serialize(hub.GetStatus(), JsonOptions));
                return 0;

            case "routing":
            {
                Console.WriteLine($"default: {string.Join(" → ", hub.RoutingTable.DefaultChain)}");
                foreach (var (taskType, chain) in hub.RoutingTable.TaskRouting.OrderBy(kv => kv.Key))
                {
                    Console.WriteLine($"{taskType,-24} {string.Join(" → ", chain)}");
                }
                return 0;
            }

            case "help":
            case "--help":
            case "-h":
            case null:
                PrintHelp();
                return 0;

            default:
                PrintHelp();
                return Fail($"Unknown command '{command}'.");
        }
    }

    private static int PrintResult(ChatResult result)
    {
        if (result.Success)
        {
            Console.WriteLine(result.Text);
            Console.Error.WriteLine(
                $"[{result.Provider}/{result.Model} in {result.Latency.TotalSeconds:F1}s" +
                (result.OutputTokens is null ? "]" : $", {result.InputTokens}→{result.OutputTokens} tokens]"));
            return 0;
        }
        Console.Error.WriteLine($"{result.Provider}: {result.Error}");
        return 1;
    }

    private static int Fail(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }

    private static void PrintHelp()
    {
        Console.WriteLine("""
            helios-ai — HELIOS cross-LLM shell

            Commands:
              ask "<prompt>" [--provider P] [--model M] [--system S]   Ask one provider (default: routed chain)
              route <task-type> "<prompt>" [--system S]                Route by task type with fallback
              compare "<prompt>" [--providers a,b,c]                   Fan out to several providers in parallel
              status                                                    Provider readiness (no network calls)
              providers                                                 Status as JSON
              routing                                                   Show the task-routing table
              help                                                      This text

            Global options:
              --config <path>   Explicit path to aihub.json (default: config/aihub.json walking up)

            Providers come from config/aihub.json; secrets from environment variables or
            Azure Key Vault (AZURE_KEY_VAULT_URI). Unconfigured providers show hints in status.
            """);
    }

    private static (string? Command, List<string> Positionals, Dictionary<string, string?> Options) Parse(string[] args)
    {
        string? command = null;
        var positionals = new List<string>();
        var options = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (arg.StartsWith("--", StringComparison.Ordinal))
            {
                var name = arg[2..];
                string? value = null;
                if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
                {
                    value = args[++i];
                }
                options[name] = value;
            }
            else if (command is null)
            {
                command = arg.ToLowerInvariant();
            }
            else
            {
                positionals.Add(arg);
            }
        }

        return (command, positionals, options);
    }
}
