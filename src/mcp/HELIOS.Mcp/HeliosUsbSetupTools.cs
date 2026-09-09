using System.ComponentModel;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using HELIOS.AIHub.Setup;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

[McpServerToolType]
public static class HeliosUsbSetupTools
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 16,
        Converters = { new JsonStringEnumConverter(allowIntegerValues: false) },
    };

    [McpServerTool(Name = "helios_usb_plan_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Plan USB installation media and profile storage requirements from caller-supplied inventory. Same portable planner as the Desktop wizard. No disk discovery, formatting, partitioning, driver install or boot changes; canExecute always false. Unknown safety inputs block a layout proposal.")]
    public static string GetUsbPlan(
        [Description("UsbSetupRequest as camelCase JSON, at most 16 KiB. Enum names are strings. See docs/USB_SETUP.md; omit unknown safety booleans rather than inventing false.")] string requestJson)
    {
        if (requestJson is null || requestJson.Length > 16 * 1024 || Encoding.UTF8.GetByteCount(requestJson) > 16 * 1024)
            throw new McpException("USB plan input must fit 16 KiB.");
        try
        {
            using var parsed = JsonDocument.Parse(requestJson, new JsonDocumentOptions { MaxDepth = 16 });
            if (DuplicateKeys(parsed.RootElement)) throw new JsonException();
            var request = parsed.RootElement.Deserialize<UsbSetupRequest>(Options) ?? throw new JsonException();
            return JsonSerializer.Serialize(new UsbSetupPlanner().CreatePlan(request), Options);
        }
        catch (Exception ex) when (ex is JsonException or ArgumentException)
        {
            throw new McpException("USB plan input is malformed, ambiguous or contains unsupported fields. Read docs/USB_SETUP.md.");
        }
    }

    private static bool DuplicateKeys(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
                if (!names.Add(property.Name) || DuplicateKeys(property.Value)) return true;
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var value in element.EnumerateArray()) if (DuplicateKeys(value)) return true;
        return false;
    }
}
