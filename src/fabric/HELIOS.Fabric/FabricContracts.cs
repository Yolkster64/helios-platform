using System.Collections.ObjectModel;
using System.Text.Json.Serialization;

namespace HELIOS.Fabric;

/// <summary>Risk class for an operation proposed through the HELIOS fabric.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<FabricOperationClass>))]
public enum FabricOperationClass
{
    Read,
    Plan,
    Request,
    Act,
    Admin,
    Physical
}

/// <summary>Lifecycle state for a fabric activation step or external dependency.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<FabricReadinessState>))]
public enum FabricReadinessState
{
    Unknown,
    Ready,
    Degraded,
    Blocked
}

/// <summary>Immutable source identity carried by every plan or action.</summary>
public sealed record FabricSource(
    string Repository,
    string Commit,
    string? WorkflowRun = null);

/// <summary>Receipt proving a human or policy gate approved a consequential action.</summary>
public sealed record FabricApprovalReceipt(
    string ReceiptId,
    string ApprovedBy,
    DateTimeOffset ApprovedAt,
    string Scope,
    string SourceCommit,
    DateTimeOffset? ExpiresAt = null);

/// <summary>Receipt returned after a bounded external effect is independently verified.</summary>
public sealed record FabricResultReceipt(
    string ReceiptId,
    string Provider,
    string ResourceId,
    DateTimeOffset CompletedAt,
    string Status,
    string? EvidenceUri = null,
    string? Sha256 = null);

/// <summary>
/// Normalized envelope used by models, agents, MCP tools, workflows, and connector adapters.
/// It contains references and receipts only; secret values are never valid metadata.
/// </summary>
public sealed record FabricOperationEnvelope
{
    public required string EventId { get; init; }
    public required string CorrelationId { get; init; }
    public required string IdempotencyKey { get; init; }
    public required string Operation { get; init; }
    public required FabricOperationClass OperationClass { get; init; }
    public required string Classification { get; init; }
    public required FabricSource Source { get; init; }
    public DateTimeOffset RequestedAt { get; init; } = DateTimeOffset.UtcNow;
    public FabricApprovalReceipt? Approval { get; init; }
    public FabricResultReceipt? Result { get; init; }
    public IReadOnlyDictionary<string, string> Metadata { get; init; } =
        new ReadOnlyDictionary<string, string>(new Dictionary<string, string>());

    /// <summary>Returns deterministic contract violations without performing an external effect.</summary>
    public IReadOnlyList<string> Validate()
    {
        var errors = new List<string>();
        Require(EventId, nameof(EventId), errors);
        Require(CorrelationId, nameof(CorrelationId), errors);
        Require(IdempotencyKey, nameof(IdempotencyKey), errors);
        Require(Operation, nameof(Operation), errors);
        Require(Classification, nameof(Classification), errors);
        Require(Source.Repository, "Source.Repository", errors);
        Require(Source.Commit, "Source.Commit", errors);

        if (OperationClass is FabricOperationClass.Act or FabricOperationClass.Admin or FabricOperationClass.Physical)
        {
            if (Approval is null)
            {
                errors.Add($"{OperationClass} operations require an approval receipt.");
            }
            else
            {
                if (!StringComparer.Ordinal.Equals(Approval.SourceCommit, Source.Commit))
                {
                    errors.Add("Approval receipt source commit does not match the operation source commit.");
                }

                if (Approval.ExpiresAt is { } expiration && expiration <= RequestedAt)
                {
                    errors.Add("Approval receipt is expired for the requested operation time.");
                }
            }
        }

        foreach (var pair in Metadata)
        {
            if (SecretKeyClassifier.IsSensitiveName(pair.Key))
            {
                errors.Add($"Metadata key '{pair.Key}' is secret-like; use a managed reference instead.");
            }
        }

        return errors;
    }

    private static void Require(string? value, string name, ICollection<string> errors)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors.Add($"{name} is required.");
        }
    }
}

internal static class SecretKeyClassifier
{
    private static readonly string[] SensitiveFragments =
    [
        "PASSWORD", "SECRET", "TOKEN", "PRIVATE_KEY", "API_KEY", "CONNECTION_STRING"
    ];

    internal static bool IsSensitiveName(string name) =>
        SensitiveFragments.Any(fragment => name.Contains(fragment, StringComparison.OrdinalIgnoreCase));
}
