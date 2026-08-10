using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;

namespace HELIOS.Shell.Services;

/// <summary>
/// Wire shape of one element of <c>GET /v1/status</c> (see
/// src/ai/HELIOS.AIHub.Api/ApiModels.cs, <c>ProviderStatusResponse</c>). Readiness is the
/// <c>ProviderReadiness</c> enum name: "Unconfigured", "Ready", or "Degraded".
/// </summary>
public sealed record ProviderStatusDto(
    string Name, string Kind, string? Model, string Readiness, string? Detail);

/// <summary>
/// Thin REST client over helios-ai-api. The shell never talks to LLM providers or loads
/// hub assemblies — provider state comes exclusively from the API process, so the CLI,
/// MCP server, and shell always agree (hub-and-spoke rule).
/// </summary>
public sealed class AIHubApiClient : IDisposable
{
    /// <summary>Environment variable that overrides the API base URL.</summary>
    public const string BaseUrlEnvVar = "HELIOS_API_URL";

    /// <summary>Environment variable containing the API key for Docker/remote URLs.</summary>
    public const string AccessKeyEnvVar = "HELIOS_API_ACCESS_KEY";

    /// <summary>Header accepted by helios-ai-api for non-loopback requests.</summary>
    public const string AccessKeyHeader = "X-HELIOS-Api-Key";

    /// <summary>Default helios-ai-api base URL for a local dev loop.</summary>
    public const string DefaultBaseUrl = "http://localhost:5170";

    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    private readonly HttpClient _http;

    public AIHubApiClient() : this(ResolveBaseAddress())
    {
    }

    public AIHubApiClient(Uri baseAddress)
    {
        BaseAddress = baseAddress;
        // Do not forward the custom access-key header across redirects.
        _http = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false })
        {
            BaseAddress = baseAddress,
            // Snappy offline detection: the dashboard's "API not running" state should
            // appear in seconds, not after HttpClient's 100 s default.
            Timeout = TimeSpan.FromSeconds(5),
        };
        var accessKey = Environment.GetEnvironmentVariable(AccessKeyEnvVar);
        if (!string.IsNullOrWhiteSpace(accessKey))
        {
            _http.DefaultRequestHeaders.Add(AccessKeyHeader, accessKey);
        }
    }

    /// <summary>Resolved API base address (env var or default) — surfaced in the UI.</summary>
    public Uri BaseAddress { get; }

    /// <summary>
    /// Fetches provider status from <c>GET /v1/status</c>. Throws
    /// <see cref="HttpRequestException"/> / <see cref="TaskCanceledException"/> when the
    /// API is unreachable; the view model turns that into the "API not running" state.
    /// </summary>
    public async Task<IReadOnlyList<ProviderStatusDto>> GetStatusAsync(
        CancellationToken cancellationToken = default)
    {
        var payload = await _http
            .GetFromJsonAsync<List<ProviderStatusDto>>("/v1/status", JsonOptions, cancellationToken)
            .ConfigureAwait(false);
        return payload ?? [];
    }

    public void Dispose() => _http.Dispose();

    private static Uri ResolveBaseAddress()
    {
        var raw = Environment.GetEnvironmentVariable(BaseUrlEnvVar);
        if (!string.IsNullOrWhiteSpace(raw)
            && Uri.TryCreate(raw, UriKind.Absolute, out var configured))
        {
            return configured;
        }
        return new Uri(DefaultBaseUrl);
    }
}
