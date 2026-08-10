using HELIOS.AIHub.Resilience;
using Xunit;

namespace HELIOS.AIHub.Tests.Resilience;

public class CircuitBreakerTests
{
    private sealed class FakeClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.UnixEpoch;

        public override DateTimeOffset GetUtcNow() => Now;
    }

    [Fact]
    public void OpensAfterThreshold_AndBlocksUntilCooldown()
    {
        var clock = new FakeClock();
        var breaker = new CircuitBreaker(failureThreshold: 3, openDuration: TimeSpan.FromSeconds(60), clock);

        for (var i = 0; i < 3; i++)
        {
            Assert.True(breaker.CanExecute());
            breaker.RecordFailure();
        }

        Assert.Equal(CircuitState.Open, breaker.State);
        Assert.False(breaker.CanExecute());

        clock.Now += TimeSpan.FromSeconds(61);
        Assert.True(breaker.CanExecute());
        Assert.Equal(CircuitState.HalfOpen, breaker.State);
    }

    [Fact]
    public void HalfOpenProbe_SuccessCloses_FailureReopens()
    {
        var clock = new FakeClock();
        var breaker = new CircuitBreaker(failureThreshold: 1, openDuration: TimeSpan.FromSeconds(10), clock);

        breaker.RecordFailure();
        Assert.Equal(CircuitState.Open, breaker.State);

        clock.Now += TimeSpan.FromSeconds(11);
        Assert.True(breaker.CanExecute());
        breaker.RecordFailure();
        Assert.Equal(CircuitState.Open, breaker.State);
        Assert.False(breaker.CanExecute());

        clock.Now += TimeSpan.FromSeconds(11);
        Assert.True(breaker.CanExecute());
        breaker.RecordSuccess();
        Assert.Equal(CircuitState.Closed, breaker.State);
        Assert.True(breaker.CanExecute());
    }

    [Fact]
    public void HalfOpen_AdmitsOnlyOneProbe_UntilItRecords()
    {
        var clock = new FakeClock();
        var breaker = new CircuitBreaker(failureThreshold: 1, openDuration: TimeSpan.FromSeconds(10), clock);

        breaker.RecordFailure();
        clock.Now += TimeSpan.FromSeconds(11);

        Assert.True(breaker.CanExecute());   // the single probe
        Assert.False(breaker.CanExecute());  // concurrent burst is rejected
        Assert.False(breaker.CanExecute());

        breaker.RecordSuccess();
        Assert.Equal(CircuitState.Closed, breaker.State);
        Assert.True(breaker.CanExecute());
    }

    [Fact]
    public void HalfOpen_ProbeThatNeverRecords_RearmsAfterCooldown()
    {
        var clock = new FakeClock();
        var breaker = new CircuitBreaker(failureThreshold: 1, openDuration: TimeSpan.FromSeconds(10), clock);

        breaker.RecordFailure();
        clock.Now += TimeSpan.FromSeconds(11);
        Assert.True(breaker.CanExecute());   // probe taken, caller dies without recording
        Assert.False(breaker.CanExecute());

        clock.Now += TimeSpan.FromSeconds(11);
        Assert.True(breaker.CanExecute());   // a stuck probe must not wedge the circuit
    }

    [Fact]
    public void SuccessResetsConsecutiveFailureCount()
    {
        var breaker = new CircuitBreaker(failureThreshold: 2);
        breaker.RecordFailure();
        breaker.RecordSuccess();
        breaker.RecordFailure();
        Assert.Equal(CircuitState.Closed, breaker.State);
    }
}
