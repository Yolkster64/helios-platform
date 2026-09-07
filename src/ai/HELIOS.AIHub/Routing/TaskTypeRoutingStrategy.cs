using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.Platform.Core.AI.Interfaces;
using HELIOS.Platform.Core.AI.Router;

namespace HELIOS.AIHub.Routing;

/// <summary>
/// Capability-based strategy over the config task-routing table: the request's
/// RoutingHints["taskType"] selects an ordered provider chain; the first Ready provider
/// in the chain wins. Falls back to the default chain, then to any Ready agent.
///
/// An optional RoutingHints["language"] adds a second dimension: a chain configured
/// under the key <c>"{taskType}:{language}"</c> is tried before the bare task type,
/// so <c>code_generation:fsharp</c> can order providers differently from
/// <c>code_generation</c> without touching every other language.
/// </summary>
public sealed class TaskTypeRoutingStrategy : IRoutingStrategy
{
    public const string TaskTypeHint = "taskType";

    /// <summary>Routing hint carrying the normalized language key (see <see cref="NormalizeLanguage"/>).</summary>
    public const string LanguageHint = "language";

    /// <summary>Separator between the task type and the language in a qualified routing key.</summary>
    public const char LanguageSeparator = ':';

    /// <summary>
    /// Spellings callers commonly use that map onto the canonical lower-case keys the
    /// routing table is written in. Canonical keys pass through unchanged.
    /// </summary>
    private static readonly Dictionary<string, string> LanguageAliases = new(StringComparer.Ordinal)
    {
        ["c#"] = "csharp",
        ["cs"] = "csharp",
        ["f#"] = "fsharp",
        ["fs"] = "fsharp",
        ["c++"] = "cpp",
        ["cxx"] = "cpp",
        ["cc"] = "cpp",
        ["py"] = "python",
        ["ps"] = "powershell",
        ["ps1"] = "powershell",
        ["pwsh"] = "powershell",
        ["yml"] = "yaml",
        ["ts"] = "typescript",
        ["js"] = "javascript",
        ["sh"] = "bash",
        ["shell"] = "bash",
    };

    private readonly RoutingOptions _routing;

    public TaskTypeRoutingStrategy(RoutingOptions routing)
    {
        _routing = routing;
    }

    public string StrategyName => RoutingStrategies.CapabilityBased;

    /// <summary>
    /// Canonical form of a language value: trimmed, lower-case, a leading extension dot
    /// dropped, and common aliases folded ("C#" → csharp, "F#" → fsharp, "c++" → cpp,
    /// "ps1" → powershell). Null (no language dimension) for null, empty, or blank input,
    /// so a caller that forwards an unset option gets exactly the language-less behavior.
    /// </summary>
    public static string? NormalizeLanguage(string? language)
    {
        if (string.IsNullOrWhiteSpace(language))
        {
            return null;
        }

        var normalized = language.Trim().ToLowerInvariant().TrimStart('.');
        if (normalized.Length == 0)
        {
            return null;
        }
        return LanguageAliases.TryGetValue(normalized, out var canonical) ? canonical : normalized;
    }

    /// <summary>The routing-table key for a task type qualified by a (normalized) language.</summary>
    public static string RoutingKey(string taskType, string language) =>
        string.Concat(taskType, LanguageSeparator, language);

    /// <summary>
    /// Splits a routing-table key into its task type and optional language; a key with
    /// no separator is a bare task type (language null).
    /// </summary>
    public static (string TaskType, string? Language) SplitRoutingKey(string key)
    {
        var separator = key.IndexOf(LanguageSeparator);
        return separator < 0
            ? (key, null)
            : (key[..separator], key[(separator + 1)..]);
    }

    /// <summary>
    /// The canonical (taskType, language) for a route request that carries NO language.
    /// The table's keys are public (helios_task_routing_get, /v1/routing, helios-ai
    /// routing list them verbatim), so a caller may send <c>code_generation:fsharp</c> as
    /// the task type; served as-is it would walk the qualified chain but record and learn
    /// under TaskType "code_generation:fsharp" with no language — a second evidence
    /// bucket the (taskType, language) reads never see. When the task type contains the
    /// separator, the table holds that exact key with a non-empty chain, and the language
    /// part is already canonical (so <see cref="GetChain"/> on the split resolves the very
    /// same chain), it splits into (<c>code_generation</c>, <c>fsharp</c>). Anything else
    /// — a bare task type, an unknown qualified key, a non-canonical spelling — comes
    /// back unchanged with a null language and is treated as an ordinary task type.
    /// </summary>
    public (string TaskType, string? Language) CanonicalizeTaskType(string taskType)
    {
        if (taskType.IndexOf(LanguageSeparator) < 0
            || !_routing.TaskRouting.TryGetValue(taskType, out var chain)
            || chain.Count == 0)
        {
            return (taskType, null);
        }

        var (bareTaskType, language) = SplitRoutingKey(taskType);
        return bareTaskType.Length > 0
               && language is not null
               && string.Equals(NormalizeLanguage(language), language, StringComparison.Ordinal)
            ? (bareTaskType, language)
            : (taskType, null);
    }

    public IAgent? SelectAgent(AgentRoutingRequest request, IReadOnlyList<IAgent> availableAgents) =>
        SelectAgents(request, availableAgents, maxAgents: 1).FirstOrDefault();

    public IReadOnlyList<IAgent> SelectAgents(
        AgentRoutingRequest request, IReadOnlyList<IAgent> availableAgents, int maxAgents)
    {
        var chain = ResolveChain(request);
        var byProvider = availableAgents
            .OfType<IChatProviderAgent>()
            .ToDictionary(agent => agent.Provider, StringComparer.OrdinalIgnoreCase);

        var ordered = new List<IAgent>();
        foreach (var provider in chain)
        {
            if (byProvider.TryGetValue(provider, out var agent)
                && agent.Readiness == ProviderReadiness.Ready
                && !ordered.Contains(agent))
            {
                ordered.Add(agent);
            }
        }

        // Any remaining Ready providers act as last-resort fallbacks.
        foreach (var agent in byProvider.Values)
        {
            if (agent.Readiness == ProviderReadiness.Ready && !ordered.Contains(agent))
            {
                ordered.Add(agent);
            }
        }

        return ordered.Take(Math.Max(1, maxAgents)).ToList();
    }

    /// <summary>
    /// The configured chain for a task type (used by the hub for fallback execution).
    /// Lookup order: <c>taskRouting["{taskType}:{language}"]</c> when a language is
    /// given, then <c>taskRouting[taskType]</c>, then <c>defaultChain</c>. The language
    /// is normalized here, so callers may pass it raw.
    /// </summary>
    public IReadOnlyList<string> GetChain(string? taskType, string? language = null) =>
        ResolveChain(taskType, language).Chain;

    /// <summary>
    /// The three-step lookup with the key it stopped at: the qualified key when a
    /// non-empty <c>taskType:language</c> chain is configured, else the bare task type
    /// when its chain is configured and non-empty, else null for
    /// <c>routing.defaultChain</c>. Callers that report "chain empty" name this key, not
    /// the key they asked for — an explicit language whose qualified chain does not
    /// exist resolved to the parent, and blaming <c>taskType:language</c> would send the
    /// operator to configure a chain the request never used.
    /// </summary>
    public (IReadOnlyList<string> Chain, string? ResolvedKey) ResolveChain(string? taskType, string? language = null)
    {
        if (taskType is not null)
        {
            if (NormalizeLanguage(language) is { } normalized
                && _routing.TaskRouting.TryGetValue(RoutingKey(taskType, normalized), out var qualified)
                && qualified.Count > 0)
            {
                return (qualified, RoutingKey(taskType, normalized));
            }
            if (_routing.TaskRouting.TryGetValue(taskType, out var chain) && chain.Count > 0)
            {
                return (chain, taskType);
            }
        }
        return (_routing.DefaultChain, null);
    }

    private IReadOnlyList<string> ResolveChain(AgentRoutingRequest request)
    {
        var taskType = request.RoutingHints.TryGetValue(TaskTypeHint, out var value) ? value as string : null;
        var language = request.RoutingHints.TryGetValue(LanguageHint, out var hint) ? hint as string : null;
        return GetChain(taskType, language);
    }
}
