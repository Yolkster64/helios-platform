using System.Text.Json;
using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Configuration;

/// <summary>
/// Root options bound from config/aihub.json. The file carries no secrets — only the
/// names of environment variables (or Key Vault secret names) that hold them.
/// </summary>
public sealed class AIHubOptions
{
    [JsonPropertyName("providers")]
    public Dictionary<string, ProviderOptions> Providers { get; set; } = new();

    [JsonPropertyName("cliAgents")]
    public List<CliAgentOptions> CliAgents { get; set; } = new();

    [JsonPropertyName("routing")]
    public RoutingOptions Routing { get; set; } = new();

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    public static AIHubOptions Load(string path)
    {
        using var stream = File.OpenRead(path);
        return JsonSerializer.Deserialize<AIHubOptions>(stream, SerializerOptions)
               ?? throw new InvalidDataException($"'{path}' deserialized to null.");
    }

    /// <summary>
    /// Finds config/aihub.json walking up from <paramref name="startDirectory"/> (or the
    /// current directory), so the CLI works from any subdirectory of the repo.
    /// </summary>
    public static string? FindConfigFile(string? startDirectory = null)
    {
        var dir = new DirectoryInfo(startDirectory ?? Directory.GetCurrentDirectory());
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "config", "aihub.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }
            dir = dir.Parent;
        }
        return null;
    }
}

/// <summary>One API-backed provider entry.</summary>
public sealed class ProviderOptions
{
    /// <summary>Provider kind: openai | azure-openai | anthropic | github-models | ollama | azure-foundry-agent.</summary>
    [JsonPropertyName("type")]
    public string Type { get; set; } = "";

    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; } = true;

    /// <summary>Default model (or Azure OpenAI deployment name) for this provider.</summary>
    [JsonPropertyName("model")]
    public string? Model { get; set; }

    /// <summary>Environment variable holding the API key.</summary>
    [JsonPropertyName("apiKeyEnv")]
    public string? ApiKeyEnv { get; set; }

    /// <summary>Key Vault secret name fallback when the environment variable is unset.</summary>
    [JsonPropertyName("apiKeySecretName")]
    public string? ApiKeySecretName { get; set; }

    /// <summary>Environment variable holding the endpoint (azure-openai, azure-foundry-agent, ollama).</summary>
    [JsonPropertyName("endpointEnv")]
    public string? EndpointEnv { get; set; }

    /// <summary>Fixed base URL (github-models default endpoint, ollama default).</summary>
    [JsonPropertyName("baseUrl")]
    public string? BaseUrl { get; set; }
}

/// <summary>One external CLI agent (claude, codex, copilot, gh models, hermes).</summary>
public sealed class CliAgentOptions
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; } = true;

    /// <summary>Executable name resolved via PATH.</summary>
    [JsonPropertyName("command")]
    public string Command { get; set; } = "";

    /// <summary>
    /// Argument template; {prompt} and {model} are substituted. The prompt is passed as a
    /// single argv element — never through a shell — so no quoting/injection issues.
    /// </summary>
    [JsonPropertyName("argsTemplate")]
    public string ArgsTemplate { get; set; } = "";

    [JsonPropertyName("model")]
    public string? Model { get; set; }

    [JsonPropertyName("timeoutSeconds")]
    public int TimeoutSeconds { get; set; } = 300;
}

/// <summary>Task-type → provider-chain routing table.</summary>
public sealed class RoutingOptions
{
    /// <summary>Chain used when no task type matches.</summary>
    [JsonPropertyName("defaultChain")]
    public List<string> DefaultChain { get; set; } = new();

    /// <summary>Task type → ordered provider chain (first = primary, rest = fallbacks).</summary>
    [JsonPropertyName("taskRouting")]
    public Dictionary<string, List<string>> TaskRouting { get; set; } = new();
}
