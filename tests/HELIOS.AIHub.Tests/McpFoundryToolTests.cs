using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using HELIOS.AIHub.Providers;
using HELIOS.Mcp;
using ModelContextProtocol;
using Xunit;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// The Foundry agent-administration MCP tools (helios_foundry_agent_list,
/// helios_foundry_agent_create) and their service seam. Keyless-deterministic:
/// everything runs against a scripted <see cref="IFoundryAgentAdministration"/> fake or
/// the unconfigured (null endpoint) state — no credentials, no network, ever.
/// </summary>
public sealed class McpFoundryToolTests
{
    private static readonly DateTimeOffset SampleCreated = new(2026, 8, 1, 12, 0, 0, TimeSpan.Zero);

    // ---- discoverability -----------------------------------------------------------

    [Theory]
    [InlineData(nameof(HeliosFoundryTools.ListFoundryAgents), "helios_foundry_agent_list", true)]
    [InlineData(nameof(HeliosFoundryTools.CreateFoundryAgent), "helios_foundry_agent_create", false)]
    public void FoundryTools_AreDiscoverable_WithExpectedAnnotations(
        string methodName, string expectedToolName, bool expectedReadOnly)
    {
        var method = typeof(HeliosFoundryTools).GetMethod(methodName, BindingFlags.Public | BindingFlags.Static);

        Assert.NotNull(method);
        var toolAttribute = Assert.Single(
            method.GetCustomAttributes(),
            attribute => attribute.GetType().Name == "McpServerToolAttribute");
        var attributeType = toolAttribute.GetType();
        Assert.Equal(expectedToolName, attributeType.GetProperty("Name")?.GetValue(toolAttribute)?.ToString());
        Assert.Equal(expectedReadOnly, attributeType.GetProperty("ReadOnly")?.GetValue(toolAttribute));
    }

    // ---- unconfigured state --------------------------------------------------------

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Service_WithoutEndpoint_IsUnconfigured(string? endpoint)
    {
        var service = new FoundryAgentService(endpoint);

        Assert.False(service.IsConfigured);
    }

    [Fact]
    public async Task ListTool_Unconfigured_ReturnsHint_NeverThrows()
    {
        var service = new FoundryAgentService(projectEndpoint: null);

        var json = await HeliosFoundryTools.ListFoundryAgents(service);
        using var document = JsonDocument.Parse(json);

        Assert.False(document.RootElement.GetProperty("configured").GetBoolean());
        var hint = document.RootElement.GetProperty("hint").GetString();
        Assert.Contains("AZURE_FOUNDRY_PROJECT_ENDPOINT", hint);
        // Same wording as the azure-foundry provider's unconfigured hint.
        Assert.Equal(FoundryAgentService.UnconfiguredHint, hint);
    }

    [Fact]
    public async Task CreateTool_Unconfigured_ThrowsActionableMcpException()
    {
        var service = new FoundryAgentService(projectEndpoint: null);

        var exception = await Assert.ThrowsAsync<McpException>(() =>
            HeliosFoundryTools.CreateFoundryAgent(service, "reviewer", "gpt-5-mini", "Review code."));

        Assert.Contains("Set AZURE_FOUNDRY_PROJECT_ENDPOINT", exception.Message);
    }

    // ---- parameter validation (before any seam/network call) ------------------------

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(101)]
    public async Task ListTool_InvalidLimit_Throws_WithoutTouchingSeam(int limit)
    {
        var fake = new FakeFoundryAgentAdministration();
        var service = NewConfiguredService(fake);

        await Assert.ThrowsAsync<McpException>(() =>
            HeliosFoundryTools.ListFoundryAgents(service, limit));

        Assert.Equal(0, fake.ListCalls);
    }

    [Theory]
    [InlineData(null, "gpt-5-mini", "instructions", "name")]
    [InlineData("  ", "gpt-5-mini", "instructions", "name")]
    [InlineData("agent", null, "instructions", "model")]
    [InlineData("agent", "", "instructions", "model")]
    [InlineData("agent", "gpt-5-mini", null, "instructions")]
    [InlineData("agent", "gpt-5-mini", "   ", "instructions")]
    public async Task CreateTool_MissingRequiredParam_Throws_WithoutTouchingSeam(
        string? name, string? model, string? instructions, string expectedParameter)
    {
        var fake = new FakeFoundryAgentAdministration();
        var service = NewConfiguredService(fake);

        var exception = await Assert.ThrowsAsync<McpException>(() =>
            HeliosFoundryTools.CreateFoundryAgent(service, name!, model!, instructions!));

        Assert.Contains(expectedParameter, exception.Message);
        Assert.Empty(fake.CreateCalls);
    }

    // ---- response shaping through the fake seam -------------------------------------

    [Fact]
    public async Task ListTool_ShapesAgents_AsIdNameModelCreated()
    {
        var fake = new FakeFoundryAgentAdministration
        {
            Agents =
            {
                new FoundryAgentSummary("asst_1", "helios-aihub", "gpt-5-mini", SampleCreated, "hub agent"),
                new FoundryAgentSummary("asst_2", "reviewer", "gpt-5", SampleCreated.AddMinutes(5)),
            },
        };
        var service = NewConfiguredService(fake);

        var json = await HeliosFoundryTools.ListFoundryAgents(service);
        using var document = JsonDocument.Parse(json);

        var root = document.RootElement;
        Assert.True(root.GetProperty("configured").GetBoolean());
        Assert.Equal(2, root.GetProperty("count").GetInt32());
        var first = root.GetProperty("agents")[0];
        Assert.Equal("asst_1", first.GetProperty("id").GetString());
        Assert.Equal("helios-aihub", first.GetProperty("name").GetString());
        Assert.Equal("gpt-5-mini", first.GetProperty("model").GetString());
        Assert.Equal(SampleCreated, first.GetProperty("created").GetDateTimeOffset());
        Assert.Equal(1, fake.ListCalls);
    }

    [Fact]
    public async Task ListTool_CapsResults_AtRequestedLimit()
    {
        var fake = new FakeFoundryAgentAdministration();
        for (var i = 0; i < 7; i++)
        {
            fake.Agents.Add(new FoundryAgentSummary($"asst_{i}", $"agent-{i}", "gpt-5-mini", SampleCreated));
        }
        var service = NewConfiguredService(fake);

        var json = await HeliosFoundryTools.ListFoundryAgents(service, limit: 3);
        using var document = JsonDocument.Parse(json);

        Assert.Equal(3, document.RootElement.GetProperty("count").GetInt32());
        Assert.Equal(3, document.RootElement.GetProperty("agents").GetArrayLength());
    }

    [Fact]
    public async Task CreateTool_CallsSeamExactlyOnce_AndReturnsCreatedIdentity()
    {
        var fake = new FakeFoundryAgentAdministration();
        var service = NewConfiguredService(fake);

        var json = await HeliosFoundryTools.CreateFoundryAgent(
            service, "fleet-reviewer", "gpt-5-mini", "Review fleet task output.", "HELIOS fleet reviewer");
        using var document = JsonDocument.Parse(json);

        var call = Assert.Single(fake.CreateCalls);
        Assert.Equal(("gpt-5-mini", "fleet-reviewer", "Review fleet task output.", "HELIOS fleet reviewer"), call);
        var root = document.RootElement;
        Assert.True(root.GetProperty("created").GetBoolean());
        Assert.Equal("asst_created_1", root.GetProperty("id").GetString());
        Assert.Equal("fleet-reviewer", root.GetProperty("name").GetString());
        Assert.Equal("gpt-5-mini", root.GetProperty("model").GetString());
    }

    [Fact]
    public async Task Service_Create_TrimsParams_AndDefaultsBlankDescriptionToNull()
    {
        var fake = new FakeFoundryAgentAdministration();
        var service = NewConfiguredService(fake);

        var created = await service.CreateAgentAsync("  reviewer  ", " gpt-5-mini ", " Review. ", "   ");

        var call = Assert.Single(fake.CreateCalls);
        Assert.Equal(("gpt-5-mini", "reviewer", "Review.", null), call);
        Assert.Equal("asst_created_1", created.Id);
    }

    [Fact]
    public async Task Service_List_Unconfigured_ReturnsEmptyWithHint()
    {
        var service = new FoundryAgentService(projectEndpoint: null);

        var result = await service.ListAgentsAsync();

        Assert.False(result.Configured);
        Assert.Equal(FoundryAgentService.UnconfiguredHint, result.Hint);
        Assert.Empty(result.Agents);
    }

    private static FoundryAgentService NewConfiguredService(IFoundryAgentAdministration administration) =>
        new("https://example.services.ai.azure.com/api/projects/test", () => administration);

    /// <summary>Scriptable seam: hand-rolled fake per the repo's no-Moq idiom.</summary>
    private sealed class FakeFoundryAgentAdministration : IFoundryAgentAdministration
    {
        public List<FoundryAgentSummary> Agents { get; } = new();

        public List<(string Model, string Name, string Instructions, string? Description)> CreateCalls { get; } = new();

        public int ListCalls { get; private set; }

        public async IAsyncEnumerable<FoundryAgentSummary> ListAgentsAsync(
            int pageSize, [EnumeratorCancellation] CancellationToken cancellationToken)
        {
            ListCalls++;
            foreach (var agent in Agents)
            {
                cancellationToken.ThrowIfCancellationRequested();
                yield return agent;
            }
            await Task.CompletedTask;
        }

        public Task<FoundryAgentSummary> CreateAgentAsync(
            string model, string name, string instructions, string? description, CancellationToken cancellationToken)
        {
            CreateCalls.Add((model, name, instructions, description));
            return Task.FromResult(new FoundryAgentSummary(
                $"asst_created_{CreateCalls.Count}", name, model, SampleCreated, description));
        }
    }
}
