using HELIOS.Fabric;

namespace HELIOS.Fabric.Tests;

public sealed class FabricActivationPlanTests
{
    [Fact]
    public void Canonical_repository_targets_are_loaded_from_contract()
    {
        var root = FindRepositoryRoot();
        var plan = new FabricActivationPlanBuilder().Build(root);

        Assert.Equal("Yolkster64/helios-platform", plan.CurrentRepository);
        Assert.Equal("Yolkster64/helios-control", plan.TargetCoreRepository);
        Assert.Equal("Yolkster64/helios-gui", plan.TargetGuiRepository);
        Assert.False(plan.ProductionEnabled);
        Assert.False(plan.ApplyDefault);
        Assert.NotEmpty(plan.Steps);
        Assert.All(plan.Steps, step => Assert.Equal(FabricReadinessState.Blocked, step.State));
    }

    [Fact]
    public void Repository_rename_is_classified_as_consequential_admin_work()
    {
        var plan = new FabricActivationPlanBuilder().Build(FindRepositoryRoot());
        var rename = Assert.Single(plan.Steps, step => step.Id == "in-place-core-rename");

        Assert.True(rename.Consequential);
        Assert.Contains("administrator", rename.RequiredAuthority, StringComparison.OrdinalIgnoreCase);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "config", "fabric", "helios-fabric.v1.json")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Repository root not found from test output path.");
    }
}
