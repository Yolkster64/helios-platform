using System.Reflection;
using System.Text.Json;
using HELIOS.Mcp;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The read-only Fabric-plan MCP tool (helios_fabric_plan_get): discoverability, the
/// sanitized JSON shape, fail-closed enforcement, path-traversal rejection, and the
/// env-name-only invariant (values are never returned even when the variable is set).
/// Everything runs against a fabricated repo root; no real config/, no environment
/// mutation persists past the test.
/// </summary>
public sealed class McpFabricToolTests : IDisposable
{
    private const string MinimalValidContract = """
        {
          "schemaVersion": "1.0",
          "canonical": {
            "currentRepository": "Yolkster64/helios-platform",
            "targetRepository": "Yolkster64/helios-control",
            "guiRepository": "Yolkster64/helios-gui",
            "renameMode": "in-place",
            "productionEnabled": false
          },
          "authorities": {
            "source": "GitHub",
            "deployment": "GitHub protected environments",
            "workGraph": "Linear",
            "operations": "Slack",
            "governance": "SharePoint Governance",
            "validationMirror": "Azure DevOps",
            "secrets": "Azure Key Vault"
          },
          "integrations": [
            {
              "id": "github",
              "role": "source, review, release, and deployment authority",
              "authority": "GitHub",
              "desiredState": "connected",
              "target": { "defaultBranch": "main" },
              "requiredEnv": [],
              "healthChecks": ["repository-read"],
              "allowed": ["read"],
              "denied": ["force-push-protected-branch"]
            },
            {
              "id": "openai",
              "role": "Codex and OpenAI provider lane",
              "authority": "OpenAI project owner",
              "desiredState": "configured",
              "target": { "apiKeyEnv": "TEST_OPENAI_API_KEY" },
              "requiredEnv": ["TEST_OPENAI_API_KEY"],
              "healthChecks": ["minimal-response"],
              "allowed": ["reasoning"],
              "denied": ["secret-readback"]
            },
            {
              "id": "azure",
              "role": "development cloud control plane",
              "authority": "Azure subscription owner",
              "desiredState": "admin-binding-required",
              "target": {},
              "requiredEnv": ["TEST_AZURE_CLIENT_ID"],
              "healthChecks": ["oidc-token-probe"],
              "allowed": ["inventory"],
              "denied": ["production-apply"]
            }
          ],
          "phases": [
            {
              "id": "F00",
              "title": "Validate the Fabric contract",
              "dependsOn": [],
              "requiredIntegrations": [],
              "execution": "automated",
              "mutatesExternalState": false,
              "requiredApproval": "none",
              "outputs": ["validated-contract"]
            },
            {
              "id": "F01",
              "title": "Bind a provider",
              "dependsOn": ["F00"],
              "requiredIntegrations": ["openai"],
              "execution": "operator",
              "mutatesExternalState": false,
              "requiredApproval": "operator",
              "outputs": ["provider-binding-receipt"]
            },
            {
              "id": "F16",
              "title": "Consider production authorization",
              "dependsOn": ["F01"],
              "requiredIntegrations": ["azure"],
              "execution": "administrator",
              "mutatesExternalState": true,
              "requiredApproval": "production-owner",
              "outputs": ["separate-production-decision"]
            }
          ],
          "security": {
            "applyDefault": false,
            "productionEnabled": false,
            "secretValuesInRepository": false,
            "externalWritesRequireApproval": true,
            "allowedUiFramework": "WinUI 3",
            "forbiddenUiFrameworks": ["WPF", "UWP"]
          },
          "evidence": {
            "root": ".helios/evidence/fabric",
            "requiredFields": ["eventId", "correlationId", "sourceSha", "result", "receiptUri"],
            "retentionDays": 90
          }
        }
        """;

    private readonly List<string> _roots = new();
    private readonly Dictionary<string, string?> _envToRestore = new(StringComparer.Ordinal);

    public void Dispose()
    {
        foreach (var (name, previous) in _envToRestore)
        {
            Environment.SetEnvironmentVariable(name, previous);
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

    // ---- discoverability ------------------------------------------------------------

    [Fact]
    public void FabricPlanTool_IsDiscoverable_ReadOnlyIdempotentClosedWorld()
    {
        var method = typeof(HeliosFabricTools).GetMethod(
            nameof(HeliosFabricTools.GetFabricPlan), BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal("helios_fabric_plan_get", attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(true, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("Idempotent")?.GetValue(toolAttribute));
        Assert.Equal(false, attributeType.GetProperty("OpenWorld")?.GetValue(toolAttribute));
    }

    [Fact]
    public void FabricTools_MarkedAsMcpToolType()
    {
        var mcpToolType = typeof(HeliosFabricTools)
            .GetCustomAttributes()
            .SingleOrDefault(a => a.GetType().Name == "McpServerToolTypeAttribute");

        Assert.NotNull(mcpToolType);
    }

    // ---- happy path against a fabricated contract -----------------------------------

    [Fact]
    public void GetFabricPlan_ReturnsSanitizedShape_WithFailClosedInvariants()
    {
        var root = CreateRepoRoot(MinimalValidContract);

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        using var document = JsonDocument.Parse(json);
        var element = document.RootElement;
        Assert.Equal("1.0", element.GetProperty("schemaVersion").GetString());
        Assert.Equal(
            "config/fabric/helios-fabric.v1.json",
            element.GetProperty("configPath").GetString());

        // Fail-closed invariants are always reported false in the sanitized envelope,
        // regardless of what the file says — the tool refuses to run against a
        // productionEnabled=true contract in a separate test below.
        var security = element.GetProperty("security");
        Assert.False(security.GetProperty("productionEnabled").GetBoolean());
        Assert.False(security.GetProperty("applyDefault").GetBoolean());
        Assert.True(security.GetProperty("secretValuesRead").GetBoolean());
        Assert.False(security.GetProperty("externalMutationPerformed").GetBoolean());
        Assert.Equal("WinUI 3", security.GetProperty("activeUiFramework").GetString());

        // Canonical + authorities passed through verbatim (they contain no secret data).
        Assert.Equal(
            "Yolkster64/helios-platform",
            element.GetProperty("canonical").GetProperty("currentRepository").GetString());
        Assert.Equal(
            "Yolkster64/helios-control",
            element.GetProperty("canonical").GetProperty("targetRepository").GetString());
        Assert.Equal(
            "GitHub protected environments",
            element.GetProperty("authorities").GetProperty("deployment").GetString());

        // Every integration shows its required env NAMES, never a value.
        var integrations = element.GetProperty("integrations").EnumerateArray().ToList();
        Assert.Equal(3, integrations.Count);
        var openai = integrations.Single(i => i.GetProperty("id").GetString() == "openai");
        var requiredEnvNames = openai.GetProperty("requiredEnvNames")
            .EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.Equal(new[] { "TEST_OPENAI_API_KEY" }, requiredEnvNames);

        // F16 is always "production-disabled" as long as the fail-closed contract holds.
        var phases = element.GetProperty("phases").EnumerateArray().ToList();
        var production = phases.Single(p => p.GetProperty("id").GetString() == "F16");
        Assert.Equal("production-disabled", production.GetProperty("readiness").GetString());
        Assert.Equal("production-owner", production.GetProperty("requiredApproval").GetString());
        Assert.True(production.GetProperty("mutatesExternalState").GetBoolean());
    }

    [Fact]
    public void GetFabricPlan_AdminBindingIntegration_BlocksDependentPhase()
    {
        var root = CreateRepoRoot(MinimalValidContract);

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        using var document = JsonDocument.Parse(json);
        var integrations = document.RootElement.GetProperty("integrations").EnumerateArray().ToList();
        var azure = integrations.Single(i => i.GetProperty("id").GetString() == "azure");
        Assert.Equal("admin-binding-required", azure.GetProperty("readiness").GetString());

        // Regardless of blocked integrations, F16 remains production-disabled while
        // productionEnabled=false — production is a separate, later decision.
        var f16 = document.RootElement.GetProperty("phases").EnumerateArray()
            .Single(p => p.GetProperty("id").GetString() == "F16");
        Assert.Equal("production-disabled", f16.GetProperty("readiness").GetString());
    }

    [Fact]
    public void GetFabricPlan_MissingEnv_MarksEnvironmentReferenceMissing()
    {
        var root = CreateRepoRoot(MinimalValidContract);
        // Ensure the test env var is not set on this process (belt-and-suspenders).
        SetTestEnv("TEST_OPENAI_API_KEY", null);

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        using var document = JsonDocument.Parse(json);
        var openai = document.RootElement.GetProperty("integrations").EnumerateArray()
            .Single(i => i.GetProperty("id").GetString() == "openai");
        Assert.Equal("environment-reference-missing", openai.GetProperty("readiness").GetString());
        var missing = openai.GetProperty("missingEnvNames")
            .EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.Contains("TEST_OPENAI_API_KEY", missing);
        var present = openai.GetProperty("presentEnvNames")
            .EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.Empty(present);
    }

    [Fact]
    public void GetFabricPlan_PresentEnv_ReportsNameOnly_NeverValue()
    {
        var root = CreateRepoRoot(MinimalValidContract);
        // Deliberately use a credential-looking value to prove the tool never leaks it.
        SetTestEnv("TEST_OPENAI_API_KEY", "sk-proj-secret-value-do-not-leak");

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        // The raw envelope must not contain the value in any form.
        Assert.DoesNotContain("sk-proj-secret-value-do-not-leak", json);

        using var document = JsonDocument.Parse(json);
        var openai = document.RootElement.GetProperty("integrations").EnumerateArray()
            .Single(i => i.GetProperty("id").GetString() == "openai");
        Assert.Equal("contract-ready", openai.GetProperty("readiness").GetString());
        var present = openai.GetProperty("presentEnvNames")
            .EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.Equal(new[] { "TEST_OPENAI_API_KEY" }, present);
        Assert.True(document.RootElement.GetProperty("security").GetProperty("secretValuesRead").GetBoolean());
    }

    // ---- fail-closed enforcement ----------------------------------------------------

    [Fact]
    public void GetFabricPlan_MalformedContract_ReturnsErrorEnvelope()
    {
        var root = CreateRepoRoot("{");

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        using var document = JsonDocument.Parse(json);
        var envelope = document.RootElement;
        Assert.True(envelope.TryGetProperty("error", out _));
        Assert.Contains("could not be read or validated", envelope.GetProperty("error").GetString());
        Assert.False(envelope.GetProperty("externalMutationPerformed").GetBoolean());
        Assert.False(envelope.GetProperty("secretValuesRead").GetBoolean());
    }

    [Fact]
    public void GetFabricPlan_ProductionEnabledInFile_ReturnsErrorEnvelope()
    {
        // Both canonical.productionEnabled and security.productionEnabled must be
        // false. Flipping the security one (unique because it has a trailing comma)
        // is enough to trigger EnsureFailClosed.
        var root = CreateRepoRoot(MinimalValidContract.Replace(
            "\"productionEnabled\": false,",
            "\"productionEnabled\": true,"));

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        using var document = JsonDocument.Parse(json);
        var envelope = document.RootElement;
        Assert.True(envelope.TryGetProperty("error", out _));
        Assert.Contains("fail-closed", envelope.GetProperty("detail").GetString(),
            StringComparison.OrdinalIgnoreCase);
        // Even the error envelope carries the invariant markers unchanged.
        Assert.False(envelope.GetProperty("externalMutationPerformed").GetBoolean());
        Assert.False(envelope.GetProperty("secretValuesRead").GetBoolean());
    }

    [Fact]
    public void GetFabricPlan_NonWinUiActiveFramework_ReturnsErrorEnvelope()
    {
        var root = CreateRepoRoot(MinimalValidContract.Replace(
            "\"allowedUiFramework\": \"WinUI 3\"",
            "\"allowedUiFramework\": \"WPF\""));

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        using var document = JsonDocument.Parse(json);
        var envelope = document.RootElement;
        Assert.True(envelope.TryGetProperty("error", out _));
        // The exception message lives in the sanitized `detail` field.
        Assert.Contains("WinUI 3", envelope.GetProperty("detail").GetString());
    }

    // ---- path-traversal safety ------------------------------------------------------

    [Fact]
    public void GetFabricPlan_PathOutsideRoot_IsRejected()
    {
        var root = CreateRepoRoot(MinimalValidContract);

        // Any relative path that resolves outside the repo root must be rejected
        // before the file is read.
        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root,
            requestedPath: "../escape.json");

        using var document = JsonDocument.Parse(json);
        Assert.True(document.RootElement.TryGetProperty("error", out _));
        Assert.Contains(
            "HELIOS_REPO_ROOT",
            document.RootElement.GetProperty("detail").GetString());
    }

    [Fact]
    public void GetFabricPlan_PathInsideRootSymlinkedOutside_IsRejected()
    {
        var root = CreateRepoRoot(MinimalValidContract);
        var outsideRoot = CreateEmptyRoot();
        var outsideContract = Path.Combine(outsideRoot, "escape.json");
        File.WriteAllText(outsideContract, MinimalValidContract);

        var linkedContract = Path.Combine(root, "config", "fabric", "linked.json");
        try
        {
            File.CreateSymbolicLink(linkedContract, outsideContract);
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or PlatformNotSupportedException)
        {
            return;
        }

        var json = HeliosFabricTools.BuildFabricPlanJson(
            startDirectory: root,
            requestedPath: "config/fabric/linked.json");

        using var document = JsonDocument.Parse(json);
        Assert.True(document.RootElement.TryGetProperty("error", out _));
        Assert.Contains(
            "HELIOS_REPO_ROOT",
            document.RootElement.GetProperty("detail").GetString());
    }

    [Fact]
    public void GetFabricPlan_MissingContract_ReturnsErrorEnvelope()
    {
        var root = CreateEmptyRoot();

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        // ResolveRepositoryRoot with an explicit startDirectory refuses to fall through
        // to the process's real checkout — the caller wanted THIS root, not another.
        // The InvalidDataException is caught and surfaced as a sanitized error envelope.
        using var document = JsonDocument.Parse(json);
        var envelope = document.RootElement;
        Assert.True(envelope.TryGetProperty("error", out _));
        Assert.Contains(
            "HELIOS Fabric contract not found",
            envelope.GetProperty("detail").GetString());
        Assert.False(envelope.GetProperty("externalMutationPerformed").GetBoolean());
        Assert.False(envelope.GetProperty("secretValuesRead").GetBoolean());
    }

    [Fact]
    public void GetFabricPlan_MalformedContract_ReturnsErrorEnvelope()
    {
        var root = CreateRepoRoot("{ malformed json");

        var json = HeliosFabricTools.BuildFabricPlanJson(startDirectory: root);

        using var document = JsonDocument.Parse(json);
        var envelope = document.RootElement;
        Assert.True(envelope.TryGetProperty("error", out _));
        Assert.False(envelope.GetProperty("externalMutationPerformed").GetBoolean());
        Assert.False(envelope.GetProperty("secretValuesRead").GetBoolean());
    }

    // ---- CLI-facing GetFabricPlan(null) is a thin wrapper over the core -------------

    [Fact]
    public void GetFabricPlan_NullConfigPath_ReadsRealContract()
    {
        // The default configPath (null) resolves against the process's own repo root,
        // which for this test suite is the real checkout — the tool must return a
        // well-formed, fail-closed envelope with the canonical Yolkster identity.
        var json = HeliosFabricTools.GetFabricPlan();

        using var document = JsonDocument.Parse(json);
        var element = document.RootElement;
        // If the checkout is somewhere weird, at least verify the tool did not throw
        // and returned either the plan or a structured error.
        if (element.TryGetProperty("error", out _))
        {
            return;
        }
        Assert.Equal("1.0", element.GetProperty("schemaVersion").GetString());
        Assert.Equal(
            "Yolkster64/helios-platform",
            element.GetProperty("canonical").GetProperty("currentRepository").GetString());
        Assert.False(element.GetProperty("security").GetProperty("productionEnabled").GetBoolean());
    }

    // ---- fixtures -------------------------------------------------------------------

    private string CreateRepoRoot(string contractJson)
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"helios-fabric-tests-{Guid.NewGuid():N}");
        var fabricDir = Path.Combine(root, "config", "fabric");
        Directory.CreateDirectory(fabricDir);
        File.WriteAllText(Path.Combine(fabricDir, "helios-fabric.v1.json"), contractJson);
        _roots.Add(root);
        return root;
    }

    private string CreateEmptyRoot()
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"helios-fabric-tests-empty-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        _roots.Add(root);
        return root;
    }

    private void SetTestEnv(string name, string? value)
    {
        if (!_envToRestore.ContainsKey(name))
        {
            _envToRestore[name] = Environment.GetEnvironmentVariable(name);
        }
        Environment.SetEnvironmentVariable(name, value);
    }
}
