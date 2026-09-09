using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using HELIOS.Mcp;
using ModelContextProtocol;
using Xunit;

namespace HELIOS.AIHub.Tests;

public sealed class AgentCatalogTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("helios-catalog-test-").FullName;
    private const string Instructions = "Shared HELIOS instructions. Inspect the project contract and return evidence.";
    private HeliosAgentCatalogStore Store => new(_root);

    public AgentCatalogTests()
    {
        Write("AGENTS.md", "trusted test checkout");
        var source = FindRepo();
        foreach (var path in new[] { HeliosAgentCatalogStore.CatalogPath, HeliosAgentCatalogStore.SchemaPath })
            Write(path, File.ReadAllText(Path.Combine(source, path)));
        Write(HeliosAgentCatalogStore.SkillPath, Instructions);
        Write(".claude/agents/reviewer.md", "Reviewer profile");
        Write(".claude/skills/csharp/SKILL.md", "C# skill");
        Write("config/aihub.json", """
            {"providers":{"apiKey":"TEST_SECRET_DO_NOT_RETURN"},"routing":{
              "defaultChain":["default-provider"],"taskRouting":{
                "code_generation":["codex-cli"],"code_generation:csharp":["claude-cli"],
                "code_generation:fsharp":[],"code_review":["claude-cli"],
                "architecture_design":["anthropic"],"agent_fleet_dispatch":["hermes"]}}}
            """);
    }

    [Fact]
    public void CatalogCombinesActualProfilesAndExistingRoutesWithoutCredentialsOrActivation()
    {
        using var result = JsonDocument.Parse(Store.Catalog());
        var root = result.RootElement;
        Assert.Equal(7, root.GetProperty("roles").GetArrayLength());
        Assert.Equal("reviewer", root.GetProperty("agentProfiles")[0].GetProperty("name").GetString());
        Assert.Equal("csharp", root.GetProperty("skills")[0].GetProperty("name").GetString());
        Assert.Equal("config/aihub.json", root.GetProperty("routingSource").GetString());
        Assert.False(root.GetProperty("customProfileApplied").GetBoolean());
        Assert.False(root.GetProperty("runtimeVerified").GetBoolean());
        Assert.False(root.GetProperty("automaticExecution").GetBoolean());
        Assert.DoesNotContain("TEST_SECRET", result.RootElement.GetRawText());
        Assert.False(Directory.Exists(Path.Combine(_root, ".helios")));
    }

    [Theory]
    [InlineData("implement", "code_generation")]
    [InlineData("review", "code_review")]
    [InlineData("hybrid-plan", "architecture_design")]
    [InlineData("fleet-plan", "agent_fleet_dispatch")]
    public void EveryTaskPacketCarriesTheSameSkillHashAndHandoffContract(string kind, string route)
    {
        var first = Store.TaskPacket(kind);
        Assert.Equal(first, Store.TaskPacket(kind));
        using var result = JsonDocument.Parse(first);
        var root = result.RootElement;
        Assert.Equal(route, root.GetProperty("routeTaskType").GetString());
        Assert.Equal("config/aihub.json", root.GetProperty("routingSource").GetString());
        Assert.False(root.GetProperty("customProfileApplied").GetBoolean());
        Assert.Equal(Instructions, root.GetProperty("instructions").GetProperty("text").GetString());
        Assert.Equal(Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Instructions))).ToLowerInvariant(),
            root.GetProperty("instructions").GetProperty("sha256").GetString());
        Assert.Equal(7, root.GetProperty("handoffContract").GetProperty("recipients").GetArrayLength());
        Assert.Equal("helios_handoff_submit", root.GetProperty("handoffContract").GetProperty("submitTool").GetString());
        Assert.Contains("AGENTS.md", first);
        Assert.False(root.GetProperty("automaticExecution").GetBoolean());
        Assert.False(Directory.Exists(Path.Combine(_root, ".helios")));
    }

    [Fact]
    public void PacketUsesTheCoreLanguageNormalizerAndRoutingFallback()
    {
        using var csharp = JsonDocument.Parse(Store.TaskPacket("implement", "C#"));
        Assert.Equal("csharp", csharp.RootElement.GetProperty("language").GetString());
        Assert.Equal("claude-cli", csharp.RootElement.GetProperty("configuredChain")[0].GetString());
        using var fsharp = JsonDocument.Parse(Store.TaskPacket("implement", "F#"));
        Assert.Equal("codex-cli", fsharp.RootElement.GetProperty("configuredChain")[0].GetString());
        Assert.Equal("code_generation", fsharp.RootElement.GetProperty("resolvedRouteKey").GetString());
    }

    [Theory]
    [InlineData("deploy", null)]
    [InlineData("../../.env", null)]
    [InlineData("implement", "../../.env")]
    [InlineData("implement", "csharp; run something")]
    public void CallersCannotSelectArbitraryTasksPathsOrCommands(string kind, string? language) =>
        Assert.Throws<McpException>(() => Store.TaskPacket(kind, language));

    [Fact]
    public void CatalogCannotEnableExecutionOrChangeItsFixedInstructionSource()
    {
        var path = Path.Combine(_root, HeliosAgentCatalogStore.CatalogPath);
        var catalog = JsonNode.Parse(File.ReadAllText(path))!;
        catalog["automaticExecution"] = true;
        File.WriteAllText(path, catalog.ToJsonString());
        Assert.Throws<McpException>(() => Store.Catalog());
        catalog["automaticExecution"] = false;
        catalog["sources"]!["canonicalSkill"] = ".env";
        File.WriteAllText(path, catalog.ToJsonString());
        Assert.Throws<McpException>(() => Store.TaskPacket("implement"));
    }

    [Fact]
    public void MissingOrOversizedCanonicalSkillIsAnExplicitFailure()
    {
        var path = Path.Combine(_root, HeliosAgentCatalogStore.SkillPath);
        File.Delete(path);
        Assert.Throws<McpException>(() => Store.TaskPacket("review"));
        File.WriteAllText(path, new string('x', 32 * 1024 + 1));
        Assert.Throws<McpException>(() => Store.TaskPacket("review"));
    }

    [Fact]
    public void HybridAndFleetPacketsKeepCurrentImplementationGapsVisible()
    {
        using var hybrid = JsonDocument.Parse(Store.TaskPacket("hybrid-plan"));
        Assert.Contains("Terraform", hybrid.RootElement.GetProperty("readinessNotes").GetRawText());
        Assert.Contains("ARC", hybrid.RootElement.GetProperty("readinessNotes").GetRawText());
        using var fleet = JsonDocument.Parse(Store.TaskPacket("fleet-plan"));
        Assert.Contains("stubs", fleet.RootElement.GetProperty("readinessNotes").GetRawText());
    }

    [Theory]
    [InlineData("root")]
    [InlineData("ancestor")]
    [InlineData("marker")]
    public void LinkedCheckoutRootAncestorOrMarkerIsRejectedBeforeUse(string linkedPart)
    {
        if (OperatingSystem.IsWindows())
            return; // Creation requires privileges there; Linux CI exercises every case.

        var selectedRoot = _root;
        string? directoryLink = null;
        try
        {
            if (linkedPart == "marker")
            {
                Write("real-contract.md", "inert contract fixture");
                File.Delete(Path.Combine(_root, "AGENTS.md"));
                File.CreateSymbolicLink(Path.Combine(_root, "AGENTS.md"), Path.Combine(_root, "real-contract.md"));
            }
            else
            {
                Write("physical/checkout/AGENTS.md", "inert checkout fixture");
                directoryLink = Path.Combine(_root, "linked");
                Directory.CreateSymbolicLink(directoryLink,
                    Path.Combine(_root, linkedPart == "root" ? "physical/checkout" : "physical"));
                selectedRoot = linkedPart == "root" ? directoryLink : Path.Combine(directoryLink, "checkout");
            }

            // Each path resolves to a real checkout marker; rejection must come
            // from the link boundary rather than a missing file or catalog.
            Assert.True(File.Exists(Path.Combine(selectedRoot, "AGENTS.md")));
            var error = Assert.Throws<McpException>(() => new HeliosAgentCatalogStore(selectedRoot));
            Assert.Contains("Linked shared instruction", error.Message);
            Assert.DoesNotContain(_root, error.Message);
        }
        finally
        {
            if (directoryLink is not null) Directory.Delete(directoryLink);
        }
    }

    private void Write(string path, string text)
    {
        var full = Path.Combine(_root, path);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, text);
    }

    private static string FindRepo()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, HeliosAgentCatalogStore.CatalogPath))) return directory.FullName;
        throw new InvalidOperationException("Cannot locate the test catalog in the checkout.");
    }

    public void Dispose() => Directory.Delete(_root, recursive: true);
}
