using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using Azure;
using Azure.Identity;
using HELIOS.AIHub.Providers;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Azure AI Foundry persistent-agent administration tools — thin wrappers over
/// <see cref="FoundryAgentService"/> (HELIOS.AIHub), which owns validation, the
/// Unconfigured state, and response shaping so all of that is testable without MCP
/// plumbing. helios_foundry_agent_list is a pure read that degrades to a hint when
/// AZURE_FOUNDRY_PROJECT_ENDPOINT is unset; helios_foundry_agent_create is the tool
/// surface's one explicit mutation — exactly one create per call, never a retry.
/// </summary>
[McpServerToolType]
public static class HeliosFoundryTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    [McpServerTool(Name = "helios_foundry_agent_list", ReadOnly = true, Idempotent = true, OpenWorld = true)]
    [Description("List the persistent agents on the configured Azure AI Foundry project as JSON (id, name, model, created, description). Read-only. When AZURE_FOUNDRY_PROJECT_ENDPOINT is unset it returns { configured: false } with a fix hint instead of failing.")]
    public static async Task<string> ListFoundryAgents(
        FoundryAgentService foundry,
        [Description("Maximum number of agents to return, 1-100. Defaults to 50.")]
        int limit = FoundryAgentService.DefaultListLimit,
        CancellationToken cancellationToken = default)
    {
        FoundryAgentListResult result;
        try
        {
            result = await foundry.ListAgentsAsync(limit, cancellationToken);
        }
        catch (ArgumentOutOfRangeException)
        {
            throw new McpException($"limit must be between 1 and {FoundryAgentService.MaxListLimit}.");
        }
        catch (Exception ex) when (ex is RequestFailedException or AuthenticationFailedException)
        {
            throw new McpException(
                $"Foundry agent list failed: {ex.Message} — check that DefaultAzureCredential can reach the " +
                "project (e.g. run 'az login') and that AZURE_FOUNDRY_PROJECT_ENDPOINT is the project endpoint.");
        }

        if (!result.Configured)
        {
            return JsonSerializer.Serialize(new { configured = false, hint = result.Hint }, JsonOptions);
        }

        return JsonSerializer.Serialize(new
        {
            configured = true,
            count = result.Agents.Count,
            agents = result.Agents.Select(a => new
            {
                id = a.Id,
                name = a.Name,
                model = a.Model,
                created = a.Created,
                description = a.Description,
            }),
        }, JsonOptions);
    }

    [McpServerTool(Name = "helios_foundry_agent_create", ReadOnly = false, Destructive = false, Idempotent = false, OpenWorld = true)]
    [Description("Create ONE persistent agent on the configured Azure AI Foundry project and return its id/name/model as JSON. Explicit mutation: parameters are validated before any network call, exactly one create is issued, and nothing is retried or executed. Requires AZURE_FOUNDRY_PROJECT_ENDPOINT.")]
    public static async Task<string> CreateFoundryAgent(
        FoundryAgentService foundry,
        [Description("Display name for the new agent.")] string name,
        [Description("Model DEPLOYMENT name on the Foundry project (infra output 'modelDeploymentNames'), e.g. gpt-5-mini — not the bare model id.")] string model,
        [Description("System instructions the agent bakes in at creation.")] string instructions,
        [Description("Optional human-readable description of the agent.")] string? description = null,
        CancellationToken cancellationToken = default)
    {
        FoundryAgentSummary created;
        try
        {
            created = await foundry.CreateAgentAsync(name, model, instructions, description, cancellationToken);
        }
        catch (ArgumentException ex)
        {
            throw new McpException(ex.Message);
        }
        catch (InvalidOperationException ex)
        {
            // Unconfigured: actionable "Set X" message (FoundryAgentService.UnconfiguredHint).
            throw new McpException(ex.Message);
        }
        catch (Exception ex) when (ex is RequestFailedException or AuthenticationFailedException)
        {
            throw new McpException(
                $"Foundry agent create failed: {ex.Message} — verify the model deployment name exists on the " +
                "project and that DefaultAzureCredential has Azure AI User access (e.g. run 'az login'). " +
                "Check helios_foundry_agent_list before retrying: the create is not retried automatically " +
                "precisely so a transient failure cannot double-create.");
        }

        return JsonSerializer.Serialize(new
        {
            created = true,
            id = created.Id,
            name = created.Name,
            model = created.Model,
            createdAt = created.Created,
            description = created.Description,
        }, JsonOptions);
    }
}
