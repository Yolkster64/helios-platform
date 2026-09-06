using System.Text.Json;

namespace HELIOS.Fabric;

public sealed record FabricActivationStep(
    int Order,
    string Id,
    FabricReadinessState State,
    string Reason,
    bool Consequential,
    string? RequiredAuthority = null);

public sealed record FabricActivationPlan(
    string CurrentRepository,
    string TargetCoreRepository,
    string TargetGuiRepository,
    DateTimeOffset GeneratedAt,
    IReadOnlyList<FabricActivationStep> Steps,
    bool ProductionEnabled,
    bool ApplyDefault);

/// <summary>Builds a deterministic, non-mutating activation plan from the canonical fabric document.</summary>
public sealed class FabricActivationPlanBuilder
{
    public FabricActivationPlan Build(string repositoryRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(repositoryRoot);
        var path = Path.Combine(repositoryRoot, "config", "fabric", "helios-fabric.v1.json");
        using var document = JsonDocument.Parse(File.ReadAllBytes(path));
        var root = document.RootElement;
        var current = root.GetProperty("currentAuthority").GetProperty("repository").GetString() ?? string.Empty;
        var topology = root.GetProperty("targetTopology");
        var safety = root.GetProperty("safety");

        var steps = new List<FabricActivationStep>();
        var order = 0;
        foreach (var element in root.GetProperty("activationOrder").EnumerateArray())
        {
            var id = element.GetString() ?? string.Empty;
            var (consequential, authority) = Classify(id);
            steps.Add(new FabricActivationStep(
                ++order,
                id,
                FabricReadinessState.Blocked,
                consequential
                    ? $"Requires verified prerequisites and approval by {authority}."
                    : "Requires the preceding validation evidence.",
                consequential,
                authority));
        }

        return new FabricActivationPlan(
            current,
            topology.GetProperty("coreRepository").GetString() ?? string.Empty,
            topology.GetProperty("guiRepository").GetString() ?? string.Empty,
            DateTimeOffset.UtcNow,
            steps,
            safety.GetProperty("productionEnabled").GetBoolean(),
            safety.GetProperty("applyDefault").GetBoolean());
    }

    private static (bool Consequential, string? Authority) Classify(string id) => id switch
    {
        "repository-cutover-contract" or "current-main-ci" => (false, null),
        "in-place-core-rename" => (true, "GitHub repository administrator"),
        "winui3-gui-extraction" => (true, "GitHub repository owner and Windows code owner"),
        "github-environments-and-oidc" => (true, "GitHub and Azure administrators"),
        "azure-devops-wif" => (true, "Azure DevOps and Entra administrators"),
        "sharepoint-evidence-binding" => (true, "SharePoint governance owner"),
        "slack-linear-routing" => (true, "Slack workspace and Linear project owners"),
        "provider-secret-references" => (true, "provider project and Key Vault owners"),
        "development-what-if" => (true, "azure-dev-plan environment"),
        "separate-development-apply-approval" => (true, "azure-dev-deploy environment"),
        "independent-test-and-production-gates" => (true, "test and production environment owners"),
        _ => (true, "explicit owner")
    };
}
