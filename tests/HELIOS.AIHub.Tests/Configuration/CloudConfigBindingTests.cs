using HELIOS.AIHub.Configuration;
using Xunit;

namespace HELIOS.AIHub.Tests.Configuration;

/// <summary>
/// Binds the real shipped config/aihub.cloud.json so drift in the cloud-only profile
/// fails CI, and pins its contract: hosted APIs only — no local runtimes, no CLI agents.
/// </summary>
public class CloudConfigBindingTests
{
    private static AIHubOptions LoadCloudConfig()
    {
        var basePath = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.False(basePath is null, "config/aihub.json not found walking up from test output directory");
        var cloudPath = Path.Combine(Path.GetDirectoryName(basePath!)!, "aihub.cloud.json");
        Assert.True(File.Exists(cloudPath), $"cloud profile missing next to base config: {cloudPath}");
        return AIHubOptions.Load(cloudPath);
    }

    [Fact]
    public void CloudConfig_ContainsOnlyHostedApiProviders()
    {
        var options = LoadCloudConfig();

        foreach (var expected in new[] { "azure-openai", "azure-foundry", "openai", "anthropic", "anthropic-foundry", "github-models" })
        {
            Assert.True(options.Providers.ContainsKey(expected), $"provider '{expected}' missing");
        }
        Assert.False(options.Providers.ContainsKey("ollama"), "cloud profile must not carry local runtimes");
        Assert.Empty(options.CliAgents);
    }

    [Fact]
    public void CloudConfig_RoutingChains_ReferenceOnlyCloudProviders()
    {
        var options = LoadCloudConfig();
        var known = options.Providers.Keys.ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.NotEmpty(options.Routing.DefaultChain);
        foreach (var name in options.Routing.DefaultChain)
        {
            Assert.Contains(name, known);
        }
        foreach (var (taskType, chain) in options.Routing.TaskRouting)
        {
            Assert.True(chain.Count > 0, $"task '{taskType}' has an empty chain");
            foreach (var name in chain)
            {
                Assert.True(known.Contains(name), $"task '{taskType}' references unknown provider '{name}'");
            }
        }
    }

    [Fact]
    public void CloudConfig_DropsLocalOnlyTaskTypes()
    {
        var options = LoadCloudConfig();

        Assert.False(options.Routing.TaskRouting.ContainsKey("offline"), "offline routes to ollama — not a cloud task");
        Assert.False(options.Routing.TaskRouting.ContainsKey("agent_fleet_dispatch"), "fleet dispatch is CLI-only");
        Assert.True(options.Routing.TaskRouting.ContainsKey("enterprise_data"));
        Assert.True(options.Routing.TaskRouting.ContainsKey("code_generation"));
    }

    [Fact]
    public void CloudConfig_EnablesLearningLocally()
    {
        var options = LoadCloudConfig();

        Assert.True(options.Learning.Enabled);
        Assert.Equal("local", options.Learning.Mode);
    }
}
