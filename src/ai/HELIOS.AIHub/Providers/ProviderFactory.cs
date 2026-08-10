using System.ClientModel;
using Azure.AI.OpenAI;
using Azure.Identity;
using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using Microsoft.Extensions.AI;
using OllamaSharp;
using OpenAI;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// Builds provider agents from configuration. A missing secret or endpoint yields an
/// Unconfigured agent with a hint — never an exception — so `helios-ai status` always works.
/// </summary>
public static class ProviderFactory
{
    public const string GitHubModelsEndpoint = "https://models.github.ai/inference";
    public const string DefaultOllamaEndpoint = "http://localhost:11434";

    public static IReadOnlyList<IChatProviderAgent> CreateAll(AIHubOptions options, ISecretResolver secrets)
    {
        var agents = new List<IChatProviderAgent>();
        foreach (var (name, provider) in options.Providers)
        {
            if (provider.Enabled)
            {
                agents.Add(Create(name, provider, secrets));
            }
        }
        foreach (var cli in options.CliAgents)
        {
            if (cli.Enabled)
            {
                agents.Add(new CliProcessAgent(cli));
            }
        }
        return agents;
    }

    public static IChatProviderAgent Create(string name, ProviderOptions provider, ISecretResolver secrets)
    {
        return provider.Type.ToLowerInvariant() switch
        {
            "openai" => CreateOpenAi(name, provider, secrets),
            "github-models" => CreateGitHubModels(name, provider, secrets),
            "azure-openai" => CreateAzureOpenAi(name, provider, secrets),
            "anthropic" => new AnthropicAgent(
                name, "Claude (Anthropic)", provider.Model,
                secrets.Resolve(provider.ApiKeyEnv ?? "ANTHROPIC_API_KEY", provider.ApiKeySecretName)),
            "ollama" => CreateOllama(name, provider),
            "azure-foundry-agent" => new FoundryAgentProvider(
                name, "Azure AI Foundry Agent", provider.Model,
                Environment.GetEnvironmentVariable(provider.EndpointEnv ?? "AZURE_FOUNDRY_PROJECT_ENDPOINT")),
            _ => new ChatClientAgent(name, name, provider.Model, null,
                $"Unknown provider type '{provider.Type}' — expected openai | azure-openai | anthropic | github-models | ollama | azure-foundry-agent."),
        };
    }

    private static IChatProviderAgent CreateOpenAi(string name, ProviderOptions provider, ISecretResolver secrets)
    {
        var key = secrets.Resolve(provider.ApiKeyEnv ?? "OPENAI_API_KEY", provider.ApiKeySecretName);
        if (key is null)
        {
            return new ChatClientAgent(name, "OpenAI", provider.Model, null,
                "Set OPENAI_API_KEY (or configure the Key Vault secret 'openai-api-key').");
        }
        var client = new OpenAIClient(key);
        return new ChatClientAgent(name, "OpenAI", provider.Model,
            model => client.GetChatClient(model).AsIChatClient());
    }

    private static IChatProviderAgent CreateGitHubModels(string name, ProviderOptions provider, ISecretResolver secrets)
    {
        var key = secrets.Resolve(provider.ApiKeyEnv ?? "GITHUB_MODELS_TOKEN", provider.ApiKeySecretName)
                  ?? Environment.GetEnvironmentVariable("GITHUB_TOKEN");
        if (key is null)
        {
            return new ChatClientAgent(name, "GitHub Models", provider.Model, null,
                "Set GITHUB_MODELS_TOKEN or GITHUB_TOKEN (a GitHub PAT with models:read).");
        }
        // A malformed baseUrl is "unconfigured", not a construction crash — same
        // contract as the Azure OpenAI endpoint below.
        var baseUrl = provider.BaseUrl ?? GitHubModelsEndpoint;
        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var baseUri)
            || (baseUri.Scheme != Uri.UriSchemeHttps && baseUri.Scheme != Uri.UriSchemeHttp))
        {
            return new ChatClientAgent(name, "GitHub Models", provider.Model, null,
                "github-models baseUrl is not an absolute http(s) URL; fix config/aihub.json to enable this provider.");
        }
        var client = new OpenAIClient(
            new ApiKeyCredential(key),
            new OpenAIClientOptions { Endpoint = baseUri });
        return new ChatClientAgent(name, "GitHub Models", provider.Model,
            model => client.GetChatClient(model).AsIChatClient());
    }

    private static IChatProviderAgent CreateAzureOpenAi(string name, ProviderOptions provider, ISecretResolver secrets)
    {
        var endpoint = Environment.GetEnvironmentVariable(provider.EndpointEnv ?? "AZURE_OPENAI_ENDPOINT");
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            return new ChatClientAgent(name, "Azure OpenAI", provider.Model, null,
                "Set AZURE_OPENAI_ENDPOINT (infra output 'openAiEndpoint').");
        }

        // A malformed endpoint value is "unconfigured", not a construction crash — one
        // bad environment variable must not take down status and every other provider.
        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var endpointUri)
            || (endpointUri.Scheme != Uri.UriSchemeHttps && endpointUri.Scheme != Uri.UriSchemeHttp))
        {
            return new ChatClientAgent(name, "Azure OpenAI", provider.Model, null,
                "AZURE_OPENAI_ENDPOINT is not an absolute http(s) URL; fix it to enable this provider.");
        }

        // Key when present; otherwise Entra ID via DefaultAzureCredential (CLI login,
        // managed identity, workload identity — matches AzureConfiguration semantics).
        var key = secrets.Resolve(provider.ApiKeyEnv ?? "AZURE_OPENAI_API_KEY", provider.ApiKeySecretName);
        var client = key is null
            ? new AzureOpenAIClient(endpointUri, new DefaultAzureCredential())
            : new AzureOpenAIClient(endpointUri, new ApiKeyCredential(key));
        return new ChatClientAgent(name, "Azure OpenAI / Foundry Models", provider.Model,
            deployment => client.GetChatClient(deployment).AsIChatClient());
    }

    private static IChatProviderAgent CreateOllama(string name, ProviderOptions provider)
    {
        var endpoint = Environment.GetEnvironmentVariable(provider.EndpointEnv ?? "OLLAMA_BASE_URL")
                       ?? provider.BaseUrl
                       ?? DefaultOllamaEndpoint;
        return new ChatClientAgent(name, "Ollama (local)", provider.Model,
            model => new OllamaApiClient(new Uri(endpoint), model));
    }
}
