namespace HELIOS.AIHub.Resilience;

public enum CircuitState
{
    Closed,
    Open,
    HalfOpen,
}

/// <summary>
/// Per-provider circuit breaker. After <c>failureThreshold</c> consecutive failures the
/// circuit opens for <c>openDuration</c>; the next call after the cooldown runs half-open
/// (one probe: success closes, failure re-opens).
/// </summary>
public sealed class CircuitBreaker
{
    private readonly int _failureThreshold;
    private readonly TimeSpan _openDuration;
    private readonly TimeProvider _clock;
    private readonly object _gate = new();

    private int _consecutiveFailures;
    private DateTimeOffset _openedAt;
    private CircuitState _state = CircuitState.Closed;
    private bool _probeInFlight;
    private DateTimeOffset _probeStartedAt;

    public CircuitBreaker(int failureThreshold = 5, TimeSpan? openDuration = null, TimeProvider? clock = null)
    {
        if (failureThreshold < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(failureThreshold), "Threshold must be at least 1.");
        }
        _failureThreshold = failureThreshold;
        _openDuration = openDuration ?? TimeSpan.FromSeconds(60);
        _clock = clock ?? TimeProvider.System;
    }

    public CircuitState State
    {
        get
        {
            lock (_gate)
            {
                return _state;
            }
        }
    }

    /// <summary>True when a call may proceed; transitions Open→HalfOpen after the cooldown.</summary>
    public bool CanExecute()
    {
        lock (_gate)
        {
            switch (_state)
            {
                case CircuitState.Closed:
                    return true;
                case CircuitState.HalfOpen:
                    // One probe at a time: a burst arriving after the cooldown must not
                    // stampede a provider that is still being tested. A probe that never
                    // records (caller crashed) re-arms after another openDuration.
                    if (!_probeInFlight || _clock.GetUtcNow() - _probeStartedAt >= _openDuration)
                    {
                        _probeInFlight = true;
                        _probeStartedAt = _clock.GetUtcNow();
                        return true;
                    }
                    return false;
                case CircuitState.Open:
                    if (_clock.GetUtcNow() - _openedAt >= _openDuration)
                    {
                        _state = CircuitState.HalfOpen;
                        _probeInFlight = true;
                        _probeStartedAt = _clock.GetUtcNow();
                        return true;
                    }
                    return false;
                default:
                    return false;
            }
        }
    }

    public void RecordSuccess()
    {
        lock (_gate)
        {
            _consecutiveFailures = 0;
            _state = CircuitState.Closed;
            _probeInFlight = false;
        }
    }

    public void RecordFailure()
    {
        lock (_gate)
        {
            if (_state == CircuitState.HalfOpen)
            {
                _state = CircuitState.Open;
                _openedAt = _clock.GetUtcNow();
                _probeInFlight = false;
                return;
            }

            _consecutiveFailures++;
            if (_consecutiveFailures >= _failureThreshold)
            {
                _state = CircuitState.Open;
                _openedAt = _clock.GetUtcNow();
            }
        }
    }
}
