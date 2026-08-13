using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub.Providers;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Auth-lane diagnosis tool — a thin wrapper over <see cref="AuthStatusService"/>
/// (HELIOS.AIHub), which owns the lane logic, the token-probe seam, and the
/// missing-config degradation so all of that is testable without MCP plumbing.
/// Strictly diagnose-only: environment variables are reported by NAME and set/unset
/// state only (never a value), the one Azure token acquired is discarded, and nothing
/// is repaired — repair is scripts/bootstrap/auth-doctor.ps1's job.
/// </summary>
[McpServerToolType]
public static class HeliosAuthTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>Every report carries this so no caller mistakes a diagnosis for a repair.</summary>
    public const string DiagnoseOnlyNote =
        "Diagnose-only: environment variables are reported by name and set/unset state only — " +
        "no secret value was read into this report, and nothing was repaired. " +
        "To repair lanes run: pwsh scripts/bootstrap/auth-doctor.ps1 " +
        "(report-first; -Apply adds automatic non-interactive repair).";

    [McpServerTool(Name = "helios_auth_status_get", ReadOnly = true, Idempotent = true, OpenWorld = true)]
    [Description("Diagnose-only status of the HELIOS auth lanes: environment (actions|local via GITHUB_ACTIONS), github (which of GH_TOKEN/GITHUB_TOKEN is set — by NAME, values are never read into the output), azure (one DefaultAzureCredential management-plane token probe; missing credentials return authenticated:false with a fix hint, never an error), and one lane per config/aihub.json provider ({name, apiKeyEnv, set} — set is omitted for providers that declare no key variable). Repairs nothing; the note points to scripts/bootstrap/auth-doctor.ps1 for repair.")]
    public static async Task<string> GetAuthStatus(
        AuthStatusService auth,
        CancellationToken cancellationToken = default)
    {
        AuthStatusReport report;
        try
        {
            report = await auth.GetStatusAsync(cancellationToken);
        }
        catch (InvalidDataException ex)
        {
            // Exists-but-unreadable config/aihub.json (a MISSING config is already a
            // reported state with a hint, per the service contract).
            throw new McpException(ex.Message);
        }

        return JsonSerializer.Serialize(new
        {
            environment = report.Environment,
            github = new
            {
                set = report.GitHub.Set,
                tokenEnv = report.GitHub.TokenEnv,
            },
            azure = new
            {
                authenticated = report.Azure.Authenticated,
                hint = report.Azure.Hint,
            },
            providers = report.Providers.Select(provider => new
            {
                name = provider.Name,
                apiKeyEnv = provider.ApiKeyEnv,
                set = provider.Set,
            }),
            providersHint = report.ProvidersHint,
            note = DiagnoseOnlyNote,
        }, JsonOptions);
    }
}
