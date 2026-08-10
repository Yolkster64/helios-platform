using System.Globalization;
using System.Text.Json;
using HELIOS.AIHub;
using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Learning;

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
        if (options.TryGetValue("config", out var explicitConfig)
            && string.IsNullOrWhiteSpace(explicitConfig))
        {
            return Fail("--config requires a path.");
        }
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
                string? optimizedModel = null;
                if (provider is null && optimize is not null)
                {
                    var forTask = options.GetValueOrDefault("for");
                    if (forTask is null)
                    {
                        return Fail("--optimize requires --for <task-type> so the catalog knows what it's optimizing.");
                    }
                    if (hub.SelectOptimalProfile(forTask, optimize) is not { } profile)
                    {
                        return Fail($"No catalog entry (config/model-catalog.json) covers task '{forTask}'; " +
                                     "falling back to `route` is your next move.");
                    }
                    // Send the request to the model the catalog actually ranked, not the
                    // provider's configured default.
                    (provider, optimizedModel) = profile;
                    Console.Error.WriteLine($"[optimize={optimize} for={forTask} -> {provider}/{optimizedModel}]");
                }
                var result = await hub.AskAsync(
                    positionals[0], provider,
                    options.GetValueOrDefault("model") ?? optimizedModel,
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

            case "tandem":
            {
                if (positionals.Count < 2)
                {
                    return Fail("Usage: helios-ai tandem <task-type> \"<prompt>\" [--system S]\n" +
                                "Runs the task type's whole provider chain concurrently (e.g. ChatGPT + Codex " +
                                "for code_generation) instead of sequential fallback, and reports which the " +
                                "learned policy currently favors.");
                }
                var tandem = await hub.TandemAsync(positionals[0], positionals[1], options.GetValueOrDefault("system"));
                foreach (var result in tandem.Results)
                {
                    var marker = ReferenceEquals(result, tandem.Winner) ? "★" : " ";
                    Console.WriteLine($"{marker} ────── {result.Provider} ({result.Model}) " +
                                      $"{(result.Success ? $"{result.Latency.TotalSeconds:F1}s" : "FAILED")} ──────");
                    Console.WriteLine(result.Success ? result.Text : $"  {result.Error}");
                    Console.WriteLine();
                }
                if (tandem.Winner is not null)
                {
                    Console.Error.WriteLine($"[tandem winner: {tandem.Winner.Provider} — learned-policy favorite among successes]");
                }
                return tandem.Results.Any(r => r.Success) ? 0 : 1;
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

            case "engines":
            {
                if (positionals.Count != 0)
                {
                    return Fail(
                        "Usage: helios-ai engines [--cuda[=BOOL]] [--include-candidates[=BOOL]]");
                }
                if (FindUnexpectedOption(options, "config", "cuda", "include-candidates") is { } unexpected)
                {
                    return Fail($"Unknown option '--{unexpected}' for engines.");
                }
                if (!TryReadFlag(options, "cuda", out var cudaEnabled, out var flagError)
                    || !TryReadFlag(
                        options, "include-candidates", out var includeCandidates, out flagError))
                {
                    return Fail(flagError!);
                }
                var spoke = new PythonInsightsSpoke();
                var catalog = await spoke.GetEngineCatalogAsync(
                    cudaEnabled: cudaEnabled,
                    includeCandidates: includeCandidates);
                if (catalog is null)
                {
                    return Fail(
                        "Python engine spoke unavailable; install Python 3 and keep src/ai/python "
                        + "beside the checkout (or set HELIOS_PYTHON_SPOKE). No engine was run.");
                }
                Console.WriteLine(catalog.Value.GetRawText());
                return 0;
            }

            case "engine-plan":
            {
                if (positionals.Count != 0)
                {
                    return Fail(
                        "Usage: helios-ai engine-plan [--security-profile P] [--pressure 0..1] "
                        + "[--fleet-size N] [--cuda[=BOOL]] [--include-candidates[=BOOL]]");
                }
                if (FindUnexpectedOption(
                        options,
                        "config", "security-profile", "pressure", "fleet-size", "cuda",
                        "include-candidates") is { } unexpected)
                {
                    return Fail($"Unknown option '--{unexpected}' for engine-plan.");
                }
                foreach (var valuedOption in new[] { "security-profile", "pressure", "fleet-size" })
                {
                    if (options.TryGetValue(valuedOption, out var value)
                        && string.IsNullOrWhiteSpace(value))
                    {
                        return Fail($"--{valuedOption} requires a value.");
                    }
                }
                if (!TryReadFlag(options, "cuda", out var cudaEnabled, out var flagError)
                    || !TryReadFlag(
                        options, "include-candidates", out var includeCandidates, out flagError))
                {
                    return Fail(flagError!);
                }

                var securityProfile = options.GetValueOrDefault("security-profile") ?? "balanced";
                if (securityProfile.ToLowerInvariant()
                    is not ("balanced" or "hardened" or "paranoid" or "performance"))
                {
                    return Fail(
                        "--security-profile must be balanced, hardened, paranoid, or performance.");
                }
                if (!double.TryParse(
                        options.GetValueOrDefault("pressure") ?? "0.5",
                        NumberStyles.Float,
                        CultureInfo.InvariantCulture,
                        out var pressure)
                    || !double.IsFinite(pressure)
                    || pressure is < 0 or > 1)
                {
                    return Fail("--pressure must be a number between 0 and 1.");
                }
                if (!int.TryParse(
                        options.GetValueOrDefault("fleet-size") ?? "0",
                        NumberStyles.Integer,
                        CultureInfo.InvariantCulture,
                        out var fleetSize)
                    || fleetSize is < 0 or > 100_000)
                {
                    return Fail("--fleet-size must be an integer between 0 and 100000.");
                }

                var spoke = new PythonInsightsSpoke();
                var plan = await spoke.RecommendEnginesAsync(
                    cudaEnabled: cudaEnabled,
                    securityProfile: securityProfile,
                    optimizationPressure: pressure,
                    fleetSize: fleetSize,
                    includeCandidates: includeCandidates);
                if (plan is null)
                {
                    return Fail(
                        "Python engine spoke unavailable or rejected the request. "
                        + "No engine was selected, installed, or run.");
                }
                Console.WriteLine(plan.Value.GetRawText());
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
              tandem <task-type> "<prompt>" [--system S]               Run the whole chain concurrently (e.g. ChatGPT+Codex), report the learned winner
              compare "<prompt>" [--providers a,b,c]                   Fan out to several providers in parallel
              status                                                    Provider readiness (no network calls)
              providers                                                 Status as JSON
              routing                                                   Show the task-routing table
              engines [--cuda[=BOOL]] [--include-candidates[=BOOL]]      Show implemented capabilities and runtime availability
              engine-plan [--security-profile P] [--pressure 0..1]
                          [--fleet-size N] [--cuda[=BOOL]]
                          [--include-candidates[=BOOL]]
                                                                        Recommend available implementations; candidates stay advisory
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
                var option = arg[2..];
                var separator = option.IndexOf('=');
                var name = separator >= 0 ? option[..separator] : option;
                string? value = separator >= 0 ? option[(separator + 1)..] : null;
                if (separator < 0
                    && i + 1 < args.Length
                    && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
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

    private static string? FindUnexpectedOption(
        IReadOnlyDictionary<string, string?> options,
        params string[] allowed)
    {
        var allowedSet = new HashSet<string>(allowed, StringComparer.OrdinalIgnoreCase);
        return options.Keys.FirstOrDefault(key => !allowedSet.Contains(key));
    }

    private static bool TryReadFlag(
        IReadOnlyDictionary<string, string?> options,
        string name,
        out bool value,
        out string? error)
    {
        if (!options.TryGetValue(name, out var raw))
        {
            value = false;
            error = null;
            return true;
        }
        if (raw is null)
        {
            value = true;
            error = null;
            return true;
        }
        if (bool.TryParse(raw, out value))
        {
            error = null;
            return true;
        }

        error = $"--{name} accepts only true or false when a value is supplied.";
        return false;
    }
}
