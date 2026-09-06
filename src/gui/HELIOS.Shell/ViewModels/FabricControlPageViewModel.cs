using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;

namespace HELIOS.Shell.ViewModels;

/// <summary>
/// Read-only operator view over the HELIOS Fabric integration seams. This page never
/// reads or renders secret values and never mutates Azure/GitHub configuration itself;
/// it exposes the governed bootstrap/verify commands and links to the authoritative
/// control-plane surfaces.
/// </summary>
public partial class FabricControlPageViewModel : ObservableObject
{
    private const string RepositoryUrl = "https://github.com/Yolkster64/helios-platform";
    private const string ClaudeWorkflowUrl = RepositoryUrl + "/actions/workflows/claude-foundry.yml";
    private const string ClaudeIssueUrl = RepositoryUrl + "/issues/146";
    private const string ClaudePrUrl = RepositoryUrl + "/pull/152";
    private const string AzurePortalUrl = "https://portal.azure.com/#home";

    [ObservableProperty]
    private string _statusMessage = "Fabric readiness has not been refreshed yet.";

    public ObservableCollection<FabricIntegrationItemViewModel> Integrations { get; } = [];

    public string BootstrapCommand =>
        "pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 -Repo Yolkster64/helios-platform";

    public string VerifyCommand =>
        "pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 -Repo Yolkster64/helios-platform -VerifyOnly -SkipGitHubVariables";

    [RelayCommand]
    private void Refresh()
    {
        Integrations.Clear();

        var dedicatedOidc = HasAll(
            "CLAUDE_AZURE_CLIENT_ID",
            "CLAUDE_AZURE_TENANT_ID",
            "CLAUDE_AZURE_SUBSCRIPTION_ID");
        var compatibilityOidc = HasAll("AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID");
        var foundryResource = Environment.GetEnvironmentVariable("ANTHROPIC_FOUNDRY_RESOURCE");
        var hasFoundry = !string.IsNullOrWhiteSpace(foundryResource);
        var hasKeyVault = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("AZURE_KEY_VAULT_URI"));
        var hasOpenAiCredential = HasAny("OPENAI_API_KEY", "AZURE_OPENAI_API_KEY") || hasKeyVault;
        var brokerUrl = FirstNonEmpty("HELIOS_INTEGRATION_BROKER_URL", "HELIOS_BROKER_URL");
        var apiUrl = FirstNonEmpty("HELIOS_API_URL") ?? "http://localhost:5170";

        Integrations.Add(new(
            "GitHub control plane",
            "Ready",
            "Yolkster64/helios-platform is the engineering source of truth; Claude, Codex, CI, and OIDC workflows are repository-managed.",
            "GitHub"));

        Integrations.Add(new(
            "Claude Code",
            "Ready",
            "Claude project settings, agents/skills, GitHub workflow, and split-authority patch publishing are installed. Runtime model access still depends on Foundry identity readiness.",
            "GitHub + Claude"));

        Integrations.Add(new(
            "Dedicated Claude Azure OIDC",
            dedicatedOidc ? "Ready" : compatibilityOidc ? "Degraded" : "Unconfigured",
            dedicatedOidc
                ? "Dedicated CLAUDE_AZURE_* identifiers are present in this operator session. Values are intentionally hidden."
                : compatibilityOidc
                    ? "Dedicated identifiers are absent; the compatibility AZURE_* chain is present. Run the dedicated bootstrap to reduce privilege."
                    : "No usable OIDC identifiers are visible in this operator session. Run the dedicated bootstrap from an authenticated Azure CLI session.",
            "Entra + GitHub OIDC"));

        Integrations.Add(new(
            "Microsoft Foundry / Claude models",
            hasFoundry && (dedicatedOidc || compatibilityOidc) ? "Ready" : hasFoundry ? "Degraded" : "Unconfigured",
            hasFoundry
                ? "Foundry resource name is configured; the bootstrap/verify command checks Sonnet and Haiku deployment readiness without displaying credentials."
                : "ANTHROPIC_FOUNDRY_RESOURCE is not visible locally. The bootstrap can discover exactly one AIServices account and write the non-secret GitHub variable.",
            "Azure AI Foundry"));

        Integrations.Add(new(
            "Key Vault + OpenAI/Codex",
            hasOpenAiCredential ? "Ready" : "Degraded",
            hasOpenAiCredential
                ? "A supported local credential source or Key Vault URI is configured. Secret values are never rendered in the control panel."
                : "No local OpenAI/Key Vault credential source is visible. Repository policy expects Key Vault or environment injection, never committed secrets.",
            "Azure Key Vault + AIHub"));

        Integrations.Add(new(
            "Hermes / AIHub",
            "Ready",
            $"AIHub control surface is configured at {apiUrl}. Use the AI Hub page for live provider health; this Fabric page owns integration readiness only.",
            "HELIOS AIHub"));

        Integrations.Add(new(
            "Slack · Linear · Teams · SharePoint",
            brokerUrl is not null ? "Ready" : "Degraded",
            brokerUrl is not null
                ? $"Governed connector broker endpoint is configured at {brokerUrl}."
                : "No local integration-broker URL is visible. Collaboration connectors remain governed by the broker/evidence contracts rather than direct desktop credentials.",
            "HELIOS Integration Broker"));

        StatusMessage = $"{Integrations.Count} Fabric lanes · refreshed {DateTimeOffset.Now:HH:mm:ss} · secret values hidden";
    }

    [RelayCommand]
    private void CopyBootstrap()
    {
        CopyText(BootstrapCommand);
        StatusMessage = "Copied dedicated Claude/Foundry OIDC bootstrap command.";
    }

    [RelayCommand]
    private void CopyVerify()
    {
        CopyText(VerifyCommand);
        StatusMessage = "Copied non-mutating Claude/Foundry verification command.";
    }

    [RelayCommand]
    private static Task OpenRepositoryAsync() => OpenUriAsync(RepositoryUrl);

    [RelayCommand]
    private static Task OpenClaudeWorkflowAsync() => OpenUriAsync(ClaudeWorkflowUrl);

    [RelayCommand]
    private static Task OpenClaudeIssueAsync() => OpenUriAsync(ClaudeIssueUrl);

    [RelayCommand]
    private static Task OpenClaudePrAsync() => OpenUriAsync(ClaudePrUrl);

    [RelayCommand]
    private static Task OpenAzurePortalAsync() => OpenUriAsync(AzurePortalUrl);

    private static void CopyText(string text)
    {
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
    }

    private static async Task OpenUriAsync(string uri)
    {
        _ = await Launcher.LaunchUriAsync(new Uri(uri));
    }

    private static bool HasAll(params string[] names) =>
        names.All(name => !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)));

    private static bool HasAny(params string[] names) =>
        names.Any(name => !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)));

    private static string? FirstNonEmpty(params string[] names) =>
        names.Select(Environment.GetEnvironmentVariable).FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
}
