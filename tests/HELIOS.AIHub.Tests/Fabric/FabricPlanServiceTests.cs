using HELIOS.AIHub.Fabric;
using Xunit;

namespace HELIOS.AIHub.Tests.Fabric;

public sealed class FabricPlanServiceTests
{
    [Fact]
    public void BuildPlan_RenameGatesItems_WhenRenameNotCompleted()
    {
        var service = new FabricPlanService();
        var plan = service.BuildPlan(Contract(
            Item("schema", "done"),
            Item("oidc", "blocked", requiresRename: true),
            Item("what-if", "pending", requiresRename: true, dependsOn: new[] { "schema" })), renameCompleted: false);

        Assert.Equal(3, plan.Summary.Total);
        Assert.Equal(1, plan.Summary.Done);
        Assert.Equal(2, plan.Summary.Blocked);
        var oidc = Assert.Single(plan.Plan, entry => entry.Id == "oidc");
        Assert.Equal("blocked", oidc.EffectiveStatus);
        Assert.Contains("rename", oidc.BlockingReason!);
    }

    [Fact]
    public void BuildPlan_DependenciesBlockItems_UntilDone()
    {
        var service = new FabricPlanService();
        var plan = service.BuildPlan(Contract(
            Item("schema", "pending"),
            Item("catalog", "pending", dependsOn: new[] { "schema" })), renameCompleted: true);

        Assert.Equal(1, plan.Summary.Pending);
        Assert.Equal(1, plan.Summary.Blocked);
        var catalog = Assert.Single(plan.Plan, entry => entry.Id == "catalog");
        Assert.Equal("blocked", catalog.EffectiveStatus);
        Assert.Contains("schema", catalog.BlockingReason!);
    }

    [Fact]
    public void BuildPlan_RenameCompleted_UnblocksRenameItems_WhenDependenciesAreDone()
    {
        var service = new FabricPlanService();
        var plan = service.BuildPlan(Contract(
            Item("schema", "done"),
            Item("oidc", "in_progress", requiresRename: true, dependsOn: new[] { "schema" })), renameCompleted: true);

        var oidc = Assert.Single(plan.Plan, entry => entry.Id == "oidc");
        Assert.Equal("in_progress", oidc.EffectiveStatus);
        Assert.Null(oidc.BlockingReason);
    }

    [Fact]
    public void BuildPlan_UnknownStatus_DegradesToPending()
    {
        var service = new FabricPlanService();
        var plan = service.BuildPlan(Contract(Item("x", "mystery-status")), renameCompleted: true);

        var entry = Assert.Single(plan.Plan);
        Assert.Equal("pending", entry.DeclaredStatus);
        Assert.Equal("pending", entry.EffectiveStatus);
        Assert.Equal(1, plan.Summary.Pending);
    }

    private static FabricContract Contract(params FabricChecklistItem[] checklist) => new()
    {
        Version = 1,
        MigrationIssue = "HC-029",
        AzureActivation = new FabricAzureActivation
        {
            RenameTarget = "Yolkster64/helios-control",
        },
        Checklist = checklist,
    };

    private static FabricChecklistItem Item(
        string id,
        string status,
        bool requiresRename = false,
        string[]? dependsOn = null) =>
        new()
        {
            Id = id,
            Title = id,
            Status = status,
            Category = "validation",
            Owner = "test",
            RequiresRename = requiresRename,
            DependsOn = dependsOn ?? Array.Empty<string>(),
            ExternalAction = false,
        };
}
