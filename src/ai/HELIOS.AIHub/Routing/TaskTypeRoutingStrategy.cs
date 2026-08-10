using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.Platform.Core.AI.Interfaces;
using HELIOS.Platform.Core.AI.Router;

namespace HELIOS.AIHub.Routing;

/// <summary>
/// Capability-based strategy over the config task-routing table: the request's
/// RoutingHints["taskType"] selects an ordered provider chain; the first Ready provider
/// in the chain wins. Falls back to the default chain, then to any Ready agent.
/// </summary>
public sealed class TaskTypeRoutingStrategy : IRoutingStrategy
{
    public const string TaskTypeHint = "taskType";

    private readonly RoutingOptions _routing;

    public TaskTypeRoutingStrategy(RoutingOptions routing)
    {
        _routing = routing;
    }

    public string StrategyName => RoutingStrategies.CapabilityBased;

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

    /// <summary>The configured chain for a task type (used by the hub for fallback execution).</summary>
    public IReadOnlyList<string> GetChain(string? taskType)
    {
        if (taskType is not null && _routing.TaskRouting.TryGetValue(taskType, out var chain) && chain.Count > 0)
        {
            return chain;
        }
        return _routing.DefaultChain;
    }

    private IReadOnlyList<string> ResolveChain(AgentRoutingRequest request)
    {
        var taskType = request.RoutingHints.TryGetValue(TaskTypeHint, out var value) ? value as string : null;
        return GetChain(taskType);
    }
}
