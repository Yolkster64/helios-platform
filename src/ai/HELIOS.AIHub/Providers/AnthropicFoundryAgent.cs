using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Net.Http.Headers;
using Anthropic.SDK;
using Azure.Core;
using HELIOS.AIHub.Abstractions;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// Claude models deployed in Microsoft Foundry, reached through the same community
/// Anthropic.SDK as <see cref="AnthropicAgent"/> but pointed at the Foundry Messages
/// endpoint <c>https://&lt;resource&gt;.services.ai.azure.com/anthropic/v1/messages</c>
/// (Microsoft Learn: azure/foundry/foundry-models/how-to/use-foundry-models-claude).
/// <para>
/// Auth is either the deployment API key (sent as <c>x-api-key</c>, exactly like
/// api.anthropic.com) or a Microsoft Entra ID bearer token for scope
/// <see cref="EntraScope"/>. The SDK stamps <c>x-api-key</c> inside its own request
/// pipeline — after any <see cref="IRequestInterceptor"/> pre-hook has run (verified
/// against 5.10.0: the interceptor sees a header-less request) — so the Entra swap lives
/// in a <see cref="DelegatingHandler"/> on the injected <see cref="HttpClient"/>, which
/// is the only seam that sees the final header set.
/// </para>
/// <para>
/// The <c>model</c> sent to Foundry is the DEPLOYMENT name (may differ from the model id);
/// the default matches <c>scripts/ai-integration/Connect-ClaudeFoundry.ps1</c>.
/// </para>
/// </summary>
public sealed class AnthropicFoundryAgent : ProviderAgentBase
{
    /// <summary>Environment variable holding the Foundry resource name or https base URL.</summary>
    public const string DefaultEndpointEnv = "ANTHROPIC_FOUNDRY_RESOURCE";

    /// <summary>Environment variable holding the deployment/project API key (empty = Entra ID).</summary>
    public const string DefaultApiKeyEnv = "ANTHROPIC_FOUNDRY_API_KEY";

    /// <summary>Key Vault secret name consulted when <see cref="DefaultApiKeyEnv"/> is unset.</summary>
    public const string DefaultApiKeySecretName = "anthropic-foundry-api-key";

    /// <summary>Microsoft Entra ID scope for Foundry data-plane calls.</summary>
    public const string EntraScope = "https://ai.azure.com/.default";

    /// <summary>Default Foundry deployment name (same default as Connect-ClaudeFoundry.ps1).</summary>
    public const string DefaultDeployment = "claude-sonnet-4-6";

    private const string FoundryHostSuffix = ".services.ai.azure.com";
    private const string AnthropicPathSegment = "/anthropic";
    private const string MessagesSuffix = "/v1/messages";

    private readonly Lazy<AnthropicClient>? _client;
    private readonly string? _configurationHint;

    /// <summary>Unconfigured agent: <paramref name="configurationHint"/> tells the operator what to set.</summary>
    public AnthropicFoundryAgent(string provider, string displayName, string? defaultModel, string configurationHint)
        : base(provider, displayName, defaultModel)
    {
        _configurationHint = string.IsNullOrWhiteSpace(configurationHint)
            ? MissingEndpointHint(DefaultEndpointEnv)
            : configurationHint;
    }

    /// <summary>API-key mode: the key is sent as <c>x-api-key</c> on every request.</summary>
    /// <param name="transport">Innermost handler; tests inject a fake, production uses the default stack.</param>
    public AnthropicFoundryAgent(
        string provider,
        string displayName,
        string? defaultModel,
        Uri baseUri,
        string apiKey,
        HttpMessageHandler? transport = null)
        : base(provider, displayName, defaultModel)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        if (!TryResolveBaseUri(baseUri.OriginalString, "baseUri", out var normalized, out var hint))
        {
            _configurationHint = hint;
            return;
        }
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            // Not a bug, a configuration state: the factory only takes this path with a
            // key in hand, but a direct caller gets the same Unconfigured contract.
            _configurationHint = $"Set {DefaultApiKeyEnv} (or the Key Vault secret '{DefaultApiKeySecretName}'), " +
                                 "or omit the key to use Microsoft Entra ID.";
            return;
        }

        _client = CreateClient(normalized, apiKey, () => new HttpClient(transport ?? new HttpClientHandler()));
    }

    /// <summary>
    /// Microsoft Entra ID mode: a bearer token for <see cref="EntraScope"/> is acquired
    /// lazily on first use, cached, and refreshed at least five minutes before expiry.
    /// The agent is Ready immediately; credential failures surface as failed
    /// <see cref="ChatResult"/>s through the base-class provider boundary.
    /// </summary>
    /// <param name="transport">Innermost handler; tests inject a fake, production uses the default stack.</param>
    /// <param name="timeProvider">Clock for token-expiry decisions (tests inject a fake).</param>
    public AnthropicFoundryAgent(
        string provider,
        string displayName,
        string? defaultModel,
        Uri baseUri,
        TokenCredential credential,
        HttpMessageHandler? transport = null,
        TimeProvider? timeProvider = null)
        : base(provider, displayName, defaultModel)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        ArgumentNullException.ThrowIfNull(credential);
        if (!TryResolveBaseUri(baseUri.OriginalString, "baseUri", out var normalized, out var hint))
        {
            _configurationHint = hint;
            return;
        }

        // The SDK refuses a null key at request time; an empty one is accepted and only
        // produces an empty x-api-key header, which the bearer handler removes.
        _client = CreateClient(normalized, string.Empty, () => new HttpClient(
            new EntraBearerHandler(credential, EntraScope, timeProvider ?? TimeProvider.System)
            {
                InnerHandler = transport ?? new HttpClientHandler(),
            }));
    }

    public override ProviderReadiness Readiness =>
        _client is null ? ProviderReadiness.Unconfigured : ProviderReadiness.Ready;

    public override string? ConfigurationHint => _configurationHint;

    /// <summary>
    /// Turns the configured endpoint value into the Foundry base URI
    /// (<c>https://&lt;resource&gt;.services.ai.azure.com/anthropic</c>) or a hint saying why
    /// it cannot. Accepts a bare resource name (<c>helios-aijcut</c>) or an absolute https
    /// URL without userinfo, which is normalized: trailing slashes dropped, a pasted
    /// <c>/v1/messages</c> target URI trimmed back to its base, <c>/anthropic</c> appended
    /// when missing, query/fragment discarded. Never throws — bad configuration is a
    /// readiness state.
    /// </summary>
    /// <param name="sourceName">Where the value came from (env var name or config key), for the hint.</param>
    public static bool TryResolveBaseUri(
        string? value,
        string sourceName,
        [NotNullWhen(true)] out Uri? baseUri,
        [NotNullWhen(false)] out string? hint)
    {
        baseUri = null;
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            hint = MissingEndpointHint(sourceName);
            return false;
        }

        hint = $"{sourceName} is neither a Foundry resource name nor an absolute https URL without userinfo " +
               "(expected e.g. 'helios-aijcut' or 'https://helios-aijcut.services.ai.azure.com/anthropic'); fix it to enable this provider.";

        if (trimmed.Any(char.IsWhiteSpace))
        {
            return false;
        }

        if (IsResourceName(trimmed)
            && Uri.TryCreate($"https://{trimmed}{FoundryHostSuffix}{AnthropicPathSegment}", UriKind.Absolute, out var fromName))
        {
            baseUri = fromName;
            hint = null;
            return true;
        }

        // Userinfo (user:password@host) is rejected outright: a credential embedded in a
        // resource value would ride along in config or an env var, and the SDK would send
        // it — the only credentials this provider accepts are the key and the Entra token.
        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri)
            || !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
            || string.IsNullOrEmpty(uri.Host)
            || !string.IsNullOrEmpty(uri.UserInfo))
        {
            return false;
        }

        var path = uri.AbsolutePath.TrimEnd('/');
        if (path.EndsWith(MessagesSuffix, StringComparison.OrdinalIgnoreCase))
        {
            path = path[..^MessagesSuffix.Length].TrimEnd('/');
        }
        if (!path.EndsWith(AnthropicPathSegment, StringComparison.OrdinalIgnoreCase))
        {
            path += AnthropicPathSegment;
        }

        if (!Uri.TryCreate(uri.GetLeftPart(UriPartial.Authority) + path, UriKind.Absolute, out var normalized))
        {
            return false;
        }

        baseUri = normalized;
        hint = null;
        return true;
    }

    protected override async Task<ChatResult> ChatCoreAsync(ChatRequest request, CancellationToken cancellationToken)
    {
        var deployment = request.Model ?? DefaultModel ?? DefaultDeployment;
        var parameters = AnthropicMessageMapping.ToParameters(request, deployment);

        var stopwatch = Stopwatch.StartNew();
        var response = await _client!.Value.Messages
            .GetClaudeMessageAsync(parameters, cancellationToken)
            .ConfigureAwait(false);

        return AnthropicMessageMapping.ToResult(response, Provider, deployment, stopwatch.Elapsed);
    }

    /// <summary>
    /// The hint for a missing resource value. <c>Connect-ClaudeFoundry.ps1</c> exports only
    /// the default <see cref="DefaultEndpointEnv"/>, so an entry that overrides
    /// <c>endpointEnv</c> is pointed at the shell or <c>.helios/azure.env</c> instead of at
    /// a script that would never set its variable.
    /// </summary>
    internal static string MissingEndpointHint(string sourceName) =>
        $"Set {sourceName} (Foundry resource name or https base URL) — " +
        (string.Equals(sourceName, DefaultEndpointEnv, StringComparison.Ordinal)
            ? "scripts/ai-integration/Connect-ClaudeFoundry.ps1 sets it from your Azure CLI login, and azure-up writes it into .helios/azure.env."
            : $"set it in your shell or .helios/azure.env (scripts/ai-integration/Connect-ClaudeFoundry.ps1 sets only the default {DefaultEndpointEnv}).");

    /// <summary>Azure resource-name shape: alphanumerics and hyphens, 1–64 chars, leading alphanumeric.</summary>
    private static bool IsResourceName(string value)
    {
        if (value.Length is < 1 or > 64 || !char.IsAsciiLetterOrDigit(value[0]))
        {
            return false;
        }
        foreach (var c in value)
        {
            if (!char.IsAsciiLetterOrDigit(c) && c != '-')
            {
                return false;
            }
        }
        return true;
    }

    private static Lazy<AnthropicClient> CreateClient(Uri baseUri, string apiKey, Func<HttpClient> httpClientFactory) =>
        new(() =>
        {
            var httpClient = httpClientFactory();
            try
            {
                return new AnthropicClient(new APIAuthentication(apiKey), httpClient, null)
                {
                    // {0} = ApiVersion ("v1"), {1} = endpoint ("messages") — same placeholder
                    // semantics as the SDK default "https://api.anthropic.com/{0}/{1}".
                    ApiUrlFormat = baseUri.AbsoluteUri.TrimEnd('/') + "/{0}/{1}",
                    // Foundry's documented request carries only anthropic-version; the hub
                    // uses no beta features, so drop the SDK's default anthropic-beta list.
                    AnthropicBetaVersion = string.Empty,
                };
            }
            catch
            {
                httpClient.Dispose();
                throw;
            }
        }, LazyThreadSafetyMode.ExecutionAndPublication);
}

/// <summary>
/// Replaces the SDK's <c>x-api-key</c> header with <c>Authorization: Bearer</c> from a
/// <see cref="TokenCredential"/>. Tokens are cached and refreshed once they are within
/// <see cref="RefreshWindow"/> of expiry; acquisition is serialized so concurrent requests
/// share one credential round-trip. The token value is never logged or exposed.
/// </summary>
internal sealed class EntraBearerHandler : DelegatingHandler
{
    internal static readonly TimeSpan RefreshWindow = TimeSpan.FromMinutes(5);

    private readonly TokenCredential _credential;
    private readonly string _scope;
    private readonly TimeProvider _timeProvider;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);

    // AccessToken is a struct; the reference wrapper gives Volatile.Read/Write an atomic target.
    private CachedToken? _cached;

    internal EntraBearerHandler(TokenCredential credential, string scope, TimeProvider timeProvider)
    {
        _credential = credential;
        _scope = scope;
        _timeProvider = timeProvider;
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await GetAccessTokenAsync(cancellationToken).ConfigureAwait(false);

        request.Headers.Remove("x-api-key");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);

        return await base.SendAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<AccessToken> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        var cached = Volatile.Read(ref _cached);
        if (IsFresh(cached))
        {
            return cached.Value;
        }

        await _refreshGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            cached = Volatile.Read(ref _cached);
            if (IsFresh(cached))
            {
                return cached.Value;
            }

            var token = await _credential
                .GetTokenAsync(new TokenRequestContext(new[] { _scope }), cancellationToken)
                .ConfigureAwait(false);
            Volatile.Write(ref _cached, new CachedToken(token));
            return token;
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    private bool IsFresh([NotNullWhen(true)] CachedToken? cached) =>
        cached is not null && cached.Value.ExpiresOn - _timeProvider.GetUtcNow() > RefreshWindow;

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _refreshGate.Dispose();
        }
        base.Dispose(disposing);
    }

    private sealed class CachedToken
    {
        internal CachedToken(AccessToken value) => Value = value;

        internal AccessToken Value { get; }
    }
}
