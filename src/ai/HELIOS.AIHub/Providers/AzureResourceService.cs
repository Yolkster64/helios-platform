using System.Runtime.CompilerServices;
using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.Resources;

namespace HELIOS.AIHub.Providers;

/// <summary>The subscription an inventory was read from.</summary>
public sealed record AzureSubscriptionInfo(string SubscriptionId, string? DisplayName);

/// <summary>One resource group's identity (management-plane read, no properties).</summary>
public sealed record AzureResourceGroupInfo(string Name, string? Location);

/// <summary>One resource's identity: ARM id, name, type, location, owning group.</summary>
public sealed record AzureResourceInfo(
    string Id, string Name, string Type, string? Location, string? ResourceGroup);

/// <summary>
/// One resource group with the resources attributed to it by the subscription-level
/// scan. <see cref="ResourceCount"/> counts every scanned resource in the group;
/// <see cref="Resources"/> is capped per group, and <see cref="ResourcesTruncated"/>
/// says the cap dropped some — so a count larger than the list is explicit, never silent.
/// </summary>
public sealed record AzureResourceGroupInventory(
    string Name,
    string? Location,
    int ResourceCount,
    bool ResourcesTruncated,
    IReadOnlyList<AzureResourceInfo> Resources);

/// <summary>
/// Result of a read-only inventory. Unauthenticated is a state, not an error (the same
/// contract as <see cref="FoundryAgentListResult"/>'s Unconfigured): when
/// DefaultAzureCredential cannot produce a management-plane token,
/// <see cref="Authenticated"/> is false and <see cref="Hint"/> names the exact fix —
/// the call never throws for missing credentials.
/// </summary>
public sealed record AzureInventoryResult(
    bool Authenticated,
    string? Hint,
    AzureSubscriptionInfo? Subscription,
    int ResourceGroupCount,
    bool ResourceGroupsTruncated,
    bool ResourceScanTruncated,
    IReadOnlyList<AzureResourceGroupInventory> ResourceGroups);

/// <summary>
/// Minimal read-only seam over the ARM management plane, so inventory shaping is
/// testable without network or credentials (the <see cref="IFoundryAgentAdministration"/>
/// idiom). The only production implementation is <see cref="ArmResourceGateway"/>;
/// tests substitute a fake. Resources are listed at SUBSCRIPTION scope — one pageable
/// for the whole subscription instead of one HTTP call per resource group — and the
/// service attributes them to groups client-side via the resource id.
/// </summary>
public interface IAzureResourceGateway
{
    /// <summary>Resolves the named subscription, or the credential's default when null.</summary>
    Task<AzureSubscriptionInfo> ResolveSubscriptionAsync(string? subscriptionId, CancellationToken cancellationToken);

    /// <summary>Streams the subscription's resource groups (name + location).</summary>
    IAsyncEnumerable<AzureResourceGroupInfo> ListResourceGroupsAsync(string subscriptionId, CancellationToken cancellationToken);

    /// <summary>Streams every resource in the subscription (generic identity only).</summary>
    IAsyncEnumerable<AzureResourceInfo> ListResourcesAsync(string subscriptionId, CancellationToken cancellationToken);
}

/// <summary>
/// SDK-backed seam: ArmClient over DefaultAzureCredential, exactly like
/// <see cref="FoundryAgentAdministration"/>. Generic resources only — no typed
/// resource-provider packages, because id/name/type/location inventory does not need
/// them (see .claude/skills/csharp-orchestrator/references/azure-management-sdk.md).
/// The credential resolves lazily at the first REST call, not at construction, so
/// building this gateway never throws for missing credentials.
/// </summary>
public sealed class ArmResourceGateway : IAzureResourceGateway
{
    private readonly ArmClient _client = new(new DefaultAzureCredential());

    public async Task<AzureSubscriptionInfo> ResolveSubscriptionAsync(
        string? subscriptionId, CancellationToken cancellationToken)
    {
        SubscriptionResource subscription = subscriptionId is null
            ? await _client.GetDefaultSubscriptionAsync(cancellationToken).ConfigureAwait(false)
            : (await _client.GetSubscriptions().GetAsync(subscriptionId, cancellationToken).ConfigureAwait(false)).Value;
        return new AzureSubscriptionInfo(
            subscription.Data.SubscriptionId, subscription.Data.DisplayName);
    }

    public async IAsyncEnumerable<AzureResourceGroupInfo> ListResourceGroupsAsync(
        string subscriptionId, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        // CreateResourceIdentifier + GetSubscriptionResource builds the typed client
        // without another GET on the subscription the caller already resolved.
        var subscription = _client.GetSubscriptionResource(
            SubscriptionResource.CreateResourceIdentifier(subscriptionId));
        await foreach (ResourceGroupResource group in subscription.GetResourceGroups()
            .GetAllAsync(cancellationToken: cancellationToken)
            .ConfigureAwait(false))
        {
            yield return new AzureResourceGroupInfo(group.Data.Name, group.Data.Location.ToString());
        }
    }

    public async IAsyncEnumerable<AzureResourceInfo> ListResourcesAsync(
        string subscriptionId, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var subscription = _client.GetSubscriptionResource(
            SubscriptionResource.CreateResourceIdentifier(subscriptionId));
        await foreach (GenericResource resource in subscription
            .GetGenericResourcesAsync(cancellationToken: cancellationToken)
            .ConfigureAwait(false))
        {
            var data = resource.Data;
            yield return new AzureResourceInfo(
                data.Id.ToString(),
                data.Name,
                data.ResourceType.ToString(),
                data.Location.ToString(),
                data.Id.ResourceGroupName);
        }
    }
}

/// <summary>
/// Read-only inventory over the Azure management plane (Azure.ResourceManager) — the
/// service the MCP tool helios_azure_inventory_get wraps. Strictly non-mutating: it
/// resolves one subscription, lists resource groups, and lists resources; deployment
/// what-if is deliberately NOT wrapped yet (documented next step in
/// .claude/skills/csharp-orchestrator/references/azure-management-sdk.md). There is no
/// endpoint to configure — DefaultAzureCredential is the whole configuration — so the
/// degraded state here is Unauthenticated rather than Unconfigured, with the same
/// hint-not-exception contract as <see cref="FoundryAgentService"/>.
/// </summary>
public sealed class AzureResourceService
{
    /// <summary>Same remediation wording shape as <see cref="FoundryAgentService.UnconfiguredHint"/>.</summary>
    public const string UnauthenticatedHint =
        "Azure credentials are unavailable — DefaultAzureCredential could not get a management-plane token. " +
        "Run 'az login' (or set AZURE_TENANT_ID / AZURE_CLIENT_ID / AZURE_CLIENT_SECRET for a service principal), " +
        "then retry.";

    /// <summary>Caps for the resource-group list (count of groups returned).</summary>
    public const int MaxResourceGroups = 200;
    public const int DefaultResourceGroups = 50;

    /// <summary>Caps for the per-group resource list (ResourceCount still counts the rest).</summary>
    public const int MaxResourcesPerGroup = 100;
    public const int DefaultResourcesPerGroup = 25;

    /// <summary>
    /// Total-scan budget for the subscription-level resource enumeration, so one huge
    /// subscription cannot page forever. Hitting it sets ResourceScanTruncated: counts
    /// past this point are unknown, not zero.
    /// </summary>
    public const int ResourceScanBudget = 1000;

    private readonly Lazy<IAzureResourceGateway> _gateway;

    /// <summary>
    /// <paramref name="gatewayFactory"/> is the test seam; null uses the real SDK
    /// client. Lazy so no client/credential work happens until a tool actually runs.
    /// </summary>
    public AzureResourceService(Func<IAzureResourceGateway>? gatewayFactory = null)
    {
        _gateway = new Lazy<IAzureResourceGateway>(gatewayFactory ?? (() => new ArmResourceGateway()));
    }

    /// <summary>
    /// Inventories one subscription: resource groups plus their resources, with counts
    /// and truncation flags. Missing/failed credentials return a hint-carrying result
    /// instead of throwing; invalid caps throw before any gateway call. Transport and
    /// authorization failures (e.g. 403 with a valid token) still propagate as the
    /// SDK's RequestFailedException for the caller to convert.
    /// </summary>
    public async Task<AzureInventoryResult> GetInventoryAsync(
        string? subscriptionId = null,
        int maxResourceGroups = DefaultResourceGroups,
        int maxResourcesPerGroup = DefaultResourcesPerGroup,
        CancellationToken cancellationToken = default)
    {
        if (maxResourceGroups is < 1 or > MaxResourceGroups)
        {
            throw new ArgumentOutOfRangeException(
                nameof(maxResourceGroups), maxResourceGroups,
                $"maxResourceGroups must be between 1 and {MaxResourceGroups}.");
        }
        if (maxResourcesPerGroup is < 1 or > MaxResourcesPerGroup)
        {
            throw new ArgumentOutOfRangeException(
                nameof(maxResourcesPerGroup), maxResourcesPerGroup,
                $"maxResourcesPerGroup must be between 1 and {MaxResourcesPerGroup}.");
        }

        var requestedSubscription = string.IsNullOrWhiteSpace(subscriptionId) ? null : subscriptionId.Trim();

        try
        {
            var gateway = _gateway.Value;
            var subscription = await gateway
                .ResolveSubscriptionAsync(requestedSubscription, cancellationToken)
                .ConfigureAwait(false);

            // Resource groups, in service order, capped at the caller's budget.
            var groups = new List<AzureResourceGroupInfo>();
            var groupsTruncated = false;
            await foreach (var group in gateway
                .ListResourceGroupsAsync(subscription.SubscriptionId, cancellationToken)
                .ConfigureAwait(false))
            {
                if (groups.Count >= maxResourceGroups)
                {
                    groupsTruncated = true;
                    break;
                }
                groups.Add(group);
            }

            // One subscription-scope scan, attributed to groups client-side. Group
            // names are case-insensitive in ARM, hence the OrdinalIgnoreCase key.
            var byGroup = new Dictionary<string, (int Count, List<AzureResourceInfo> Kept)>(
                StringComparer.OrdinalIgnoreCase);
            var scanned = 0;
            var scanTruncated = false;
            await foreach (var resource in gateway
                .ListResourcesAsync(subscription.SubscriptionId, cancellationToken)
                .ConfigureAwait(false))
            {
                if (scanned >= ResourceScanBudget)
                {
                    scanTruncated = true;
                    break;
                }
                scanned++;
                if (resource.ResourceGroup is not { Length: > 0 } groupName)
                {
                    continue; // defensive: a subscription-scope id without a group
                }
                if (!byGroup.TryGetValue(groupName, out var bucket))
                {
                    bucket = (0, new List<AzureResourceInfo>());
                }
                bucket.Count++;
                if (bucket.Kept.Count < maxResourcesPerGroup)
                {
                    bucket.Kept.Add(resource);
                }
                byGroup[groupName] = bucket;
            }

            var inventories = new List<AzureResourceGroupInventory>(groups.Count);
            foreach (var group in groups)
            {
                byGroup.TryGetValue(group.Name, out var bucket);
                var kept = (IReadOnlyList<AzureResourceInfo>?)bucket.Kept ?? Array.Empty<AzureResourceInfo>();
                inventories.Add(new AzureResourceGroupInventory(
                    group.Name,
                    group.Location,
                    bucket.Count,
                    ResourcesTruncated: bucket.Count > kept.Count,
                    kept));
            }

            return new AzureInventoryResult(
                Authenticated: true,
                Hint: null,
                subscription,
                ResourceGroupCount: inventories.Count,
                ResourceGroupsTruncated: groupsTruncated,
                ResourceScanTruncated: scanTruncated,
                inventories);
        }
        catch (AuthenticationFailedException ex)
        {
            // Covers CredentialUnavailableException too (it derives from this): the
            // whole DefaultAzureCredential chain failed — expired az login/MFA, no
            // service-principal env vars, no managed identity. Same contract as
            // SecretResolver: bad auth is a state to report, never a crash.
            return new AzureInventoryResult(
                Authenticated: false,
                Hint: $"{UnauthenticatedHint} ({ex.Message.Split('\n')[0].TrimEnd()})",
                Subscription: null,
                ResourceGroupCount: 0,
                ResourceGroupsTruncated: false,
                ResourceScanTruncated: false,
                Array.Empty<AzureResourceGroupInventory>());
        }
    }
}
