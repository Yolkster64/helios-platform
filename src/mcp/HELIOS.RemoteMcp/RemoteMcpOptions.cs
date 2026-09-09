using System.Net;
using System.Security.Claims;

namespace HELIOS.RemoteMcp;

/// <summary>Operator-owned launch settings. Remote callers cannot change these.</summary>
public sealed record RemoteMcpOptions
{
    public required string RepositoryRoot { get; init; }
    public required Uri ListenUri { get; init; }
    public required IPAddress ListenAddress { get; init; }
    public string AuthMode { get; init; } = "loopback";
    public Uri? PublicOrigin { get; init; }
    public string? TenantId { get; init; }
    public string? Audience { get; init; }
    public string? ScopeResource { get; init; }
    public string ReadScope { get; init; } = "access_as_user";
    public string ClaudeScope => "claude.invoke";
    public IReadOnlySet<string> AllowedOrigins { get; init; } = new HashSet<string>();
    public bool ClaudeEnabled { get; init; }
    public string? ClaudeExecutable { get; init; }
    public bool UsesEntra => AuthMode == "entra";
    public string Authority => $"https://login.microsoftonline.com/{TenantId}/v2.0";
    public string Resource => $"{PublicOrigin!.GetLeftPart(UriPartial.Authority)}/mcp";
    public string MetadataUrl => $"{PublicOrigin!.GetLeftPart(UriPartial.Authority)}/.well-known/oauth-protected-resource/mcp";
    public string OAuthScope(string scope) => $"{ScopeResource}/{scope}";

    public static RemoteMcpOptions Load(IConfiguration configuration)
    {
        var root = configuration["HELIOS_REPO_ROOT"];
        if (string.IsNullOrWhiteSpace(root) || !Path.IsPathFullyQualified(root) ||
            !File.Exists(Path.Combine(root, "AGENTS.md")))
            throw new InvalidOperationException("HELIOS_REPO_ROOT must name an absolute trusted HELIOS checkout containing AGENTS.md.");
        var mode = configuration["HELIOS_REMOTE_AUTH_MODE"] ?? "loopback";
        if (mode is not ("loopback" or "entra"))
            throw new InvalidOperationException("HELIOS_REMOTE_AUTH_MODE must be loopback or entra.");
        var listen = ParseOrigin(configuration["HELIOS_REMOTE_URL"] ?? "http://127.0.0.1:7078", requireHttps: false);
        if (listen.Scheme != "http" || !IPAddress.TryParse(listen.Host, out var address))
            throw new InvalidOperationException("HELIOS_REMOTE_URL must be one explicit HTTP IP listener; terminate remote TLS at an approved proxy.");
        if (mode == "loopback" && !IPAddress.IsLoopback(address))
            throw new InvalidOperationException("Loopback mode cannot bind a network interface.");
        if (configuration.GetSection("Kestrel:Endpoints").Exists())
            throw new InvalidOperationException("Use HELIOS_REMOTE_URL; extra Kestrel endpoints are not permitted.");

        Uri? publicOrigin = null;
        string? tenant = null;
        string? audience = null;
        string? scopeResource = null;
        var scope = configuration["HELIOS_REMOTE_SCOPE"] ?? "access_as_user";
        if (scope.Length is < 1 or > 100 || scope.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('.' or '_')))
            throw new InvalidOperationException("HELIOS_REMOTE_SCOPE must be one delegated scope name.");
        if (mode == "entra")
        {
            publicOrigin = ParseOrigin(configuration["HELIOS_REMOTE_PUBLIC_ORIGIN"], requireHttps: true);
            if (publicOrigin.IsLoopback)
                throw new InvalidOperationException("Entra mode requires a public HTTPS origin.");
            if (!Guid.TryParse(configuration["AZURE_TENANT_ID"], out var tenantGuid) || tenantGuid == Guid.Empty)
                throw new InvalidOperationException("AZURE_TENANT_ID must be the exact Entra tenant GUID.");
            tenant = tenantGuid.ToString();
            audience = configuration["HELIOS_REMOTE_AUDIENCE"];
            if (string.IsNullOrWhiteSpace(audience) || audience.Length > 256 || audience.Any(char.IsWhiteSpace) ||
                audience.Contains('"') || audience.Contains('<') || audience.Contains('>'))
                throw new InvalidOperationException("HELIOS_REMOTE_AUDIENCE must be the registered API audience.");
            // Entra requests need fully qualified scopes; JWT scp claims contain
            // only the bare names. A v2 audience GUID is not itself an OAuth scope URI.
            scopeResource = configuration["HELIOS_REMOTE_SCOPE_RESOURCE"]?.TrimEnd('/') ??
                (Guid.TryParse(audience, out var appId) ? $"api://{appId}" : audience.TrimEnd('/'));
            if (!Uri.TryCreate(scopeResource, UriKind.Absolute, out var scopeUri) ||
                scopeUri.Scheme is not ("api" or "https") || string.IsNullOrEmpty(scopeUri.Host) ||
                !string.IsNullOrEmpty(scopeUri.UserInfo) || !string.IsNullOrEmpty(scopeUri.Query) ||
                !string.IsNullOrEmpty(scopeUri.Fragment) || scopeResource.Any(char.IsWhiteSpace) ||
                scopeResource.Contains('"') || scopeResource.Length > 256)
                throw new InvalidOperationException("HELIOS_REMOTE_SCOPE_RESOURCE must be the registered Entra Application ID URI.");
        }
        var origins = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var value in (configuration["HELIOS_REMOTE_ALLOWED_ORIGINS"] ?? "")
                     .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            origins.Add(ParseOrigin(value, requireHttps: mode == "entra").GetLeftPart(UriPartial.Authority));
        if (mode == "loopback") origins.Add(listen.GetLeftPart(UriPartial.Authority));

        var claudeEnabledValue = configuration["HELIOS_REMOTE_CLAUDE_ENABLED"] ?? "false";
        if (!bool.TryParse(claudeEnabledValue, out var claudeEnabled))
            throw new InvalidOperationException("HELIOS_REMOTE_CLAUDE_ENABLED must be true or false.");
        var executable = configuration["HELIOS_REMOTE_CLAUDE_EXECUTABLE"];
        if (claudeEnabled && (string.IsNullOrWhiteSpace(executable) || !Path.IsPathFullyQualified(executable) ||
            !File.Exists(executable) || (OperatingSystem.IsWindows() && !executable.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))))
            throw new InvalidOperationException("Claude requires HELIOS_REMOTE_CLAUDE_EXECUTABLE pointing to an installed native executable.");

        return new RemoteMcpOptions
        {
            RepositoryRoot = Path.GetFullPath(root), ListenUri = listen, ListenAddress = address,
            AuthMode = mode, PublicOrigin = publicOrigin, TenantId = tenant, Audience = audience, ScopeResource = scopeResource,
            ReadScope = scope, AllowedOrigins = origins, ClaudeEnabled = claudeEnabled, ClaudeExecutable = executable,
        };
    }

    internal static Uri ParseOrigin(string? value, bool requireHttps)
    {
        if (string.IsNullOrWhiteSpace(value) || !Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("https" or "http") || (requireHttps && uri.Scheme != "https") ||
            !string.IsNullOrEmpty(uri.UserInfo) || uri.AbsolutePath != "/" ||
            !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment) || value.Contains('*'))
            throw new InvalidOperationException("An exact HTTP(S) origin without credentials, path, query, fragment, or wildcard is required.");
        return uri;
    }

    public bool HasScope(ClaimsPrincipal user, string scope) => user.Identity?.IsAuthenticated == true &&
        user.FindAll("scp").SelectMany(claim => claim.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            .Contains(scope, StringComparer.Ordinal);

    public bool AllowsRequest(HttpContext context)
    {
        var localAuthority = ListenUri.Authority;
        var host = context.Request.Host.Value;
        // Do not trust forwarded headers or request Host when constructing OAuth URLs.
        if (!string.Equals(host, localAuthority, StringComparison.OrdinalIgnoreCase) &&
            !(UsesEntra && string.Equals(host, PublicOrigin!.Authority, StringComparison.OrdinalIgnoreCase)))
            return false;
        if (!UsesEntra && (context.Connection.RemoteIpAddress is not { } remote || !IPAddress.IsLoopback(remote)))
            return false;
        var origins = context.Request.Headers.Origin;
        if (origins.Count == 0) return true;
        if (origins.Count != 1) return false;
        try { return AllowedOrigins.Contains(ParseOrigin(origins[0], UsesEntra).GetLeftPart(UriPartial.Authority)); }
        catch (InvalidOperationException) { return false; }
    }
}
