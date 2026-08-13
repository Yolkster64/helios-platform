using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace HELIOS.Platform.Core.AI.Interfaces
{
    /// <summary>
    /// Unified agent interface consolidating all agent-related contracts.
    /// Replaces scattered IAgent*, IOptimizer*, etc. interfaces.
    /// Design: Composition-based with optional capability extensions.
    /// Expected impact: -40% interface bloat, easier mocking, clearer contracts
    /// </summary>
    public interface IAgent
    {
        /// <summary>
        /// Unique identifier for this agent instance
        /// </summary>
        string AgentId { get; }

        /// <summary>
        /// Agent display name
        /// </summary>
        string Name { get; }

        /// <summary>
        /// Agent type classification (Coordinator, Optimizer, Predictor, etc.)
        /// </summary>
        AgentType AgentType { get; }

        /// <summary>
        /// Current agent status
        /// </summary>
        AgentStatus Status { get; }

        /// <summary>
        /// Initializes the agent asynchronously
        /// </summary>
        Task InitializeAsync(CancellationToken cancellationToken = default);

        /// <summary>
        /// Starts the agent operation
        /// </summary>
        Task StartAsync(CancellationToken cancellationToken = default);

        /// <summary>
        /// Stops the agent operation
        /// </summary>
        Task StopAsync(CancellationToken cancellationToken = default);

        /// <summary>
        /// Executes agent logic with input and returns output
        /// </summary>
        Task<AgentResult> ExecuteAsync(
            AgentRequest request,
            CancellationToken cancellationToken = default);

        /// <summary>
        /// Gets capabilities of this agent
        /// </summary>
        IReadOnlyList<ICapability> GetCapabilities();

        /// <summary>
        /// Checks if agent has specific capability
        /// </summary>
        bool HasCapability(string capabilityName);

        /// <summary>
        /// Gets agent metrics
        /// </summary>
        AgentMetrics GetMetrics();

        /// <summary>
        /// Health check - returns true if agent is healthy
        /// </summary>
        Task<bool> HealthCheckAsync(CancellationToken cancellationToken = default);
    }

    /// <summary>
    /// Agent capability abstraction for composition
    /// </summary>
    public interface ICapability
    {
        string CapabilityName { get; }
        string Description { get; }
        Version Version { get; }
        Task InitializeAsync();
    }

    /// <summary>
    /// Request object for agent execution
    /// </summary>
    public class AgentRequest
    {
        public string RequestId { get; set; } = Guid.NewGuid().ToString();
        public string Operation { get; set; } = string.Empty;
        public Dictionary<string, object> Parameters { get; set; } = new();
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(30);
    }

    /// <summary>
    /// Result object from agent execution
    /// </summary>
    public class AgentResult
    {
        public string RequestId { get; set; } = string.Empty;
        public bool Success { get; set; }
        public object? ResultData { get; set; }
        public string? ErrorMessage { get; set; }
        public TimeSpan ExecutionTime { get; set; }
        public DateTime CompletedAt { get; set; } = DateTime.UtcNow;
    }

    /// <summary>
    /// Agent type classification
    /// </summary>
    public enum AgentType
    {
        Unknown = 0,
        Coordinator = 1,
        Optimizer = 2,
        Predictor = 3,
        Monitor = 4,
        Executor = 5,
        Analyzer = 6,
        Orchestrator = 7
    }

    /// <summary>
    /// Agent operational status
    /// </summary>
    public enum AgentStatus
    {
        Uninitialized,
        Initializing,
        Ready,
        Running,
        Paused,
        Stopping,
        Stopped,
        Failed,
        Unhealthy
    }

    /// <summary>
    /// Agent performance metrics
    /// </summary>
    public class AgentMetrics
    {
        public long TotalRequestsProcessed { get; set; }
        public long SuccessfulRequests { get; set; }
        public long FailedRequests { get; set; }
        public double AverageExecutionTimeMs { get; set; }
        public double P99ExecutionTimeMs { get; set; }
        public long PeakMemoryMb { get; set; }
        public DateTime LastHealthCheckTime { get; set; }
        public bool IsHealthy { get; set; }

        public double SuccessRate =>
            TotalRequestsProcessed > 0
                ? (double)SuccessfulRequests / TotalRequestsProcessed
                : 0;
    }
}
