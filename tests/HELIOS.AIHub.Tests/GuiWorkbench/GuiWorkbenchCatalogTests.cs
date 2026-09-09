using System.Text;
using System.Text.Json.Nodes;
using HELIOS.Shell.Services;
using Xunit;

namespace HELIOS.AIHub.Tests.GuiWorkbench;

public class GuiWorkbenchCatalogTests
{
    private static JsonObject Manifest()
    {
        var pieces = new JsonObject();
        foreach (var id in new[] { "home", "aihub", "fabric", "usb", "themes" })
            pieces[id] = new JsonObject
            {
                ["name"] = $"Name from manifest: {id}",
                ["purpose"] = $"Purpose from manifest: {id}",
                ["paths"] = new JsonArray("src/gui/example.xaml"),
                ["linkedParts"] = new JsonArray("core"),
            };
        return new JsonObject
        {
            ["schemaVersion"] = 1,
            ["parts"] = new JsonObject
            {
                ["gui"] = new JsonObject
                {
                    ["testProfile"] = "gui",
                    ["workflows"] = new JsonArray(".github/workflows/gui-windows.yml"),
                    ["releaseBoundary"] = "Desktop packages the shared native build.",
                    ["pieces"] = pieces,
                },
            },
        };
    }

    private static GuiWorkbenchCatalog Parse(JsonObject value)
        => GuiWorkbenchCatalog.Parse(Encoding.UTF8.GetBytes(value.ToJsonString()));

    [Fact]
    public void UsesManifestLabelsAndFixedNavigationOrderWithoutClaimingLiveStatus()
    {
        var catalog = Parse(Manifest());
        Assert.True(catalog.IsAvailable);
        Assert.Equal(new[] { "home", "aihub", "fabric", "usb", "themes" }, catalog.Modules.Select(m => m.Id));
        Assert.Equal("Name from manifest: aihub", catalog.Modules[1].Name);
        Assert.Equal("Purpose from manifest: aihub", catalog.Modules[1].Purpose);
        Assert.Equal("src/gui/example.xaml", catalog.Modules[1].SourceDisplay);
        Assert.Equal("core", catalog.Modules[1].DependenciesDisplay);
        Assert.Contains("not been queried", catalog.Status);
        Assert.Contains("configured runtime", catalog.Modules[1].OpenLabel);
        Assert.Contains("leaves fixtures", catalog.Modules[2].RuntimeNotice);
    }

    [Theory]
    [InlineData("")]
    [InlineData("{")]
    [InlineData("[]")]
    [InlineData("null")]
    [InlineData("{}")]
    [InlineData("{\"schemaVersion\":\"1\",\"parts\":{}}")]
    public void MalformedOrMissingMetadataReturnsUnavailable(string json)
    {
        var catalog = GuiWorkbenchCatalog.Parse(Encoding.UTF8.GetBytes(json));
        Assert.False(catalog.IsAvailable);
        Assert.Empty(catalog.Modules);
        Assert.Empty(catalog.Workflows);
        Assert.Contains("unavailable", catalog.Status);
    }

    [Fact]
    public void OversizedManifestIsRejectedBeforeParsing()
    {
        var bytes = new byte[GuiWorkbenchCatalog.MaximumBytes + 1];
        Assert.False(GuiWorkbenchCatalog.Parse(bytes).IsAvailable);
    }

    [Fact]
    public void DuplicatePropertiesCannotOverrideDisplayedAuthority()
    {
        var json = Manifest().ToJsonString().Replace("\"testProfile\":\"gui\"", "\"testProfile\":\"desktop\",\"testProfile\":\"gui\"");
        Assert.False(GuiWorkbenchCatalog.Parse(Encoding.UTF8.GetBytes(json)).IsAvailable);
    }

    [Fact]
    public void ExtraNavigationIdentifiersAreRejected()
    {
        var manifest = Manifest();
        manifest["parts"]!["gui"]!["pieces"]!["run-shell"] = new JsonObject();
        Assert.False(Parse(manifest).IsAvailable);
    }

    [Fact]
    public void MissingRequiredPieceDoesNotInventFallbackMap()
    {
        var manifest = Manifest();
        manifest["parts"]!["gui"]!["pieces"]!.AsObject().Remove("usb");
        Assert.False(Parse(manifest).IsAvailable);
    }

    [Fact]
    public void WrongTestProfileIsNotReplacedWithAssumedGuiProfile()
    {
        var manifest = Manifest();
        manifest["parts"]!["gui"]!["testProfile"] = "cloud";
        Assert.False(Parse(manifest).IsAvailable);
    }

    [Fact]
    public void ControlCharactersInLabelsAreRejected()
    {
        var manifest = Manifest();
        manifest["parts"]!["gui"]!["pieces"]!["home"]!["name"] = "HELIOS\nRun something";
        Assert.False(Parse(manifest).IsAvailable);
    }

    [Fact]
    public void ExcessiveListsAreRejected()
    {
        var manifest = Manifest();
        manifest["parts"]!["gui"]!["workflows"] = new JsonArray(Enumerable.Range(0, 33).Select(i => JsonValue.Create($"workflow-{i}") as JsonNode).ToArray());
        Assert.False(Parse(manifest).IsAvailable);
    }

    [Fact]
    public void MissingFieldOrWrongTypeReturnsUnavailable()
    {
        var manifest = Manifest();
        manifest["parts"]!["gui"]!["pieces"]!["usb"]!["paths"] = false;
        Assert.False(Parse(manifest).IsAvailable);
    }
}
