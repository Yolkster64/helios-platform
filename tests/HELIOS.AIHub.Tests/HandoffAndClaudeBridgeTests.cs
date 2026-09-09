using System.Diagnostics;
using HELIOS.Mcp;
using HELIOS.RemoteMcp;
using ModelContextProtocol;
using Xunit;

namespace HELIOS.AIHub.Tests;

public sealed class HandoffAndClaudeBridgeTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("helios-handoff-test-").FullName;
    private static readonly string CorrelationId = "11111111-2222-3333-4444-555555555555";
    public HandoffAndClaudeBridgeTests() => File.WriteAllText(Path.Combine(_root, "AGENTS.md"), "test contract");

    [Fact]
    public void HandoffReceiptPersistsAndRetriesDoNotRewriteIt()
    {
        var store = new HeliosHandoffStore(_root);
        var id = Guid.NewGuid().ToString();
        var first = store.Submit(id, CorrelationId, "chatgpt", "Claude has a review ready.", new string('a', 40));
        var afterRestart = new HeliosHandoffStore(_root);
        Assert.Equal(first, afterRestart.Fetch(id));
        Assert.Equal(first, afterRestart.Submit(id, CorrelationId, "chatgpt", "Claude has a review ready.", new string('a', 40)));
        Assert.Contains(id, afterRestart.List("chatgpt"));
        Assert.DoesNotContain(id, afterRestart.List("claude"));
        Assert.Contains("recipient must retrieve", first.Delivery);
        Assert.Throws<McpException>(() => store.Submit(id, CorrelationId, "chatgpt", "Different content."));
        Assert.Equal(first, afterRestart.Fetch(id));
    }

    [Theory]
    [InlineData("chatgpt")]
    [InlineData("claude")]
    [InlineData("codex")]
    [InlineData("copilot")]
    [InlineData("hermes")]
    [InlineData("xcore")]
    [InlineData("human")]
    public void AllWorkspaceRolesShareTheSameImmutableHandoffContract(string recipient)
    {
        var store = new HeliosHandoffStore(_root);
        var id = Guid.NewGuid().ToString();
        var receipt = store.Submit(id, CorrelationId, recipient, "Review this evidence.");
        Assert.Equal(recipient, receipt.Recipient);
        Assert.Equal(receipt, store.Fetch(id));
        Assert.Equal(receipt, store.Submit(id, CorrelationId, recipient, "Review this evidence."));
        Assert.Contains(id, store.List(recipient));
        Assert.Throws<McpException>(() => store.Submit(id, CorrelationId, recipient, "Changed evidence."));
        Assert.Equal(receipt, store.Fetch(id));
    }

    [Theory]
    [InlineData("../../.env", "chatgpt", "valid note", null)]
    [InlineData("11111111-1111-1111-1111-111111111111", "shell", "valid note", null)]
    [InlineData("11111111-1111-1111-1111-111111111111", "chatgpt", "", null)]
    [InlineData("11111111-1111-1111-1111-111111111111", "chatgpt", "valid note", "not-a-sha")]
    [InlineData("11111111-1111-1111-1111-111111111111", "chatgpt", "Bearer TEST_CREDENTIAL_0123456789", null)]
    [InlineData("11111111-1111-1111-1111-111111111111", "chatgpt", "github_pat_TESTCREDENTIAL0123456789", null)]
    [InlineData("11111111-1111-1111-1111-111111111111", "chatgpt", "-----BEGIN PRIVATE KEY-----", null)]
    [InlineData("11111111-1111-1111-1111-111111111111", "chatgpt", "https://hooks.slack.com/services/TEST/TEST/TEST", null)]
    public void InvalidOrSecretHandoffsNeverCreateStorage(string id, string recipient, string note, string? sha)
    {
        var store = new HeliosHandoffStore(_root);
        Assert.Throws<McpException>(() => store.Submit(id, CorrelationId, recipient, note, sha));
        Assert.False(Directory.Exists(Path.Combine(_root, ".helios", "bridge")));
    }

    [Fact]
    public void LimitsAreCheckedInBytesAndReadsStayBounded()
    {
        var store = new HeliosHandoffStore(_root);
        Assert.Throws<McpException>(() => store.Submit(Guid.NewGuid().ToString(), CorrelationId, "chatgpt", new string('語', 3000)));
        Assert.Throws<McpException>(() => store.List("chatgpt", 51));
        var id = Guid.NewGuid().ToString();
        store.Submit(id, CorrelationId, "chatgpt", "a review");
        File.WriteAllText(Path.Combine(_root, ".helios", "bridge", id + ".json"), new string('x', 65537));
        Assert.Throws<McpException>(() => store.Fetch(id));
    }

    [Fact]
    public void LinkedWorktreesResolveThePrimaryCheckoutInbox()
    {
        var worktree = Path.Combine(_root, "worktree");
        var metadata = Path.Combine(_root, ".git", "worktrees", "review");
        Directory.CreateDirectory(worktree); Directory.CreateDirectory(metadata);
        File.WriteAllText(Path.Combine(worktree, "AGENTS.md"), "linked project");
        File.WriteAllText(Path.Combine(worktree, ".git"), "gitdir: " + metadata);
        File.WriteAllText(Path.Combine(metadata, "commondir"), "../..");
        File.WriteAllText(Path.Combine(metadata, "gitdir"), Path.Combine(worktree, ".git"));
        var id = Guid.NewGuid().ToString();
        var receipt = new HeliosHandoffStore(worktree).Submit(id, CorrelationId, "chatgpt", "worktree review");
        Assert.Equal(receipt, new HeliosHandoffStore(_root).Fetch(id));
        Assert.False(Directory.Exists(Path.Combine(worktree, ".helios", "bridge")));
        File.WriteAllText(Path.Combine(metadata, "gitdir"), Path.Combine(_root, "unrelated", ".git"));
        Assert.Throws<McpException>(() => new HeliosHandoffStore(worktree));
    }

    [Fact]
    public void FullInboxStillAllowsIdempotentRetrieval()
    {
        var store = new HeliosHandoffStore(_root);
        var id = Guid.NewGuid().ToString();
        var original = store.Submit(id, CorrelationId, "codex", "first note");
        for (var index = 1; index < HeliosHandoffStore.MaxItems; index++)
            store.Submit(Guid.NewGuid().ToString(), CorrelationId, "codex", "note " + index);
        Assert.Throws<McpException>(() => store.Submit(Guid.NewGuid().ToString(), CorrelationId, "codex", "over capacity"));
        Assert.Equal(original, store.Submit(id, CorrelationId, "codex", "first note"));
    }

    [Fact]
    public async Task ConcurrentHandoffWritersNeverOverwriteAReceipt()
    {
        var id = Guid.NewGuid().ToString();
        var store = new HeliosHandoffStore(_root);
        store.Submit(id, CorrelationId, "claude", "original");
        await Task.WhenAll(Enumerable.Range(0, 8).Select(index => Task.Run(() =>
        {
            Assert.Throws<McpException>(() => new HeliosHandoffStore(_root).Submit(id, CorrelationId, "claude", "change " + index));
        })));
        Assert.Equal("original", store.Fetch(id).Note);
    }

    // Python is already the repository's required portable spoke/CI prerequisite.
    // These fixed inert fixtures replace Claude; they never make model/network calls.
    private static ProcessStartInfo Fixture(string script)
    {
        var start = new ProcessStartInfo(OperatingSystem.IsWindows() ? "python" : "python3")
        {
            UseShellExecute = false, RedirectStandardInput = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
        };
        start.ArgumentList.Add("-c"); start.ArgumentList.Add(script);
        return start;
    }

    [Fact]
    public async Task ClaudeTextTravelsOnlyOverStdinAndReturnsOnlyResultText()
    {
        var fixture = Fixture("import sys,json; value=sys.stdin.read(); print(json.dumps({'result':value,'is_error':False,'ignored':'private-diagnostic'}))");
        var prompt = "Review this literal text: $(do_not_execute) `also_literal`\nsecond line";
        var result = await ClaudeTextBridge.RunAsync(fixture, prompt, TimeSpan.FromSeconds(5), default);
        Assert.True(result.Success); Assert.Equal(prompt, result.Text);
        Assert.False(result.ExistingWebSessionAttached);
        Assert.DoesNotContain(prompt, fixture.ArgumentList);
    }

    [Fact]
    public async Task ClaudeFailuresNeverReturnRawDiagnosticsOrCredentialMaterial()
    {
        var fixture = Fixture("import sys; sys.stderr.write('TEST_SECRET_DO_NOT_RETURN'); sys.exit(1)");
        var result = await ClaudeTextBridge.RunAsync(fixture, "test", TimeSpan.FromSeconds(5), default);
        Assert.False(result.Success); Assert.Null(result.Text);
        Assert.DoesNotContain("TEST_SECRET", result.ToString());
    }

    [Fact]
    public async Task ClaudeTimeoutAndOversizedStreamsTerminateWithoutReturningPartialText()
    {
        var slow = await ClaudeTextBridge.RunAsync(Fixture("import time; time.sleep(30)"), "test", TimeSpan.FromMilliseconds(150), default);
        Assert.False(slow.Success); Assert.Null(slow.Text);
        var stdout = await ClaudeTextBridge.RunAsync(Fixture("import sys; sys.stdout.write('x'*300000); sys.stdout.flush()"), "test", TimeSpan.FromSeconds(5), default);
        Assert.False(stdout.Success); Assert.Null(stdout.Text);
        var stderr = await ClaudeTextBridge.RunAsync(Fixture("import sys; sys.stderr.write('x'*300000); sys.stderr.flush()"), "test", TimeSpan.FromSeconds(5), default);
        Assert.False(stderr.Success); Assert.Null(stderr.Text);
    }

    [Fact]
    public async Task CallerCancellationPropagatesAndStopsTheChild()
    {
        using var cancel = new CancellationTokenSource(TimeSpan.FromMilliseconds(150));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => ClaudeTextBridge.RunAsync(
            Fixture("import time; time.sleep(30)"), "test", TimeSpan.FromSeconds(10), cancel.Token));
    }

    public void Dispose() => Directory.Delete(_root, recursive: true);
}
