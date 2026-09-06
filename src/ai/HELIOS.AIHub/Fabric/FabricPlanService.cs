using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Fabric;

public sealed record FabricPlanEntry
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("category")]
    public string Category { get; init; } = "";

    [JsonPropertyName("owner")]
    public string Owner { get; init; } = "";

    [JsonPropertyName("declaredStatus")]
    public string DeclaredStatus { get; init; } = "";

    [JsonPropertyName("effectiveStatus")]
    public string EffectiveStatus { get; init; } = "";

    [JsonPropertyName("requiresRename")]
    public bool RequiresRename { get; init; }

    [JsonPropertyName("externalAction")]
    public bool ExternalAction { get; init; }

    [JsonPropertyName("dependsOn")]
    public IReadOnlyList<string> DependsOn { get; init; } = Array.Empty<string>();

    [JsonPropertyName("receiptRef")]
    public string? ReceiptRef { get; init; }

    [JsonPropertyName("notes")]
    public string? Notes { get; init; }

    [JsonPropertyName("blockingReason")]
    public string? BlockingReason { get; init; }
}

public sealed record FabricPlanSummary
{
    [JsonPropertyName("total")]
    public int Total { get; init; }

    [JsonPropertyName("pending")]
    public int Pending { get; init; }

    [JsonPropertyName("inProgress")]
    public int InProgress { get; init; }

    [JsonPropertyName("blocked")]
    public int Blocked { get; init; }

    [JsonPropertyName("done")]
    public int Done { get; init; }

    [JsonPropertyName("externalActions")]
    public int ExternalActions { get; init; }
}

public sealed record FabricPlanResult
{
    [JsonPropertyName("summary")]
    public FabricPlanSummary Summary { get; init; } = new();

    [JsonPropertyName("plan")]
    public IReadOnlyList<FabricPlanEntry> Plan { get; init; } = Array.Empty<FabricPlanEntry>();

    [JsonPropertyName("nextActions")]
    public IReadOnlyList<string> NextActions { get; init; } = Array.Empty<string>();

    [JsonPropertyName("message")]
    public string? Message { get; init; }
}

/// <summary>
/// Builds an advisory execution view over the HC-029 Fabric checklist.
/// It never mutates config; it only explains what can run now and what is gated.
/// </summary>
public sealed class FabricPlanService
{
    public const string Pending = "pending";
    public const string InProgress = "in_progress";
    public const string Blocked = "blocked";
    public const string Done = "done";

    public const string AdvisoryNote =
        "Advisory only — this plan reports contract readiness and does not perform " +
        "Slack/Linear/SharePoint writes, repository rename, OIDC/WIF changes, Azure " +
        "what-if, deployment, or rollback actions.";

    public FabricPlanResult BuildPlan(FabricContract contract, bool renameCompleted = false)
    {
        var normalizedById = contract.Checklist
            .Where(item => !string.IsNullOrWhiteSpace(item.Id))
            .ToDictionary(item => item.Id, item => NormalizeStatus(item.Status), StringComparer.Ordinal);

        var entries = new List<FabricPlanEntry>(contract.Checklist.Count);
        foreach (var item in contract.Checklist)
        {
            var declared = NormalizeStatus(item.Status);
            var effective = declared;
            string? blockingReason = null;

            if (declared != Done && item.RequiresRename && !renameCompleted)
            {
                effective = Blocked;
                var target = string.IsNullOrWhiteSpace(contract.AzureActivation.RenameTarget)
                    ? "Yolkster64/helios-control"
                    : contract.AzureActivation.RenameTarget;
                blockingReason = $"Blocked until repository rename to {target} completes.";
            }

            var unmet = item.DependsOn
                .Where(dep => normalizedById.TryGetValue(dep, out var state) ? state != Done : true)
                .ToArray();
            if (effective != Done && unmet.Length > 0)
            {
                effective = Blocked;
                blockingReason = unmet.Length == 1
                    ? $"Blocked by incomplete dependency '{unmet[0]}'."
                    : $"Blocked by incomplete dependencies: {string.Join(", ", unmet)}.";
            }

            if (effective == Blocked && string.IsNullOrWhiteSpace(blockingReason) && !string.IsNullOrWhiteSpace(item.Notes))
            {
                blockingReason = item.Notes;
            }

            entries.Add(new FabricPlanEntry
            {
                Id = item.Id,
                Title = item.Title,
                Category = item.Category,
                Owner = item.Owner,
                DeclaredStatus = declared,
                EffectiveStatus = effective,
                RequiresRename = item.RequiresRename,
                ExternalAction = item.ExternalAction,
                DependsOn = item.DependsOn,
                ReceiptRef = item.ReceiptRef,
                Notes = item.Notes,
                BlockingReason = blockingReason,
            });
        }

        var summary = new FabricPlanSummary
        {
            Total = entries.Count,
            Pending = entries.Count(entry => entry.EffectiveStatus == Pending),
            InProgress = entries.Count(entry => entry.EffectiveStatus == InProgress),
            Blocked = entries.Count(entry => entry.EffectiveStatus == Blocked),
            Done = entries.Count(entry => entry.EffectiveStatus == Done),
            ExternalActions = entries.Count(entry => entry.ExternalAction && entry.EffectiveStatus != Done),
        };

        var nextActions = entries
            .Where(entry => entry.EffectiveStatus != Done)
            .Select(FormatNextAction)
            .Take(8)
            .ToArray();

        return new FabricPlanResult
        {
            Summary = summary,
            Plan = entries,
            NextActions = nextActions,
            Message = entries.Count == 0
                ? "The Fabric contract checklist is empty — nothing to execute."
                : null,
        };
    }

    private static string NormalizeStatus(string? status)
    {
        var normalized = (status ?? Pending).Trim().ToLowerInvariant().Replace('-', '_');
        return normalized switch
        {
            Pending => Pending,
            InProgress => InProgress,
            Blocked => Blocked,
            Done => Done,
            _ => Pending,
        };
    }

    private static string FormatNextAction(FabricPlanEntry entry)
    {
        var owner = string.IsNullOrWhiteSpace(entry.Owner) ? "owner-unset" : entry.Owner;
        var reason = entry.EffectiveStatus == Blocked && !string.IsNullOrWhiteSpace(entry.BlockingReason)
            ? $" ({entry.BlockingReason})"
            : "";
        return $"[{entry.EffectiveStatus}] {entry.Id} -> {owner}{reason}";
    }
}
