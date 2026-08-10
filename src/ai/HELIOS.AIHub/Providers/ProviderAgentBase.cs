using System.Diagnostics;
using HELIOS.AIHub.Abstractions;
using HELIOS.Platform.Core.AI.Interfaces;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// Shared IAgent plumbing for every provider kind: status transitions, metrics,
/// capabilities, and the AgentRequest → ChatRequest mapping.
/// </summary>
public abstract class ProviderAgentBase : IChatProviderAgent
{
    private readonly object _metricsGate = new();
    private long _totalRequests;
    private long _successfulRequests;
    private long _failedRequests;
    private double _totalExecutionMs;
    private DateTime _lastHealthCheck = DateTime.UtcNow;

    protected ProviderAgentBase(string provider, string displayName, string? defaultModel)
    {
        Provider = provider;
        Name = displayName;
        DefaultModel = defaultModel;
        AgentId = $"aihub-{provider}";
    }

    public string AgentId { get; }

    public string Name { get; }

    public AgentType AgentType => AgentType.Executor;

    public AgentStatus Status { get; protected set; } = AgentStatus.Uninitialized;

    public string Provider { get; }

    public string? DefaultModel { get; }

    public abstract ProviderReadiness Readiness { get; }

    /// <summary>Short human-readable hint shown when the provider is unconfigured.</summary>
    public abstract string? ConfigurationHint { get; }

    public virtual Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        Status = AgentStatus.Ready;
        return Task.CompletedTask;
    }

    public virtual Task StartAsync(CancellationToken cancellationToken = default)
    {
        Status = AgentStatus.Running;
        return Task.CompletedTask;
    }

    public virtual Task StopAsync(CancellationToken cancellationToken = default)
    {
        Status = AgentStatus.Stopped;
        return Task.CompletedTask;
    }

    public async Task<AgentResult> ExecuteAsync(AgentRequest request, CancellationToken cancellationToken = default)
    {
        var chatRequest = new ChatRequest(
            Prompt: GetParameter<string>(request, "prompt") ?? string.Empty,
            System: GetParameter<string>(request, "system"),
            Model: GetParameter<string>(request, "model"),
            TaskType: GetParameter<string>(request, "taskType"),
            MaxTokens: GetParameter<int?>(request, "maxTokens"),
            Temperature: GetParameter<double?>(request, "temperature"));

        var result = await ChatAsync(chatRequest, cancellationToken).ConfigureAwait(false);
        return new AgentResult
        {
            RequestId = request.RequestId,
            Success = result.Success,
            ResultData = result,
            ErrorMessage = result.Error,
            ExecutionTime = result.Latency,
        };
    }

    public async Task<ChatResult> ChatAsync(ChatRequest request, CancellationToken cancellationToken = default)
    {
        var model = request.Model ?? DefaultModel ?? string.Empty;
        if (Readiness == ProviderReadiness.Unconfigured)
        {
            return new ChatResult(false, null, Provider, model, TimeSpan.Zero,
                Error: ConfigurationHint ?? $"Provider '{Provider}' is not configured.");
        }

        var stopwatch = Stopwatch.StartNew();
        try
        {
            var result = await ChatCoreAsync(request, cancellationToken).ConfigureAwait(false);
            RecordExecution(result.Success, stopwatch.Elapsed);
            return result;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // Provider boundary: any SDK/transport failure becomes a failed ChatResult so
            // the fallback chain can move on to the next provider.
            RecordExecution(success: false, stopwatch.Elapsed);
            return new ChatResult(false, null, Provider, model, stopwatch.Elapsed, Error: ex.Message);
        }
    }

    protected abstract Task<ChatResult> ChatCoreAsync(ChatRequest request, CancellationToken cancellationToken);

    public IReadOnlyList<ICapability> GetCapabilities() =>
        new ICapability[] { new ChatCapability(Provider) };

    public bool HasCapability(string capabilityName) =>
        string.Equals(capabilityName, ChatCapability.CapabilityKey, StringComparison.OrdinalIgnoreCase);

    public AgentMetrics GetMetrics()
    {
        lock (_metricsGate)
        {
            return new AgentMetrics
            {
                TotalRequestsProcessed = _totalRequests,
                SuccessfulRequests = _successfulRequests,
                FailedRequests = _failedRequests,
                AverageExecutionTimeMs = _totalRequests > 0 ? _totalExecutionMs / _totalRequests : 0,
                LastHealthCheckTime = _lastHealthCheck,
                IsHealthy = Readiness == ProviderReadiness.Ready,
            };
        }
    }

    public virtual Task<bool> HealthCheckAsync(CancellationToken cancellationToken = default)
    {
        lock (_metricsGate)
        {
            _lastHealthCheck = DateTime.UtcNow;
        }
        return Task.FromResult(Readiness == ProviderReadiness.Ready);
    }

    private void RecordExecution(bool success, TimeSpan elapsed)
    {
        lock (_metricsGate)
        {
            _totalRequests++;
            if (success)
            {
                _successfulRequests++;
            }
            else
            {
                _failedRequests++;
            }
            _totalExecutionMs += elapsed.TotalMilliseconds;
        }
    }

    private static T? GetParameter<T>(AgentRequest request, string key)
    {
        if (request.Parameters is not null && request.Parameters.TryGetValue(key, out var value) && value is T typed)
        {
            return typed;
        }
        return default;
    }

    private sealed class ChatCapability : ICapability
    {
        public const string CapabilityKey = "chat";

        private readonly string _provider;

        public ChatCapability(string provider) => _provider = provider;

        public string CapabilityName => CapabilityKey;

        public string Description => $"Chat completion via the '{_provider}' provider.";

        public Version Version => new(1, 0);

        public Task InitializeAsync() => Task.CompletedTask;
    }
}
