using System.Net;
using System.Text;
using System.Text.Json;
using Azure.Core;
using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Providers;
using Xunit;

namespace HELIOS.AIHub.Tests.Providers;

/// <summary>
/// Keyless and offline: every request terminates in <see cref="FakeHttpHandler"/>, which
/// records what the SDK actually put on the wire (URI, headers, JSON body) so the tests
/// pin the Foundry contract — endpoint shape, <c>anthropic-version</c>, key vs bearer auth —
/// rather than the SDK's internals.
/// </summary>
public class AnthropicFoundryAgentTests
{
    private const string OkBody =
        """{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-4-6","content":[{"type":"text","text":"Hello "},{"type":"text","text":"world"}],"stop_reason":"end_turn","usage":{"input_tokens":7,"output_tokens":3}}""";

    private static readonly Uri ResBase = new("https://res.services.ai.azure.com/anthropic");

    // ---- fakes ---------------------------------------------------------------------

    private sealed class FakeHttpHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _respond;

        public FakeHttpHandler(Func<HttpRequestMessage, HttpResponseMessage>? respond = null)
        {
            _respond = respond ?? (_ => Json(HttpStatusCode.OK, OkBody));
        }

        public List<(Uri? Uri, Dictionary<string, string> Headers, string Body)> Calls { get; } = new();

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken);
            var headers = request.Headers.ToDictionary(
                h => h.Key, h => string.Join(",", h.Value), StringComparer.OrdinalIgnoreCase);
            Calls.Add((request.RequestUri, headers, body));
            return _respond(request);
        }

        public static HttpResponseMessage Json(HttpStatusCode status, string body) =>
            new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
    }

    private sealed class FakeTokenCredential : TokenCredential
    {
        private readonly Func<AccessToken> _issue;

        public FakeTokenCredential(Func<AccessToken> issue) => _issue = issue;

        public int Requests { get; private set; }

        public List<string> Scopes { get; } = new();

        public override AccessToken GetToken(TokenRequestContext requestContext, CancellationToken cancellationToken)
        {
            Requests++;
            Scopes.AddRange(requestContext.Scopes);
            return _issue();
        }

        public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext requestContext, CancellationToken cancellationToken) =>
            new(GetToken(requestContext, cancellationToken));
    }

    private sealed class FakeClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.UnixEpoch;

        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class FakeSecrets : ISecretResolver
    {
        private readonly string? _value;

        public FakeSecrets(string? value) => _value = value;

        public string? Resolve(string? envName, string? secretName) => _value;
    }

    /// <summary>Every factory product derives from ProviderAgentBase, which carries the hint.</summary>
    private static ProviderAgentBase Build(ProviderOptions options, string? key) =>
        Assert.IsAssignableFrom<ProviderAgentBase>(
            ProviderFactory.Create("anthropic-foundry", options, new FakeSecrets(key)));

    // ---- (a) endpoint shape ----------------------------------------------------------

    [Fact]
    public async Task ResourceName_TargetsFoundryMessagesEndpoint_WithAnthropicVersionHeader()
    {
        Assert.True(AnthropicFoundryAgent.TryResolveBaseUri("res", "ANTHROPIC_FOUNDRY_RESOURCE", out var baseUri, out _));
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "my-deployment", baseUri!, "k1", http);

        var result = await agent.ChatAsync(new ChatRequest("hi"));

        Assert.True(result.Success, result.Error);
        var call = Assert.Single(http.Calls);
        Assert.Equal(new Uri("https://res.services.ai.azure.com/anthropic/v1/messages"), call.Uri);
        Assert.Equal("2023-06-01", call.Headers["anthropic-version"]);
        // Foundry's documented request carries no anthropic-beta header.
        Assert.False(call.Headers.ContainsKey("anthropic-beta"));
    }

    [Fact]
    public async Task Request_SendsDeploymentNameAsModel_WithSystemTemperatureAndMaxTokens()
    {
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "default-deploy", ResBase, "k1", http);

        await agent.ChatAsync(new ChatRequest("hello", System: "be brief", MaxTokens: 42, Temperature: 0.5, Model: "other-deploy"));

        using var body = JsonDocument.Parse(Assert.Single(http.Calls).Body);
        var root = body.RootElement;
        Assert.Equal("other-deploy", root.GetProperty("model").GetString());
        Assert.Equal(42, root.GetProperty("max_tokens").GetInt32());
        Assert.Equal(0.5m, root.GetProperty("temperature").GetDecimal());
        Assert.Equal("be brief", root.GetProperty("system")[0].GetProperty("text").GetString());
        var message = Assert.Single(root.GetProperty("messages").EnumerateArray());
        Assert.Equal("user", message.GetProperty("role").GetString());
    }

    [Fact]
    public async Task Request_FallsBackToDefaultDeployment_WhenNoneConfigured()
    {
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", null, ResBase, "k1", http);

        await agent.ChatAsync(new ChatRequest("hello"));

        using var body = JsonDocument.Parse(Assert.Single(http.Calls).Body);
        Assert.Equal(AnthropicFoundryAgent.DefaultDeployment, body.RootElement.GetProperty("model").GetString());
    }

    // ---- (b) Entra mode --------------------------------------------------------------

    [Fact]
    public async Task EntraMode_SendsBearerToken_AndNoApiKeyHeader()
    {
        var clock = new FakeClock();
        var credential = new FakeTokenCredential(() => new AccessToken("fake-token", clock.Now.AddHours(1)));
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "d", ResBase, credential, http, clock);

        Assert.Equal(ProviderReadiness.Ready, agent.Readiness);
        Assert.Null(agent.ConfigurationHint);
        Assert.Equal(0, credential.Requests); // lazy: nothing acquired at construction

        var result = await agent.ChatAsync(new ChatRequest("hi"));

        Assert.True(result.Success, result.Error);
        var call = Assert.Single(http.Calls);
        Assert.Equal("Bearer fake-token", call.Headers["Authorization"]);
        Assert.False(call.Headers.ContainsKey("x-api-key"));
        Assert.Equal("2023-06-01", call.Headers["anthropic-version"]);
        Assert.Equal(new[] { AnthropicFoundryAgent.EntraScope }, credential.Scopes);
    }

    [Fact]
    public async Task EntraMode_CachesToken_AndRefreshesInsideFiveMinuteWindow()
    {
        var clock = new FakeClock();
        var issued = 0;
        var credential = new FakeTokenCredential(() => new AccessToken($"tok-{++issued}", clock.Now.AddHours(1)));
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "d", ResBase, credential, http, clock);

        await agent.ChatAsync(new ChatRequest("1"));
        await agent.ChatAsync(new ChatRequest("2"));
        Assert.Equal(1, credential.Requests);
        Assert.Equal("Bearer tok-1", http.Calls[1].Headers["Authorization"]);

        // 56 minutes later the token has 4 minutes left: inside the refresh window.
        clock.Now = clock.Now.AddMinutes(56);
        await agent.ChatAsync(new ChatRequest("3"));
        Assert.Equal(2, credential.Requests);
        Assert.Equal("Bearer tok-2", http.Calls[2].Headers["Authorization"]);
    }

    [Fact]
    public async Task EntraMode_CredentialFailure_BecomesFailedResult_NotThrow()
    {
        var credential = new FakeTokenCredential(() => throw new Azure.Identity.CredentialUnavailableException("no az login"));
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "d", ResBase, credential, http);

        var result = await agent.ChatAsync(new ChatRequest("hi"));

        Assert.False(result.Success);
        Assert.Contains("no az login", result.Error);
        Assert.Empty(http.Calls);
    }

    // ---- (c) key mode ----------------------------------------------------------------

    [Fact]
    public async Task KeyMode_SendsXApiKey_AndNoAuthorizationHeader()
    {
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "d", ResBase, "k1", http);

        Assert.Equal(ProviderReadiness.Ready, agent.Readiness);
        var result = await agent.ChatAsync(new ChatRequest("hi"));

        Assert.True(result.Success, result.Error);
        var call = Assert.Single(http.Calls);
        Assert.Equal("k1", call.Headers["x-api-key"]);
        Assert.False(call.Headers.ContainsKey("Authorization"));
    }

    // ---- (d) endpoint normalization --------------------------------------------------

    [Theory]
    [InlineData("helios-aijcut", "https://helios-aijcut.services.ai.azure.com/anthropic")]
    [InlineData("  helios-aijcut  ", "https://helios-aijcut.services.ai.azure.com/anthropic")]
    [InlineData("https://x.services.ai.azure.com", "https://x.services.ai.azure.com/anthropic")]
    [InlineData("https://x.services.ai.azure.com/", "https://x.services.ai.azure.com/anthropic")]
    [InlineData("https://x.services.ai.azure.com/anthropic", "https://x.services.ai.azure.com/anthropic")]
    [InlineData("https://x.services.ai.azure.com/anthropic/", "https://x.services.ai.azure.com/anthropic")]
    [InlineData("https://x.services.ai.azure.com/anthropic/v1/messages", "https://x.services.ai.azure.com/anthropic")]
    [InlineData("https://x.services.ai.azure.com/anthropic?api-version=1#frag", "https://x.services.ai.azure.com/anthropic")]
    [InlineData("https://gateway.example.com:8443/claude/", "https://gateway.example.com:8443/claude/anthropic")]
    public void TryResolveBaseUri_NormalizesResourceNamesAndUrls(string input, string expected)
    {
        Assert.True(AnthropicFoundryAgent.TryResolveBaseUri(input, "ANTHROPIC_FOUNDRY_RESOURCE", out var baseUri, out var hint), hint);
        Assert.Equal(expected, baseUri!.AbsoluteUri);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void TryResolveBaseUri_Blank_HintsToSetTheVariable(string? input)
    {
        Assert.False(AnthropicFoundryAgent.TryResolveBaseUri(input, "ANTHROPIC_FOUNDRY_RESOURCE", out var baseUri, out var hint));
        Assert.Null(baseUri);
        Assert.Contains("Set ANTHROPIC_FOUNDRY_RESOURCE", hint);
        Assert.Contains("Connect-ClaudeFoundry.ps1", hint);
    }

    [Theory]
    [InlineData("http://x.services.ai.azure.com/anthropic")] // https only
    [InlineData("ftp://x.services.ai.azure.com")]
    [InlineData("not a resource name")]
    [InlineData("-leading-hyphen")]
    [InlineData("under_score")]
    [InlineData("/relative/path")]
    [InlineData("x.services.ai.azure.com/anthropic")] // dotted host without scheme
    [InlineData("https://user:dummy-not-a-credential@x.services.ai.azure.com/anthropic")] // userinfo never rides in the resource value
    [InlineData("https://user@x.services.ai.azure.com/anthropic")]
    public void TryResolveBaseUri_Malformed_HintsNamingTheSource(string input)
    {
        Assert.False(AnthropicFoundryAgent.TryResolveBaseUri(input, "ANTHROPIC_FOUNDRY_RESOURCE", out var baseUri, out var hint));
        Assert.Null(baseUri);
        Assert.Contains("ANTHROPIC_FOUNDRY_RESOURCE", hint);
        Assert.Contains("https", hint);
        Assert.DoesNotContain("dummy-not-a-credential", hint);
    }

    // ---- (e) Unconfigured: no HTTP, hint surfaces --------------------------------------

    [Fact]
    public async Task Unconfigured_ReturnsHint_WithoutHttpCall()
    {
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "d",
            "Set ANTHROPIC_FOUNDRY_RESOURCE (Foundry resource name or https base URL).");

        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
        var result = await agent.ChatAsync(new ChatRequest("q"));

        Assert.False(result.Success);
        Assert.Contains("ANTHROPIC_FOUNDRY_RESOURCE", result.Error);
        Assert.Equal(0, agent.GetMetrics().TotalRequestsProcessed);
    }

    [Fact]
    public void Factory_MissingResourceEnv_IsUnconfigured_WithHintNamingTheEnvVar()
    {
        var envName = "HELIOS_TEST_UNSET_FOUNDRY_" + Guid.NewGuid().ToString("N");
        var agent = Build(new ProviderOptions { Type = "anthropic-foundry", Model = "d", EndpointEnv = envName }, "some-key");

        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
        Assert.Contains(envName, agent.ConfigurationHint);
        Assert.Contains("https base URL", agent.ConfigurationHint);
    }

    [Fact]
    public void Factory_BlankEndpointEnv_NoBaseUrl_IsUnconfigured_NamingTheConfigProperty()
    {
        // A declared-blank endpointEnv names no variable: the factory must not read the
        // variable "" and the hint must name the config property, not an empty name.
        var agent = Build(new ProviderOptions { Type = "anthropic-foundry", Model = "d", EndpointEnv = "" }, "some-key");

        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
        Assert.Contains("endpointEnv", agent.ConfigurationHint);
        Assert.Contains("ANTHROPIC_FOUNDRY_RESOURCE", agent.ConfigurationHint);
        Assert.Contains("baseUrl", agent.ConfigurationHint);
        Assert.DoesNotContain("Set  ", agent.ConfigurationHint);
    }

    [Fact]
    public void Factory_BlankEndpointEnv_WithBaseUrl_StillResolves()
    {
        var agent = Build(new ProviderOptions { Type = "anthropic-foundry", Model = "d", EndpointEnv = "", BaseUrl = "https://x.services.ai.azure.com" }, "key");

        Assert.Equal(ProviderReadiness.Ready, agent.Readiness);
        Assert.Null(agent.ConfigurationHint);
    }

    [Fact]
    public void Factory_AzureOpenAi_BlankEndpointEnv_IsUnconfigured_NamingTheConfigProperty()
    {
        // The same guard applies to the provider whose contract this one mirrors.
        var agent = Assert.IsAssignableFrom<ProviderAgentBase>(
            ProviderFactory.Create("azure-openai", new ProviderOptions { Type = "azure-openai", Model = "d", EndpointEnv = "" }, new FakeSecrets(null)));

        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
        Assert.Contains("endpointEnv", agent.ConfigurationHint);
        Assert.Contains("AZURE_OPENAI_ENDPOINT", agent.ConfigurationHint);
    }

    [Fact]
    public void Factory_MalformedBaseUrl_IsUnconfigured_NamingTheConfigKey()
    {
        var agent = Build(new ProviderOptions { Type = "anthropic-foundry", Model = "d", BaseUrl = "http://insecure.example", EndpointEnv = "HELIOS_TEST_UNSET_" + Guid.NewGuid().ToString("N") }, null);

        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
        Assert.Contains("baseUrl", agent.ConfigurationHint);
        Assert.Contains("config/aihub.json", agent.ConfigurationHint);
    }

    [Fact]
    public void Factory_ValidBaseUrl_NoKey_IsReady_ViaEntraFallback()
    {
        var agent = Build(new ProviderOptions { Type = "anthropic-foundry", Model = "d", BaseUrl = "https://x.services.ai.azure.com", EndpointEnv = "HELIOS_TEST_UNSET_" + Guid.NewGuid().ToString("N") }, null);

        // Same contract as azure-openai: a missing key means Entra ID, not Unconfigured.
        Assert.IsType<AnthropicFoundryAgent>(agent);
        Assert.Equal(ProviderReadiness.Ready, agent.Readiness);
        Assert.Null(agent.ConfigurationHint);
    }

    [Fact]
    public void Factory_ValidBaseUrl_WithKey_IsReady()
    {
        var agent = Build(new ProviderOptions { Type = "anthropic-foundry", Model = "d", BaseUrl = "https://x.services.ai.azure.com/anthropic/", EndpointEnv = "HELIOS_TEST_UNSET_" + Guid.NewGuid().ToString("N") }, "key");

        Assert.Equal(ProviderReadiness.Ready, agent.Readiness);
        Assert.Equal("aihub-anthropic-foundry", agent.AgentId);
    }

    [Fact]
    public void Factory_UnknownType_HintListsAnthropicFoundry()
    {
        var agent = Assert.IsAssignableFrom<ProviderAgentBase>(
            ProviderFactory.Create("x", new ProviderOptions { Type = "nope" }, new FakeSecrets(null)));

        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
        Assert.Contains("anthropic-foundry", agent.ConfigurationHint);
    }

    // ---- (f) response mapping ---------------------------------------------------------

    [Fact]
    public async Task Response_ConcatenatesTextBlocks_AndMapsUsage()
    {
        var http = new FakeHttpHandler();
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "d", ResBase, "k1", http);

        var result = await agent.ChatAsync(new ChatRequest("hi"));

        Assert.True(result.Success, result.Error);
        Assert.Equal("Hello world", result.Text);
        Assert.Equal("claude-sonnet-4-6", result.Model);
        Assert.Equal(7, result.InputTokens);
        Assert.Equal(3, result.OutputTokens);
        Assert.Equal("anthropic-foundry", result.Provider);
        Assert.Equal(1, agent.GetMetrics().SuccessfulRequests);
    }

    // ---- (g) transport failure -------------------------------------------------------

    [Fact]
    public async Task Transport401_BecomesFailedResult_WithErrorText_NotThrow()
    {
        var http = new FakeHttpHandler(_ => FakeHttpHandler.Json(
            HttpStatusCode.Unauthorized,
            """{"error":{"type":"authentication_error","message":"invalid token for scope"}}"""));
        var agent = new AnthropicFoundryAgent("anthropic-foundry", "Claude (Foundry)", "d", ResBase, "bad-key", http);

        var result = await agent.ChatAsync(new ChatRequest("hi"));

        Assert.False(result.Success);
        Assert.Null(result.Text);
        Assert.Contains("invalid token for scope", result.Error);
        Assert.Equal(1, agent.GetMetrics().FailedRequests);
    }
}
