using System.Globalization;
using System.Text.Json;
using HELIOS.AIHub.Learning;

namespace HELIOS.AIHub.Cli;

/// <summary>Offline JSON report over an explicit local snapshot, before hub initialization.</summary>
public static class ComboAnalysisCommand
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static async Task<int> ExecuteAsync(
        IReadOnlyList<string> positionals, IReadOnlyDictionary<string, string?> options,
        TextWriter output, TextWriter error, CancellationToken cancellationToken = default)
    {
        var allowed = new[] { "config", "outcomes", "task", "language", "limit", "json" };
        var unexpected = options.Keys.FirstOrDefault(k => !allowed.Contains(k, StringComparer.OrdinalIgnoreCase));
        if (positionals.Count != 0 || unexpected is not null)
            return Fail("Usage: helios-ai combo-analyze --outcomes PATH --task TYPE [--language LANG] [--limit N] [--json]", error);
        foreach (var required in new[] { "outcomes", "task" })
            if (!options.TryGetValue(required, out var value) || string.IsNullOrWhiteSpace(value))
                return Fail($"--{required} requires a value.", error);
        if (options.TryGetValue("language", out var language) && string.IsNullOrWhiteSpace(language))
            return Fail("--language requires a value.", error);
        if (options.TryGetValue("limit", out var rawLimit) && string.IsNullOrWhiteSpace(rawLimit))
            return Fail("--limit requires a value.", error);
        if (!int.TryParse(options.GetValueOrDefault("limit") ?? "200", NumberStyles.None,
                CultureInfo.InvariantCulture, out var limit) || limit is < 1 or > ComboAnalysisService.MaxWindow)
            return Fail($"--limit must be between 1 and {ComboAnalysisService.MaxWindow}.", error);
        if (options.TryGetValue("json", out var json) && json is not null
            && !string.Equals(json, "true", StringComparison.OrdinalIgnoreCase))
            return Fail("combo-analyze always emits JSON; --json accepts true or no value.", error);

        try
        {
            // Open read-only and bound both allocation and the actual bytes read: an
            // append while reading must not bypass the initial size check.
            await using var stream = new FileStream(options["outcomes"]!, FileMode.Open,
                FileAccess.Read, FileShare.ReadWrite, 4096, FileOptions.Asynchronous);
            if (stream.Length > ComboAnalysisService.MaxSnapshotBytes)
                return Fail($"Outcome snapshot exceeds {ComboAnalysisService.MaxSnapshotBytes} bytes.", error);
            using var snapshot = new MemoryStream();
            var buffer = new byte[8192];
            int read;
            while ((read = await stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) != 0)
            {
                if (snapshot.Length + read > ComboAnalysisService.MaxSnapshotBytes)
                    return Fail($"Outcome snapshot exceeds {ComboAnalysisService.MaxSnapshotBytes} bytes.", error);
                snapshot.Write(buffer, 0, read);
            }
            var report = ComboAnalysisService.AnalyzeJsonl(snapshot.ToArray(), options["task"]!, language, limit);
            await output.WriteLineAsync(JsonSerializer.Serialize(report, JsonOptions)).ConfigureAwait(false);
            return 0;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            // Do not echo file content or provider payloads into shared CI logs.
            return Fail(ex is ArgumentException ? ex.Message : "Could not read the local outcome snapshot.", error);
        }
    }

    private static int Fail(string message, TextWriter error)
    {
        error.WriteLine(message);
        return 1;
    }
}
