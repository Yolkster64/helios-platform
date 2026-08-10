using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using HELIOS.Platform.Core.AI.Interfaces;

namespace HELIOS.Platform.Core.AI.Router
{
    /// <summary>
    /// High-performance routing engine for agent selection and request dispatch.
    /// Uses strategy pattern with built-in caching and metrics collection.
    /// Expected impact: -50% agent selection latency, +3x throughput
    /// </summary>
    public interface IRouter
    {
        /// <summary>
        /// Registers an agent with the router
        /// </summary>
        void RegisterAgent(IAgent agent, string[] tags = null);

        /// <summary>
        /// Unregisters an agent from the router
        /// </summary>
        void UnregisterAgent(string agentId);

        /// <summary>
        /// Routes a request to the best-matching agent
        /// </summary>
        Task<RoutingResult> RouteAsync(
            AgentRoutingRequest request,
            CancellationToken cancellationToken = default);

        /// <summary>
        /// Routes a request to agents matching criteria
        /// </summary>
        Task<RoutingResultSet> RouteToMultipleAsync(
            AgentRoutingRequest request,
            int maxAgents = 3,
            CancellationToken cancellationToken = default);

        /// <summary>
        /// Gets available agents matching criteria
        /// </summary>
        IReadOnlyList<IAgent> GetAvailableAgents(string[] tags = null);

        /// <summary>
        /// Gets router statistics
        /// </summary>
        RouterStatistics GetStatistics();

        /// <summary>
        /// Sets routing strategy
        /// </summary>
        void SetRoutingStrategy(IRoutingStrategy strategy);

        /// <summary>
        /// Gets routing strategy
        /// </summary>
        IRoutingStrategy GetRoutingStrategy();

        /// <summary>
        /// Clears the routing cache
        /// </summary>
        void ClearCache();
    }

    /// <summary>
    /// Routing strategy abstraction
    /// </summary>
    public interface IRoutingStrategy
    {
        string StrategyName { get; }

        /// <summary>
        /// Selects the best agent for the request
        /// </summary>
        IAgent SelectAgent(
            AgentRoutingRequest request,
            IReadOnlyList<IAgent> availableAgents);

        /// <summary>
        /// Selects multiple agents in priority order
        /// </summary>
        IReadOnlyList<IAgent> SelectAgents(
            AgentRoutingRequest request,
            IReadOnlyList<IAgent> availableAgents,
            int maxAgents);
    }

    /// <summary>
    /// Agent routing request
    /// </summary>
    public class AgentRoutingRequest
    {
        public string RequestId { get; set; } = Guid.NewGuid().ToString();
        public string[] RequiredTags { get; set; } = Array.Empty<string>();
        public string[] PreferredAgentTypes { get; set; } = Array.Empty<string>();
        public Dictionary<string, object> RoutingHints { get; set; } = new();
        public int TimeoutMs { get; set; } = 100;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    /// <summary>
    /// Single routing result
    /// </summary>
    public class RoutingResult
    {
        public string RequestId { get; set; }
        public IAgent SelectedAgent { get; set; }
        public double ScoreMetric { get; set; }
        public string StrategyUsed { get; set; }
        public TimeSpan RoutingLatency { get; set; }
        public bool CacheHit { get; set; }
    }

    /// <summary>
    /// Multiple agents routing result
    /// </summary>
    public class RoutingResultSet
    {
        public string RequestId { get; set; }
        public IReadOnlyList<(IAgent Agent, double Score)> SelectedAgents { get; set; }
        public string StrategyUsed { get; set; }
        public TimeSpan RoutingLatency { get; set; }
    }

    /// <summary>
    /// Router performance statistics
    /// </summary>
    public class RouterStatistics
    {
        public long TotalRoutingRequests { get; set; }
        public long CacheHits { get; set; }
        public long CacheMisses { get; set; }
        public double AverageRoutingTimeMs { get; set; }
        public double P99RoutingTimeMs { get; set; }
        public int RegisteredAgentsCount { get; set; }
        public int CacheEntriesCount { get; set; }
        public DateTime LastResetTime { get; set; }

        public double CacheHitRate =>
            (TotalRoutingRequests > 0)
                ? (double)CacheHits / TotalRoutingRequests
                : 0;
    }

    /// <summary>
    /// Built-in routing strategies
    /// </summary>
    public static class RoutingStrategies
    {
        /// <summary>
        /// Route to agent with lowest current latency
        /// </summary>
        public const string LowestLatency = "LowestLatency";

        /// <summary>
        /// Route to agent with lowest memory usage
        /// </summary>
        public const string LowestMemory = "LowestMemory";

        /// <summary>
        /// Route in round-robin fashion
        /// </summary>
        public const string RoundRobin = "RoundRobin";

        /// <summary>
        /// Route based on consistent hashing
        /// </summary>
        public const string ConsistentHash = "ConsistentHash";

        /// <summary>
        /// Route to healthiest agent
        /// </summary>
        public const string HealthAware = "HealthAware";

        /// <summary>
        /// Route based on capability matching
        /// </summary>
        public const string CapabilityBased = "CapabilityBased";
    }
}
