using HELIOS.Fabric;

namespace HELIOS.Fabric.Tests;

public sealed class FabricOperationEnvelopeTests
{
    [Fact]
    public void Plan_operation_does_not_require_approval()
    {
        var envelope = Create(FabricOperationClass.Plan);

        Assert.Empty(envelope.Validate());
    }

    [Fact]
    public void Act_operation_requires_approval()
    {
        var envelope = Create(FabricOperationClass.Act);

        Assert.Contains(envelope.Validate(), error => error.Contains("approval receipt", StringComparison.Ordinal));
    }

    [Fact]
    public void Approval_must_match_source_commit()
    {
        var envelope = Create(FabricOperationClass.Act) with
        {
            Approval = new FabricApprovalReceipt(
                "approval-1",
                "owner",
                DateTimeOffset.UtcNow,
                "dev",
                "different-commit")
        };

        Assert.Contains(envelope.Validate(), error => error.Contains("source commit", StringComparison.Ordinal));
    }

    [Fact]
    public void Secret_like_metadata_is_rejected()
    {
        var envelope = Create(FabricOperationClass.Plan) with
        {
            Metadata = new Dictionary<string, string>
            {
                ["OPENAI_API_KEY"] = "reference-not-value"
            }
        };

        Assert.Contains(envelope.Validate(), error => error.Contains("secret-like", StringComparison.Ordinal));
    }

    private static FabricOperationEnvelope Create(FabricOperationClass operationClass) => new()
    {
        EventId = "event-1",
        CorrelationId = "correlation-1",
        IdempotencyKey = "idempotency-1",
        Operation = "test",
        OperationClass = operationClass,
        Classification = "internal",
        Source = new FabricSource("Yolkster64/helios-platform", new string('a', 40))
    };
}
