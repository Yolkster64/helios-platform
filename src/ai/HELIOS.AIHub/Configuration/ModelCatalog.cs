using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub.Domain;

namespace HELIOS.AIHub.Configuration;

/// <summary>Published capability/cost/speed profile for one provider/model (config/model-catalog.json).</summary>
public sealed class ModelProfile
{
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = "";

    [JsonPropertyName("model")]
    public string Model { get; set; } = "";

    /// <summary>frontier | balanced | specialist | fast | local.</summary>
    [JsonPropertyName("class")]
    public string Class { get; set; } = "fast";

    [JsonPropertyName("contextTokens")]
    public int ContextTokens { get; set; }

    [JsonPropertyName("inputPerMillionUsd")]
    public double InputPerMillionUsd { get; set; }

    [JsonPropertyName("outputPerMillionUsd")]
    public double OutputPerMillionUsd { get; set; }

    /// <summary>fast | medium | slow | hardware-bound.</summary>
    [JsonPropertyName("relativeSpeed")]
    public string RelativeSpeed { get; set; } = "medium";

    [JsonPropertyName("strengths")]
    public List<string> Strengths { get; set; } = new();
}

public sealed class ModelCatalogFile
{
    [JsonPropertyName("models")]
    public List<ModelProfile> Models { get; set; } = new();
}

/// <summary>
/// Loads config/model-catalog.json and answers "which provider is best for this task
/// under this preference?" via the F# ModelSelection module. Optional: callers that never
/// set a preference never touch this — the config/aihub.json routing chain still governs.
/// </summary>
public sealed class ModelCatalog
{
    private readonly IReadOnlyList<ModelProfile> _models;

    public ModelCatalog(IReadOnlyList<ModelProfile> models)
    {
        _models = models;
    }

    public static ModelCatalog? TryLoad(string? path = null)
    {
        path ??= FindCatalogFile();
        if (path is null || !File.Exists(path))
        {
            return null;
        }
        using var stream = File.OpenRead(path);
        var file = JsonSerializer.Deserialize<ModelCatalogFile>(stream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        return file is null ? null : new ModelCatalog(file.Models);
    }

    private static string? FindCatalogFile()
    {
        var configPath = AIHubOptions.FindConfigFile();
        if (configPath is null)
        {
            return null;
        }
        var candidate = Path.Combine(Path.GetDirectoryName(configPath)!, "model-catalog.json");
        return File.Exists(candidate) ? candidate : null;
    }

    /// <summary>
    /// Best provider key for a task under "cost" | "latency" | "quality" | "balanced".
    /// Returns null when the catalog has no entry for the task type — callers should fall
    /// back to the configured routing chain rather than guess.
    /// </summary>
    public string? SelectProvider(string taskType, string preference)
    {
        if (_models.Count == 0)
        {
            return null;
        }

        var result = ModelSelectionInterop.SelectBestProvider(
            taskType,
            preference,
            _models.Select(m => m.Provider).ToArray(),
            _models.Select(m => m.Model).ToArray(),
            _models.Select(m => m.Class).ToArray(),
            _models.Select(m => m.ContextTokens).ToArray(),
            _models.Select(m => m.InputPerMillionUsd).ToArray(),
            _models.Select(m => m.OutputPerMillionUsd).ToArray(),
            _models.Select(m => m.RelativeSpeed).ToArray(),
            _models.Select(m => string.Join(',', m.Strengths)).ToArray());

        return string.IsNullOrEmpty(result) ? null : result;
    }

    /// <summary>
    /// Best provider/model pair for a task — the model belongs to the profile that won
    /// the ranking, so the caller can send the request to the model that was actually
    /// scored rather than the provider's configured default. When
    /// <paramref name="allowedProviders"/> is given, only those providers' profiles
    /// compete — the ranking must not be won by a provider the caller cannot use.
    /// </summary>
    public (string Provider, string Model)? SelectProfile(
        string taskType, string preference, IReadOnlySet<string>? allowedProviders = null)
    {
        var models = allowedProviders is null
            ? _models
            : _models.Where(m => allowedProviders.Contains(m.Provider)).ToList();
        if (models.Count == 0)
        {
            return null;
        }

        var result = ModelSelectionInterop.SelectBestProfile(
            taskType,
            preference,
            models.Select(m => m.Provider).ToArray(),
            models.Select(m => m.Model).ToArray(),
            models.Select(m => m.Class).ToArray(),
            models.Select(m => m.ContextTokens).ToArray(),
            models.Select(m => m.InputPerMillionUsd).ToArray(),
            models.Select(m => m.OutputPerMillionUsd).ToArray(),
            models.Select(m => m.RelativeSpeed).ToArray(),
            models.Select(m => string.Join(',', m.Strengths)).ToArray());

        return result is [var provider, var model] ? (provider, model) : null;
    }

    public IReadOnlyList<ModelProfile> AllModels => _models;
}
