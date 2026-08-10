using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Providers;
using Microsoft.Extensions.AI;
using Xunit;

namespace HELIOS.AIHub.Tests.Providers;

public class ChatClientAgentTests
{
    [Fact]
    public async Task ChatAsync_MapsPromptSystemAndOptions()
    {
        var fake = new FakeChatClient((messages, options) => new ChatResponse(
            new ChatMessage(ChatRole.Assistant, "hello back"))
        {
            ModelId = options?.ModelId,
        });
        var agent = new ChatClientAgent("openai", "OpenAI", "default-model", _ => fake);

        var result = await agent.ChatAsync(new ChatRequest(
            "hello", System: "be brief", MaxTokens: 42, Temperature: 0.5));

        Assert.True(result.Success);
        Assert.Equal("hello back", result.Text);
        Assert.Equal("default-model", result.Model);
        var (messages, options) = Assert.Single(fake.Calls);
        Assert.Equal(2, messages.Count);
        Assert.Equal(ChatRole.System, messages[0].Role);
        Assert.Equal(ChatRole.User, messages[1].Role);
        Assert.Equal(42, options!.MaxOutputTokens);
        Assert.Equal(0.5f, options.Temperature);
    }

    [Fact]
    public async Task ChatAsync_UsesRequestModelOverride()
    {
        var requestedModels = new List<string>();
        var agent = new ChatClientAgent("openai", "OpenAI", "default-model", model =>
        {
            requestedModels.Add(model);
            return new FakeChatClient((_, _) => new ChatResponse(new ChatMessage(ChatRole.Assistant, "ok")));
        });

        await agent.ChatAsync(new ChatRequest("q", Model: "special-model"));

        Assert.Equal(new[] { "special-model" }, requestedModels);
    }

    [Fact]
    public async Task ChatAsync_Unconfigured_ReturnsHint_WithoutThrowing()
    {
        var agent = new ChatClientAgent("openai", "OpenAI", "m", null, "set OPENAI_API_KEY");

        var result = await agent.ChatAsync(new ChatRequest("q"));

        Assert.False(result.Success);
        Assert.Contains("OPENAI_API_KEY", result.Error);
        Assert.Equal(ProviderReadiness.Unconfigured, agent.Readiness);
    }

    [Fact]
    public async Task ChatAsync_ConvertsProviderException_ToFailedResult()
    {
        var agent = new ChatClientAgent("openai", "OpenAI", "m",
            _ => new FakeChatClient((_, _) => throw new HttpRequestException("boom")));

        var result = await agent.ChatAsync(new ChatRequest("q"));

        Assert.False(result.Success);
        Assert.Contains("boom", result.Error);
        Assert.Equal(1, agent.GetMetrics().FailedRequests);
    }

    [Fact]
    public async Task ExecuteAsync_MapsAgentRequestParameters()
    {
        var agent = new ChatClientAgent("openai", "OpenAI", "m",
            _ => new FakeChatClient((_, _) => new ChatResponse(new ChatMessage(ChatRole.Assistant, "ok"))));

        var agentResult = await agent.ExecuteAsync(new Platform.Core.AI.Interfaces.AgentRequest
        {
            Operation = "chat",
            Parameters = { ["prompt"] = "hi" },
        });

        Assert.True(agentResult.Success);
        var chat = Assert.IsType<ChatResult>(agentResult.ResultData);
        Assert.Equal("ok", chat.Text);
    }
}
