using System.Text.Json;
using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Fabric;

public sealed record FabricRequiredCheck
{
    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("result")]
    public string Result { get; init; } = "";

    [JsonPropertyName("evidenceRef")]
    public string EvidenceRef { get; init; } = "";
}

public sealed record FabricSourcePullRequest
{
    [JsonPropertyName("repository")]
    public string Repository { get; init; } = "";

    [JsonPropertyName("number")]
    public int Number { get; init; }

    [JsonPropertyName("mergeSha")]
    public string MergeSha { get; init; } = "";

    [JsonPropertyName("requiredChecks")]
    public IReadOnlyList<FabricRequiredCheck> RequiredChecks { get; init; } = Array.Empty<FabricRequiredCheck>();
}

public sealed record FabricSafetyState
{
    [JsonPropertyName("productionEnabled")]
    public bool ProductionEnabled { get; init; }

    [JsonPropertyName("applyDefault")]
    public bool ApplyDefault { get; init; }

    [JsonPropertyName("secretValuesInRepository")]
    public bool SecretValuesInRepository { get; init; }

    [JsonPropertyName("activeUiFramework")]
    public string ActiveUiFramework { get; init; } = "";
}

public sealed record FabricMcpVerification
{
    [JsonPropertyName("requiredTool")]
    public string RequiredTool { get; init; } = "";

    [JsonPropertyName("verificationMethod")]
    public string VerificationMethod { get; init; } = "";

    [JsonPropertyName("catalogReceiptPath")]
    public string CatalogReceiptPath { get; init; } = "";
}

public sealed record FabricSlackConnector
{
    [JsonPropertyName("workspaceId")]
    public string WorkspaceId { get; init; } = "";

    [JsonPropertyName("conversationId")]
    public string ConversationId { get; init; } = "";

    [JsonPropertyName("receiptPath")]
    public string ReceiptPath { get; init; } = "";
}

public sealed record FabricLinearConnector
{
    [JsonPropertyName("teamKey")]
    public string TeamKey { get; init; } = "";

    [JsonPropertyName("issueKey")]
    public string IssueKey { get; init; } = "";

    [JsonPropertyName("receiptPath")]
    public string ReceiptPath { get; init; } = "";
}

public sealed record FabricSharePointConnector
{
    [JsonPropertyName("documentRoot")]
    public string DocumentRoot { get; init; } = "";

    [JsonPropertyName("receiptPath")]
    public string ReceiptPath { get; init; } = "";
}

public sealed record FabricConnectors
{
    [JsonPropertyName("slack")]
    public FabricSlackConnector Slack { get; init; } = new();

    [JsonPropertyName("linear")]
    public FabricLinearConnector Linear { get; init; } = new();

    [JsonPropertyName("sharePoint")]
    public FabricSharePointConnector SharePoint { get; init; } = new();
}

public sealed record FabricWhatIfState
{
    [JsonPropertyName("apply")]
    public bool Apply { get; init; }

    [JsonPropertyName("planHash")]
    public string? PlanHash { get; init; }

    [JsonPropertyName("receiptPath")]
    public string ReceiptPath { get; init; } = "";

    [JsonPropertyName("lastRunUtc")]
    public string? LastRunUtc { get; init; }
}

public sealed record FabricAzureActivation
{
    [JsonPropertyName("requiresRepositoryRename")]
    public bool RequiresRepositoryRename { get; init; }

    [JsonPropertyName("renameTarget")]
    public string RenameTarget { get; init; } = "";

    [JsonPropertyName("oidcStatus")]
    public string OidcStatus { get; init; } = "";

    [JsonPropertyName("adoWifStatus")]
    public string AdoWifStatus { get; init; } = "";

    [JsonPropertyName("whatIf")]
    public FabricWhatIfState WhatIf { get; init; } = new();
}

public sealed record FabricChecklistItem
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("status")]
    public string Status { get; init; } = "";

    [JsonPropertyName("category")]
    public string Category { get; init; } = "";

    [JsonPropertyName("owner")]
    public string Owner { get; init; } = "";

    [JsonPropertyName("requiresRename")]
    public bool RequiresRename { get; init; }

    [JsonPropertyName("dependsOn")]
    public IReadOnlyList<string> DependsOn { get; init; } = Array.Empty<string>();

    [JsonPropertyName("externalAction")]
    public bool ExternalAction { get; init; }

    [JsonPropertyName("receiptRef")]
    public string? ReceiptRef { get; init; }

    [JsonPropertyName("notes")]
    public string? Notes { get; init; }
}

/// <summary>
/// Read-only contract view of config/fabric/helios-fabric.v1.json. It captures the
/// executable HC-029 activation checklist and gate state; mutation happens by editing
/// the JSON contract, never through code.
/// </summary>
public sealed record FabricContract
{
    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("migrationIssue")]
    public string MigrationIssue { get; init; } = "";

    [JsonPropertyName("sourcePullRequest")]
    public FabricSourcePullRequest SourcePullRequest { get; init; } = new();

    [JsonPropertyName("safetyState")]
    public FabricSafetyState SafetyState { get; init; } = new();

    [JsonPropertyName("mcp")]
    public FabricMcpVerification Mcp { get; init; } = new();

    [JsonPropertyName("connectors")]
    public FabricConnectors Connectors { get; init; } = new();

    [JsonPropertyName("azureActivation")]
    public FabricAzureActivation AzureActivation { get; init; } = new();

    [JsonPropertyName("checklist")]
    public IReadOnlyList<FabricChecklistItem> Checklist { get; init; } = Array.Empty<FabricChecklistItem>();

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    /// <summary>
    /// Finds config/fabric/helios-fabric.v1.json by walking up from the provided
    /// directory (or current directory and app base directory).
    /// </summary>
    public static string? FindContractFile(string? startDirectory = null)
    {
        var starts = startDirectory is not null
            ? new[] { startDirectory }
            : new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory };

        foreach (var start in starts)
        {
            var dir = new DirectoryInfo(start);
            while (dir is not null)
            {
                var candidate = Path.Combine(
                    dir.FullName, "config", "fabric", "helios-fabric.v1.json");
                if (File.Exists(candidate))
                {
                    return candidate;
                }
                dir = dir.Parent;
            }
        }
        return null;
    }

    /// <summary>
    /// Loads the Fabric contract and folds IO/parse failures into a status result so
    /// callers can report readiness gaps instead of crashing.
    /// </summary>
    public static FabricContractLoadResult TryLoad(string? path = null)
    {
        var resolved = path ?? FindContractFile();
        if (resolved is null)
        {
            return new FabricContractLoadResult
            {
                Error = "config/fabric/helios-fabric.v1.json not found in this directory or any parent; "
                        + "run from the repo checkout or pass an explicit path.",
            };
        }
        if (!File.Exists(resolved))
        {
            return new FabricContractLoadResult
            {
                Path = resolved,
                Error = $"Fabric contract '{resolved}' does not exist.",
            };
        }

        try
        {
            using var stream = File.OpenRead(resolved);
            var contract = JsonSerializer.Deserialize<FabricContract>(stream, ReadOptions);
            return contract is null
                ? new FabricContractLoadResult
                {
                    Path = resolved,
                    Error = $"'{resolved}' deserialized to null.",
                }
                : new FabricContractLoadResult { Path = resolved, Contract = contract };
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return new FabricContractLoadResult
            {
                Path = resolved,
                Error = $"Failed to read '{resolved}': {ex.Message}",
            };
        }
    }
}

public sealed record FabricContractLoadResult
{
    public FabricContract? Contract { get; init; }

    public string? Path { get; init; }

    public string? Error { get; init; }
}
