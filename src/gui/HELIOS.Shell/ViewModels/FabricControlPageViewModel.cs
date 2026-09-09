using System.Collections.ObjectModel;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using HELIOS.Shell.Services;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;

namespace HELIOS.Shell.ViewModels;

public partial class FabricControlPageViewModel : ObservableObject
{
    private const string RepositoryUrl = "https://github.com/Yolkster64/helios-platform";
    private const string ClaudeWorkflowUrl = RepositoryUrl + "/actions/workflows/claude-foundry.yml";
    private const string ClaudeOidcRecordUrl = RepositoryUrl + "/pull/152";
    private const string AzurePortalUrl = "https://portal.azure.com/#home";

    private readonly AIHubApiClient _api;

    public FabricControlPageViewModel(AIHubApiClient api) => _api = api;

    [ObservableProperty]
    private bool _isRefreshing;

    [ObservableProperty]
    private string _statusMessage = "Fabric readiness has not been refreshed yet.";

    public ObservableCollection<FabricIntegrationItemViewModel> Integrations { get; } = [];

    public string BootstrapCommand => "pwsh -NoProfile -File scripts/bootstrap/claude-foundry-oidc-setup.ps1 -Repo Yolkster64/helios-platform";
    public string VerifyCommand => "pwsh -NoProfile -File scripts/bootstrap/claude-foundry-oidc-setup.ps1 -Repo Yolkster64/helios-platform -VerifyOnly -SkipGitHubVariables";

    [RelayCommand]
    private async Task RefreshAsync()
    {
        IsRefreshing = true;
        StatusMessage = "Checking AIHub and local configuration…";
        try
        {
            Integrations.Clear();
            var dedicatedOidc = HasAll("CLAUDE_AZURE_CLIENT_ID", "CLAUDE_AZURE_TENANT_ID", "CLAUDE_AZURE_SUBSCRIPTION_ID");
            var compatibilityOidc = HasAll("AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID");
            var hasFoundry = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ANTHROPIC_FOUNDRY_RESOURCE"));
            var hasKeyVault = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("AZURE_KEY_VAULT_URI"));
            var hasOpenAiCredential = HasAny("OPENAI_API_KEY", "AZURE_OPENAI_API_KEY") || hasKeyVault;
            var brokerUrl = FirstNonEmpty("HELIOS_INTEGRATION_BROKER_URL", "HELIOS_BROKER_URL");
            var hasLiveAiHubStatus = await CanReachAiHubAsync().ConfigureAwait(true);

            Integrations.Add(new("GitHub control plane", "Unverified", "Repository configuration is available. GitHub authentication and workflow execution have not been checked by this page.", "GitHub"));
            Integrations.Add(new("Claude Code / Codex / Copilot", "Unverified", "The repository supplies shared configuration. Client installation, login and model access require their own checks.", "GitHub + Claude"));
            Integrations.Add(new("Dedicated Claude Azure OIDC", dedicatedOidc ? "Unverified" : compatibilityOidc ? "Unverified" : "Unconfigured", dedicatedOidc ? "Dedicated CLAUDE_AZURE_* identifiers are configured locally. Run the verify-only bootstrap to confirm the credential, trust subject, and role assignment." : compatibilityOidc ? "Compatibility AZURE_* identifiers are present; run the dedicated bootstrap to reduce privilege and verify the dedicated identity." : "No usable OIDC identifiers are visible locally. Run the dedicated bootstrap from an authenticated Azure CLI session.", "Entra + GitHub OIDC"));
            Integrations.Add(new("Microsoft Foundry / Claude models", hasFoundry ? "Unverified" : "Unconfigured", hasFoundry ? "Foundry resource is configured locally; run the verify-only bootstrap to confirm Sonnet/Haiku deployment readiness without displaying credentials." : "ANTHROPIC_FOUNDRY_RESOURCE is not visible locally; bootstrap can discover it and set the non-secret GitHub variable.", "Azure AI Foundry"));
            Integrations.Add(new("Key Vault + OpenAI/Codex", hasOpenAiCredential ? "Unverified" : "Unconfigured", hasOpenAiCredential ? "A supported local credential source or Key Vault URI is configured, but live access is not verified from this page. Secret values are never rendered." : "No local OpenAI or Key Vault source is visible. Repository policy expects Key Vault or environment injection, never committed secrets.", "Azure Key Vault + AIHub"));
            Integrations.Add(new("AIHub API", hasLiveAiHubStatus ? "Reachable" : "Unavailable", hasLiveAiHubStatus ? "The configured API returned a readable status response. Open AI Hub to inspect each provider; this check does not establish provider login or fleet availability." : "The configured API did not return a readable status response. Check the API process and its connection settings.", "HELIOS AIHub"));
            Integrations.Add(new("Hermes / XCore / hybrid fleets", "Unverified", "Fleet execution requires a configured worker and a real job receipt. API reachability does not prove that a worker is running.", "HELIOS Fleet"));
            Integrations.Add(new("Slack · Linear · SharePoint · Outlook", brokerUrl is not null ? "Unverified" : "Unconfigured", brokerUrl is not null ? "A local integration-broker setting is present. This page has not checked broker authentication, connector adapters or delivery receipts." : "No local integration-broker setting is visible. Use the shared setup guide to configure runtime connectors.", "HELIOS Integration Broker"));
            StatusMessage = $"{Integrations.Count} Fabric lanes · refreshed {DateTimeOffset.Now:HH:mm:ss} · local presence is not authentication";
        }
        finally
        {
            IsRefreshing = false;
        }
    }

    [RelayCommand] private void CopyBootstrap() => CopyText(BootstrapCommand, "Setup command copied. Review its identity and resource changes before running it.");
    [RelayCommand] private void CopyVerify() => CopyText(VerifyCommand, "Read-only verification command copied. Run it from the repository folder.");
    [RelayCommand] private Task OpenRepositoryAsync() => OpenUriAsync(RepositoryUrl);
    [RelayCommand] private Task OpenClaudeWorkflowAsync() => OpenUriAsync(ClaudeWorkflowUrl);
    [RelayCommand] private Task OpenClaudeIssueAsync() => OpenUriAsync(ClaudeOidcRecordUrl);
    [RelayCommand] private Task OpenAzurePortalAsync() => OpenUriAsync(AzurePortalUrl);

    private void CopyText(string text, string message)
    {
        try
        {
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
            StatusMessage = message;
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or ArgumentException)
        {
            StatusMessage = "Clipboard unavailable. Select and copy the command shown on this page.";
        }
    }

    private async Task OpenUriAsync(string uri)
    {
        try
        {
            StatusMessage = await Launcher.LaunchUriAsync(new Uri(uri))
                ? "Opened in your browser." : "Could not open the link. Check your default browser.";
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or ArgumentException)
        {
            StatusMessage = "Could not open the link. Check your default browser.";
        }
    }
    private static bool HasAll(params string[] names) => names.All(name => !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)));
    private static bool HasAny(params string[] names) => names.Any(name => !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)));
    private static string? FirstNonEmpty(params string[] names) => names.Select(Environment.GetEnvironmentVariable).FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
    private async Task<bool> CanReachAiHubAsync()
    {
        try
        {
            _ = await _api.GetStatusAsync().ConfigureAwait(false);
            return true;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException or NotSupportedException or InvalidOperationException)
        {
            return false;
        }
    }
}
