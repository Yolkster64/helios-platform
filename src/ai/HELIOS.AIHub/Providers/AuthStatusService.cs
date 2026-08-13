using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using HELIOS.AIHub.Configuration;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// The gh lane: which of the token environment variables gh honors (GH_TOKEN first,
/// then GITHUB_TOKEN) is set. Names only — the value is never read into this record,
/// matching scripts/bootstrap/auth-doctor.ps1's secrets policy.
/// </summary>
public sealed record GitHubTokenLane(bool Set, string? TokenEnv);

/// <summary>
/// The az lane: whether DefaultAzureCredential could produce a management-plane token.
/// Unauthenticated is a state, not an error (the <see cref="AzureResourceService"/>
/// contract): <see cref="Hint"/> names the exact fix and the probe never throws for
/// missing credentials.
/// </summary>
public sealed record AzureAuthLane(bool Authenticated, string? Hint);

/// <summary>
/// One provider lane from config/aihub.json: the provider key, the environment-variable
/// NAME it declares for its API key, and whether that variable is set. <see cref="Set"/>
/// is null when the provider declares no apiKeyEnv (ollama, azure-foundry — endpoint- or
/// credential-based), so "nothing to check" is never conflated with "key missing".
/// </summary>
public sealed record ProviderKeyLane(string Name, string? ApiKeyEnv, bool? Set);

/// <summary>
/// A diagnose-only snapshot of the HELIOS auth lanes.
/// <see cref="Environment"/> is "actions" (GITHUB_ACTIONS=true) or "local" — the same
/// heuristic auth-doctor.ps1 uses to decide whose job a fix is.
/// <see cref="ProvidersHint"/> is set (with <see cref="Providers"/> empty) when
/// config/aihub.json could not be found — a missing config is a reported state here,
/// not an error.
/// </summary>
public sealed record AuthStatusReport(
    string Environment,
    GitHubTokenLane GitHub,
    AzureAuthLane Azure,
    IReadOnlyList<ProviderKeyLane> Providers,
    string? ProvidersHint);

/// <summary>
/// Minimal token-probe seam so the az lane is testable without network or credentials
/// (the <see cref="IAzureResourceGateway"/> idiom — that seam is an inventory gateway
/// over subscriptions and resources, so it is deliberately not reused for a bare token
/// probe). The only production implementation is
/// <see cref="DefaultAzureCredentialTokenProbe"/>; tests substitute a fake. A successful
/// probe returns; a failed credential chain throws
/// <see cref="AuthenticationFailedException"/> (which covers
/// <see cref="CredentialUnavailableException"/>) for the service to convert to a state.
/// </summary>
public interface IAzureTokenProbe
{
    /// <summary>Attempts to acquire one management-plane token. The token itself is discarded.</summary>
    Task ProbeAsync(CancellationToken cancellationToken);
}

/// <summary>
/// The production probe: one DefaultAzureCredential GetToken attempt for the ARM scope,
/// bounded by a short internal timeout so a wedged credential source (an unreachable
/// IMDS endpoint, a hung broker) degrades to "unauthenticated" instead of hanging a
/// status tool. The credential resolves lazily inside the call, never at construction.
/// </summary>
public sealed class DefaultAzureCredentialTokenProbe : IAzureTokenProbe
{
    /// <summary>Same management-plane audience ArmClient tokens carry.</summary>
    public const string ManagementScope = "https://management.azure.com/.default";

    /// <summary>
    /// Generous enough for an az-CLI subprocess token exchange, short enough that a
    /// diagnosis never feels hung.
    /// </summary>
    public static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(15);

    public async Task ProbeAsync(CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(ProbeTimeout);
        var credential = new DefaultAzureCredential();
        // The AccessToken is deliberately dropped: this lane reports CAN authenticate,
        // never WHAT the credential is — no token material may reach the report.
        _ = await credential.GetTokenAsync(
            new TokenRequestContext(new[] { ManagementScope }), timeout.Token).ConfigureAwait(false);
    }
}

/// <summary>
/// Diagnose-only auth status across the HELIOS auth lanes — the service the MCP tool
/// helios_auth_status_get wraps. It stays consistent with the lane vocabulary of
/// scripts/bootstrap/auth-doctor.ps1 (gh env token by name, az token probe, provider
/// apiKeyEnv presence) but deliberately ports NONE of its repair logic: this service
/// reads and reports, repair is the doctor script's job.
///
/// Secrets policy (CLAUDE.md rule): environment variables are checked by NAME and
/// set/unset state only — no value is ever stored on a report or interpolated into a
/// hint. Everything is keyless-deterministic through the
/// <see cref="IAzureTokenProbe"/> seam plus environment manipulation.
/// </summary>
public sealed class AuthStatusService
{
    /// <summary>GitHub Actions marks its runners with GITHUB_ACTIONS=true.</summary>
    public const string ActionsEnvironmentVariable = "GITHUB_ACTIONS";

    /// <summary>
    /// The token variables the gh CLI honors, in its own precedence order: GH_TOKEN
    /// wins over GITHUB_TOKEN when both are set (auth-doctor.ps1 gh-lane contract).
    /// </summary>
    public static readonly IReadOnlyList<string> GitHubTokenEnvNames = new[] { "GH_TOKEN", "GITHUB_TOKEN" };

    /// <summary>Reported when config/aihub.json cannot be found — a state, not an error.</summary>
    public const string MissingConfigHint =
        "config/aihub.json not found in this directory or any parent — provider lanes unavailable. " +
        "Run from the repo checkout (or set AIHUB_CONFIG for the CLI surfaces).";

    private readonly Lazy<IAzureTokenProbe> _probe;
    private readonly string? _startDirectory;

    /// <summary>
    /// <paramref name="probeFactory"/> is the test seam; null uses the real
    /// DefaultAzureCredential probe. Lazy so no credential work happens until a status
    /// is actually requested. <paramref name="startDirectory"/> anchors the
    /// config/aihub.json walk for tests pointing at a fabricated repo root; null means
    /// "resolve from the process's own location", exactly like the other MCP tools.
    /// </summary>
    public AuthStatusService(Func<IAzureTokenProbe>? probeFactory = null, string? startDirectory = null)
    {
        _probe = new Lazy<IAzureTokenProbe>(probeFactory ?? (() => new DefaultAzureCredentialTokenProbe()));
        _startDirectory = startDirectory;
    }

    /// <summary>
    /// Diagnoses every lane. Never throws for absence — a missing token, failed
    /// credential chain, or missing config are all reported states. The one exception
    /// path is an UNREADABLE config/aihub.json (exists but cannot be parsed), which
    /// surfaces as <see cref="InvalidDataException"/> naming the file, for the MCP
    /// layer to convert.
    /// </summary>
    public async Task<AuthStatusReport> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        var environment = string.Equals(
            System.Environment.GetEnvironmentVariable(ActionsEnvironmentVariable),
            "true", StringComparison.OrdinalIgnoreCase)
            ? "actions"
            : "local";

        var azure = await GetAzureLaneAsync(cancellationToken).ConfigureAwait(false);
        var (providers, providersHint) = GetProviderLanes();
        return new AuthStatusReport(environment, GetGitHubLane(), azure, providers, providersHint);
    }

    private static GitHubTokenLane GetGitHubLane()
    {
        foreach (var name in GitHubTokenEnvNames)
        {
            // Presence check only: the value is inspected for emptiness and dropped on
            // the spot — it never reaches a field, a report, or a log.
            if (!string.IsNullOrEmpty(System.Environment.GetEnvironmentVariable(name)))
            {
                return new GitHubTokenLane(Set: true, TokenEnv: name);
            }
        }
        return new GitHubTokenLane(Set: false, TokenEnv: null);
    }

    private async Task<AzureAuthLane> GetAzureLaneAsync(CancellationToken cancellationToken)
    {
        try
        {
            await _probe.Value.ProbeAsync(cancellationToken).ConfigureAwait(false);
            return new AzureAuthLane(Authenticated: true, Hint: null);
        }
        catch (AuthenticationFailedException ex)
        {
            // Covers CredentialUnavailableException too (it derives from this): the
            // whole DefaultAzureCredential chain failed. Same hint contract as
            // AzureResourceService — bad auth is a state to report, never a crash.
            return new AzureAuthLane(
                Authenticated: false,
                Hint: $"{AzureResourceService.UnauthenticatedHint} ({FirstLine(ex.Message)})");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // The probe's internal timeout, not the caller cancelling: a credential
            // source that hangs is indistinguishable from unauthenticated for a
            // diagnosis, so report it as that state with the extra detail.
            return new AzureAuthLane(
                Authenticated: false,
                Hint: $"{AzureResourceService.UnauthenticatedHint} (the token probe timed out " +
                      "— a credential source may be unreachable from this host)");
        }
    }

    /// <summary>
    /// One lane per provider in config/aihub.json, in file order: the declared apiKeyEnv
    /// NAME and whether it is set. A missing config file degrades to a hint;
    /// an unreadable one throws <see cref="InvalidDataException"/> naming the file.
    /// </summary>
    private (IReadOnlyList<ProviderKeyLane> Lanes, string? Hint) GetProviderLanes()
    {
        var configPath = AIHubOptions.FindConfigFile(_startDirectory);
        if (configPath is null)
        {
            return (Array.Empty<ProviderKeyLane>(), MissingConfigHint);
        }

        AIHubOptions options;
        try
        {
            options = AIHubOptions.Load(configPath);
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
        {
            throw new InvalidDataException($"Failed to read '{configPath}': {ex.Message}", ex);
        }

        var lanes = new List<ProviderKeyLane>(options.Providers.Count);
        foreach (var (name, provider) in options.Providers)
        {
            var apiKeyEnv = string.IsNullOrWhiteSpace(provider.ApiKeyEnv) ? null : provider.ApiKeyEnv;
            // Null Set = "this provider declares no key variable" (endpoint- or
            // credential-configured); presence check drops the value immediately.
            bool? set = apiKeyEnv is null
                ? null
                : !string.IsNullOrEmpty(System.Environment.GetEnvironmentVariable(apiKeyEnv));
            lanes.Add(new ProviderKeyLane(name, apiKeyEnv, set));
        }
        return (lanes, null);
    }

    private static string FirstLine(string message) => message.Split('\n')[0].TrimEnd();
}
