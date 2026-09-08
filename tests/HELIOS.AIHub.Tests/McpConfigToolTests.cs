using System.Reflection;
using System.Text.Json;
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
    [InlineData("""{ "type": "string", "format": "date-time" }""", "\"Sept 7 2026 23:00\"", false)]
    public void JsonSchemaLite_ComparesValuesCountsCodePointsAndChecksDateTimeShape(string schemaJson, string instanceJson, bool expectedValid)
    {
        using var schema = JsonDocument.Parse(schemaJson);
        using var instance = JsonDocument.Parse(instanceJson);

        var issues = JsonSchemaLite.Validate(schema.RootElement, instance.RootElement);

        Assert.Equal(expectedValid, issues.Count == 0);
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
