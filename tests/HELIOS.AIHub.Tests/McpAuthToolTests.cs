using System.Reflection;
using System.Text.Json;
using Azure.Identity;
using HELIOS.AIHub.Providers;
using HELIOS.Mcp;
using ModelContextProtocol;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The auth-lane diagnosis MCP tool (helios_auth_status_get) and its service. Keyless
/// and deterministic: the az lane runs against a scripted <see cref="IAzureTokenProbe"/>
/// fake, the gh/provider lanes against environment variables that are saved on
/// construction and restored on dispose, and the provider lanes against a fabricated
/// repo root whose config declares test-only env names. The recurring assertion is the
/// secrets policy: env-var VALUES must never appear anywhere in the tool's output.
/// </summary>
public sealed class McpAuthToolTests : IDisposable
{
    private const string FakeKeyEnvA = "HELIOS_TEST_AUTH_KEY_A";
    private const string FakeKeyEnvB = "HELIOS_TEST_AUTH_KEY_B";
    private const string SecretValue = "fake-secret-value-that-must-never-leak-1a2b3c";

    /// <summary>Every variable any test here mutates — saved up front, restored in Dispose.</summary>
    private static readonly string[] MutatedVariables =
    {
        "GH_TOKEN", "GITHUB_TOKEN", "GITHUB_ACTIONS", FakeKeyEnvA, FakeKeyEnvB,
    };

    private readonly Dictionary<string, string?> _savedEnv = new();
    private readonly List<string> _roots = new();

    public McpAuthToolTests()
    {
        foreach (var name in MutatedVariables)
        {
            _savedEnv[name] = Environment.GetEnvironmentVariable(name);
        }
    }

    public void Dispose()
    {
        foreach (var (name, value) in _savedEnv)
        {
            Environment.SetEnvironmentVariable(name, value);
        }
        foreach (var root in _roots)
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    // ---- discoverability -----------------------------------------------------------

    [Fact]
    public void AuthTool_IsDiscoverable_ReadOnlyIdempotentOpenWorld()
    {
        var method = typeof(HeliosAuthTools).GetMethod(
            nameof(HeliosAuthTools.GetAuthStatus), BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal("helios_auth_status_get", attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(true, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("Idempotent")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("OpenWorld")?.GetValue(toolAttribute));
    }

    // ---- github lane (names only, gh precedence) -------------------------------------

    [Fact]
    public async Task GitHubLane_BothTokensSet_ReportsGhTokenName_AndNeverTheValues()
    {
        Environment.SetEnvironmentVariable("GH_TOKEN", SecretValue);
        Environment.SetEnvironmentVariable("GITHUB_TOKEN", SecretValue + "-second");

        var json = await HeliosAuthTools.GetAuthStatus(AuthenticatedService());
        using var doc = JsonDocument.Parse(json);

        var github = doc.RootElement.GetProperty("github");
        Assert.True(github.GetProperty("set").GetBoolean());
        // GH_TOKEN wins when both are set — the precedence gh itself applies.
        Assert.Equal("GH_TOKEN", github.GetProperty("tokenEnv").GetString());
        Assert.DoesNotContain(SecretValue, json);
    }

    [Fact]
    public async Task GitHubLane_OnlyGithubTokenSet_ReportsThatName()
    {
        Environment.SetEnvironmentVariable("GH_TOKEN", null);
        Environment.SetEnvironmentVariable("GITHUB_TOKEN", SecretValue);

        var json = await HeliosAuthTools.GetAuthStatus(AuthenticatedService());
        using var doc = JsonDocument.Parse(json);

        var github = doc.RootElement.GetProperty("github");
        Assert.True(github.GetProperty("set").GetBoolean());
        Assert.Equal("GITHUB_TOKEN", github.GetProperty("tokenEnv").GetString());
        Assert.DoesNotContain(SecretValue, json);
    }

    [Fact]
    public async Task GitHubLane_NoTokenSet_ReportsUnset_WithoutTokenEnv()
    {
        Environment.SetEnvironmentVariable("GH_TOKEN", null);
        Environment.SetEnvironmentVariable("GITHUB_TOKEN", null);

        var json = await HeliosAuthTools.GetAuthStatus(AuthenticatedService());
        using var doc = JsonDocument.Parse(json);

        var github = doc.RootElement.GetProperty("github");
        Assert.False(github.GetProperty("set").GetBoolean());
        Assert.False(github.TryGetProperty("tokenEnv", out _));
    }

    // ---- azure lane through the fake probe seam --------------------------------------

    [Fact]
    public async Task AzureLane_ProbeSucceeds_ReportsAuthenticated_NoHint()
    {
        var probe = new FakeTokenProbe();

        var json = await HeliosAuthTools.GetAuthStatus(Service(probe));
        using var doc = JsonDocument.Parse(json);

        var azure = doc.RootElement.GetProperty("azure");
        Assert.True(azure.GetProperty("authenticated").GetBoolean());
        Assert.False(azure.TryGetProperty("hint", out _));
        Assert.Equal(1, probe.Probes);
    }

    [Fact]
    public async Task AzureLane_CredentialChainFails_ReturnsHint_NeverThrows()
    {
        // CredentialUnavailableException is what a fully exhausted DefaultAzureCredential
        // chain throws (it derives from AuthenticationFailedException).
        var probe = new FakeTokenProbe
        {
            Failure = new CredentialUnavailableException(
                "DefaultAzureCredential failed to retrieve a token from the included credentials."),
        };

        var json = await HeliosAuthTools.GetAuthStatus(Service(probe));
        using var doc = JsonDocument.Parse(json);

        var azure = doc.RootElement.GetProperty("azure");
        Assert.False(azure.GetProperty("authenticated").GetBoolean());
        var hint = azure.GetProperty("hint").GetString();
        Assert.Contains("az login", hint);
        Assert.StartsWith(AzureResourceService.UnauthenticatedHint, hint);
    }

    [Fact]
    public async Task AzureLane_ProbeTimesOut_ReportsUnauthenticated_NotACrash()
    {
        var probe = new FakeTokenProbe { TimesOut = true };

        var report = await Service(probe).GetStatusAsync();

        Assert.False(report.Azure.Authenticated);
        Assert.Contains("timed out", report.Azure.Hint);
        Assert.Contains("az login", report.Azure.Hint);
    }

    // ---- provider lanes against a fabricated config -----------------------------------

    [Fact]
    public async Task ProviderLanes_ReportDeclaredEnvNames_AndSetState_ValuesNeverLeak()
    {
        var root = CreateRepoRoot();
        Environment.SetEnvironmentVariable(FakeKeyEnvA, SecretValue);
        Environment.SetEnvironmentVariable(FakeKeyEnvB, null);

        var json = await HeliosAuthTools.GetAuthStatus(AuthenticatedService(root));
        using var doc = JsonDocument.Parse(json);

        var providers = doc.RootElement.GetProperty("providers").EnumerateArray().ToList();
        Assert.Equal(3, providers.Count);

        var alpha = providers.Single(p => p.GetProperty("name").GetString() == "alpha");
        Assert.Equal(FakeKeyEnvA, alpha.GetProperty("apiKeyEnv").GetString());
        Assert.True(alpha.GetProperty("set").GetBoolean());

        var beta = providers.Single(p => p.GetProperty("name").GetString() == "beta");
        Assert.Equal(FakeKeyEnvB, beta.GetProperty("apiKeyEnv").GetString());
        Assert.False(beta.GetProperty("set").GetBoolean());

        // No apiKeyEnv declared (ollama-style): "nothing to check" is omitted, not
        // reported as a missing key.
        var keyless = providers.Single(p => p.GetProperty("name").GetString() == "keyless");
        Assert.False(keyless.TryGetProperty("apiKeyEnv", out _));
        Assert.False(keyless.TryGetProperty("set", out _));

        Assert.DoesNotContain(SecretValue, json);
        Assert.False(doc.RootElement.TryGetProperty("providersHint", out _));
    }

    [Fact]
    public async Task ProviderLanes_MissingConfig_DegradesToHint_NotAnError()
    {
        // A bare directory with no config/aihub.json anywhere up its (temp) ancestry.
        var root = CreateBareDirectory();

        var json = await HeliosAuthTools.GetAuthStatus(AuthenticatedService(root));
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(0, doc.RootElement.GetProperty("providers").GetArrayLength());
        Assert.Contains("config/aihub.json", doc.RootElement.GetProperty("providersHint").GetString());
    }

    [Fact]
    public async Task ProviderLanes_UnreadableConfig_ThrowsMcpException_NamingTheFile()
    {
        var root = CreateBareDirectory();
        Directory.CreateDirectory(Path.Combine(root, "config"));
        File.WriteAllText(Path.Combine(root, "config", "aihub.json"), "{ this is not json");

        var ex = await Assert.ThrowsAsync<McpException>(
            () => HeliosAuthTools.GetAuthStatus(AuthenticatedService(root)));

        Assert.Contains("aihub.json", ex.Message);
    }

    // ---- environment heuristic and the diagnose-only note ----------------------------

    [Theory]
    [InlineData("true", "actions")]
    [InlineData("TRUE", "actions")]
    [InlineData(null, "local")]
    [InlineData("false", "local")]
    public async Task Environment_ActionsHeuristic_FollowsGithubActionsVariable(
        string? githubActions, string expected)
    {
        Environment.SetEnvironmentVariable("GITHUB_ACTIONS", githubActions);

        var json = await HeliosAuthTools.GetAuthStatus(AuthenticatedService());
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(expected, doc.RootElement.GetProperty("environment").GetString());
    }

    [Fact]
    public async Task Note_StatesDiagnoseOnly_AndPointsToAuthDoctor()
    {
        var json = await HeliosAuthTools.GetAuthStatus(AuthenticatedService());
        using var doc = JsonDocument.Parse(json);

        var note = doc.RootElement.GetProperty("note").GetString();
        Assert.Contains("scripts/bootstrap/auth-doctor.ps1", note);
        Assert.Contains("Diagnose-only", note);
        Assert.Contains("nothing was repaired", note);
    }

    // ---- helpers ---------------------------------------------------------------------

    /// <summary>Service over a probe that succeeds, anchored at a fabricated repo root.</summary>
    private AuthStatusService AuthenticatedService(string? root = null) =>
        Service(new FakeTokenProbe(), root);

    private AuthStatusService Service(FakeTokenProbe probe, string? root = null) =>
        new(() => probe, root ?? CreateRepoRoot());

    /// <summary>
    /// Fabricates a repo root whose config/aihub.json declares three providers: two with
    /// test-only apiKeyEnv names and one keyless (ollama-style, endpoint-configured).
    /// </summary>
    private string CreateRepoRoot()
    {
        var root = CreateBareDirectory();
        Directory.CreateDirectory(Path.Combine(root, "config"));
        File.WriteAllText(Path.Combine(root, "config", "aihub.json"), $$"""
            {
              "providers": {
                "alpha": { "type": "openai", "model": "m-a", "apiKeyEnv": "{{FakeKeyEnvA}}" },
                "beta": { "type": "anthropic", "model": "m-b", "apiKeyEnv": "{{FakeKeyEnvB}}" },
                "keyless": { "type": "ollama", "model": "m-c", "endpointEnv": "HELIOS_TEST_AUTH_ENDPOINT" }
              }
            }
            """);
        return root;
    }

    private string CreateBareDirectory()
    {
        var root = Path.Combine(Path.GetTempPath(), $"helios-mcp-auth-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        _roots.Add(root);
        return root;
    }

    /// <summary>Scriptable token probe: hand-rolled fake per the repo's no-Moq idiom.</summary>
    private sealed class FakeTokenProbe : IAzureTokenProbe
    {
        /// <summary>When set, every probe throws it (credential-chain failure).</summary>
        public AuthenticationFailedException? Failure { get; init; }

        /// <summary>Simulate the probe's internal timeout (an OCE the caller did not request).</summary>
        public bool TimesOut { get; init; }

        public int Probes { get; private set; }

        public Task ProbeAsync(CancellationToken cancellationToken)
        {
            Probes++;
            if (Failure is not null)
            {
                throw Failure;
            }
            if (TimesOut)
            {
                // The production probe's CancelAfter fires on ITS linked token, not the
                // caller's — so the caller's token reads not-cancelled.
                throw new OperationCanceledException("The token probe timed out.");
            }
            return Task.CompletedTask;
        }
    }
}
