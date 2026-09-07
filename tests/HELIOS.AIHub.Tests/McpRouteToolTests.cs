using System.ComponentModel;
using System.Reflection;
using System.Text.Json;
using HELIOS.AIHub.Configuration;
using HELIOS.Mcp;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The MCP schema is generated from the method signature, so the language dimension
/// of helios_ai_route is pinned here: an optional, described string that sits before
/// the cancellation token (which the server binds itself and must stay last) — and,
/// because system and language are both optional strings, that the tool hands the
/// language (not the system prompt) to the hub's language slot.
/// </summary>
public sealed class McpRouteToolTests
{
    /// <summary>Two echo agents; the fsharp-qualified chain reverses the bare order.</summary>
    private static AIHubOptions LanguageEchoOptions() => new()
    {
        CliAgents = new List<CliAgentOptions>
        {
            new() { Name = "alpha", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
            new() { Name = "beta", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
        },
        Routing = new RoutingOptions
        {
            TaskRouting = new Dictionary<string, List<string>>
            {
                ["echo_task"] = new() { "alpha", "beta" },
                ["echo_task:fsharp"] = new() { "beta", "alpha" },
            },
        },
        Learning = new LearningOptions { Enabled = true },
    };

    [Fact]
    public async Task RouteTool_ForwardsLanguageByName_IntoTheHubRequest()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var store = new FakeLearningStore();
        var hub = new AIHubService(LanguageEchoOptions(), learning: store);

        // A system prompt AND a language: a positional swap inside the tool would still
        // compile and still pass the schema test below, so the recorded outcome pins
        // which value reached which slot.
        var json = await HeliosAiTools.Route(hub, "echo_task", "ping", system: "be brief", language: "fsharp");

        using var document = JsonDocument.Parse(json);
        Assert.True(document.RootElement.GetProperty("Success").GetBoolean(), json);
        Assert.Equal("beta", document.RootElement.GetProperty("Provider").GetString()); // the fsharp chain
        var outcome = Assert.Single(store.Recorded);
        Assert.Equal("echo_task", outcome.TaskType);
        Assert.Equal("fsharp", outcome.Language);
    }

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
