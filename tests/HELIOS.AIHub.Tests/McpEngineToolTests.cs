using System.Reflection;
using System.Text.Json;
using HELIOS.AIHub.Learning;
using HELIOS.Mcp;
using Xunit;

namespace HELIOS.AIHub.Tests;

public sealed class McpEngineToolTests
{
    private static readonly bool RequirePythonSpoke =
        Environment.GetEnvironmentVariable("HELIOS_REQUIRE_PYTHON_SPOKE") == "1";

    [Theory]
    [InlineData(nameof(HeliosAiTools.GetEngineCatalog), "helios_engine_catalog_get")]
    [InlineData(nameof(HeliosAiTools.RecommendEngineMix), "helios_engine_mix_recommend")]
    public void EngineTools_AreDiscoverable(string methodName, string expectedToolName)
    {
        var method = typeof(HeliosAiTools).GetMethod(methodName, BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var name = toolAttribute.GetType().GetProperty("Name")?.GetValue(toolAttribute)?.ToString();
        Assert.Equal(expectedToolName, name);
    }

    [Fact]
    public async Task EngineCatalogTool_InvokesPackagedContract()
    {
        var json = await HeliosAiTools.GetEngineCatalog(new PythonInsightsSpoke());
        using var document = JsonDocument.Parse(json);

        if (IsUnavailable(document.RootElement))
        {
            Assert.False(RequirePythonSpoke, "The required Python spoke did not round-trip.");
            return;
        }

        Assert.True(document.RootElement.GetProperty("implemented_count").GetInt32() > 0);
    }

    [Fact]
    public async Task EngineRecommendationTool_NormalizesExplicitNullProfile()
    {
        var json = await HeliosAiTools.RecommendEngineMix(
            new PythonInsightsSpoke(),
            securityProfile: null);
        using var document = JsonDocument.Parse(json);

        if (IsUnavailable(document.RootElement))
        {
            Assert.False(RequirePythonSpoke, "The required Python spoke did not round-trip.");
            return;
        }

        Assert.Equal(
            "balanced",
            document.RootElement.GetProperty("inputs").GetProperty("security_profile").GetString());
    }

    private static bool IsUnavailable(JsonElement root) =>
        root.TryGetProperty("available", out var available) && !available.GetBoolean();
}
