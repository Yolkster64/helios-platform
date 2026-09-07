using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Routing;
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
    public void CloudConfig_LanguageQualifiedChains_MirrorTheLocalProfile()
    {
        var cloud = LoadCloudConfig();
        var local = AIHubOptions.Load(AIHubOptions.FindConfigFile(AppContext.BaseDirectory)!);

        static List<string> Qualified(AIHubOptions options) => options.Routing.TaskRouting.Keys
            .Where(key => TaskTypeRoutingStrategy.SplitRoutingKey(key).Language is not null)
            .OrderBy(key => key, StringComparer.Ordinal)
            .ToList();

        // Same language dimension in both profiles — a caller switching AIHUB_CONFIG
        // keeps every language-qualified route, just over hosted providers.
        Assert.Equal(Qualified(local), Qualified(cloud));
        foreach (var key in Qualified(cloud))
        {
            var (taskType, language) = TaskTypeRoutingStrategy.SplitRoutingKey(key);
            Assert.True(cloud.Routing.TaskRouting.ContainsKey(taskType), $"'{key}' has no bare parent '{taskType}'");
            Assert.Equal(TaskTypeRoutingStrategy.NormalizeLanguage(language), language);
            Assert.NotEqual(cloud.Routing.TaskRouting[taskType], cloud.Routing.TaskRouting[key]);
        }
    }

    [Fact]
    public void CloudConfig_EnablesLearningLocally()
    {
        var options = LoadCloudConfig();

        Assert.True(options.Learning.Enabled);
        Assert.Equal("local", options.Learning.Mode);
    }

    [Fact]
    public void CloudConfig_OptsIntoAdaptiveRouting_Explicitly()
    {
        // The C# default and the local profile keep adaptive routing OFF; the cloud
        // profile opts in on purpose (every routed call there is a paid API call, so the
        // learned reorder earns its keep immediately). Pinned so the opt-in can only
        // change through a visible config edit — and so a profile that merely omitted
        // the key would fail here instead of silently inheriting the off default.
        var options = LoadCloudConfig();

        Assert.True(options.Learning.AdaptiveRouting);
        Assert.NotEqual(new LearningOptions().AdaptiveRouting, options.Learning.AdaptiveRouting);
    }
}
