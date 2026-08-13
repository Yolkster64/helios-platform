using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using HELIOS.Mcp;
using Xunit;

namespace HELIOS.AIHub.Tests;

public sealed class OperatorContextToolsTests : IDisposable
{
    private readonly string _repoRoot = Path.Combine(
        Path.GetTempPath(),
        $"helios-operator-tests-{Guid.NewGuid():N}");

    public OperatorContextToolsTests()
    {
        Directory.CreateDirectory(Path.Combine(_repoRoot, "config"));
        File.WriteAllText(Path.Combine(_repoRoot, "config", "aihub.json"), "{}");
    }

    [Theory]
    [InlineData(nameof(HeliosOperatorTools.GetProfile), "helios_operator_profile_get")]
    [InlineData(nameof(HeliosOperatorTools.SaveProfile), "helios_operator_profile_save")]
    [InlineData(nameof(HeliosOperatorTools.SyncContext), "helios_operator_context_sync")]
    [InlineData(nameof(HeliosOperatorTools.GetNextSteps), "helios_operator_next_steps_get")]
    public void OperatorTools_AreDiscoverable(string methodName, string expectedToolName)
    {
        var method = typeof(HeliosOperatorTools).GetMethod(methodName, BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        Assert.Equal(
            expectedToolName,
            toolAttribute.GetType().GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
    }

    [Fact]
    public async Task Profile_RoundTripsInspectablePreferences_AndRejectsSecrets()
    {
        var store = CreateStore(new FakeCommandRunner());

        var saved = await store.SaveProfileAsync(
            "John",
            "southcentralus",
            "helios-jm",
            "{\"project\":\"helios\",\"owner\":\"john\"}",
            "claude-code,codex,hermes",
            CancellationToken.None);

        Assert.Equal("southcentralus", saved.PreferredAzureLocation);
        Assert.Equal("helios-jm", saved.NamingPrefix);
        Assert.Equal("helios", saved.DefaultTags["project"]);
        Assert.Equal(new[] { "claude-code", "codex", "hermes" }, saved.AssistantSurfaces);
        var loaded = store.GetProfile();
        Assert.Equal(saved.DisplayName, loaded.DisplayName);
        Assert.Equal(saved.PreferredAzureLocation, loaded.PreferredAzureLocation);
        Assert.Equal(saved.NamingPrefix, loaded.NamingPrefix);
        Assert.Equal(saved.DefaultTags.Count, loaded.DefaultTags.Count);
        Assert.All(saved.DefaultTags, pair => Assert.Equal(pair.Value, loaded.DefaultTags[pair.Key]));
        Assert.Equal(saved.AssistantSurfaces, loaded.AssistantSurfaces);

        var credentialLike = $"sk-{new string('x', 24)}";
        await Assert.ThrowsAsync<ArgumentException>(() => store.SaveProfileAsync(
            null,
            null,
            null,
            $"{{\"api-key\":\"{credentialLike}\"}}",
            null,
            CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentException>(() => store.SaveProfileAsync(
            null,
            null,
            null,
            "{\"costCenter\":42}",
            null,
            CancellationToken.None));
    }

    [Theory]
    [InlineData("clientSecret")]
    [InlineData("sasToken")]
    [InlineData("secretValue")]
    public async Task SaveProfile_RejectsCamelCaseCredentialTagNames(string tagName)
    {
        var store = CreateStore(new FakeCommandRunner());

        await Assert.ThrowsAsync<ArgumentException>(() => store.SaveProfileAsync(
            null,
            null,
            null,
            $"{{\"{tagName}\":\"rotate-me\"}}",
            null,
            CancellationToken.None));
    }

    [Fact]
    public async Task SaveProfile_RejectsCredentialLikeDisplayName()
    {
        var store = CreateStore(new FakeCommandRunner());

        await Assert.ThrowsAsync<ArgumentException>(() => store.SaveProfileAsync(
            FakeCommandRunner.CredentialLike,
            null,
            null,
            null,
            null,
            CancellationToken.None));
        Assert.False(File.Exists(store.ProfilePath));
    }

    [Fact]
    public async Task SaveProfile_EmptyTagsJson_ClearsSavedTags()
    {
        var store = CreateStore(new FakeCommandRunner());
        await store.SaveProfileAsync(null, null, null, "{\"project\":\"helios\"}", null, CancellationToken.None);

        var cleared = await store.SaveProfileAsync(null, null, null, string.Empty, null, CancellationToken.None);

        Assert.Empty(cleared.DefaultTags);
        Assert.Empty(store.GetProfile().DefaultTags);
    }

    [Fact]
    public async Task SaveProfile_UnchangedProfile_IsNoOp()
    {
        var store = CreateStore(new FakeCommandRunner());

        // A save that changes nothing on a fresh store writes neither profile nor journal.
        var untouched = await store.SaveProfileAsync(null, null, null, null, null, CancellationToken.None);
        Assert.False(File.Exists(store.ProfilePath));
        Assert.False(File.Exists(store.JournalPath));
        Assert.Null(untouched.DisplayName);

        await store.SaveProfileAsync("John", null, null, null, null, CancellationToken.None);
        Assert.Single(File.ReadLines(store.JournalPath));

        // Repeating the identical save appends no second journal entry and keeps the profile.
        var repeated = await store.SaveProfileAsync("John", null, null, null, null, CancellationToken.None);
        Assert.Equal("John", repeated.DisplayName);
        Assert.Single(File.ReadLines(store.JournalPath));
    }

    [Fact]
    public async Task ContextSync_PersistsSanitizedAzureDeltaAndJournal()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);

        var first = await store.SyncAsync(
            "claude-code",
            includeAzure: true,
            includeResources: true,
            CancellationToken.None);

        Assert.Equal("Yolkster64/helios-platform", first.Repository.Repository);
        Assert.Equal("ready", first.Azure.Status);
        Assert.True(first.Azure.ResourcesIncluded);
        Assert.False(first.Changes.Comparable);
        Assert.Equal("<redacted>", first.Azure.ResourceGroups[0].Tags["api-key"]);

        runner.SnapshotVersion = 2;
        var second = await store.SyncAsync(
            "codex",
            includeAzure: true,
            includeResources: true,
            CancellationToken.None);

        Assert.True(second.Changes.Comparable);
        Assert.Contains("rg-ai", second.Changes.ResourceGroupsAdded);
        Assert.Contains("rg-core", second.Changes.ResourceGroupsChanged);
        Assert.True(second.Changes.ResourcesComparable);
        Assert.Contains("rg-ai|Microsoft.KeyVault/vaults|helios-kv", second.Changes.ResourcesAdded);
        Assert.Contains("rg-core|Microsoft.Compute/virtualMachines|helios-vm", second.Changes.ResourcesChanged);

        var context = File.ReadAllText(store.ContextPath);
        Assert.False(context.Contains(FakeCommandRunner.CredentialLike, StringComparison.OrdinalIgnoreCase));
        Assert.Equal(2, File.ReadLines(store.JournalPath).Count());
        Assert.All(File.ReadLines(store.JournalPath), line => Assert.Contains("contextSha256", line));
    }

    [Fact]
    public async Task ContextSync_RedactsCamelCaseCredentialAzureTags()
    {
        var store = CreateStore(new FakeCommandRunner());

        var snapshot = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.Equal("<redacted>", snapshot.Azure.ResourceGroups[0].Tags["clientSecret"]);
    }

    [Fact]
    public async Task ContextSync_RepoOnlySync_PreservesReadyAzureBaseline()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        var first = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        Assert.Equal("ready", first.Azure.Status);

        var repoOnly = await store.SyncAsync("codex", includeAzure: false, includeResources: false, CancellationToken.None);

        Assert.Equal("ready", repoOnly.Azure.Status);
        Assert.Equal(first.Azure.ResourceGroups.Count, repoOnly.Azure.ResourceGroups.Count);
        Assert.False(repoOnly.Changes.Comparable);
        Assert.Contains("not requested", repoOnly.Changes.Summary, StringComparison.OrdinalIgnoreCase);

        runner.SnapshotVersion = 2;
        var third = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.True(third.Changes.Comparable);
        Assert.Contains("rg-ai", third.Changes.ResourceGroupsAdded);
    }

    [Fact]
    public async Task ContextSync_SubscriptionSwitch_IsNotComparable()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        runner.SnapshotVersion = 2;
        runner.SubscriptionId = "sub-2";
        var second = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.False(second.Changes.Comparable);
        Assert.Empty(second.Changes.ResourceGroupsAdded);
    }

    [Fact]
    public async Task ContextSync_TagTruncatedItems_AreNotComparable()
    {
        var runner = new FakeCommandRunner { GroupTagCount = 40 };
        var store = CreateStore(runner);

        var first = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        var second = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.True(first.Azure.ResourceGroups[0].TagsTruncated);
        Assert.Equal(32, first.Azure.ResourceGroups[0].Tags.Count);
        Assert.False(second.Changes.Comparable);
    }

    [Fact]
    public async Task ContextSync_GitStatusFailure_DoesNotClaimCleanCheckout()
    {
        var runner = new FakeCommandRunner { GitStatusFails = true };
        var store = CreateStore(runner);

        var snapshot = await store.SyncAsync("manual", includeAzure: false, includeResources: false, CancellationToken.None);

        Assert.Equal("ready", snapshot.Repository.Status);
        Assert.Null(snapshot.Repository.IsDirty);
    }

    [Fact]
    public async Task ContextSync_GitUnavailable_IsDetectedThroughRunner()
    {
        var runner = new FakeCommandRunner { GitAvailable = false };
        var store = CreateStore(runner);

        var snapshot = await store.SyncAsync("manual", includeAzure: false, includeResources: false, CancellationToken.None);

        Assert.Equal("git-unavailable", snapshot.Repository.Status);
        Assert.Null(snapshot.Repository.IsDirty);
    }

    [Fact]
    public async Task ContextSync_JournalReceipt_MatchesContextFileBytesAndRecordsBranch()
    {
        var store = CreateStore(new FakeCommandRunner());

        await store.SyncAsync("claude-code", includeAzure: false, includeResources: false, CancellationToken.None);

        using var entry = JsonDocument.Parse(File.ReadLines(store.JournalPath).Last());
        var recordedSha = entry.RootElement.GetProperty("contextSha256").GetString();
        var diskSha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(store.ContextPath))).ToLowerInvariant();
        Assert.Equal(diskSha, recordedSha);
        Assert.Equal(
            "integration/claude-code-operator-plugin",
            entry.RootElement.GetProperty("repositoryBranch").GetString());
        Assert.Equal("0123456789abcdef", entry.RootElement.GetProperty("repositoryHead").GetString());
    }

    public void Dispose()
    {
        if (Directory.Exists(_repoRoot))
        {
            Directory.Delete(_repoRoot, recursive: true);
        }
    }

    private OperatorContextStore CreateStore(FakeCommandRunner runner) => new(
        _repoRoot,
        runner,
        () => new DateTimeOffset(2026, 8, 10, 12, 0, 0, TimeSpan.Zero),
        () => new Dictionary<string, bool>(StringComparer.Ordinal)
        {
            ["az"] = true,
            ["claude"] = true,
            ["codex"] = true,
            ["copilot"] = true,
            ["dotnet"] = true,
            ["gh"] = true,
            ["hermes"] = true,
        });

    private sealed class FakeCommandRunner : ICommandRunner
    {
        internal static readonly string CredentialLike = $"sk-{new string('x', 24)}";
        internal int SnapshotVersion { get; set; } = 1;
        internal bool GitAvailable { get; set; } = true;
        internal bool GitStatusFails { get; set; }
        internal string SubscriptionId { get; set; } = "sub-1";
        internal int GroupTagCount { get; set; }

        public Task<CommandResult> RunAsync(
            string fileName,
            IReadOnlyList<string> arguments,
            TimeSpan timeout,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (fileName == "git")
            {
                return Task.FromResult(GitAvailable ? Git(arguments) : CommandResult.NotStarted);
            }
            if (fileName == "az")
            {
                return Task.FromResult(Azure(arguments));
            }
            return Task.FromResult(CommandResult.NotStarted);
        }

        private CommandResult Git(IReadOnlyList<string> arguments)
        {
            var command = arguments.Skip(2).ToArray();
            return command switch
            {
                ["branch", "--show-current"] => Success("integration/claude-code-operator-plugin\n"),
                ["rev-parse", "HEAD"] => Success("0123456789abcdef\n"),
                ["remote", "get-url", "origin"] => Success("git@github.com:Yolkster64/helios-platform.git\n"),
                ["status", "--porcelain=v1"] => GitStatusFails
                    ? new CommandResult(true, 128, string.Empty, "fatal: unable to read the index")
                    : Success(string.Empty),
                _ => new CommandResult(true, 1, string.Empty, "unexpected git command"),
            };
        }

        private string GroupTagsJson() => GroupTagCount > 0
            ? "{" + string.Join(',', Enumerable.Range(0, GroupTagCount).Select(i => $"\"tag{i:D2}\":\"v\"")) + "}"
            : "{\"api-key\":\"" + CredentialLike + "\",\"clientSecret\":\"rotate-me\",\"project\":\"helios\"}";

        private CommandResult Azure(IReadOnlyList<string> arguments)
        {
            if (arguments.Take(2).SequenceEqual(new[] { "account", "show" }))
            {
                return Success("{\"id\":\"" + SubscriptionId + "\",\"name\":\"HELIOS Dev\",\"tenantId\":\"tenant-1\",\"state\":\"Enabled\"}");
            }
            if (arguments.Take(2).SequenceEqual(new[] { "group", "list" }))
            {
                return Success(SnapshotVersion == 1
                    ? "[{\"name\":\"rg-core\",\"location\":\"southcentralus\",\"provisioningState\":\"Succeeded\",\"tags\":" + GroupTagsJson() + "}]"
                    : "[{\"name\":\"rg-core\",\"location\":\"centralus\",\"provisioningState\":\"Succeeded\",\"tags\":{\"project\":\"helios\"}},{\"name\":\"rg-ai\",\"location\":\"centralus\",\"provisioningState\":\"Succeeded\",\"tags\":{}}]");
            }
            if (arguments.Take(2).SequenceEqual(new[] { "resource", "list" }))
            {
                return Success(SnapshotVersion == 1
                    ? "[{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-core/providers/Microsoft.Compute/virtualMachines/helios-vm\",\"name\":\"helios-vm\",\"type\":\"Microsoft.Compute/virtualMachines\",\"location\":\"southcentralus\",\"resourceGroup\":\"rg-core\",\"tags\":{}}]"
                    : "[{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-core/providers/Microsoft.Compute/virtualMachines/helios-vm\",\"name\":\"helios-vm\",\"type\":\"Microsoft.Compute/virtualMachines\",\"location\":\"centralus\",\"resourceGroup\":\"rg-core\",\"tags\":{}},{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-ai/providers/Microsoft.KeyVault/vaults/helios-kv\",\"name\":\"helios-kv\",\"type\":\"Microsoft.KeyVault/vaults\",\"location\":\"centralus\",\"resourceGroup\":\"rg-ai\",\"tags\":{}}]");
            }
            return new CommandResult(true, 1, string.Empty, "unexpected az command");
        }

        private static CommandResult Success(string output) => new(true, 0, output, string.Empty);
    }
}
