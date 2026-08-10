using System.Collections.Concurrent;

namespace HELIOS.AIHub.Resilience;

/// <summary>Thrown when every provider in a fallback chain failed or was skipped.</summary>
public sealed class FallbackChainExhaustedException : Exception
{
    public FallbackChainExhaustedException(IReadOnlyDictionary<string, string> failures)
        : base($"All providers in the chain failed: {string.Join("; ", failures.Select(kv => $"{kv.Key}: {kv.Value}"))}")
    {
        Failures = failures;
    }

    /// <summary>Provider name → failure reason, in chain order.</summary>
    public IReadOnlyDictionary<string, string> Failures { get; }
}

/// <summary>
/// Provider fallback chain with per-provider circuit breakers.
///
/// Ported from cloud-integration/fallbacks/FallbackChain.cs with its core bug fixed: the
/// original re-invoked the same delegate for every fallback service, so it never actually
/// switched provider. Here the operation is parameterized by provider name.
/// </summary>
public sealed class FallbackChain
{
    private readonly ConcurrentDictionary<string, CircuitBreaker> _breakers = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, long> _failovers = new(StringComparer.OrdinalIgnoreCase);
    private readonly Func<CircuitBreaker> _breakerFactory;

    public FallbackChain(Func<CircuitBreaker>? breakerFactory = null)
    {
        _breakerFactory = breakerFactory ?? (static () => new CircuitBreaker());
    }

    /// <summary>Circuit state for a provider (Closed when the provider was never used).</summary>
    public CircuitState GetState(string provider) =>
        _breakers.TryGetValue(provider, out var breaker) ? breaker.State : CircuitState.Closed;

    /// <summary>Times each provider was skipped or failed over, for status reporting.</summary>
    public IReadOnlyDictionary<string, long> FailoverCounts => _failovers;

    /// <param name="providerChain">Ordered provider names: first is primary, the rest are fallbacks.</param>
    /// <param name="operationForProvider">The operation, parameterized by the provider to run against.</param>
    /// <param name="isSuccess">Optional predicate marking a returned value as a soft failure that should fall through.</param>
    public async Task<T> ExecuteAsync<T>(
        IReadOnlyList<string> providerChain,
        Func<string, Task<T>> operationForProvider,
        Func<T, bool>? isSuccess = null,
        CancellationToken cancellationToken = default)
    {
        if (providerChain.Count == 0)
        {
            throw new ArgumentException("Provider chain must not be empty.", nameof(providerChain));
        }

        var failures = new Dictionary<string, string>();
        foreach (var provider in providerChain)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var breaker = _breakers.GetOrAdd(provider, _ => _breakerFactory());
            if (!breaker.CanExecute())
            {
                failures[provider] = "circuit open";
                _failovers.AddOrUpdate(provider, 1, static (_, n) => n + 1);
                continue;
            }

            try
            {
                var result = await operationForProvider(provider).ConfigureAwait(false);
                if (isSuccess is null || isSuccess(result))
                {
                    breaker.RecordSuccess();
                    return result;
                }

                breaker.RecordFailure();
                failures[provider] = "provider reported failure";
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                breaker.RecordFailure();
                failures[provider] = ex.Message;
            }

            _failovers.AddOrUpdate(provider, 1, static (_, n) => n + 1);
        }

        throw new FallbackChainExhaustedException(failures);
    }
}
