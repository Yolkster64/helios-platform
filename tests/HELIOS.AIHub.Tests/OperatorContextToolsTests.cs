using System.Reflection;
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

        public Task<CommandResult> RunAsync(
            string fileName,
            IReadOnlyList<string> arguments,
            TimeSpan timeout,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (fileName == "git")
            {
                return Task.FromResult(Git(arguments));
            }
            if (fileName == "az")
            {
                return Task.FromResult(Azure(arguments));
            }
            return Task.FromResult(CommandResult.NotStarted);
        }

        private static CommandResult Git(IReadOnlyList<string> arguments)
        {
            var command = arguments.Skip(2).ToArray();
            return command switch
            {
                ["branch", "--show-current"] => Success("integration/claude-code-operator-plugin\n"),
                ["rev-parse", "HEAD"] => Success("0123456789abcdef\n"),
                ["remote", "get-url", "origin"] => Success("git@github.com:Yolkster64/helios-platform.git\n"),
                ["status", "--porcelain=v1"] => Success(string.Empty),
                _ => new CommandResult(true, 1, string.Empty, "unexpected git command"),
            };
        }

        private CommandResult Azure(IReadOnlyList<string> arguments)
        {
            if (arguments.Take(2).SequenceEqual(new[] { "account", "show" }))
            {
                return Success("{\"id\":\"sub-1\",\"name\":\"HELIOS Dev\",\"tenantId\":\"tenant-1\",\"state\":\"Enabled\"}");
            }
            if (arguments.Take(2).SequenceEqual(new[] { "group", "list" }))
            {
                return Success(SnapshotVersion == 1
                    ? "[{\"name\":\"rg-core\",\"location\":\"southcentralus\",\"provisioningState\":\"Succeeded\",\"tags\":{\"api-key\":\"" + CredentialLike + "\",\"project\":\"helios\"}}]"
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
