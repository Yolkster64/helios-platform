using System.Reflection;
using System.Text.Json;
using HELIOS.Mcp;
using Xunit;

namespace HELIOS.AIHub.Tests;

public sealed class McpFabricPlanToolTests : IDisposable
{
    private readonly List<string> _roots = new();

    public void Dispose()
    {
        foreach (var root in _roots)
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    [Fact]
    public void FabricPlanTool_IsDiscoverable_ReadOnlyIdempotentClosedWorld()
    {
        var method = typeof(HeliosFabricPlanTools).GetMethod(
            nameof(HeliosFabricPlanTools.GetFabricPlan), BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal("helios_fabric_plan_get", attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(true, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("Idempotent")?.GetValue(toolAttribute));
        Assert.Equal(false, attributeType.GetProperty("OpenWorld")?.GetValue(toolAttribute));
    }

    [Fact]
    public void FabricPlan_BuildsSummary_AndNextActions()
    {
        var contractPath = WriteContract("""
            {
              "version": 1,
              "migrationIssue": "HC-029",
              "sourcePullRequest": {
                "repository": "Yolkster64/helios-platform",
                "number": 154,
                "mergeSha": "pending",
                "requiredChecks": [
                  { "name": "CI", "result": "pending", "evidenceRef": "docs" }
                ]
              },
              "safetyState": {
                "productionEnabled": false,
                "applyDefault": false,
                "secretValuesInRepository": false,
                "activeUiFramework": "WinUI 3"
              },
              "mcp": {
                "requiredTool": "helios_fabric_plan_get",
                "verificationMethod": "stdio-jsonrpc-tools-list",
                "catalogReceiptPath": "docs"
              },
              "connectors": {
                "slack": { "workspaceId": "T0BAFGSNY5P", "conversationId": "D0BB80HRZFA", "receiptPath": "docs" },
                "linear": { "teamKey": "JOH", "issueKey": "JOH-208", "receiptPath": "docs" },
                "sharePoint": { "documentRoot": "Helios/Governance", "receiptPath": "docs" }
              },
              "azureActivation": {
                "requiresRepositoryRename": true,
                "renameTarget": "Yolkster64/helios-control",
                "oidcStatus": "blocked-by-rename",
                "adoWifStatus": "blocked-by-rename",
                "whatIf": { "apply": false, "planHash": null, "receiptPath": "docs", "lastRunUtc": null }
              },
              "checklist": [
                {
                  "id": "schema",
                  "title": "Schema validated",
                  "status": "done",
                  "category": "schema",
                  "owner": "copilot",
                  "requiresRename": false,
                  "dependsOn": [],
                  "externalAction": false,
                  "receiptRef": "scripts/validation/validate_helios_fabric_contract.py"
                },
                {
                  "id": "oidc",
                  "title": "Configure OIDC",
                  "status": "in_progress",
                  "category": "azure",
                  "owner": "repo-owner",
                  "requiresRename": true,
                  "dependsOn": ["schema"],
                  "externalAction": true
                }
              ]
            }
            """);

        var json = HeliosFabricPlanTools.GetFabricPlan(contractPath, renameCompleted: false);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal("HC-029", doc.RootElement.GetProperty("migrationIssue").GetString());
        var summary = doc.RootElement.GetProperty("summary");
        Assert.Equal(2, summary.GetProperty("total").GetInt32());
        Assert.Equal(1, summary.GetProperty("done").GetInt32());
        Assert.Equal(1, summary.GetProperty("blocked").GetInt32());
        Assert.Equal(1, summary.GetProperty("externalActions").GetInt32());
        Assert.Contains(
            "Advisory only",
            doc.RootElement.GetProperty("advisory").GetString());
        var blocked = doc.RootElement.GetProperty("plan").EnumerateArray()
            .Single(row => row.GetProperty("id").GetString() == "oidc");
        Assert.Equal("blocked", blocked.GetProperty("effectiveStatus").GetString());
        Assert.True(doc.RootElement.GetProperty("nextActions").GetArrayLength() >= 1);
    }

    [Fact]
    public void FabricPlan_MissingContract_ReturnsMessage_NotException()
    {
        var path = Path.Combine(CreateDirectory(), "missing-fabric.json");
        var json = HeliosFabricPlanTools.GetFabricPlan(path, renameCompleted: false);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("total").GetInt32());
        Assert.Contains(path, doc.RootElement.GetProperty("message").GetString());
    }

    private string WriteContract(string json)
    {
        var path = Path.Combine(CreateDirectory(), "helios-fabric.v1.json");
        File.WriteAllText(path, json);
        return path;
    }

    private string CreateDirectory()
    {
        var root = Path.Combine(Path.GetTempPath(), $"helios-mcp-fabric-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        _roots.Add(root);
        return root;
    }
}
