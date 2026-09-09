using System.IO;
using System.Text.Json;

namespace HELIOS.Shell.Services;

/// <summary>Public navigation from the same manifest used by connect.ps1; no credentials.</summary>
public sealed record ControlProjectLinks(Uri? Repository, Uri? Linear, Uri? Slack)
{
    public bool IsAvailable => Repository is not null && Linear is not null && Slack is not null;
    public Uri? Guide => Repository is null ? null : new Uri(Repository.AbsoluteUri.TrimEnd('/') + "/blob/main/docs/CONNECT.md");

    public static ControlProjectLinks Load()
    {
        const int limit = 64 * 1024;
        try
        {
            // Read one bounded buffer from the installed app directory, never the cwd.
            using var stream = File.OpenRead(Path.Combine(AppContext.BaseDirectory, "control-project.json"));
            var bytes = new byte[limit + 1];
            var count = stream.ReadAtLeast(bytes, bytes.Length, throwOnEndOfStream: false);
            if (count > limit) return new(null, null, null);
            using var document = JsonDocument.Parse(bytes.AsMemory(0, count));
            var root = document.RootElement;
            return new(ReadUri(root, "repositoryUrl"),
                ReadUri(root, "integrations", "linear", "projectUrl"),
                ReadUri(root, "integrations", "slack", "canvasUrl"));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return new(null, null, null);
        }
    }

    private static Uri? ReadUri(JsonElement element, params string[] path)
    {
        foreach (var property in path)
        {
            if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(property, out element))
                return null;
        }
        if (element.ValueKind != JsonValueKind.String ||
            !Uri.TryCreate(element.GetString(), UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || string.IsNullOrWhiteSpace(uri.Host) ||
            uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0)
            return null;
        return uri;
    }
}
