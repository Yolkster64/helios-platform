using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using HELIOS.AIHub.Configuration;
using HELIOS.Mcp;
using ModelContextProtocol;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// helios_config_validate: discoverability annotations, the shipped manifests against
/// their mapped schemas (the drift test — a schema or manifest edit that disagrees
/// fails here), fabricated bad manifests, and the path rules. Fabricated roots carry
/// the config/aihub.json marker root resolution needs plus a copy of the real
/// config/schemas/ directory, so the map and the schemas under test are the shipped ones.
/// </summary>
public sealed class McpConfigToolTests : IDisposable
{
    private readonly List<string> _roots = new();

    public void Dispose()
    {
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

    [Fact]
    public void ConfigValidateTool_IsDiscoverable_ReadOnlyIdempotentClosedWorld()
    {
        var method = typeof(HeliosConfigTools).GetMethod(
            nameof(HeliosConfigTools.ValidateConfig), BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal("helios_config_validate", attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(true, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
        Assert.Equal(true, attributeType.GetProperty("Idempotent")?.GetValue(toolAttribute));
        Assert.Equal(false, attributeType.GetProperty("OpenWorld")?.GetValue(toolAttribute));
    }

    [Fact]
    public void ShippedLabels_AreValid()
    {
        var json = HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, ShippedRepoRoot());

        using var doc = JsonDocument.Parse(json);
        Assert.Equal("config/github/labels.json", doc.RootElement.GetProperty("path").GetString());
        Assert.Equal("config/schemas/github-labels.schema.json", doc.RootElement.GetProperty("schema").GetString());
        Assert.True(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal(0, doc.RootElement.GetProperty("errors").GetArrayLength());
    }

    [Fact]
    public void EveryMappedManifest_IsValid_AgainstItsSchema()
    {
        var root = ShippedRepoRoot();
        using var mapping = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "config", "schemas", "manifests.json")));
        var manifests = mapping.RootElement.GetProperty("mappings").EnumerateArray()
            .Select(entry => entry.GetProperty("manifest").GetString()!)
            .ToList();
        Assert.NotEmpty(manifests);

        foreach (var manifest in manifests)
        {
            var json = HeliosConfigTools.BuildValidationJson(manifest, null, root);
            using var doc = JsonDocument.Parse(json);
            Assert.True(doc.RootElement.GetProperty("valid").GetBoolean(), $"{manifest}: {json}");
        }
    }

    [Fact]
    public void Label_WithSevenCharColor_IsInvalid()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/labels.json", """
            {
              "labels": [
                { "name": "bug", "color": "d73a4a", "description": "Something isn't working" },
                { "name": "ai-hub", "color": "ededed1", "description": "Seven hex digits is one too many" }
              ]
            }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean());
        var errors = doc.RootElement.GetProperty("errors").EnumerateArray().ToList();
        Assert.Contains(errors, error => error.GetProperty("path").GetString() == "$.labels[1].color");
        Assert.DoesNotContain(errors, error => error.GetProperty("path").GetString()!.StartsWith("$.labels[0]", StringComparison.Ordinal));
    }

    [Fact]
    public void Label_WithUnknownKey_IsInvalid_AndNamesTheKey()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/labels.json", """
            { "labels": [ { "name": "bug", "color": "d73a4a", "descr": "typo" } ] }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean());
        Assert.Contains(doc.RootElement.GetProperty("errors").EnumerateArray(),
            error => error.GetProperty("message").GetString()!.Contains("'descr'", StringComparison.Ordinal));
    }

    [Fact]
    public void Labels_BareArrayForm_IsValid()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/labels.json", """
            [ { "name": "bug", "color": "#D73A4A", "description": "Something isn't working" } ]
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.True(doc.RootElement.GetProperty("valid").GetBoolean(), json);
    }

    [Theory]
    [InlineData("2026-13-01")]
    [InlineData("2026-02-30")]
    [InlineData("06/09/2026")]
    public void Milestone_WithBadDate_IsInvalid(string dueOn)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/milestones.json", $$"""
            { "milestones": [ { "title": "Control fabric", "description": "d", "due_on": "{{dueOn}}" } ] }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/github/milestones.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains(doc.RootElement.GetProperty("errors").EnumerateArray(),
            error => error.GetProperty("path").GetString() == "$.milestones[0].due_on");
    }

    [Fact]
    public void Milestone_WithoutDueDate_IsValid()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/milestones.json", """
            { "milestones": [ { "title": "Backlog", "description": "no managed due date" } ] }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/github/milestones.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.True(doc.RootElement.GetProperty("valid").GetBoolean(), json);
    }

    [Theory]
    [InlineData("../config/aihub.json")]
    [InlineData("config/../../etc/passwd")]
    [InlineData("config/github/../github/labels.json")]
    [InlineData("/etc/passwd")]
    [InlineData("C:\\Windows\\win.ini")]
    [InlineData("")]
    public void PathOutsideRepo_IsRefused(string path)
    {
        var root = CreateRepoRoot();

        var ex = Assert.Throws<McpException>(() => HeliosConfigTools.BuildValidationJson(path, null, root));

        Assert.Contains("repo-relative", ex.Message);
    }

    [Fact]
    public void SchemaPathOutsideRepo_IsRefused()
    {
        var root = ShippedRepoRoot();

        var ex = Assert.Throws<McpException>(
            () => HeliosConfigTools.BuildValidationJson("config/github/labels.json", "../schema.json", root));

        Assert.Contains("schemaPath", ex.Message);
    }

    [Fact]
    public void MissingManifest_ThrowsActionableError()
    {
        var root = CreateRepoRoot();

        var ex = Assert.Throws<McpException>(
            () => HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root));

        Assert.Contains("config/github/labels.json", ex.Message);
        Assert.Contains("does not exist", ex.Message);
    }

    [Fact]
    public void UnmappedManifest_ThrowsAndNamesTheMap()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/unmapped.json", "{}");

        var ex = Assert.Throws<McpException>(
            () => HeliosConfigTools.BuildValidationJson("config/unmapped.json", null, root));

        Assert.Contains("config/schemas/manifests.json", ex.Message);
        Assert.Contains("schemaPath", ex.Message);
    }

    [Fact]
    public void SchemaPathOverride_ValidatesADraft()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "drafts/labels.json", """
            { "labels": [ { "name": "draft", "color": "0e8a16", "description": "from templates/" } ] }
            """);

        var json = HeliosConfigTools.BuildValidationJson(
            "drafts/labels.json", "config/schemas/github-labels.schema.json", root);

        using var doc = JsonDocument.Parse(json);
        Assert.True(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal("config/schemas/github-labels.schema.json", doc.RootElement.GetProperty("schema").GetString());
    }

    [Fact]
    public void MalformedJson_ReportsAnError_NotAnException()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/labels.json", "{ \"labels\": [ ");

        var json = HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean());
        var error = Assert.Single(doc.RootElement.GetProperty("errors").EnumerateArray());
        Assert.Equal("$", error.GetProperty("path").GetString());
        Assert.StartsWith("invalid JSON", error.GetProperty("message").GetString());
    }

    [Fact]
    public void ConnectorsTypo_IsInvalid()
    {
        var root = CreateRepoRoot();
        var shipped = File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "connectors.json"));
        WriteManifest(root, "config/connectors.json", shipped.Replace("\"notifyOn\"", "\"notifyon\""));

        var json = HeliosConfigTools.BuildValidationJson("config/connectors.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean());
    }

    [Fact]
    public void JsonSchemaLite_RefusesUnsupportedKeyword()
    {
        using var schema = JsonDocument.Parse("""{ "type": "object", "dependentRequired": { "a": ["b"] } }""");

        Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.CheckSchema(schema.RootElement));
    }

    [Theory]
    [InlineData("""{ "type": "integer" }""", "2.0", true)]
    [InlineData("""{ "type": "integer" }""", "2.5", false)]
    [InlineData("""{ "type": "integer" }""", "true", false)]
    [InlineData("""{ "type": "number", "minimum": 1 }""", "0", false)]
    [InlineData("""{ "enum": [1, "a", null] }""", "null", true)]
    [InlineData("""{ "const": { "b": 1, "a": [1, 2] } }""", """{ "a": [1, 2], "b": 1 }""", true)]
    [InlineData("""{ "type": "string", "format": "date" }""", "\"2026-02-29\"", false)]
    [InlineData("""{ "type": "string", "format": "date" }""", "\"2028-02-29\"", true)]
    [InlineData("""{ "type": "array", "uniqueItems": true }""", "[1, 2, 1]", false)]
    [InlineData("""{ "type": "array", "contains": { "const": 3 } }""", "[1, 2]", false)]
    [InlineData("""{ "if": { "properties": { "s": { "const": "done" } } }, "then": { "required": ["r"] } }""", """{ "s": "done" }""", false)]
    [InlineData("""{ "if": { "properties": { "s": { "const": "done" } } }, "then": { "required": ["r"] } }""", """{ "s": "open" }""", true)]
    [InlineData("""{ "propertyNames": { "pattern": "^[a-z]+$" } }""", """{ "Ok": 1 }""", false)]
    [InlineData("""{ "$defs": { "n": { "type": "string" } }, "items": { "$ref": "#/$defs/n" } }""", "[\"a\", 1]", false)]
    [InlineData("""{ "anyOf": [ { "type": "object", "required": ["labels"] }, { "type": "array" } ] }""", "[]", true)]
    [InlineData("""{ "anyOf": [ { "type": "object", "required": ["labels"] }, { "type": "array" } ] }""", "{}", false)]
    public void JsonSchemaLite_KeywordSubset(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Fact]
    public void JsonSchemaLite_SelfReferentialRef_IsASchemaError_NotAStackOverflow()
    {
        using var schema = JsonDocument.Parse("""{ "$defs": { "a": { "$ref": "#/$defs/b" }, "b": { "$ref": "#/$defs/a" } }, "$ref": "#/$defs/a" }""");
        using var instance = JsonDocument.Parse("""{ }""");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("$ref cycle", ex.Message);
    }

    [Fact]
    public void SelfReferentialDraftSchema_IsAnActionableToolError()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/draft.json", """{ "name": "x" }""");
        WriteManifest(root, "config/schemas/loop.schema.json", """{ "$ref": "#" }""");

        var ex = Assert.Throws<McpException>(() => HeliosConfigTools.BuildValidationJson("config/draft.json", "config/schemas/loop.schema.json", root));

        Assert.Contains("is not usable", ex.Message);
    }

    [Theory]
    [InlineData("""{ "enum": ["\u0041"] }""", "\"A\"", true)]
    [InlineData("""{ "const": 1.0 }""", "1", true)]
    [InlineData("""{ "type": "array", "uniqueItems": true }""", """["\u0041", "A"]""", false)]
    [InlineData("""{ "type": "string", "minLength": 2 }""", "\"e\u0301\"", true)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\" 2026-09-07T23:00:00Z\"", false)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"2026-09-07T23:00:00Z\"", true)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"2026-09-07T23:00:00.250+02:00\"", true)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"2026-09-07t23:00:00z\"", true)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"2026-09-07T23:00\"", false)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"2026-09-07T23:00:00\"", false)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"2026-09-07 23:00:00Z\"", false)]
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"Sept 7 2026 23:00\"", false)]
    public void JsonSchemaLite_ComparesValuesCountsCodePointsAndChecksDateTimeShape(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Theory]
    [InlineData("^(a+)+$")]
    [InlineData(@"^(?:\d*)*$")]
    [InlineData("^([a-z]+){2,}$")]
    [InlineData("^(x{2,})+$")]
    [InlineData("^(a+?)+$")]
    [InlineData("^(a?)+$")]
    public void JsonSchemaLite_RefusesNestedQuantifiers(string pattern)
    {
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new Dictionary<string, object> { ["type"] = "string", ["pattern"] = pattern }));
        using var instance = JsonDocument.Parse("\"aaaaaaaaaaaaaaaaaaaaaaaaaaaab\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("catastrophic backtracking", ex.Message);
    }

    // A quantified group that must consume a literal on every iteration is linear, not the
    // catastrophic shape - the manifests map's repo-relative path pattern is exactly that.
    [Theory]
    [InlineData("^[a-z]+(-[a-z]+)*$", "abc-def")]
    [InlineData(@"^([A-Za-z0-9_-][A-Za-z0-9._-]*/)*[A-Za-z0-9_-][A-Za-z0-9._-]*\.json$", "config/github/labels.json")]
    [InlineData("^(?:ab*)*c$", "abbbabc")]
    public void JsonSchemaLite_AcceptsLinearQuantifiedGroups(string pattern, string value)
    {
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new Dictionary<string, object> { ["type"] = "string", ["pattern"] = pattern }));
        using var instance = JsonDocument.Parse(JsonSerializer.Serialize(value));

        Assert.Empty(JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));
    }

    [Theory]
    [InlineData("""{ "minLength": "1" }""")]
    [InlineData("""{ "minimum": "0" }""")]
    [InlineData("""{ "required": "name" }""")]
    [InlineData("""{ "enum": [] }""")]
    [InlineData("""{ "uniqueItems": "yes" }""")]
    [InlineData("""{ "maxItems": -1 }""")]
    [InlineData("""{ "minItems": 2.5 }""")]
    [InlineData("""{ "format": 3 }""")]
    public void JsonSchemaLite_RefusesKeywordValuesOfTheWrongShape(string schemaJson)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse("\"x\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("must be", ex.Message);
    }

    [Fact]
    public void MalformedKeywordValueInADraftSchema_IsAnActionableToolError()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/schemas/draft.schema.json", """{ "type": "object", "minProperties": "1" }""");
        WriteManifest(root, "config/draft.json", "{}");

        var ex = Assert.Throws<McpException>(() => HeliosConfigTools.BuildValidationJson("config/draft.json", "config/schemas/draft.schema.json", root));

        Assert.Contains("not usable", ex.Message);
        Assert.Contains("minProperties", ex.Message);
    }

    [Fact]
    public void AihubProviderAndCliAgentNames_AreOneRegistry()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/aihub.json", """
            {
              "providers": { "codex": { "type": "openai", "model": "gpt-5.1-codex-max", "apiKeyEnv": "OPENAI_API_KEY" } },
              "cliAgents": [
                { "name": "codex", "command": "codex", "argsTemplate": "exec {prompt}" },
                { "name": "claude-cli", "command": "claude", "argsTemplate": "-p {prompt}" },
                { "name": "claude-cli", "command": "claude", "argsTemplate": "-p {prompt}" },
                { "name": "claude-cli", "enabled": false }
              ],
              "routing": { "defaultChain": ["codex"], "taskRouting": {} }
            }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        var paths = doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).OrderBy(p => p).ToList();
        Assert.Equal(new[] { "$.cliAgents[0].name", "$.cliAgents[2].name" }, paths);
    }

    [Theory]
    [InlineData("""{ "type": "ollama" }""", false)]
    [InlineData("""{ "type": "ollama", "enabled": false }""", true)]
    [InlineData("""{ "type": "anthropic", "apiKeyEnv": "ANTHROPIC_API_KEY" }""", true)]
    [InlineData("""{ "type": "openai", "model": "m", "baseUrl": "https://user:token@host/v1" }""", false)]
    [InlineData("""{ "type": "openai", "model": "m", "baseUrl": "https://host/v1?api-key=secret" }""", false)]
    [InlineData("""{ "type": "openai", "model": "m", "baseUrl": "https://host:8443/v1/" }""", true)]
    public void AihubProviderRules_ModelAndBaseUrl(string providerJson, bool expectedValid)
    {
        var root = CreateRepoRoot();
        // "live" is here so the chain resolves to an enabled provider whatever the case under test
        // does to "p": a chain of nothing but disabled names is its own finding (AihubChains).
        WriteManifest(root, "config/aihub.json", $$"""
            { "providers": { "p": {{providerJson}}, "live": { "type": "anthropic", "apiKeyEnv": "ANTHROPIC_API_KEY" } },
              "routing": { "defaultChain": ["live"], "taskRouting": {} } }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.Equal(expectedValid, doc.RootElement.GetProperty("valid").GetBoolean());
    }

    [Theory]
    [InlineData("""{ "name": null, "command": null, "argsTemplate": null, "enabled": false }""", true)]
    [InlineData("""{ "enabled": false }""", true)]
    [InlineData("""{ "name": "x", "command": "x", "argsTemplate": "run {prompt}" }""", true)]
    [InlineData("""{ "name": null, "command": null, "argsTemplate": null }""", false)]
    [InlineData("""{ "name": "x", "command": "x", "argsTemplate": "no slot" }""", false)]
    public void AihubCliAgentRules_DisabledEntriesMayBeNull(string agentJson, bool expectedValid)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/aihub.json", $$"""
            { "providers": { "p": { "type": "ollama", "model": "llama3" } }, "cliAgents": [ {{agentJson}} ], "routing": { "defaultChain": ["p"], "taskRouting": {} } }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.Equal(expectedValid, doc.RootElement.GetProperty("valid").GetBoolean());
    }

    [Theory]
    [InlineData("^a\\Z")]
    [InlineData("(?i)abc")]
    [InlineData("(?<=x)y")]
    public void JsonSchemaLite_RefusesNonPortableRegexConstructs(string pattern)
    {
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new Dictionary<string, object> { ["type"] = "string", ["pattern"] = pattern }));
        using var instance = JsonDocument.Parse("\"abc\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("portable", ex.Message);
    }

    [Fact]
    public void SymbolicLinkLeavingTheCheckout_IsRefused()
    {
        if (OperatingSystem.IsWindows())
        {
            return; // symlink creation needs a privilege there; the Linux/macOS run covers the rule
        }
        var root = CreateRepoRoot();
        var outside = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName() + ".json");
        File.WriteAllText(outside, """{ "labels": [] }""");
        _roots.Add(Path.GetDirectoryName(outside)!.Length > 0 ? outside : outside); // deleted with the roots
        Directory.CreateDirectory(Path.Combine(root, "config", "github"));
        File.CreateSymbolicLink(Path.Combine(root, "config", "github", "labels.json"), outside);

        var ex = Assert.Throws<McpException>(() => HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root));

        Assert.Contains("symbolic link", ex.Message);
    }

    [Fact]
    public void JsonSchemaLite_AnyOf_ReportsClosestBranch()
    {
        using var schema = JsonDocument.Parse("""
            { "anyOf": [ { "type": "object", "required": ["labels"], "additionalProperties": false, "properties": { "labels": { "type": "array" } } }, { "type": "array" } ] }
            """);
        using var instance = JsonDocument.Parse("""{ "label": [] }""");

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Contains(issues, issue => issue.Message == "'labels' is a required property");
        Assert.Contains(issues, issue => issue.Message.Contains("'label' was unexpected", StringComparison.Ordinal));
    }

    private static string ShippedRepoRoot()
    {
        var configPath = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.False(configPath is null, "config/aihub.json not found walking up from the test output directory");
        return Directory.GetParent(Path.GetDirectoryName(configPath!)!)!.FullName;
    }

    [Theory]
    [InlineData("^(a|aa)+$")]
    [InlineData("^(?:ab|a)*$")]
    [InlineData("^(x|y){2,}$")]
    [InlineData("^(a|aa|aaa)+$")]
    [InlineData("^((a|b)|c)+$")]
    public void JsonSchemaLite_RefusesQuantifiedAlternations(string pattern)
    {
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new Dictionary<string, object> { ["type"] = "string", ["pattern"] = pattern }));
        using var instance = JsonDocument.Parse("\"aaaaaaaaaaaaaaaaaaaaaaaaaaaab\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("alternation", ex.Message);
    }

    [Theory]
    [InlineData("^(dev|prod)$", "dev")]
    [InlineData("^(?:https?|wss?)://[a-z]+$", "https://x")]
    [InlineData("^(a|b)?c$", "c")]
    [InlineData("^(a|b)c(d|e)f$", "acdf")]
    [InlineData("^[(a|b)+]$", "a")]
    [InlineData("^(a|b){0,1}c$", "c")]
    [InlineData("^(ab|cd){1}$", "ab")]
    public void JsonSchemaLite_AcceptsPlainAlternations(string pattern, string value)
    {
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new Dictionary<string, object> { ["type"] = "string", ["pattern"] = pattern }));
        using var instance = JsonDocument.Parse(JsonSerializer.Serialize(value));

        Assert.Empty(JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));
    }

    [Theory]
    [InlineData("""{ "type": 1 }""")]
    [InlineData("""{ "type": [] }""")]
    [InlineData("""{ "type": ["string", 2] }""")]
    [InlineData("""{ "type": null }""")]
    public void JsonSchemaLite_RefusesTypeValuesOfTheWrongShape(string schemaJson)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse("\"x\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("type", ex.Message);
    }

    [Fact]
    public void TypeOfTheWrongShapeInADraftSchema_IsAnActionableToolError()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/schemas/draft.schema.json", """{ "type": 1 }""");
        WriteManifest(root, "config/draft.json", "{}");

        var ex = Assert.Throws<McpException>(() => HeliosConfigTools.BuildValidationJson("config/draft.json", "config/schemas/draft.schema.json", root));

        Assert.Contains("not usable", ex.Message);
    }

    [Fact]
    public void ManifestMappedTwice_IsAnActionableToolError_AndReportedOnTheMapItself()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/schemas/manifests.json", """
            { "mappings": [
                { "manifest": "config/github/labels.json", "schema": "config/schemas/github-labels.schema.json" },
                { "manifest": "./config/github/labels.json", "schema": "config/schemas/manifests.schema.json" } ] }
            """);
        WriteManifest(root, "config/github/labels.json", """{ "labels": [ { "name": "bug", "color": "d73a4a" } ] }""");

        var ex = Assert.Throws<McpException>(() => HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root));
        Assert.Contains("twice", ex.Message);

        // The map validated as a manifest names the duplicate entry (an exact duplicate here:
        // "./" also fails the map's own path pattern, which would be a second issue).
        WriteManifest(root, "config/schemas/manifests.json", """
            { "mappings": [
                { "manifest": "config/github/labels.json", "schema": "config/schemas/github-labels.schema.json" },
                { "manifest": "config/github/labels.json", "schema": "config/schemas/manifests.schema.json" } ] }
            """);
        var json = HeliosConfigTools.BuildValidationJson("config/schemas/manifests.json", "config/schemas/manifests.schema.json", root);
        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal(new[] { "$.mappings[1].manifest" }, doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Theory]
    [InlineData("""{ "labels": [ { "name": "Bug", "color": "d73a4a" }, { "name": "bug", "color": "d73a4a" } ] }""", "$.labels[1].name")]
    [InlineData("""[ { "name": "Bug", "color": "d73a4a" }, { "name": "BUG", "color": "d73a4a" }, { "name": "docs", "color": "0075ca" } ]""", "$[1].name")]
    public void DuplicateLabelNames_AreReportedCaseInsensitively(string manifestJson, string expectedPath)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/labels.json", manifestJson);

        var json = HeliosConfigTools.BuildValidationJson("config/github/labels.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal(new[] { expectedPath }, doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Theory]
    [InlineData("https://:80/x", false)]
    [InlineData("https://host:bad/x", false)]
    [InlineData("https://host:99999/x", false)]
    [InlineData("https://[bad]/", false)]
    [InlineData("https://host:8443/v1/", true)]
    [InlineData("http://localhost:11434", true)]
    public void AihubBaseUrl_MustBeAnAbsoluteHttpUri(string baseUrl, bool expectedValid)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/aihub.json", $$"""
            { "providers": { "p": { "type": "ollama", "model": "llama3", "baseUrl": "{{baseUrl}}" } }, "routing": { "defaultChain": ["p"], "taskRouting": {} } }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.Equal(expectedValid, doc.RootElement.GetProperty("valid").GetBoolean());
    }

    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    public void DisabledProviderName_MayBeReusedByAnEnabledCliAgent(bool providerEnabled, bool expectedValid)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/aihub.json", $$"""
            { "providers": { "codex": { "type": "openai", "model": "m", "apiKeyEnv": "OPENAI_API_KEY", "enabled": {{(providerEnabled ? "true" : "false")}} }, "p": { "type": "ollama", "model": "llama3" } },
              "cliAgents": [ { "name": "codex", "command": "codex", "argsTemplate": "exec {prompt}" } ],
              "routing": { "defaultChain": ["p"], "taskRouting": {} } }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.Equal(expectedValid, doc.RootElement.GetProperty("valid").GetBoolean());
    }

    [Theory]
    // 9007199254740992 and 9007199254740993 are adjacent integers that share one double: reducing a
    // JSON number to double here made them equal under enum, const and uniqueItems - and disagreed
    // with the Python engine, whose integers stay exact.
    [InlineData("""{ "enum": [9007199254740992] }""", "9007199254740993", false)]
    [InlineData("""{ "enum": [9007199254740992] }""", "9007199254740992", true)]
    [InlineData("""{ "const": 1 }""", "1.0", true)]
    [InlineData("""{ "const": 1.0 }""", "1", true)]
    [InlineData("""{ "type": "array", "uniqueItems": true }""", "[9007199254740992, 9007199254740993]", true)]
    [InlineData("""{ "type": "array", "uniqueItems": true }""", "[1, 1.0]", false)]
    // decimal cannot carry it either: 1e-29 rounds to zero there, and integers beyond decimal's
    // range collapse through double. Normalizing the token arithmetically holds for both.
    [InlineData("""{ "const": 0 }""", "1e-29", false)]
    [InlineData("""{ "type": "array", "uniqueItems": true }""", "[0, 1e-29]", true)]
    [InlineData("""{ "type": "array", "uniqueItems": true }""", "[1000000000000000000000000000000, 1000000000000000000000000000001]", true)]
    [InlineData("""{ "const": 100 }""", "1e2", true)]
    [InlineData("""{ "const": 100 }""", "1.0e2", true)]
    public void JsonSchemaLite_ComparesNumbersAsWrittenNotAsDoubles(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Fact]
    public void JsonSchemaLite_RepetitionCountTooLargeForAnInt_IsASchemaError()
    {
        // QuantifierAt used int.Parse: this count overflows it, and the overflow escaped the schema
        // self-check as a crash rather than a verdict. Round 10 moved the refusal earlier - such a
        // count is outside the range every engine holds - so the verdict now names the count
        // rather than the failed compile, and the Python twin says the same thing.
        using var schema = JsonDocument.Parse("""{ "type": "string", "pattern": "a{999999999999999999999999}" }""");
        using var instance = JsonDocument.Parse("\"a\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("repetition count above", ex.Message);
    }

    [Fact]
    public void JsonSchemaLite_BacktrackingPattern_IsAbandonedNotEndured()
    {
        // ^(a+a+)+$ is not a shape CatastrophicShape names - that is the point. A scanner knows
        // only the shapes it enumerates; RegexTimeout bounds the match either way.
        using var schema = JsonDocument.Parse("""{ "type": "string", "pattern": "^(a+a+)+$" }""");
        using var instance = JsonDocument.Parse($"\"{new string('a', 40)}b\"");

        var started = System.Diagnostics.Stopwatch.StartNew();
        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("abandoned", ex.Message);
        Assert.True(started.Elapsed < TimeSpan.FromSeconds(30), $"took {started.Elapsed}");
    }

    [Theory]
    // A chain entry the hub cannot resolve is skipped silently, so a typo degrades the chain and a
    // chain of nothing but disabled names fails every request routed to it.
    [InlineData("""["live"]""", true)]
    [InlineData("""["parked", "cx"]""", true)]
    [InlineData("""["parked"]""", false)]
    [InlineData("""["typo"]""", false)]
    [InlineData("""["live", "typo"]""", false)]
    public void AihubRoutingChains_MustBeReachable(string chainJson, bool expectedValid)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/aihub.json", $$"""
            { "providers": { "live": { "type": "ollama", "model": "llama3" }, "parked": { "type": "ollama", "model": "llama3", "enabled": false } },
              "cliAgents": [ { "name": "cx", "command": "codex", "argsTemplate": "exec {prompt}" } ],
              "routing": { "defaultChain": ["live"], "taskRouting": { "code_review": {{chainJson}} } } }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.Equal(expectedValid, doc.RootElement.GetProperty("valid").GetBoolean());
    }

    [Theory]
    [InlineData("""{ "milestones": [ { "title": "Control fabric" }, { "title": "control FABRIC" } ] }""", "$.milestones[1].title")]
    [InlineData("""[ { "title": "Owner setup" }, { "title": "owner setup" } ]""", "$[1].title")]
    // OrdinalIgnoreCase folds 'ς' onto 'Σ'; the Python twin folds the same way (_ordinal_ignore_case).
    [InlineData("""[ { "title": "\u03a3" }, { "title": "\u03c2" } ]""", "$[1].title")]
    public void DuplicateMilestoneTitles_AreReportedCaseInsensitively(string manifestJson, string expectedPath)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/github/milestones.json", manifestJson);

        var json = HeliosConfigTools.BuildValidationJson("config/github/milestones.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal(new[] { expectedPath }, doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Fact]
    public void DuplicateFleetPoolNames_AreReported()
    {
        var root = CreateRepoRoot();
        var topology = JsonNode.Parse(File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "fleet", "fleet-topology.json")))!;
        var pools = topology["pools"]!.AsArray();
        pools.Add(JsonNode.Parse(pools[0]!.ToJsonString())!);
        WriteManifest(root, "config/fleet/fleet-topology.json", topology.ToJsonString());

        var json = HeliosConfigTools.BuildValidationJson("config/fleet/fleet-topology.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal(new[] { $"$.pools[{pools.Count - 1}].name" },
            doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Theory]
    // Bounds went through GetDouble(), so minimum 9007199254740993 against 9007199254740992 was
    // the same double twice and the invalid instance passed.
    [InlineData("""{ "minimum": 9007199254740993 }""", "9007199254740992", false)]
    [InlineData("""{ "minimum": 9007199254740993 }""", "9007199254740993", true)]
    [InlineData("""{ "maximum": 9007199254740992 }""", "9007199254740993", false)]
    [InlineData("""{ "exclusiveMinimum": 1e-29 }""", "0", false)]
    [InlineData("""{ "exclusiveMinimum": 0 }""", "1e-29", true)]
    [InlineData("""{ "maximum": 10 }""", "10", true)]
    [InlineData("""{ "exclusiveMaximum": 10 }""", "10", false)]
    [InlineData("""{ "minimum": -2 }""", "-3", false)]
    [InlineData("""{ "minimum": -2 }""", "-1", true)]
    [InlineData("""{ "minimum": -2.5 }""", "-2.50", true)]
    public void JsonSchemaLite_ComparesBoundsWithoutRounding(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Theory]
    // "integer" asked a double, so 1e-324 became 0 and 1.00000000000000001 became 1 — and the
    // Python twin, whose numbers are exact, disagreed about the same manifest.
    [InlineData("""{ "type": "integer" }""", "1e-324", false)]
    [InlineData("""{ "type": "integer" }""", "1.00000000000000001", false)]
    [InlineData("""{ "type": "integer" }""", "4.0", true)]
    [InlineData("""{ "type": "integer" }""", "1e2", true)]
    [InlineData("""{ "type": "integer" }""", "4.5", false)]
    [InlineData("""{ "type": "number" }""", "1e-324", true)]
    // An exponent that would wrap the normalizer's arithmetic must not reverse an ordering.
    [InlineData("""{ "minimum": 1 }""", "0.01e-9223372036854775808", false)]
    public void JsonSchemaLite_JudgesNumbersByValueNotByDouble(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Fact]
    public void JsonSchemaLite_ALeadingZeroQuantifierIsStillReadAsItsCount()
    {
        // The window this scan used to carry made {000...02} look like a literal brace, so the
        // nested quantifier behind it went unnoticed.
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(
            new Dictionary<string, string> { ["pattern"] = "^(a+){" + new string('0', 40) + "2}$" }));
        using var instance = JsonDocument.Parse("\"aaa\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("quantified group", ex.Message);
    }

    [Fact]
    public void JsonSchemaLite_ASchemaThatDoublesItsWorkIsRefused()
    {
        // An acyclic $defs chain whose allOf repeats the next $ref: 2^20 evaluations with nesting
        // far below the depth guard, so only a work budget stops it. This server answers one
        // request per process, so nothing else would.
        const int levels = 20;
        var defs = new List<string> { $"\"l{levels}\": {{ \"type\": \"object\" }}" };
        for (var level = levels - 1; level >= 0; level--)
        {
            var next = $"{{ \"$ref\": \"#/$defs/l{level + 1}\" }}";
            defs.Add($"\"l{level}\": {{ \"allOf\": [ {next}, {next} ] }}");
        }
        using var schema = JsonDocument.Parse($"{{ \"$ref\": \"#/$defs/l0\", \"$defs\": {{ {string.Join(", ", defs)} }} }}");
        using var instance = JsonDocument.Parse("{}");

        var started = System.Diagnostics.Stopwatch.StartNew();
        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("keyword evaluations", ex.Message);
        Assert.True(started.Elapsed < TimeSpan.FromSeconds(30), $"took {started.Elapsed}");
    }

    [Fact]
    public void JsonSchemaLite_UnmatchedBracesArePreflightedLinearly()
    {
        // QuantifierAt searched the rest of the pattern for '}' at every '{', which is quadratic:
        // a large pattern of unmatched braces held the preflight before any regex was built.
        var pattern = new string('{', 50_000);
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new Dictionary<string, string> { ["pattern"] = pattern }));
        using var instance = JsonDocument.Parse("\"x\"");

        var started = System.Diagnostics.Stopwatch.StartNew();
        JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.True(started.Elapsed < TimeSpan.FromSeconds(15), $"took {started.Elapsed}");
    }

    [Theory]
    // JsonDocument parses 1e400 happily, but every consumer binds a double and the Python engine
    // refuses the token while reading the file: the same manifest must not be valid here.
    [InlineData("""{ "minimum": 0 }""", "1e400", false)]
    [InlineData("""{ "minimum": 0 }""", "-1e400", false)]
    [InlineData("""{ "minimum": 0 }""", "1e308", true)]
    // Past the normalizer's exponent guard a double would answer for a value it cannot hold.
    [InlineData("""{ "type": "integer" }""", "1e-1000000001", false)]
    [InlineData("""{ "type": "number" }""", "1e-1000000001", true)]
    public void JsonSchemaLite_RefusesNumbersNoConsumerCanHold(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Theory]
    // RFC 3339 allows any two-digit offset; DateTimeOffset stops at ±14:00, and the Python twin
    // accepts the full range, so the check reads the parts instead of parsing an offset type.
    [InlineData("2026-01-01T00:00:00+15:00", true)]
    [InlineData("2026-01-01T00:00:00+23:59", true)]
    [InlineData("2026-01-01T00:00:00-14:00", true)]
    [InlineData("2026-01-01T00:00:00Z", true)]
    [InlineData("2026-01-01T00:00:00+24:00", false)]
    [InlineData("2026-01-01T00:00:00+15:60", false)]
    [InlineData("2026-02-30T00:00:00Z", false)]
    [InlineData("2026-01-01T25:00:00Z", false)]
    public void JsonSchemaLite_AcceptsTheFullRfc3339OffsetRange(string value, bool expectedValid)
    {
        using var schema = JsonDocument.Parse("""{ "type": "string", "format": "date-time" }""");
        using var instance = JsonDocument.Parse(JsonSerializer.Serialize(value));

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Fact]
    public void JsonSchemaLite_APatternPropertiesKeyIsCompiled()
    {
        // Against an instance with no properties nothing else would ever compile the key.
        using var schema = JsonDocument.Parse("""{ "type": "object", "patternProperties": { "[": {} } }""");
        using var instance = JsonDocument.Parse("{}");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("pattern", ex.Message);
    }

    [Theory]
    // AIHubOptions.Load binds case-insensitively, so the later spelling replaces the earlier.
    [InlineData("""{ "providers": { "live": { "type": "ollama", "model": "m" } }, "Providers": null, "routing": { "defaultChain": ["live"], "taskRouting": {} } }""", false)]
    [InlineData("""{ "providers": { "live": { "type": "ollama", "model": "m", "Type": "openai" } }, "routing": { "defaultChain": ["live"], "taskRouting": {} } }""", false)]
    [InlineData("""{ "providers": { "live": { "type": "ollama", "model": "m" } }, "routing": { "defaultChain": ["live"], "taskRouting": {} } }""", true)]
    public void AihubCaseInsensitiveAliases_AreRefused(string manifestJson, bool expectedValid)
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/aihub.json", manifestJson);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.Equal(expectedValid, doc.RootElement.GetProperty("valid").GetBoolean());
    }

    [Fact]
    public void DuplicateWatchlistPullRequests_AreReported()
    {
        var root = CreateRepoRoot();
        WriteManifest(root, "config/absorption/pr-watchlist.json", """
            { "candidates": [
                { "pr": 191, "title": "one", "status": "watching" },
                { "pr": 191, "title": "two", "status": "watching" } ] }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/absorption/pr-watchlist.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains("$.candidates[1].pr",
            doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Fact]
    public void SemanticRules_FollowTheSchemaFile_NotItsEditableId()
    {
        // Removing one `$id` line used to switch every semantic rule off while validation passed.
        var root = CreateRepoRoot();
        var schemaPath = Path.Combine(root, "config", "schemas", "aihub.schema.json");
        var schema = JsonNode.Parse(File.ReadAllText(schemaPath))!.AsObject();
        schema.Remove("$id");
        File.WriteAllText(schemaPath, schema.ToJsonString());
        WriteManifest(root, "config/aihub.json", """
            { "providers": { "codex": { "type": "ollama", "model": "m" } },
              "cliAgents": [ { "name": "codex", "command": "codex", "argsTemplate": "exec {prompt}" } ],
              "routing": { "defaultChain": ["codex"], "taskRouting": {} } }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal(new[] { "$.cliAgents[0].name" },
            doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Theory]
    // '$' matches before a final newline in .NET, so the shape alone accepted a timestamp with one
    // and then read its offset from the wrong six characters.
    [InlineData("2026-01-01T00:00:00Z\n", false)]
    [InlineData("2026-01-01T00:00:00+99:99\n", false)]
    [InlineData("2026-01-01T00:00:00Z", true)]
    public void JsonSchemaLite_DateTimeRejectsATrailingNewline(string value, bool expectedValid)
    {
        using var schema = JsonDocument.Parse("""{ "type": "string", "format": "date-time" }""");
        using var instance = JsonDocument.Parse(JsonSerializer.Serialize(value));

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Theory]
    // Zero is zero however it is spelled, even past the normalizer's exponent guard.
    [InlineData("""{ "type": "integer" }""", "0e-1000000001", true)]
    [InlineData("""{ "type": "integer" }""", "0.000e999999999999", true)]
    [InlineData("""{ "minimum": 0 }""", "-0", true)]
    public void JsonSchemaLite_ZeroNormalizesWhateverItsExponent(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
    }

    [Fact]
    public void NumbersOutOfDoubleRange_AreReportedWhereverTheySit()
    {
        // The Python engine refuses the token while reading the file, so a value the schema walk
        // never reaches — an unknown property here — must not leave the two engines disagreeing.
        var root = CreateRepoRoot();
        WriteManifest(root, "config/aihub.json", """
            { "providers": { "live": { "type": "ollama", "model": "m" } },
              "routing": { "defaultChain": ["live"], "taskRouting": {} },
              "unused": 1e400 }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/aihub.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains("$.unused",
            doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Fact]
    public void WatchlistDuplicates_ReadAPullRequestNumberAsSchemaValidationDoes()
    {
        // 191 and 191.0 are one pull request; the identity check must not depend on the spelling.
        var root = CreateRepoRoot();
        WriteManifest(root, "config/absorption/pr-watchlist.json", """
            { "candidates": [
                { "pr": 191.0, "title": "one", "status": "watching" },
                { "pr": 191, "title": "two", "status": "watching" } ] }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/absorption/pr-watchlist.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains("$.candidates[1].pr",
            doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Fact]
    public void SemanticRules_DoNotFollowAFamiliarNameElsewhereInTheTree()
    {
        // A file name is not identity: only config/schemas/ (or a HELIOS $id) carries these rules.
        var root = CreateRepoRoot();
        WriteManifest(root, "scratch/aihub.schema.json", """{ "type": "object" }""");
        WriteManifest(root, "config/draft.json", """{ "Providers": null }""");

        var json = HeliosConfigTools.BuildValidationJson("config/draft.json", "scratch/aihub.schema.json", root);

        using var doc = JsonDocument.Parse(json);
        Assert.True(doc.RootElement.GetProperty("valid").GetBoolean(), json);
    }

    [Fact]
    public void SemanticRules_FollowAHeliosIdWhereverTheSchemaSits()
    {
        // The $id fallback is what an explicitly passed schema outside config/schemas/ has left.
        var root = CreateRepoRoot();
        var shipped = File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "schemas", "aihub.schema.json"));
        WriteManifest(root, "scratch/custom.schema.json", shipped);
        WriteManifest(root, "config/draft.json", """
            { "providers": { "codex": { "type": "ollama", "model": "m" } },
              "cliAgents": [ { "name": "codex", "command": "codex", "argsTemplate": "exec {prompt}" } ],
              "routing": { "defaultChain": ["codex"], "taskRouting": {} } }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/draft.json", "scratch/custom.schema.json", root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Equal(new[] { "$.cliAgents[0].name" },
            doc.RootElement.GetProperty("errors").EnumerateArray().Select(e => e.GetProperty("path").GetString()).ToArray());
    }

    [Fact]
    public void JsonSchemaLite_PatternPropertyMatchesAreChargedToTheBudget()
    {
        // P patterns against N keys is P×N matches, and only recursive Validate calls used to
        // touch the budget: a pair of large files could spend millions of matches — each parsing
        // a temporary JsonDocument — against a single instance evaluation.
        var patterns = string.Join(", ", Enumerable.Range(0, 2000).Select(index => $"\"^a{index}[0-9]*$\": {{}}"));
        var members = string.Join(", ", Enumerable.Range(0, 2000).Select(index => $"\"b{index}\": 1"));
        using var schema = JsonDocument.Parse($"{{ \"type\": \"object\", \"patternProperties\": {{ {patterns} }} }}");
        using var instance = JsonDocument.Parse($"{{ {members} }}");

        var started = System.Diagnostics.Stopwatch.StartNew();
        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(() => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("keyword evaluations", ex.Message);
        Assert.True(started.Elapsed < TimeSpan.FromSeconds(60), $"took {started.Elapsed}");
    }

    [Theory]
    [InlineData("a++")]
    [InlineData("a*+")]
    [InlineData("a?+")]
    [InlineData("a{2,3}+")]
    [InlineData("(ab)++")]
    [InlineData("(?>ab)+")]
    public void JsonSchemaLite_RefusesPossessiveQuantifiers(string pattern)
    {
        // Python 3.11 accepts these and ECMA-262 has none, so the Python engine used to call such
        // a schema usable while this one reported it broken. Both refuse it now, by name.
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new { type = "string", pattern }));
        using var instance = JsonDocument.Parse("\"x\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("portable (ECMA-262) regex subset", ex.Message);
    }

    [Theory]
    [InlineData("\\++", "++")]        // one or more LITERAL plus signs, not a quantifier
    [InlineData("a+?", "a")]          // lazy, legal in both dialects
    [InlineData("^[a-z]+(-[a-z]+)*$", "a-b")]
    public void JsonSchemaLite_AcceptsQuantifiersBothDialectsShare(string pattern, string subject)
    {
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new { type = "string", pattern }));
        using var instance = JsonDocument.Parse(JsonSerializer.Serialize(subject));

        Assert.Empty(JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));
    }

    [Fact]
    public void JsonSchemaLite_RefusesADialectDeclaredBelowTheRoot()
    {
        // The Python engine refuses this so python-jsonschema cannot hand the subtree back to a
        // validator without its regex and number rules; one schema must not be usable through one
        // path and refused by the other.
        using var schema = JsonDocument.Parse("""
            { "type": "object",
              "properties": { "a": { "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "string" } } }
            """);
        using var instance = JsonDocument.Parse("""{ "a": "x" }""");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("a dialect may only be declared at the root", ex.Message);
        // The root's own $schema stays an annotation.
        using var rooted = JsonDocument.Parse("""
            { "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "string" }
            """);
        using var text = JsonDocument.Parse("\"x\"");
        Assert.Empty(JsonSchemaLite.Validate(rooted.RootElement, text.RootElement));
    }

    [Fact]
    public void JsonSchemaLite_BoundsRecursionDuringTheSchemaSelfCheck()
    {
        // CountEvaluation bounds the NUMBER of schema nodes, not the depth of the call stack, and
        // the self-check runs before the guarded instance walk: a StackOverflowException here
        // cannot be caught and would take the MCP process with it.
        var deep = new System.Text.StringBuilder();
        const int levels = 5000;
        for (var index = 0; index < levels; index++)
        {
            deep.Append("{\"not\":");
        }
        deep.Append("{}");
        deep.Append('}', levels);
        using var schema = JsonDocument.Parse(deep.ToString(), new JsonDocumentOptions { MaxDepth = levels + 8 });
        using var instance = JsonDocument.Parse("{}");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("nesting deeper than", ex.Message);
    }

    [Fact]
    public void JsonSchemaLite_OrdersNumbersExactlyBeyondTheOldExponentGuard()
    {
        // 1e-1000000001 is a real number to the Python engine (decimal.Decimal holds it), and
        // comparing doubles here made it equal to zero: the invalid instance passed `minimum`.
        using var schema = JsonDocument.Parse("""{ "type": "number", "minimum": 1e-1000000001 }""");
        using var zero = JsonDocument.Parse("0");
        using var above = JsonDocument.Parse("1e-1000000000");

        Assert.Single(JsonSchemaLite.Validate(schema.RootElement, zero.RootElement));
        Assert.Empty(JsonSchemaLite.Validate(schema.RootElement, above.RootElement));
    }

    [Fact]
    public void JsonSchemaLite_RefusesASchemaNumberItCannotOrderExactly()
    {
        // Past decimal.Decimal's own range the Python engine refuses the token while READING the
        // file, so accepting it here would leave one manifest with two verdicts.
        using var schema = JsonDocument.Parse("""{ "type": "number", "minimum": 1e-9999999999999999999 }""");
        using var instance = JsonDocument.Parse("0");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("outside the exponent range", ex.Message);
    }

    [Fact]
    public void JsonSchemaLite_ChargesEveryEnumComparisonToTheBudget()
    {
        // enum scanned every option without charging anything, and each comparison re-rendered the
        // whole instance: a large enum against a large string was billions of characters of work
        // for one keyword evaluation, in a server with no whole-request deadline.
        var options = string.Join(", ", Enumerable.Range(0, 300_000).Select(index => $"\"o{index}\""));
        using var schema = JsonDocument.Parse($"{{ \"enum\": [ {options} ] }}");
        using var instance = JsonDocument.Parse("\"" + new string('x', 20_000) + "\"");

        var started = System.Diagnostics.Stopwatch.StartNew();
        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("keyword evaluations", ex.Message);
        Assert.True(started.Elapsed < TimeSpan.FromSeconds(60), $"took {started.Elapsed}");
    }

    [Fact]
    public void JsonSchemaLite_EnumStillComparesByValueAndType()
    {
        // The cached key must not change any verdict: 191 and 191.0 are one number, true is not 1.
        using var schema = JsonDocument.Parse("""{ "enum": [191, "a", true, null, {"x": 1}] }""");
        foreach (var (text, valid) in new[] { ("191.0", true), ("191", true), ("\"a\"", true), ("true", true),
                                              ("null", true), ("{\"x\": 1.0}", true), ("1", false),
                                              ("false", false), ("\"b\"", false) })
        {
            using var instance = JsonDocument.Parse(text);
            Assert.Equal(valid, JsonSchemaLite.Validate(schema.RootElement, instance.RootElement).Count == 0);
        }
    }

    [Fact]
    public void ModelCatalog_RefusesARepeatedProviderAndModelPair()
    {
        // ModelCatalog's context filter takes the FIRST matching profile while preference ranking
        // sees both, so one catalog would state two prices for one model.
        var root = CreateRepoRoot();
        WriteManifest(root, "config/model-catalog.json", """
            { "models": [
                { "provider": "openai", "model": "gpt", "class": "balanced", "contextTokens": 128000,
                  "inputPerMillionUsd": 1, "outputPerMillionUsd": 2, "relativeSpeed": "fast",
                  "strengths": ["code"] },
                { "provider": "openai", "model": "gpt", "class": "balanced", "contextTokens": 64000,
                  "inputPerMillionUsd": 3, "outputPerMillionUsd": 4, "relativeSpeed": "fast",
                  "strengths": ["code"] } ] }
            """);

        var json = HeliosConfigTools.BuildValidationJson("config/model-catalog.json", null, root);

        using var doc = JsonDocument.Parse(json);
        Assert.False(doc.RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains("identify one profile", json);
    }

    [Fact]
    public void FabricContract_RefusesSecretLikeMaterialInAnyString()
    {
        var root = CreateRepoRoot();
        var shipped = File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "fabric", "helios-fabric.v1.json"));
        WriteManifest(root, "config/fabric/helios-fabric.v1.json", shipped);
        Assert.Contains("\"valid\": true",
            HeliosConfigTools.BuildValidationJson("config/fabric/helios-fabric.v1.json", null, root));

        using var document = JsonDocument.Parse(shipped);
        var mutated = JsonNode.Parse(shipped)!;
        mutated["contractVersion"] = "sk-" + new string('a', 24);
        WriteManifest(root, "config/fabric/helios-fabric.v1.json", mutated.ToJsonString());

        var json = HeliosConfigTools.BuildValidationJson("config/fabric/helios-fabric.v1.json", null, root);

        Assert.Contains("secret-like value", json);
    }

    [Fact]
    public void FleetTopology_IsBoundedInAggregateNotOnlyPerPool()
    {
        // Every ceiling in the schema is per pool and start-fleet selects them all: 16 pools of 64
        // workers is 1,024 processes on one host, and the burst lanes are summed into ONE
        // absolute `az vmss scale --new-capacity`.
        var root = CreateRepoRoot();
        var shipped = JsonNode.Parse(
            File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "fleet", "fleet-topology.json")))!;
        var template = shipped["pools"]!.AsArray()[0]!.ToJsonString();
        var pools = new JsonArray();
        for (var index = 0; index < 16; index++)
        {
            var pool = JsonNode.Parse(template)!.AsObject();
            pool["name"] = $"pool-{index}";
            pool["poolSize"] = 64;
            pool["autoscaling"] = new JsonObject { ["maxBurstLanes"] = 256 };
            pool.Remove("hermesFleet");   // a declared maxConcurrentLanes would clamp the spawn size
            pools.Add(pool);
        }
        shipped["pools"] = pools;
        WriteManifest(root, "config/fleet/fleet-topology.json", shipped.ToJsonString());

        var json = HeliosConfigTools.BuildValidationJson("config/fleet/fleet-topology.json", null, root);

        Assert.False(JsonDocument.Parse(json).RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains("worker processes together", json);
        Assert.Contains("az vmss scale", json);
    }

    [Fact]
    public void JsonSchemaLite_ARefMayOnlyPointWhereTheSelfCheckWalks()
    {
        // Only $defs and definitions are walked as annotations, so a $ref into `default` validated
        // against a subschema whose keywords, patterns and numbers nothing had checked - the one
        // way an unchecked bound could still reach CompareNumbers.
        using var schema = JsonDocument.Parse("""{ "$ref": "#/default", "default": { "minimum": 1e-9999999999999999999 } }""");
        using var instance = JsonDocument.Parse("0");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("$defs", ex.Message);

        // Naming a definition is not the same as descending into one: '#/$defs/a/default' reached
        // exactly the same unchecked place, one level lower.
        using var deeper = JsonDocument.Parse("""
            { "$defs": { "a": { "default": { "pattern": "a++" } } }, "$ref": "#/$defs/a/default" }
            """);
        using var text = JsonDocument.Parse("\"aa\"");
        Assert.Contains("$defs", Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(deeper.RootElement, text.RootElement)).Message);
    }

    [Fact]
    public void JsonSchemaLite_AcceptsTheRefShapesTheShippedSchemasUse()
    {
        // A cycle through $defs, a reference to the root, and a root that declares its own dialect
        // and is then referenced: all legal, and none of them a "nested dialect".
        using var cyclic = JsonDocument.Parse("""
            { "$defs": { "a": { "not": { "$ref": "#/$defs/a" } } }, "$ref": "#/$defs/a" }
            """);
        JsonSchemaLite.CheckSchema(cyclic.RootElement);

        using var rooted = JsonDocument.Parse("""
            { "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object",
              "properties": { "next": { "$ref": "#" } } }
            """);
        JsonSchemaLite.CheckSchema(rooted.RootElement);
    }

    [Theory]
    [InlineData("a{,3}")]
    [InlineData("a{,3}+")]
    [InlineData("^a{,3}$")]
    [InlineData("a{,}")]
    [InlineData("a{,}+")]
    [InlineData("a{,}?")]
    public void JsonSchemaLite_RefusesARepetitionPythonAloneUnderstands(string pattern)
    {
        // Python reads {,3} as {0,3} and this parser reads three literal characters.
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new { type = "string", pattern }));
        using var instance = JsonDocument.Parse("\"aa\"");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("omitted lower bound", ex.Message);
    }

    [Theory]
    [InlineData("^a{0,2147483648}$", false)]
    [InlineData("a{2147483648}", false)]
    [InlineData("a{2147483648,}", false)]
    [InlineData("a{2147483647}", true)]
    [InlineData("a{0002147483647}", true)]
    public void JsonSchemaLite_RefusesARepetitionCountNoEngineHolds(string pattern, bool usable)
    {
        // Python compiles a larger count; this parser refuses the pattern outright, so the shared
        // refusal has to name the count rather than leave one engine to discover it.
        using var schema = JsonDocument.Parse(JsonSerializer.Serialize(new { type = "string", pattern }));
        using var instance = JsonDocument.Parse("\"a\"");

        if (usable)
        {
            JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);
            return;
        }
        Assert.Contains("repetition count above", Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement)).Message);
    }

    [Theory]
    // Judging a NORMALIZED exponent put these on opposite sides of the limit in the two engines.
    [InlineData("1.1e-999999999999999999", true)]
    [InlineData("10e-1000000000000000000", false)]
    [InlineData("0e-1000000001", true)]
    [InlineData("0e1000000000000000000", false)]
    // A large POSITIVE exponent is out of double range as well, so both engines refuse it before
    // the exponent limit is reached.
    [InlineData("1e999999999999999999", false)]
    [InlineData("1e1000000000000000000", false)]
    public void JsonSchemaLite_StopsAtTheExponentAsWritten(string token, bool holdable)
    {
        using var instance = JsonDocument.Parse(token);

        Assert.Equal(holdable, JsonSchemaLite.IsFiniteNumber(instance.RootElement));
    }

    [Fact]
    public void JsonSchemaLite_ACharacterClassIsNotAnAtomicGroup()
    {
        // "(?>" as a raw substring hit "[(?>]" - three literal characters in a class.
        using var classSchema = JsonDocument.Parse("""{ "type": "string", "pattern": "[(?>]" }""");
        using var subject = JsonDocument.Parse("\">\"");
        Assert.Empty(JsonSchemaLite.Validate(classSchema.RootElement, subject.RootElement));

        using var atomic = JsonDocument.Parse("""{ "type": "string", "pattern": "(?>ab)" }""");
        using var text = JsonDocument.Parse("\"ab\"");
        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(atomic.RootElement, text.RootElement));
        Assert.Contains("atomic group", ex.Message);
    }

    [Theory]
    [InlineData("64", 64L)]
    [InlineData("64.0", 64L)]
    [InlineData("6.4e1", 64L)]
    [InlineData("-64", -64L)]
    [InlineData("0e100", 0L)]
    [InlineData("1000000000000000000", 1000000000000000000L)]
    [InlineData("9223372036854775807", 9223372036854775807L)]
    [InlineData("-9223372036854775808", -9223372036854775808L)]
    public void JsonSchemaLite_ReadsAWholeNumberHoweverItIsSpelled(string token, long expected)
    {
        using var document = JsonDocument.Parse(token);

        Assert.True(JsonSchemaLite.TryGetWholeNumber(document.RootElement, out var value), token);
        Assert.Equal(expected, value);
    }

    [Theory]
    [InlineData("64.5")]
    [InlineData("1e-1")]
    [InlineData("1e30")]
    [InlineData("9223372036854775808")]     // one past long.MaxValue
    public void JsonSchemaLite_RefusesANumberThatIsNotAWholeLong(string token)
    {
        using var document = JsonDocument.Parse(token);

        Assert.False(JsonSchemaLite.TryGetWholeNumber(document.RootElement, out _), token);
    }

    [Theory]
    // scale-fleet.ps1 defaults maxLocalLanes to minLocalLanes, raises the maximum back to the
    // minimum, zeroes local lanes for a cloud pool, clamps both to maxConcurrentLanes, and counts
    // burst only for a pool that may burst. The totals have to resolve the same way.
    [InlineData("""{ "autoscaling": { "minLocalLanes": 64 } }""", false)]
    [InlineData("""{ "autoscaling": { "minLocalLanes": 64, "maxLocalLanes": 1 } }""", false)]
    [InlineData("""{ "autoscaling": { "mode": "cloud", "maxLocalLanes": 64 } }""", true)]
    [InlineData("""{ "autoscaling": { "maxLocalLanes": 64 }, "hermesFleet": { "maxConcurrentLanes": 2 } }""", true)]
    [InlineData("""{ "autoscaling": { "mode": "local", "maxBurstLanes": 256 } }""", true)]
    [InlineData("""{ "autoscaling": { "mode": "hybrid", "maxBurstLanes": 256 } }""", false)]
    [InlineData("""{ "poolSize": 64.0 }""", false)]
    public void FleetTopology_TotalsResolveTheWayTheScriptsResolveThem(string defaultsJson, bool expectedValid)
    {
        var root = CreateRepoRoot();
        var pools = new JsonArray();
        for (var index = 0; index < 5; index++)
        {
            pools.Add(new JsonObject
            {
                ["name"] = $"pool-{index}",
                ["taskTypes"] = new JsonArray("code"),
                ["providerChain"] = new JsonArray("openai"),
            });
        }
        var topology = new JsonObject
        {
            ["version"] = 2,
            ["defaults"] = JsonNode.Parse(defaultsJson),
            ["pools"] = pools,
        };
        WriteManifest(root, "config/fleet/fleet-topology.json", topology.ToJsonString());

        var json = HeliosConfigTools.BuildValidationJson("config/fleet/fleet-topology.json", null, root);

        Assert.Equal(expectedValid, JsonDocument.Parse(json).RootElement.GetProperty("valid").GetBoolean());
    }

    [Fact]
    public void FabricSecrets_ReadWhitespaceTheWayThePythonScannerDoes()
    {
        // Python's \s covers U+001C-001F and .NET's does not, so a URL carrying one in its
        // userinfo read as credentials here and as plain text in the authoritative scanner.
        var root = CreateRepoRoot();
        var shipped = JsonNode.Parse(
            File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "fabric", "helios-fabric.v1.json")))!;
        var separator = ((char)0x1c).ToString();   // FILE SEPARATOR: whitespace to Python, not to .NET
        shipped["$comment"] = $"https://user{separator}:password@example.invalid/";
        WriteManifest(root, "config/fabric/helios-fabric.v1.json", shipped.ToJsonString());

        var json = HeliosConfigTools.BuildValidationJson("config/fabric/helios-fabric.v1.json", null, root);

        Assert.DoesNotContain("secret-like value", json);
        // The same URL without the separator is credentials in both engines.
        shipped["$comment"] = "https://user:password@example.invalid/";
        WriteManifest(root, "config/fabric/helios-fabric.v1.json", shipped.ToJsonString());
        Assert.Contains("secret-like value",
            HeliosConfigTools.BuildValidationJson("config/fabric/helios-fabric.v1.json", null, root));
    }

    [Fact]
    public void JsonSchemaLite_AMessageDoesNotRenderTheWholeInstance()
    {
        // Brief() Display()ed the whole value and sliced it afterwards, so one failing branch
        // against a large instance paid for a full serialization to print 120 characters — and
        // every branch of an allOf paid again, in a server with no whole-request deadline.
        var members = string.Join(", ", Enumerable.Range(0, 20_000).Select(i => $"\"k{i}\": \"{new string('y', 200)}\""));
        var branches = string.Join(", ", Enumerable.Range(0, 2_000).Select(_ => "{ \"type\": \"string\" }"));
        using var schema = JsonDocument.Parse($"{{ \"allOf\": [ {branches} ] }}");
        using var instance = JsonDocument.Parse($"{{ {members} }}");

        var started = System.Diagnostics.Stopwatch.StartNew();
        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(2_000, issues.Count);
        Assert.All(issues, issue => Assert.True(issue.Message.Length < 200, issue.Message));
        Assert.True(started.Elapsed < TimeSpan.FromSeconds(20), $"took {started.Elapsed}");
    }

    [Theory]
    [InlineData("""{ "type": "string" }""", """{ "a": 1, "b": [1, 2] }""")]
    [InlineData("""{ "type": "string" }""", "[1, 2, 3]")]
    [InlineData("""{ "type": "string" }""", "1.5")]
    [InlineData("""{ "type": "string" }""", "{}")]
    [InlineData("""{ "type": "object" }""", "\"x\"")]
    public void JsonSchemaLite_ShortValuesReadExactlyAsBefore(string schemaJson, string instanceJson)
    {
        // The bound must not change any message a manifest actually produces: a short value still
        // appears in full, and still round-trips as JSON.
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        var quoted = Assert.Single(issues).Message.Split(" is not of type ")[0];
        using var reparsed = JsonDocument.Parse(quoted);   // throws if the render was truncated
        Assert.Equal(JsonDocument.Parse(instanceJson).RootElement.ValueKind, reparsed.RootElement.ValueKind);
    }

    [Fact]
    public void JsonSchemaLite_TheSchemasOwnValuesAreBoundedToo()
    {
        // `enum` and `const` render the SCHEMA's value into the message, just as unbounded.
        var big = new string('y', 200_000);
        using var enumSchema = JsonDocument.Parse(JsonSerializer.Serialize(new { @enum = new[] { big, "b" } }));
        using var constSchema = JsonDocument.Parse(JsonSerializer.Serialize(new { @const = big }));
        using var instance = JsonDocument.Parse("\"no\"");

        Assert.True(Assert.Single(JsonSchemaLite.Validate(enumSchema.RootElement, instance.RootElement)).Message.Length < 400);
        Assert.True(Assert.Single(JsonSchemaLite.Validate(constSchema.RootElement, instance.RootElement)).Message.Length < 400);
    }

    [Fact]
    public void JsonSchemaLite_DefsMustBeAnObject()
    {
        // python-jsonschema's own check_schema refuses this, so skipping it silently made a schema
        // usable here and unusable there — and nothing walked the definitions either.
        using var broken = JsonDocument.Parse("""{ "$defs": [], "type": "object" }""");
        using var instance = JsonDocument.Parse("{}");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(broken.RootElement, instance.RootElement));
        Assert.Contains("object of named schemas", ex.Message);

        using var empty = JsonDocument.Parse("""{ "$defs": {}, "type": "object" }""");
        Assert.Empty(JsonSchemaLite.Validate(empty.RootElement, instance.RootElement));
    }

    [Fact]
    public void JsonSchemaLite_RequiredPropertyChecksAreChargedToTheBudget()
    {
        // A schema with 300,000 required names spent one evaluation and allocated one issue per
        // name, which is the work the budget exists to bound.
        var names = string.Join(", ", Enumerable.Range(0, 300_000).Select(i => $"\"p{i}\""));
        using var schema = JsonDocument.Parse($"{{ \"type\": \"object\", \"required\": [ {names} ] }}");
        using var instance = JsonDocument.Parse("{}");

        var ex = Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(schema.RootElement, instance.RootElement));

        Assert.Contains("keyword evaluations", ex.Message);
    }

    [Theory]
    [InlineData("maxLength")]
    [InlineData("maxItems")]
    [InlineData("maxProperties")]
    [InlineData("minLength")]
    public void JsonSchemaLite_ASizeBoundStaysInsideWhatBothEnginesHold(string keyword)
    {
        // These are compared against a .NET collection length; the Python twin now refuses a
        // larger bound for the same reason, so one schema gets one verdict.
        using var tooLarge = JsonDocument.Parse($"{{ \"{keyword}\": 2147483648 }}");
        using var instance = JsonDocument.Parse("\"x\"");
        Assert.Contains("2147483647", Assert.Throws<JsonSchemaLite.SchemaException>(
            () => JsonSchemaLite.Validate(tooLarge.RootElement, instance.RootElement)).Message);

        // The largest bound both hold is a usable schema; a min* bound legitimately fails a
        // short instance, so what matters here is that the SCHEMA is accepted.
        using var largest = JsonDocument.Parse($"{{ \"{keyword}\": 2147483647 }}");
        JsonSchemaLite.Validate(largest.RootElement, instance.RootElement);
    }

    [Fact]
    public void FleetTopology_AnEffectiveAssigneePrefixIsUnique()
    {
        // start-fleet.ps1 defaults the prefix to the pool name and names every worker
        // "<prefix>-<n>", deriving its log path from that name.
        var root = CreateRepoRoot();
        var shipped = JsonNode.Parse(
            File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "fleet", "fleet-topology.json")))!;
        var pools = shipped["pools"]!.AsArray();
        pools[1]!["assigneePrefix"] = pools[0]!["assigneePrefix"]!.GetValue<string>();
        WriteManifest(root, "config/fleet/fleet-topology.json", shipped.ToJsonString());

        var json = HeliosConfigTools.BuildValidationJson("config/fleet/fleet-topology.json", null, root);

        Assert.False(JsonDocument.Parse(json).RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains("effective assignee prefix", json);
    }

    [Fact]
    public void ForkWatch_ReasonsMustBeNonBlankTheWayTheWorkflowReadsThem()
    {
        // The schema's \S is ASCII by design (one dialect across three engines), so U+00A0
        // satisfies it while fork-observation.yml's str.strip() refuses the entry.
        var root = CreateRepoRoot();
        var shipped = JsonNode.Parse(
            File.ReadAllText(Path.Combine(ShippedRepoRoot(), "config", "fork-watch.json")))!;
        WriteManifest(root, "config/fork-watch.json", shipped.ToJsonString());
        Assert.Contains("\"valid\": true",
            HeliosConfigTools.BuildValidationJson("config/fork-watch.json", null, root));

        shipped["repos"]![0]!["because"] = "  ";
        WriteManifest(root, "config/fork-watch.json", shipped.ToJsonString());

        var json = HeliosConfigTools.BuildValidationJson("config/fork-watch.json", null, root);

        Assert.False(JsonDocument.Parse(json).RootElement.GetProperty("valid").GetBoolean(), json);
        Assert.Contains("str.strip()", json);
    }

    /// <summary>Temp root: the aihub.json marker plus a copy of the shipped config/schemas/.</summary>
    private string CreateRepoRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), $"helios-mcp-config-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(root, "config", "schemas"));
        File.WriteAllText(Path.Combine(root, "config", "aihub.json"), "{}");
        foreach (var file in Directory.EnumerateFiles(Path.Combine(ShippedRepoRoot(), "config", "schemas"), "*.json"))
        {
            File.Copy(file, Path.Combine(root, "config", "schemas", Path.GetFileName(file)));
        }
        _roots.Add(root);
        return root;
    }

    private static void WriteManifest(string root, string relativePath, string json)
    {
        var full = Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, json);
    }
}
