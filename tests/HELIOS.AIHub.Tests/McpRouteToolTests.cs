using System.ComponentModel;
using System.Reflection;
using HELIOS.Mcp;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The MCP schema is generated from the method signature, so the language dimension
/// of helios_ai_route is pinned here: an optional, described string that sits before
/// the cancellation token (which the server binds itself and must stay last).
/// </summary>
public sealed class McpRouteToolTests
{
    [Fact]
    public void RouteTool_ExposesOptionalDescribedLanguageParameter()
    {
        var method = typeof(HeliosAiTools).GetMethod(nameof(HeliosAiTools.Route), BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(method);

        var parameters = method.GetParameters();
        var language = Assert.Single(parameters, p => p.Name == "language");
        Assert.True(language.IsOptional, "language must be optional so existing callers keep working");
        Assert.Equal(typeof(string), language.ParameterType);
        Assert.Null(language.DefaultValue);

        var description = language.GetCustomAttribute<DescriptionAttribute>();
        Assert.NotNull(description);
        Assert.Contains("fsharp", description.Description);
        Assert.Contains("powershell", description.Description);

        Assert.Equal(typeof(CancellationToken), parameters[^1].ParameterType);
    }
}
