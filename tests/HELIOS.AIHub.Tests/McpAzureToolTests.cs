using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using Azure.Identity;
using HELIOS.AIHub.Providers;
using HELIOS.Mcp;
using ModelContextProtocol;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The Azure management-plane inventory MCP tool (helios_azure_inventory_get) and its
/// service seam. Keyless-deterministic: everything runs against a scripted
/// <see cref="IAzureResourceGateway"/> fake or a gateway that fails authentication the
/// way DefaultAzureCredential does — no credentials, no network, ever.
/// </summary>
public sealed class McpAzureToolTests
{
    private const string Sub = "00000000-0000-0000-0000-000000000001";

    // ---- discoverability -----------------------------------------------------------

    [Fact]
    public void InventoryTool_IsDiscoverable_ReadOnlyIdempotentOpenWorld()
    {
        var method = typeof(HeliosAzureTools).GetMethod(
            nameof(HeliosAzureTools.GetAzureInventory), BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal("helios_azure_inventory_get", attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(true, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("Idempotent")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("OpenWorld")?.GetValue(toolAttribute));
    }

    // ---- unauthenticated state -----------------------------------------------------

    [Fact]
    public async Task InventoryTool_CredentialChainFails_ReturnsHint_NeverThrows()
    {
        // CredentialUnavailableException is what a fully exhausted DefaultAzureCredential
        // chain throws (it derives from AuthenticationFailedException).
        var service = new AzureResourceService(() => new FakeAzureResourceGateway
        {
            AuthenticationFailure = new CredentialUnavailableException(
                "DefaultAzureCredential failed to retrieve a token from the included credentials."),
        });

        var json = await HeliosAzureTools.GetAzureInventory(service);
        using var document = JsonDocument.Parse(json);

        Assert.False(document.RootElement.GetProperty("authenticated").GetBoolean());
        var hint = document.RootElement.GetProperty("hint").GetString();
        Assert.Contains("az login", hint);
        Assert.StartsWith(AzureResourceService.UnauthenticatedHint, hint);
    }

    [Fact]
    public async Task Service_AuthenticationFailed_ReturnsUnauthenticatedResult()
    {
        var service = new AzureResourceService(() => new FakeAzureResourceGateway
        {
            AuthenticationFailure = new AuthenticationFailedException("expired token (MFA required)"),
        });

        var result = await service.GetInventoryAsync();

        Assert.False(result.Authenticated);
        Assert.Contains("az login", result.Hint);
        Assert.Contains("expired token (MFA required)", result.Hint);
        Assert.Null(result.Subscription);
        Assert.Empty(result.ResourceGroups);
    }

    // ---- parameter validation (before any seam/network call) ------------------------

    [Theory]
    [InlineData(0, 25)]
    [InlineData(-1, 25)]
    [InlineData(201, 25)]
    [InlineData(50, 0)]
    [InlineData(50, -5)]
    [InlineData(50, 101)]
    public async Task InventoryTool_InvalidCaps_Throws_WithoutTouchingSeam(
        int maxResourceGroups, int maxResourcesPerGroup)
    {
        var fake = new FakeAzureResourceGateway();
        var service = new AzureResourceService(() => fake);

        await Assert.ThrowsAsync<McpException>(() => HeliosAzureTools.GetAzureInventory(
            service, maxResourceGroups: maxResourceGroups, maxResourcesPerGroup: maxResourcesPerGroup));

        Assert.Equal(0, fake.ResolveCalls);
    }

    // ---- subscription resolution ---------------------------------------------------

    [Theory]
    [InlineData(null, null)]
    [InlineData("", null)]
    [InlineData("   ", null)]
    [InlineData("  " + Sub + " ", Sub)]
    public async Task Service_PassesTrimmedSubscription_BlankMeansDefault(
        string? requested, string? expectedAtGateway)
    {
        var fake = new FakeAzureResourceGateway();
        var service = new AzureResourceService(() => fake);

        var result = await service.GetInventoryAsync(requested);

        Assert.True(result.Authenticated);
        var call = Assert.Single(fake.ResolvedSubscriptionIds);
        Assert.Equal(expectedAtGateway, call);
        Assert.Equal(Sub, result.Subscription!.SubscriptionId);
    }

    // ---- response shaping through the fake seam -------------------------------------

    [Fact]
    public async Task InventoryTool_ShapesGroupsAndResources_AsIdNameTypeLocation()
    {
        var fake = new FakeAzureResourceGateway
        {
            Groups =
            {
                new AzureResourceGroupInfo("helios-rg", "eastus2"),
                new AzureResourceGroupInfo("empty-rg", "westus3"),
            },
            Resources =
            {
                NewResource("helios-rg", "helios-foundry", "Microsoft.CognitiveServices/accounts", "eastus2"),
                NewResource("helios-rg", "helios-kv", "Microsoft.KeyVault/vaults", "eastus2"),
            },
        };
        var service = new AzureResourceService(() => fake);

        var json = await HeliosAzureTools.GetAzureInventory(service);
        using var document = JsonDocument.Parse(json);

        var root = document.RootElement;
        Assert.True(root.GetProperty("authenticated").GetBoolean());
        Assert.Equal(Sub, root.GetProperty("subscription").GetProperty("id").GetString());
        Assert.Equal("HELIOS Dev", root.GetProperty("subscription").GetProperty("name").GetString());
        Assert.Equal(2, root.GetProperty("resourceGroupCount").GetInt32());
        Assert.False(root.GetProperty("resourceGroupsTruncated").GetBoolean());
        Assert.False(root.GetProperty("resourceScanTruncated").GetBoolean());

        var groups = root.GetProperty("resourceGroups");
        var first = groups[0];
        Assert.Equal("helios-rg", first.GetProperty("name").GetString());
        Assert.Equal("eastus2", first.GetProperty("location").GetString());
        Assert.Equal(2, first.GetProperty("resourceCount").GetInt32());
        Assert.False(first.GetProperty("resourcesTruncated").GetBoolean());
        var resource = first.GetProperty("resources")[0];
        Assert.Equal("helios-foundry", resource.GetProperty("name").GetString());
        Assert.Equal("Microsoft.CognitiveServices/accounts", resource.GetProperty("type").GetString());
        Assert.Equal("eastus2", resource.GetProperty("location").GetString());
        Assert.StartsWith($"/subscriptions/{Sub}/resourceGroups/helios-rg/", resource.GetProperty("id").GetString());

        var empty = groups[1];
        Assert.Equal(0, empty.GetProperty("resourceCount").GetInt32());
        Assert.Equal(0, empty.GetProperty("resources").GetArrayLength());
    }

    [Fact]
    public async Task Service_CapsGroupList_AndFlagsTruncation()
    {
        var fake = new FakeAzureResourceGateway();
        for (var i = 0; i < 5; i++)
        {
            fake.Groups.Add(new AzureResourceGroupInfo($"rg-{i}", "eastus2"));
        }
        var service = new AzureResourceService(() => fake);

        var result = await service.GetInventoryAsync(maxResourceGroups: 3);

        Assert.Equal(3, result.ResourceGroupCount);
        Assert.Equal(3, result.ResourceGroups.Count);
        Assert.True(result.ResourceGroupsTruncated);
        Assert.False(result.ResourceScanTruncated);
    }

    [Fact]
    public async Task Service_CapsResourcesPerGroup_ButCountsEverythingScanned()
    {
        var fake = new FakeAzureResourceGateway
        {
            Groups = { new AzureResourceGroupInfo("busy-rg", "eastus2") },
        };
        for (var i = 0; i < 7; i++)
        {
            fake.Resources.Add(NewResource("busy-rg", $"res-{i}", "Microsoft.Storage/storageAccounts", "eastus2"));
        }
        var service = new AzureResourceService(() => fake);

        var result = await service.GetInventoryAsync(maxResourcesPerGroup: 4);

        var group = Assert.Single(result.ResourceGroups);
        Assert.Equal(7, group.ResourceCount);
        Assert.Equal(4, group.Resources.Count);
        Assert.True(group.ResourcesTruncated);
    }

    [Fact]
    public async Task Service_StopsScanning_AtBudget_AndFlagsIt()
    {
        var fake = new FakeAzureResourceGateway
        {
            Groups = { new AzureResourceGroupInfo("big-rg", "eastus2") },
        };
        for (var i = 0; i < AzureResourceService.ResourceScanBudget + 5; i++)
        {
            fake.Resources.Add(NewResource("big-rg", $"res-{i}", "Microsoft.Compute/disks", "eastus2"));
        }
        var service = new AzureResourceService(() => fake);

        var result = await service.GetInventoryAsync(maxResourcesPerGroup: 1);

        Assert.True(result.ResourceScanTruncated);
        var group = Assert.Single(result.ResourceGroups);
        Assert.Equal(AzureResourceService.ResourceScanBudget, group.ResourceCount);
    }

    [Fact]
    public async Task Service_MatchesGroupNames_CaseInsensitively()
    {
        // ARM resource-group names are case-insensitive, and resource ids do not
        // always preserve the casing the group was created with.
        var fake = new FakeAzureResourceGateway
        {
            Groups = { new AzureResourceGroupInfo("Helios-RG", "eastus2") },
            Resources = { NewResource("helios-rg", "helios-search", "Microsoft.Search/searchServices", "eastus2") },
        };
        var service = new AzureResourceService(() => fake);

        var result = await service.GetInventoryAsync();

        var group = Assert.Single(result.ResourceGroups);
        Assert.Equal(1, group.ResourceCount);
        Assert.Equal("helios-search", Assert.Single(group.Resources).Name);
    }

    private static AzureResourceInfo NewResource(string group, string name, string type, string location) =>
        new(
            $"/subscriptions/{Sub}/resourceGroups/{group}/providers/{type}/{name}",
            name,
            type,
            location,
            group);

    /// <summary>Scriptable seam: hand-rolled fake per the repo's no-Moq idiom.</summary>
    private sealed class FakeAzureResourceGateway : IAzureResourceGateway
    {
        public List<AzureResourceGroupInfo> Groups { get; } = new();

        public List<AzureResourceInfo> Resources { get; } = new();

        /// <summary>When set, every gateway entry point throws it (credential-chain failure).</summary>
        public AuthenticationFailedException? AuthenticationFailure { get; init; }

        public List<string?> ResolvedSubscriptionIds { get; } = new();

        public int ResolveCalls => ResolvedSubscriptionIds.Count;

        public Task<AzureSubscriptionInfo> ResolveSubscriptionAsync(
            string? subscriptionId, CancellationToken cancellationToken)
        {
            if (AuthenticationFailure is not null)
            {
                throw AuthenticationFailure;
            }
            ResolvedSubscriptionIds.Add(subscriptionId);
            return Task.FromResult(new AzureSubscriptionInfo(subscriptionId ?? Sub, "HELIOS Dev"));
        }

        public async IAsyncEnumerable<AzureResourceGroupInfo> ListResourceGroupsAsync(
            string subscriptionId, [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            foreach (var group in Groups)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return group;
            }
            await Task.CompletedTask;
        }

        public async IAsyncEnumerable<AzureResourceInfo> ListResourcesAsync(
            string subscriptionId, [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            foreach (var resource in Resources)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return resource;
            }
            await Task.CompletedTask;
        }
    }
}
