using System.IO;
using System.Text.Json;

namespace HELIOS.Shell.Services;

public sealed record GuiWorkbenchModule(string Id, string Name, string Purpose,
    IReadOnlyList<string> Paths, IReadOnlyList<string> LinkedParts)
{
    public string SourceDisplay => string.Join("\n", Paths);
    public string DependenciesDisplay => string.Join(" · ", LinkedParts);
    public string OpenLabel => Id is "aihub" or "fabric" ? "Open page with configured runtime"
        : Id == "themes" ? "Preview themes here" : "Open page";
    public string RuntimeNotice => Id is "aihub" or "fabric"
        ? "Opening this page leaves fixtures and checks the configured AIHub runtime."
        : Id == "home" ? "Home contains the project's real external links; opening a link uses your browser."
        : Id == "usb" ? "The USB page uses manually entered inventory and a local planner; it cannot write a disk."
        : "Theme and control previews stay local to this Workbench surface.";
}

/// <summary>One bounded, inert view of the same GUI map used by the component runner.</summary>
public sealed record GuiWorkbenchCatalog(IReadOnlyList<GuiWorkbenchModule> Modules,
    IReadOnlyList<string> Workflows, string ReleaseBoundary, string Status)
{
    public const int MaximumBytes = 64 * 1024;
    private static readonly string[] ModuleOrder = ["home", "aihub", "fabric", "usb", "themes"];
    public bool IsAvailable => Modules.Count != 0;

    public static GuiWorkbenchCatalog Load()
    {
        try
        {
            using var stream = File.OpenRead(Path.Combine(AppContext.BaseDirectory, "components.json"));
            var bytes = new byte[MaximumBytes + 1];
            var count = stream.ReadAtLeast(bytes, bytes.Length, throwOnEndOfStream: false);
            return Parse(bytes.AsMemory(0, count));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Unavailable();
        }
    }

    public static GuiWorkbenchCatalog Parse(ReadOnlyMemory<byte> bytes)
    {
        if (bytes.Length > MaximumBytes) return Unavailable();
        try
        {
            using var document = JsonDocument.Parse(bytes);
            var root = Object(document.RootElement);
            if (!root.TryGetValue("schemaVersion", out var version) || !version.TryGetInt32(out var schema) || schema != 1)
                return Unavailable();
            var parts = Object(root["parts"]);
            var gui = Object(parts["gui"]);
            if (Text(gui["testProfile"]) != "gui") return Unavailable();
            var pieces = Object(gui["pieces"]);
            if (pieces.Count != ModuleOrder.Length) return Unavailable();
            var modules = ModuleOrder.Select(id =>
            {
                var piece = Object(pieces[id]);
                return new GuiWorkbenchModule(id, Text(piece["name"]), Text(piece["purpose"]),
                    TextArray(piece["paths"]), TextArray(piece["linkedParts"]));
            }).ToArray();
            return new(modules, TextArray(gui["workflows"]), Text(gui["releaseBoundary"]),
                "GUI map loaded from the installed components.json. Test and deployment results have not been queried.");
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return Unavailable();
        }
    }

    private static Dictionary<string, JsonElement> Object(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new JsonException("Expected object.");
        var properties = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var property in value.EnumerateObject())
            if (!properties.TryAdd(property.Name, property.Value)) throw new JsonException("Duplicate property.");
        return properties;
    }

    private static string Text(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.String) throw new JsonException("Expected text.");
        var text = value.GetString() ?? "";
        if (text.Length is 0 or > 2048 || text.Any(char.IsControl)) throw new JsonException("Invalid text.");
        return text;
    }

    private static IReadOnlyList<string> TextArray(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > 32) throw new JsonException("Invalid list.");
        return value.EnumerateArray().Select(Text).ToArray();
    }

    private static GuiWorkbenchCatalog Unavailable() => new([], [], "Unavailable",
        "GUI map unavailable. Restore config/components.json with its gui pieces and rebuild. Local control previews still work.");
}
