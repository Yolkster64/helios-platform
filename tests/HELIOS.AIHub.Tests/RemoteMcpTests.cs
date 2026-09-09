using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HELIOS.RemoteMcp;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using ModelContextProtocol;
using Xunit;
using RemoteProgram = HELIOS.RemoteMcp.Program;

namespace HELIOS.AIHub.Tests;

public sealed class RemoteMcpTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("helios-remote-test-").FullName;
    private readonly RSA _rsa = RSA.Create(2048);
    private const string Tenant = "12345678-1234-1234-1234-123456789abc";
    private const string Audience = "api://11111111-1111-1111-1111-111111111111";

    public RemoteMcpTests()
    {
        File.WriteAllText(Path.Combine(_root, "AGENTS.md"), "HELIOS trusted test project");
        Directory.CreateDirectory(Path.Combine(_root, "config"));
        File.WriteAllText(Path.Combine(_root, "config", "control-project.json"), "{\"id\":\"helios-control\"}");
        File.WriteAllText(Path.Combine(_root, "config", "aihub.json"),
            "{\"routing\":{\"defaultChain\":[\"claude-cli\"],\"taskRouting\":{\"review:csharp\":[\"claude-cli\"]}},\"providers\":{\"apiKey\":\"TEST_SECRET_DO_NOT_RETURN\"}}");
    }

    private Dictionary<string, string?> Config(bool entra = false) => new()
    {
        ["HELIOS_REPO_ROOT"] = _root,
        ["HELIOS_REMOTE_AUTH_MODE"] = entra ? "entra" : "loopback",
        ["HELIOS_REMOTE_URL"] = "http://127.0.0.1:7078",
        ["HELIOS_REMOTE_PUBLIC_ORIGIN"] = "https://helios.example.com",
        ["AZURE_TENANT_ID"] = Tenant,
        ["HELIOS_REMOTE_AUDIENCE"] = Audience,
        ["HELIOS_REMOTE_CLAUDE_ENABLED"] = "false",
    };

    private RemoteMcpOptions Options(Dictionary<string, string?>? values = null) =>
        RemoteMcpOptions.Load(new ConfigurationBuilder().AddInMemoryCollection(values ?? Config()).Build());

    [Theory]
    [InlineData("HELIOS_REMOTE_URL", "http://0.0.0.0:7078")]
    [InlineData("HELIOS_REMOTE_URL", "http://127.0.0.1:7078/mcp")]
    [InlineData("HELIOS_REMOTE_URL", "http://user:password@127.0.0.1:7078")]
    [InlineData("HELIOS_REMOTE_AUTH_MODE", "none")]
    [InlineData("HELIOS_REMOTE_ALLOWED_ORIGINS", "*")]
    [InlineData("Kestrel:Endpoints:Extra:Url", "http://0.0.0.0:80")]
    public void InvalidLaunchSettingsFailClosed(string key, string value)
    {
        var config = Config(); config[key] = value;
        Assert.Throws<InvalidOperationException>(() => Options(config));
    }

    [Theory]
    [InlineData("AZURE_TENANT_ID", "common")]
    [InlineData("HELIOS_REMOTE_PUBLIC_ORIGIN", "http://helios.example.com")]
    [InlineData("HELIOS_REMOTE_PUBLIC_ORIGIN", "https://user:secret@helios.example.com")]
    [InlineData("HELIOS_REMOTE_PUBLIC_ORIGIN", "https://helios.example.com/path")]
    [InlineData("HELIOS_REMOTE_PUBLIC_ORIGIN", "https://localhost")]
    [InlineData("HELIOS_REMOTE_AUDIENCE", "")]
    public void IncompleteEntraSettingsFailClosed(string key, string value)
    {
        var config = Config(entra: true); config[key] = value;
        Assert.Throws<InvalidOperationException>(() => Options(config));
    }

    [Theory]
    [InlineData("127.0.0.1:7078", null, "127.0.0.1", true)]
    [InlineData("127.0.0.1:7078", "http://127.0.0.1:7078", "127.0.0.1", true)]
    [InlineData("attacker.example", null, "127.0.0.1", false)]
    [InlineData("127.0.0.1:7078", "https://attacker.example", "127.0.0.1", false)]
    [InlineData("127.0.0.1:7078", "null", "127.0.0.1", false)]
    [InlineData("127.0.0.1:7078", null, "192.0.2.10", false)]
    public void LocalHostOriginAndPeerAreChecked(string host, string? origin, string peer, bool expected)
    {
        var context = new DefaultHttpContext();
        context.Request.Host = HostString.FromUriComponent(host);
        context.Connection.RemoteIpAddress = IPAddress.Parse(peer);
        if (origin is not null) context.Request.Headers.Origin = origin;
        Assert.Equal(expected, Options().AllowsRequest(context));
    }

    [Fact]
    public void CatalogRejectsPathsLinksAndOversizedFiles()
    {
        var repository = new RemoteRepository(Options());
        Assert.Throws<McpException>(() => repository.Fetch("../../secret"));
        Assert.Throws<McpException>(() => repository.Fetch("https://example.com"));
        Assert.Throws<McpException>(() => repository.ReadFixedFile(".env"));
        File.WriteAllText(Path.Combine(_root, "config", "control-project.json"), new string('x', RemoteRepository.MaxDocumentBytes + 1));
        Assert.Throws<McpException>(() => repository.Fetch("project"));
    }

    [Fact]
    public void CatalogSearchAndRoutingUseBoundedReviewedSources()
    {
        var repository = new RemoteRepository(Options());
        Assert.Contains("agent-contract", repository.Search("trusted"));
        Assert.Contains("helios-control", repository.Fetch("project"));
        var routing = repository.TaskRouting();
        Assert.Contains("review:csharp", routing);
        Assert.DoesNotContain("TEST_SECRET", routing);
        Assert.Throws<McpException>(() => repository.Search(new string('x', 201)));
    }

    [Fact]
    public void ScopeChecksRequireExactDelegatedScopeAndAuthenticatedIdentity()
    {
        var options = Options(Config(entra: true));
        Assert.False(options.HasScope(new ClaimsPrincipal(new ClaimsIdentity([new Claim("scp", "access_as_user")])), options.ReadScope));
        Assert.False(options.HasScope(new ClaimsPrincipal(new ClaimsIdentity([new Claim("scp", "access_as_user.evil")], "test")), options.ReadScope));
        Assert.False(options.HasScope(new ClaimsPrincipal(new ClaimsIdentity([new Claim("roles", "access_as_user")], "test")), options.ReadScope));
        Assert.True(options.HasScope(new ClaimsPrincipal(new ClaimsIdentity([new Claim("scp", "access_as_user claude.invoke")], "test")), options.ReadScope));
        Assert.Equal(Audience + "/access_as_user", options.OAuthScope(options.ReadScope));
        var custom = Config(entra: true);
        custom["HELIOS_REMOTE_AUDIENCE"] = "11111111-1111-1111-1111-111111111111";
        custom["HELIOS_REMOTE_SCOPE_RESOURCE"] = "api://helios.example.com/custom-api";
        custom["HELIOS_REMOTE_SCOPE"] = "project.read";
        var customOptions = Options(custom);
        Assert.Equal("api://helios.example.com/custom-api/project.read", customOptions.OAuthScope(customOptions.ReadScope));
    }

    [Fact]
    public async Task ClaudeDisabledAndMissingInvokeScopeNeverLaunchAProcess()
    {
        var options = Options(Config(entra: true));
        var bridge = new ClaudeTextBridge(options);
        Assert.Equal("disabled", (await bridge.AskAsync("hello", default)).State);
        var context = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("scp", "access_as_user")], "test")),
        };
        var tool = new RemoteClaudeTools(bridge, options, new HttpContextAccessor { HttpContext = context });
        await Assert.ThrowsAsync<McpException>(() => tool.Ask("hello"));
    }

    [Fact]
    public void ClaudeArgumentsDisableModelToolsAndKeepLoginWithoutBareMode()
    {
        var start = ClaudeTextBridge.BuildStartInfo("/trusted/claude", _root);
        Assert.False(start.UseShellExecute);
        Assert.True(start.RedirectStandardInput);
        Assert.Contains("--restricted", start.ArgumentList);
        Assert.Contains("--safe-mode", start.ArgumentList);
        Assert.DoesNotContain("--bare", start.ArgumentList);
        Assert.DoesNotContain("--dangerously-skip-permissions", start.ArgumentList);
        Assert.Equal("", start.ArgumentList[start.ArgumentList.IndexOf("--tools") + 1]);
        Assert.Contains("--no-session-persistence", start.ArgumentList);
        Assert.DoesNotContain("--resume", start.ArgumentList);
        start.Environment["SLACK_BOT_TOKEN"] = "TEST_SECRET";
        start.Environment["OPENAI_API_KEY"] = "TEST_SECRET";
        start.Environment["AZURE_CLIENT_SECRET"] = "TEST_SECRET";
        start.Environment["GITHUB_TOKEN"] = "TEST_SECRET";
        start.Environment["ANTHROPIC_BASE_URL"] = "https://attacker.example";
        start.Environment["CLAUDE_CODE_OAUTH_TOKEN"] = "TEST_CLAUDE_LOGIN";
        ClaudeTextBridge.FilterEnvironment(start);
        Assert.DoesNotContain(start.Environment, pair => pair.Value == "TEST_SECRET");
        Assert.False(start.Environment.ContainsKey("ANTHROPIC_BASE_URL"));
        Assert.Equal("TEST_CLAUDE_LOGIN", start.Environment["CLAUDE_CODE_OAUTH_TOKEN"]);
    }

    [Fact]
    public async Task StreamableHttpListsOnlyBoundedToolsAndFetchesSharedProject()
    {
        await using var app = await StartAsync(entra: false);
        using var client = app.GetTestClient(); client.BaseAddress = new Uri("http://127.0.0.1:7078");
        using var tools = await RpcAsync(client, "tools/list", new { });
        var names = tools.RootElement.GetProperty("result").GetProperty("tools").EnumerateArray()
            .Select(tool => tool.GetProperty("name").GetString()).ToArray();
        Assert.Equal(12, names.Length);
        Assert.Contains("search", names); Assert.Contains("fetch", names);
        Assert.DoesNotContain("helios_ai_ask", names); Assert.DoesNotContain("helios_claude_ask", names);
        using var fetched = await RpcAsync(client, "tools/call", new { name = "fetch", arguments = new { id = "project" } });
        Assert.Contains("helios-control", fetched.RootElement.ToString());
        using var refused = await RpcAsync(client, "tools/call", new { name = "fetch", arguments = new { id = "../../.env" } });
        Assert.True(refused.RootElement.GetProperty("result").GetProperty("isError").GetBoolean());
    }

    [Fact]
    public async Task EntraEndpointRequiresValidSignatureIssuerAudienceLifetimeAndScope()
    {
        await using var app = await StartAsync(entra: true);
        using var client = app.GetTestClient(); client.BaseAddress = new Uri("https://helios.example.com");
        using var noToken = await client.PostAsync("/mcp", RpcContent("tools/list", new { }));
        Assert.Equal(HttpStatusCode.Unauthorized, noToken.StatusCode);
        Assert.Contains("https://helios.example.com/.well-known/oauth-protected-resource/mcp", noToken.Headers.WwwAuthenticate.ToString());
        Assert.Contains(Audience + "/access_as_user", noToken.Headers.WwwAuthenticate.ToString());
        using var metadata = await client.GetAsync("/.well-known/oauth-protected-resource/mcp");
        var metadataText = await metadata.Content.ReadAsStringAsync();
        Assert.Contains($"https://login.microsoftonline.com/{Tenant}/v2.0", metadataText);
        Assert.Contains(Audience + "/handoff.write", metadataText);

        foreach (var token in new[]
        {
            Token(audience: "wrong-audience"), Token(issuer: "https://attacker.example"),
            Token(expired: true), Token(wrongSignature: true), "invalid-token",
        })
        {
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var denied = await client.PostAsync("/mcp", RpcContent("tools/list", new { }));
            Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
        }
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token(scope: "other"));
        using var noScope = await client.PostAsync("/mcp", RpcContent("tools/list", new { }));
        Assert.Equal(HttpStatusCode.Forbidden, noScope.StatusCode);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token());
        using var accepted = await RpcAsync(client, "tools/list", new { });
        Assert.True(accepted.RootElement.TryGetProperty("result", out _));
    }

    private async Task<WebApplication> StartAsync(bool entra)
    {
        var app = RemoteProgram.BuildApplication([], builder =>
        {
            builder.Configuration.AddInMemoryCollection(Config(entra));
            builder.WebHost.UseTestServer();
            builder.Services.AddSingleton<IStartupFilter, LoopbackTestPeer>();
            if (entra) builder.Services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, jwt =>
            {
                jwt.Configuration = new OpenIdConnectConfiguration { Issuer = $"https://login.microsoftonline.com/{Tenant}/v2.0" };
                jwt.Configuration.SigningKeys.Add(new RsaSecurityKey(_rsa) { KeyId = "test-key" });
            });
        });
        await app.StartAsync();
        return app;
    }

    private string Token(string? audience = null, string? issuer = null, string scope = "access_as_user", bool expired = false, bool wrongSignature = false)
    {
        using var other = RSA.Create(2048);
        return new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = issuer ?? $"https://login.microsoftonline.com/{Tenant}/v2.0", Audience = audience ?? Audience,
            Subject = new ClaimsIdentity([new Claim("scp", scope)]),
            NotBefore = DateTime.UtcNow.AddHours(-2), Expires = DateTime.UtcNow.AddMinutes(expired ? -30 : 30),
            SigningCredentials = new SigningCredentials(new RsaSecurityKey(wrongSignature ? other : _rsa) { KeyId = "test-key" }, SecurityAlgorithms.RsaSha256),
        });
    }

    private static StringContent RpcContent(string method, object parameters) => new(
        JsonSerializer.Serialize(new { jsonrpc = "2.0", id = 1, method, @params = parameters }), Encoding.UTF8, "application/json");

    private static async Task<JsonDocument> RpcAsync(HttpClient client, string method, object parameters)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/mcp") { Content = RpcContent(method, parameters) };
        request.Headers.Accept.ParseAdd("application/json, text/event-stream");
        request.Headers.Add("MCP-Protocol-Version", "2025-11-25");
        using var response = await client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadAsStringAsync();
        if (response.Content.Headers.ContentType?.MediaType == "text/event-stream")
            body = body.Split('\n').Last(line => line.StartsWith("data: ", StringComparison.Ordinal))[6..];
        return JsonDocument.Parse(body);
    }

    private sealed class LoopbackTestPeer : IStartupFilter
    {
        public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
        {
            app.Use((context, pipeline) => { context.Connection.RemoteIpAddress = IPAddress.Loopback; return pipeline(context); });
            next(app);
        };
    }

    public void Dispose() { _rsa.Dispose(); Directory.Delete(_root, recursive: true); }
}
