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
    [InlineData("SASToken")]
    [InlineData("APIKey")]
    [InlineData("DBPassword")]
    [InlineData("secretValue")]
    public async Task SaveProfile_RejectsCaseDelimitedCredentialTagNames(string tagName)
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

    [Theory]
    [InlineData("SASH")]
    [InlineData("Tokenizer")]
    public async Task SaveProfile_AcceptsWordsThatMerelyContainCredentialStems(string tagName)
    {
        var store = CreateStore(new FakeCommandRunner());

        var saved = await store.SaveProfileAsync(
            null,
            null,
            null,
            $"{{\"{tagName}\":\"plain-value\"}}",
            null,
            CancellationToken.None);

        Assert.Equal("plain-value", saved.DefaultTags[tagName]);
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
        Assert.Matches("^<redacted:[0-9a-f]{12}>$", first.Azure.ResourceGroups[0].Tags["api-key"]);

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
        Assert.Contains(
            "/subscriptions/sub-1/resourceGroups/rg-ai/providers/Microsoft.KeyVault/vaults/helios-kv",
            second.Changes.ResourcesAdded);
        Assert.Contains(
            "/subscriptions/sub-1/resourceGroups/rg-core/providers/Microsoft.Compute/virtualMachines/helios-vm",
            second.Changes.ResourcesChanged);

        var context = File.ReadAllText(store.ContextPath);
        Assert.False(context.Contains(FakeCommandRunner.CredentialLike, StringComparison.OrdinalIgnoreCase));
        Assert.Equal(2, File.ReadLines(store.JournalPath).Count());
        Assert.All(File.ReadLines(store.JournalPath), line => Assert.Contains("contextSha256", line));
    }

    [Theory]
    [InlineData("clientSecret")]
    [InlineData("SASToken")]
    public async Task ContextSync_RedactsCaseDelimitedCredentialAzureTags(string tagName)
    {
        var store = CreateStore(new FakeCommandRunner());

        var snapshot = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.Matches("^<redacted:[0-9a-f]{12}>$", snapshot.Azure.ResourceGroups[0].Tags[tagName]);
    }

    [Fact]
    public async Task ContextSync_RotatedSecretTagValue_SurfacesAsChange()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        var first = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        // Same inventory, same secret: the keyed fingerprint compares equal.
        var unchanged = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        Assert.True(unchanged.Changes.Comparable);
        Assert.Empty(unchanged.Changes.ResourceGroupsChanged);

        // Rotating the secret changes the fingerprint, so the delta surfaces.
        var rotated = $"sk-{new string('y', 24)}";
        runner.CredentialValue = rotated;
        var changed = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.True(changed.Changes.Comparable);
        Assert.Contains("rg-core", changed.Changes.ResourceGroupsChanged);
        Assert.NotEqual(
            first.Azure.ResourceGroups[0].Tags["api-key"],
            changed.Azure.ResourceGroups[0].Tags["api-key"]);
        var context = File.ReadAllText(store.ContextPath);
        Assert.DoesNotContain(rotated, context, StringComparison.OrdinalIgnoreCase);
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
    public async Task ContextSync_FailedAzureCapture_PreservesReadyBaseline()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        var first = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        Assert.Equal("ready", first.Azure.Status);
        Assert.Null(first.AzureCaptureFailure);

        // An Azure-REQUESTED sync whose capture fails must not destroy the baseline.
        runner.AzureNotAuthenticated = true;
        var failed = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.Equal("ready", failed.Azure.Status);
        Assert.Equal(first.Azure.ResourceGroups.Count, failed.Azure.ResourceGroups.Count);
        Assert.Equal("not-authenticated", failed.AzureCaptureFailure?.Status);
        Assert.False(failed.Changes.Comparable);
        // The failure still drives the next-step suggestion.
        Assert.Contains(failed.NextSteps, step => step.Id == "azure-sign-in");
        // The append-only journal must record that Azure evidence was unavailable at
        // this receipt, even though the stored counts describe the carried baseline.
        using (var receipt = JsonDocument.Parse(File.ReadLines(store.JournalPath).Last()))
        {
            Assert.Equal("not-authenticated", receipt.RootElement.GetProperty("azureCaptureStatus").GetString());
            Assert.Equal("sub-1", receipt.RootElement.GetProperty("azureSubscriptionId").GetString());
        }

        // The next successful capture compares against the preserved baseline.
        runner.AzureNotAuthenticated = false;
        runner.SnapshotVersion = 2;
        var recovered = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.Null(recovered.AzureCaptureFailure);
        Assert.True(recovered.Changes.Comparable);
        Assert.Contains("rg-ai", recovered.Changes.ResourceGroupsAdded);
    }

    [Fact]
    public async Task ContextSync_CaptureRunsUnderTheCrossProcessLock()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        var lockPath = Path.Combine(store.OperatorDirectory, ".write.lock");
        var observedHeldLock = 0;
        runner.OnCommand = () =>
        {
            // Every capture command must run while the store holds the exclusive lock,
            // so an attempt to take it here has to fail.
            Assert.Throws<IOException>(() => new FileStream(
                lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
            observedHeldLock++;
        };

        await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.True(observedHeldLock > 0);
    }

    [Fact]
    public async Task ContextSync_TruncatedTagName_FlagsItemNonComparable()
    {
        var runner = new FakeCommandRunner { LongGroupTagName = true };
        var store = CreateStore(runner);

        var first = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        var second = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.True(first.Azure.ResourceGroups[0].TagsTruncated);
        Assert.Equal(128, first.Azure.ResourceGroups[0].Tags.Keys.Single().Length);
        Assert.False(second.Changes.Comparable);
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
        // Azure was not requested: the receipt must say so instead of implying evidence.
        Assert.Equal(JsonValueKind.Null, entry.RootElement.GetProperty("azureCaptureStatus").ValueKind);
    }

    [Fact]
    public async Task ContextSync_GroupsOnlySync_RetainsResourceInclusiveBaseline()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        var first = await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        Assert.True(first.Azure.ResourcesIncluded);
        Assert.Single(first.Azure.Resources);

        // A groups-only ready sync must not drop the resource inventory from the baseline.
        var groupsOnly = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        Assert.True(groupsOnly.Azure.ResourcesIncluded);
        Assert.Single(groupsOnly.Azure.Resources);
        Assert.False(groupsOnly.Changes.ResourcesComparable);

        // The next resource-inclusive sync compares against the retained resources.
        runner.SnapshotVersion = 2;
        var third = await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        Assert.True(third.Changes.ResourcesComparable);
        Assert.Contains(
            "/subscriptions/sub-1/resourceGroups/rg-ai/providers/Microsoft.KeyVault/vaults/helios-kv",
            third.Changes.ResourcesAdded);
    }

    [Fact]
    public async Task ContextSync_NonEnabledSubscription_IsNotDeploymentReadyEvidence()
    {
        var runner = new FakeCommandRunner { SubscriptionState = "Disabled" };
        var store = CreateStore(runner);

        var snapshot = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.Equal("ready", snapshot.Azure.Status);
        Assert.Equal("Disabled", snapshot.Azure.SubscriptionState);
        Assert.Contains(snapshot.NextSteps, step => step.Id == "review-subscription-state");
        Assert.DoesNotContain(snapshot.NextSteps, step => step.Id == "review-azure-plan");
    }

    [Fact]
    public async Task ContextSync_DetachedHead_RecommendsTaskBranch()
    {
        var runner = new FakeCommandRunner { DetachedHead = true };
        var store = CreateStore(runner);

        var snapshot = await store.SyncAsync("manual", includeAzure: false, includeResources: false, CancellationToken.None);

        Assert.Equal("ready", snapshot.Repository.Status);
        Assert.Null(snapshot.Repository.Branch);
        Assert.True(snapshot.Repository.IsDetachedHead);
        Assert.False(snapshot.Repository.IsMainBranch);
        Assert.Contains(snapshot.NextSteps, step => step.Id == "create-task-branch");
    }

    [Fact]
    public async Task ContextSync_CarriedAzureBaseline_IsNotCurrentPlanningEvidence()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        var fresh = await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        Assert.NotNull(fresh.Azure.CapturedAtUtc);
        Assert.Contains(fresh.NextSteps, step => step.Id == "review-azure-plan");

        // A repo-only sync keeps the baseline for deltas but must not present it as
        // current evidence for planning; it recommends refreshing first.
        var repoOnly = await store.SyncAsync("codex", includeAzure: false, includeResources: false, CancellationToken.None);

        Assert.Equal("ready", repoOnly.Azure.Status);
        Assert.Null(repoOnly.AzureCaptureStatus);
        Assert.Contains(repoOnly.NextSteps, step => step.Id == "refresh-azure-inventory");
        Assert.DoesNotContain(repoOnly.NextSteps, step => step.Id == "review-azure-plan");
    }

    [Fact]
    public async Task NextSteps_AreRecomputedFromCurrentProfileAtReadTime()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        var snapshot = await store.SyncAsync("claude-code", includeAzure: false, includeResources: false, CancellationToken.None);
        Assert.Contains(snapshot.NextSteps, step => step.Id == "complete-profile");

        // Completing the profile retires the suggestion immediately, without a new sync.
        await store.SaveProfileAsync(null, "southcentralus", "helios-jm", null, null, CancellationToken.None);
        var recomputed = store.GetCurrentNextSteps();

        Assert.DoesNotContain(recomputed, step => step.Id == "complete-profile");
        // The cached snapshot on disk still holds the stale list; only the read path recomputes.
        Assert.Contains(store.GetLatestContext()!.NextSteps, step => step.Id == "complete-profile");
    }

    [Fact]
    public async Task ContextSync_GroupsOnlyInventory_IsNotPresentedAsZeroResources()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);

        var groupsOnly = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.DoesNotContain(groupsOnly.NextSteps, step => step.Id == "review-azure-plan");
        var inventoryStep = Assert.Single(groupsOnly.NextSteps, step => step.Id == "inventory-resources");
        Assert.DoesNotContain("0 resource(s)", inventoryStep.Reason);

        var full = await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        var planStep = Assert.Single(full.NextSteps, step => step.Id == "review-azure-plan");
        Assert.Contains("1 resource(s)", planStep.Reason);
    }

    [Fact]
    public async Task NextSteps_CarriedResourceInventory_IsNotPlanEvidence()
    {
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        Assert.Contains(store.GetCurrentNextSteps(), step => step.Id == "review-azure-plan");

        // Groups-only ready sync: the baseline keeps the carried resources for deltas,
        // but read-time next steps must demand a fresh resource-inclusive sync.
        var groupsOnly = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        Assert.True(groupsOnly.Azure.ResourcesIncluded);
        var readTime = store.GetCurrentNextSteps();
        Assert.Contains(readTime, step => step.Id == "refresh-resource-inventory");
        Assert.DoesNotContain(readTime, step => step.Id == "review-azure-plan");

        // A fresh resource-inclusive sync restores the plan recommendation.
        await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        Assert.Contains(store.GetCurrentNextSteps(), step => step.Id == "review-azure-plan");
    }

    [Fact]
    public async Task ContextSync_DuplicateResourceLeafNames_DoNotAbortTheSync()
    {
        var runner = new FakeCommandRunner { DuplicateResourceLeafNames = true };
        var store = CreateStore(runner);

        var first = await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        var second = await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);

        Assert.Equal(2, first.Azure.Resources.Count);
        Assert.True(second.Changes.ResourcesComparable);
        Assert.Empty(second.Changes.ResourcesAdded);
        Assert.Empty(second.Changes.ResourcesRemoved);
        Assert.Empty(second.Changes.ResourcesChanged);
    }

    [Fact]
    public async Task ContextSync_CanceledBeforeCommit_LeavesNoHalfState()
    {
        using var cts = new CancellationTokenSource();
        var runner = new FakeCommandRunner();
        var store = CreateStore(runner);
        runner.OnCommand = cts.Cancel;

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            store.SyncAsync("manual", includeAzure: false, includeResources: false, cts.Token));

        // Pre-commit cancellation must leave neither a context nor a dangling receipt;
        // post-commit, the journal append runs under CancellationToken.None so a durable
        // context can never exist without its receipt.
        Assert.False(File.Exists(store.ContextPath));
        Assert.False(File.Exists(store.JournalPath));
    }

    [Fact]
    public async Task ContextSync_PartialAndErrorCaptures_GetRecoverySteps()
    {
        var runner = new FakeCommandRunner { AzureResourceListFails = true };
        var store = CreateStore(runner);
        var partial = await store.SyncAsync("claude-code", includeAzure: true, includeResources: true, CancellationToken.None);
        Assert.Equal("partial", partial.AzureCaptureFailure?.Status);
        Assert.Contains(partial.NextSteps, step => step.Id == "retry-resource-inventory");

        runner.AzureResourceListFails = false;
        runner.AzureGroupListFails = true;
        var error = await store.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        Assert.Equal("error", error.AzureCaptureFailure?.Status);
        Assert.Contains(error.NextSteps, step => step.Id == "retry-azure-inventory");
        // The read-time tool surfaces the same recovery step from the stored failure.
        Assert.Contains(store.GetCurrentNextSteps(), step => step.Id == "retry-azure-inventory");
    }

    [Fact]
    public async Task ContextSync_CredentialLookingBranchName_IsRedactedEverywhere()
    {
        var rawBranch = $"incident/sk-{new string('z', 24)}";
        var runner = new FakeCommandRunner { BranchName = rawBranch };
        var store = CreateStore(runner);

        var snapshot = await store.SyncAsync("manual", includeAzure: false, includeResources: false, CancellationToken.None);

        Assert.Matches("^<redacted:[0-9a-f]{12}>$", snapshot.Repository.Branch);
        Assert.False(snapshot.Repository.IsMainBranch);
        Assert.DoesNotContain(rawBranch, File.ReadAllText(store.ContextPath), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(rawBranch, File.ReadAllText(store.JournalPath), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ContextSync_DirtyCheckoutOnMain_GetsBothBranchAndDiffSteps()
    {
        var runner = new FakeCommandRunner { BranchName = "main", GitStatusDirty = true };
        var store = CreateStore(runner);

        var snapshot = await store.SyncAsync("manual", includeAzure: false, includeResources: false, CancellationToken.None);

        Assert.True(snapshot.Repository.IsMainBranch);
        Assert.True(snapshot.Repository.IsDirty);
        Assert.Contains(snapshot.NextSteps, step => step.Id == "create-task-branch");
        Assert.Contains(snapshot.NextSteps, step => step.Id == "review-local-diff");
    }

    [Fact]
    public async Task ContextSync_RegeneratedSalt_MakesCapturesNonComparable()
    {
        var runner = new FakeCommandRunner();
        var storeBefore = CreateStore(runner);
        var first = await storeBefore.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);
        Assert.NotNull(first.Azure.TagSaltId);

        // Simulate a partial restore: context.json survives, the salt file does not.
        File.Delete(Path.Combine(storeBefore.OperatorDirectory, "tag-salt.bin"));
        var storeAfter = CreateStore(runner);
        var second = await storeAfter.SyncAsync("claude-code", includeAzure: true, includeResources: false, CancellationToken.None);

        Assert.NotNull(second.Azure.TagSaltId);
        Assert.NotEqual(first.Azure.TagSaltId, second.Azure.TagSaltId);
        Assert.False(second.Changes.Comparable);
    }

    [Fact]
    public async Task SaveProfile_JournalReceipt_MatchesProfileFileBytes()
    {
        var store = CreateStore(new FakeCommandRunner());

        await store.SaveProfileAsync("John", null, null, null, null, CancellationToken.None);

        using var entry = JsonDocument.Parse(File.ReadLines(store.JournalPath).Last());
        var recordedSha = entry.RootElement.GetProperty("profileSha256").GetString();
        var diskSha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(store.ProfilePath))).ToLowerInvariant();
        Assert.Equal(diskSha, recordedSha);
    }

    [Fact]
    public void LockWaitBudget_CoversWorstCaseCaptureWindow()
    {
        // Sync holds the lock across four git commands and all three Azure reads; the
        // waiter budget is derived from the same constants so they cannot drift apart.
        var worstCaseHold = 4 * OperatorContextStore.GitCommandTimeout
            + OperatorContextStore.AzureAccountTimeout
            + OperatorContextStore.AzureGroupListTimeout
            + OperatorContextStore.AzureResourceListTimeout;

        Assert.True(OperatorContextStore.LockWaitBudget >= worstCaseHold);
    }

    [Fact]
    public void CreateStartInfo_WindowsBatchShim_LaunchesViaCmd()
    {
        var info = SystemCommandRunner.CreateStartInfo(
            "az",
            new[] { "account", "show" },
            @"C:\Tools\az.cmd");

        Assert.EndsWith("cmd.exe", info.FileName, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(new[] { "/d", "/c", @"C:\Tools\az.cmd", "account", "show" }, info.ArgumentList);
        Assert.False(info.UseShellExecute);
    }

    [Fact]
    public void CreateStartInfo_NativeExecutables_LaunchDirectly()
    {
        var resolved = SystemCommandRunner.CreateStartInfo("az", new[] { "account" }, @"C:\Tools\az.exe");
        Assert.Equal(@"C:\Tools\az.exe", resolved.FileName);
        Assert.Equal(new[] { "account" }, resolved.ArgumentList);

        // Non-Windows (or unresolved) commands keep the bare name and arguments.
        var bare = SystemCommandRunner.CreateStartInfo("git", new[] { "status" }, null);
        Assert.Equal("git", bare.FileName);
        Assert.Equal(new[] { "status" }, bare.ArgumentList);
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
        internal bool GitStatusDirty { get; set; }
        internal bool DetachedHead { get; set; }
        internal string BranchName { get; set; } = "integration/claude-code-operator-plugin";
        internal bool AzureNotAuthenticated { get; set; }
        internal bool AzureGroupListFails { get; set; }
        internal bool AzureResourceListFails { get; set; }
        internal bool DuplicateResourceLeafNames { get; set; }
        internal string SubscriptionId { get; set; } = "sub-1";
        internal string SubscriptionState { get; set; } = "Enabled";
        internal string CredentialValue { get; set; } = CredentialLike;
        internal int GroupTagCount { get; set; }
        internal bool LongGroupTagName { get; set; }
        internal Action? OnCommand { get; set; }

        public Task<CommandResult> RunAsync(
            string fileName,
            IReadOnlyList<string> arguments,
            TimeSpan timeout,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            OnCommand?.Invoke();
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
                ["branch", "--show-current"] => Success(
                    DetachedHead ? string.Empty : BranchName + "\n"),
                ["rev-parse", "HEAD"] => Success("0123456789abcdef\n"),
                ["remote", "get-url", "origin"] => Success("git@github.com:Yolkster64/helios-platform.git\n"),
                ["status", "--porcelain=v1"] => GitStatusFails
                    ? new CommandResult(true, 128, string.Empty, "fatal: unable to read the index")
                    : Success(GitStatusDirty ? " M src/some-file.cs\n" : string.Empty),
                _ => new CommandResult(true, 1, string.Empty, "unexpected git command"),
            };
        }

        private string GroupTagsJson()
        {
            if (LongGroupTagName)
            {
                return "{\"" + new string('n', 200) + "\":\"v\"}";
            }
            return GroupTagCount > 0
                ? "{" + string.Join(',', Enumerable.Range(0, GroupTagCount).Select(i => $"\"tag{i:D2}\":\"v\"")) + "}"
                : "{\"api-key\":\"" + CredentialValue + "\",\"clientSecret\":\"rotate-me\",\"SASToken\":\"arbitrary-value\",\"project\":\"helios\"}";
        }

        private CommandResult Azure(IReadOnlyList<string> arguments)
        {
            if (arguments.Take(2).SequenceEqual(new[] { "account", "show" }))
            {
                if (AzureNotAuthenticated)
                {
                    return new CommandResult(true, 1, string.Empty, "Please run 'az login' to setup account.");
                }
                return Success("{\"id\":\"" + SubscriptionId + "\",\"name\":\"HELIOS Dev\",\"tenantId\":\"tenant-1\",\"state\":\"" + SubscriptionState + "\"}");
            }
            if (arguments.Take(2).SequenceEqual(new[] { "group", "list" }))
            {
                if (AzureGroupListFails)
                {
                    return new CommandResult(true, 1, string.Empty, "The group listing request was rejected.");
                }
                return Success(SnapshotVersion == 1
                    ? "[{\"name\":\"rg-core\",\"location\":\"southcentralus\",\"provisioningState\":\"Succeeded\",\"tags\":" + GroupTagsJson() + "}]"
                    : "[{\"name\":\"rg-core\",\"location\":\"centralus\",\"provisioningState\":\"Succeeded\",\"tags\":{\"project\":\"helios\"}},{\"name\":\"rg-ai\",\"location\":\"centralus\",\"provisioningState\":\"Succeeded\",\"tags\":{}}]");
            }
            if (arguments.Take(2).SequenceEqual(new[] { "resource", "list" }))
            {
                if (AzureResourceListFails)
                {
                    return new CommandResult(true, 1, string.Empty, "The resource listing request timed out.");
                }
                if (DuplicateResourceLeafNames)
                {
                    return Success(
                        "[{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-core/providers/Microsoft.Sql/servers/srv1/databases/master\",\"name\":\"master\",\"type\":\"Microsoft.Sql/servers/databases\",\"location\":\"southcentralus\",\"resourceGroup\":\"rg-core\",\"tags\":{}},"
                        + "{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-core/providers/Microsoft.Sql/servers/srv2/databases/master\",\"name\":\"master\",\"type\":\"Microsoft.Sql/servers/databases\",\"location\":\"southcentralus\",\"resourceGroup\":\"rg-core\",\"tags\":{}}]");
                }
                return Success(SnapshotVersion == 1
                    ? "[{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-core/providers/Microsoft.Compute/virtualMachines/helios-vm\",\"name\":\"helios-vm\",\"type\":\"Microsoft.Compute/virtualMachines\",\"location\":\"southcentralus\",\"resourceGroup\":\"rg-core\",\"tags\":{}}]"
                    : "[{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-core/providers/Microsoft.Compute/virtualMachines/helios-vm\",\"name\":\"helios-vm\",\"type\":\"Microsoft.Compute/virtualMachines\",\"location\":\"centralus\",\"resourceGroup\":\"rg-core\",\"tags\":{}},{\"id\":\"/subscriptions/sub-1/resourceGroups/rg-ai/providers/Microsoft.KeyVault/vaults/helios-kv\",\"name\":\"helios-kv\",\"type\":\"Microsoft.KeyVault/vaults\",\"location\":\"centralus\",\"resourceGroup\":\"rg-ai\",\"tags\":{}}]");
            }
            return new CommandResult(true, 1, string.Empty, "unexpected az command");
        }

        private static CommandResult Success(string output) => new(true, 0, output, string.Empty);
    }
}
