using HELIOS.AIHub.Resilience;
using Xunit;

namespace HELIOS.AIHub.Tests.Resilience;

public class FallbackChainTests
{
    [Fact]
    public async Task ExecuteAsync_SwitchesProvider_WhenPrimaryFails()
    {
        // Regression for the cloud-integration bug: the original chain re-invoked the same
        // delegate for every fallback, so the provider never actually changed.
        var chain = new FallbackChain();
        var invoked = new List<string>();

        var result = await chain.ExecuteAsync<string>(
            new[] { "primary", "secondary", "tertiary" },
            provider =>
            {
                invoked.Add(provider);
                return provider == "secondary"
                    ? Task.FromResult("ok-from-secondary")
                    : Task.FromException<string>(new InvalidOperationException($"{provider} down"));
            });

        Assert.Equal("ok-from-secondary", result);
        Assert.Equal(new[] { "primary", "secondary" }, invoked);
    }

    [Fact]
    public async Task ExecuteAsync_TreatsSoftFailure_AsFallthrough()
    {
        var chain = new FallbackChain();

        var result = await chain.ExecuteAsync(
            new[] { "a", "b" },
            provider => Task.FromResult(provider == "a" ? "bad" : "good"),
            isSuccess: value => value == "good");

        Assert.Equal("good", result);
    }

    [Fact]
    public async Task ExecuteAsync_Throws_WithPerProviderReasons_WhenAllFail()
    {
        var chain = new FallbackChain();

        var ex = await Assert.ThrowsAsync<FallbackChainExhaustedException>(() =>
            chain.ExecuteAsync<string>(
                new[] { "a", "b" },
                provider => Task.FromException<string>(new InvalidOperationException($"{provider} exploded"))));

        Assert.Equal(2, ex.Failures.Count);
        Assert.Contains("a exploded", ex.Failures["a"]);
        Assert.Contains("b exploded", ex.Failures["b"]);
    }

    [Fact]
    public async Task ExecuteAsync_CarriesSoftFailureReasons_IntoExhaustedSummary()
    {
        // An exhausted chain must show the real causes — the codex timeout, the
        // "Set OPENAI_API_KEY" hint — not a generic placeholder per provider.
        var chain = new FallbackChain();
        var reasons = new Dictionary<string, string?>
        {
            ["codex"] = "'codex' timed out after 600s.",
            ["openai"] = "Set OPENAI_API_KEY (or configure the Key Vault secret 'openai-api-key').",
            ["mute"] = null,
        };

        var ex = await Assert.ThrowsAsync<FallbackChainExhaustedException>(() =>
            chain.ExecuteAsync(
                new[] { "codex", "openai", "mute" },
                provider => Task.FromResult((Success: false, Error: reasons[provider])),
                isSuccess: r => r.Success,
                describeFailure: r => r.Error));

        Assert.Equal("'codex' timed out after 600s.", ex.Failures["codex"]);
        Assert.Contains("Set OPENAI_API_KEY", ex.Failures["openai"]);
        Assert.Equal("provider reported failure", ex.Failures["mute"]);
        Assert.Contains("codex: 'codex' timed out after 600s.", ex.Message);
        Assert.Contains("openai: Set OPENAI_API_KEY", ex.Message);
    }

    [Fact]
    public async Task ExecuteAsync_WithoutDescribeFailure_KeepsPlaceholderReason()
    {
        var chain = new FallbackChain();

        var ex = await Assert.ThrowsAsync<FallbackChainExhaustedException>(() =>
            chain.ExecuteAsync(new[] { "a" }, _ => Task.FromResult("bad"), isSuccess: v => v == "good"));

        Assert.Equal("provider reported failure", ex.Failures["a"]);
    }

    [Fact]
    public void SummarizeReason_IsSingleLine_AndBounded()
    {
        var multiLine = "line one\r\n  line two  \n\nline three";
        Assert.Equal("line one line two line three", FallbackChain.SummarizeReason(multiLine));

        var longReason = new string('x', FallbackChain.MaxFailureReasonLength + 50);
        var summary = FallbackChain.SummarizeReason(longReason);
        Assert.Equal(FallbackChain.MaxFailureReasonLength, summary.Length);
        Assert.EndsWith("…", summary);

        Assert.Equal("provider reported failure", FallbackChain.SummarizeReason("   "));
        Assert.Equal("provider reported failure", FallbackChain.SummarizeReason(null));
    }

    [Fact]
    public async Task ExecuteAsync_SkipsProvider_WhenCircuitOpen()
    {
        var chain = new FallbackChain(() => new CircuitBreaker(failureThreshold: 1));

        // First call trips "a"'s breaker (threshold 1) and succeeds on "b".
        var first = await chain.ExecuteAsync(
            new[] { "a", "b" },
            p => p == "a" ? Task.FromException<string>(new InvalidOperationException("down")) : Task.FromResult("ok"));
        Assert.Equal("ok", first);
        Assert.Equal(CircuitState.Open, chain.GetState("a"));

        // Second call must not touch "a" at all.
        var invoked = new List<string>();
        await chain.ExecuteAsync(
            new[] { "a", "b" },
            p =>
            {
                invoked.Add(p);
                return Task.FromResult("ok");
            });
        Assert.Equal(new[] { "b" }, invoked);
    }

    [Fact]
    public async Task ExecuteAsync_Throws_OnEmptyChain()
    {
        var chain = new FallbackChain();
        await Assert.ThrowsAsync<ArgumentException>(() =>
            chain.ExecuteAsync(Array.Empty<string>(), _ => Task.FromResult("x")));
    }
}
