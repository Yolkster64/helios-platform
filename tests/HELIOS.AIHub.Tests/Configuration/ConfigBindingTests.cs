using HELIOS.AIHub.Configuration;
using Xunit;

namespace HELIOS.AIHub.Tests.Configuration;

/// <summary>Binds the real shipped config/aihub.json so config drift fails CI.</summary>
public class ConfigBindingTests
{
    private static AIHubOptions LoadShippedConfig()
    {
        var path = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.False(path is null, "config/aihub.json not found walking up from test output directory");
        return AIHubOptions.Load(path!);
    }

    [Fact]
    public void ShippedConfig_Loads_WithExpectedProviders()
    {
        var options = LoadShippedConfig();

        foreach (var expected in new[] { "openai", "openai-codex", "anthropic", "anthropic-foundry", "azure-openai", "github-models", "ollama", "azure-foundry" })
        {
            Assert.True(options.Providers.ContainsKey(expected), $"provider '{expected}' missing");
        }
        foreach (var expectedCli in new[] { "claude-cli", "codex", "copilot", "gh-models", "hermes" })
        {
            Assert.Contains(options.CliAgents, cli => cli.Name == expectedCli);
        }
    }

    [Fact]
    public void ShippedConfig_ContainsNoSecrets()
    {
        var options = LoadShippedConfig();

        foreach (var (name, provider) in options.Providers)
        {
            // Only env-var / secret-name indirection is allowed in the config file.
            Assert.True(string.IsNullOrEmpty(provider.ApiKeyEnv) || !provider.ApiKeyEnv.Contains(' '),
                $"provider '{name}' apiKeyEnv looks like a literal value");
            Assert.DoesNotContain("sk-", provider.ApiKeyEnv ?? "");
        }
    }

    [Fact]
    public void ShippedConfig_RoutingChains_ReferenceKnownProviders()
    {
        var options = LoadShippedConfig();
        var known = options.Providers.Keys
            .Concat(options.CliAgents.Select(cli => cli.Name))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

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
    public void ShippedConfig_CoversCoreTaskTypes()
    {
        var options = LoadShippedConfig();
        foreach (var taskType in new[]
                 {
                     "code_generation", "code_review", "long_context_analysis", "security_analysis",
                     "enterprise_data", "inline_completion", "agent_fleet_dispatch", "offline",
                 })
        {
            Assert.True(options.Routing.TaskRouting.ContainsKey(taskType), $"task type '{taskType}' missing");
        }
    }
}
