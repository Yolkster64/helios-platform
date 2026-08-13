using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using Azure;
using HELIOS.AIHub.Providers;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Azure management-plane inventory tool — a thin wrapper over
/// <see cref="AzureResourceService"/> (HELIOS.AIHub), which owns validation, the
/// Unauthenticated state, and response shaping so all of that is testable without MCP
/// plumbing. Strictly read-only: one subscription resolve, one resource-group list,
/// one subscription-scope resource list; nothing is created, changed, or deleted.
/// Missing/expired credentials degrade to { authenticated: false } with a fix hint
/// (the FoundryAgentService Unconfigured idiom) — never an exception.
/// </summary>
[McpServerToolType]
public static class HeliosAzureTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    [McpServerTool(Name = "helios_azure_inventory_get", ReadOnly = true, Idempotent = true, OpenWorld = true)]
    [Description("Read-only inventory of an Azure subscription via DefaultAzureCredential: subscription identity plus resource groups and their resources (id, name, type, location) as JSON with counts and truncation flags. Never mutates anything. Without working Azure credentials it returns { authenticated: false } with an actionable hint (run 'az login' or set service-principal env vars) instead of failing.")]
    public static async Task<string> GetAzureInventory(
        AzureResourceService azure,
        [Description("Subscription id (GUID) to inventory. Omit to use DefaultAzureCredential's default subscription.")]
        string? subscriptionId = null,
        [Description("Maximum resource groups to return, 1-200. Defaults to 50.")]
        int maxResourceGroups = AzureResourceService.DefaultResourceGroups,
        [Description("Maximum resources listed per group, 1-100 (each group's resourceCount still counts the rest). Defaults to 25.")]
        int maxResourcesPerGroup = AzureResourceService.DefaultResourcesPerGroup,
        CancellationToken cancellationToken = default)
    {
        AzureInventoryResult result;
        try
        {
            result = await azure.GetInventoryAsync(
                subscriptionId, maxResourceGroups, maxResourcesPerGroup, cancellationToken);
        }
        catch (ArgumentOutOfRangeException ex)
        {
            throw new McpException(
                $"{ex.ParamName}: {ex.Message.Split('\n')[0]} " +
                $"(maxResourceGroups 1-{AzureResourceService.MaxResourceGroups}, " +
                $"maxResourcesPerGroup 1-{AzureResourceService.MaxResourcesPerGroup}).");
        }
        catch (RequestFailedException ex)
        {
            // The credential produced a token but ARM rejected the call: wrong
            // subscription id, or the identity lacks read access. Distinct from the
            // unauthenticated state, which the service returns as a result.
            throw new McpException(
                $"Azure inventory failed: {ex.Status} {ex.ErrorCode} — {ex.Message.Split('\n')[0]} " +
                "Check the subscription id and that the signed-in identity has the Reader role " +
                "on it (az role assignment list --assignee <principal>).");
        }

        if (!result.Authenticated)
        {
            return JsonSerializer.Serialize(new { authenticated = false, hint = result.Hint }, JsonOptions);
        }

        return JsonSerializer.Serialize(new
        {
            authenticated = true,
            subscription = new
            {
                id = result.Subscription!.SubscriptionId,
                name = result.Subscription.DisplayName,
            },
            resourceGroupCount = result.ResourceGroupCount,
            resourceGroupsTruncated = result.ResourceGroupsTruncated,
            resourceScanTruncated = result.ResourceScanTruncated,
            resourceGroups = result.ResourceGroups.Select(group => new
            {
                name = group.Name,
                location = group.Location,
                resourceCount = group.ResourceCount,
                resourcesTruncated = group.ResourcesTruncated,
                resources = group.Resources.Select(resource => new
                {
                    id = resource.Id,
                    name = resource.Name,
                    type = resource.Type,
                    location = resource.Location,
                }),
            }),
        }, JsonOptions);
    }
}
