using System.Diagnostics;
using HELIOS.Platform.Core.AI.Interfaces;
using HELIOS.Platform.Core.AI.Router;

namespace HELIOS.AIHub.Routing;

/// <summary>
/// First real implementation of the core IRouter seam. Thread-safe registry + strategy
/// dispatch + statistics. No routing cache in v1 — ClearCache is a no-op.
/// </summary>
public sealed class AgentRouter : IRouter
{
    private readonly object _gate = new();
    private readonly Dictionary<string, (IAgent Agent, string[] Tags)> _agents = new(StringComparer.OrdinalIgnoreCase);
    private IRoutingStrategy _strategy;
    private long _totalRequests;
    private double _totalRoutingMs;
    private readonly DateTime _startedAt = DateTime.UtcNow;

    public AgentRouter(IRoutingStrategy strategy)
    {
        _strategy = strategy;
    }

    public void RegisterAgent(IAgent agent, string[]? tags = null)
    {
        lock (_gate)
        {
            _agents[agent.AgentId] = (agent, tags ?? Array.Empty<string>());
        }
    }

    public void UnregisterAgent(string agentId)
    {
        lock (_gate)
        {
            _agents.Remove(agentId);
        }
    }

    public Task<RoutingResult> RouteAsync(AgentRoutingRequest request, CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        var available = GetAvailableAgents(request.RequiredTags);
        var selected = _strategy.SelectAgent(request, available);
        RecordRouting(stopwatch.Elapsed);
        return Task.FromResult(new RoutingResult
        {
            RequestId = request.RequestId,
            SelectedAgent = selected,
            ScoreMetric = selected is null ? 0 : 1,
            StrategyUsed = _strategy.StrategyName,
            RoutingLatency = stopwatch.Elapsed,
            CacheHit = false,
        });
    }

    public Task<RoutingResultSet> RouteToMultipleAsync(
        AgentRoutingRequest request, int maxAgents = 3, CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        var available = GetAvailableAgents(request.RequiredTags);
        var selected = _strategy.SelectAgents(request, available, maxAgents);
        RecordRouting(stopwatch.Elapsed);
        return Task.FromResult(new RoutingResultSet
        {
            RequestId = request.RequestId,
            SelectedAgents = selected.Select((agent, i) => (agent, (double)(selected.Count - i))).ToList(),
            StrategyUsed = _strategy.StrategyName,
            RoutingLatency = stopwatch.Elapsed,
        });
    }

    public IReadOnlyList<IAgent> GetAvailableAgents(string[]? tags = null)
    {
        lock (_gate)
        {
            IEnumerable<(IAgent Agent, string[] Tags)> candidates = _agents.Values;
            if (tags is { Length: > 0 })
            {
                candidates = candidates.Where(entry =>
                    tags.All(tag => entry.Tags.Contains(tag, StringComparer.OrdinalIgnoreCase)));
            }
            return candidates.Select(entry => entry.Agent).ToList();
        }
    }

    public RouterStatistics GetStatistics()
    {
        lock (_gate)
        {
            return new RouterStatistics
            {
                TotalRoutingRequests = _totalRequests,
                CacheHits = 0,
                CacheMisses = _totalRequests,
                AverageRoutingTimeMs = _totalRequests > 0 ? _totalRoutingMs / _totalRequests : 0,
                RegisteredAgentsCount = _agents.Count,
                CacheEntriesCount = 0,
                LastResetTime = _startedAt,
            };
        }
    }

    public void SetRoutingStrategy(IRoutingStrategy strategy)
    {
        lock (_gate)
        {
            _strategy = strategy;
        }
    }

    public IRoutingStrategy GetRoutingStrategy()
    {
        lock (_gate)
        {
            return _strategy;
        }
    }

    public void ClearCache()
    {
        // No routing cache in v1.
    }

    private void RecordRouting(TimeSpan elapsed)
    {
        lock (_gate)
        {
            _totalRequests++;
            _totalRoutingMs += elapsed.TotalMilliseconds;
        }
    }
}
