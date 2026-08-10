using System.Diagnostics;
using System.Text.Json;

namespace HELIOS.AIHub.Learning;

/// <summary>
/// Boundary to the Python analysis spoke (<c>src/ai/python</c>). Hub-and-spoke rule:
/// only this class talks to the Python side — one JSON request on the subprocess's
/// stdin (<c>python -m helios_agents</c>), one JSON response on its stdout. A missing
/// interpreter or spoke directory degrades to <c>null</c> results, never an exception:
/// unconfigured is a state, and insights are advisory.
/// </summary>
public sealed class PythonInsightsSpoke
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

    private readonly string? _spokeDirectory;
    private readonly string _interpreter;

    public PythonInsightsSpoke(string? spokeDirectory = null)
    {
        _spokeDirectory = spokeDirectory
            ?? Environment.GetEnvironmentVariable("HELIOS_PYTHON_SPOKE")
            ?? FindSpokeDirectory();
        _interpreter = OperatingSystem.IsWindows() ? "python" : "python3";
    }

    public bool IsAvailable => _spokeDirectory is not null;

    /// <summary>Finds src/ai/python walking up from the app base (then current) directory.</summary>
    public static string? FindSpokeDirectory()
    {
        foreach (var start in new[] { AppContext.BaseDirectory, Directory.GetCurrentDirectory() })
        {
            var dir = new DirectoryInfo(start);
            while (dir is not null)
            {
                var candidate = Path.Combine(dir.FullName, "src", "ai", "python");
                if (File.Exists(Path.Combine(candidate, "helios_agents", "__main__.py")))
                {
                    return candidate;
                }
                dir = dir.Parent;
            }
        }
        return null;
    }

    /// <summary>Per-provider stats over chronological (oldest-first) outcomes.</summary>
    public Task<JsonElement?> SummarizeAsync(
        IReadOnlyList<RoutingOutcome> chronologicalOutcomes, CancellationToken cancellationToken = default) =>
        InvokeAsync(new { op = "provider_summary", outcomes = chronologicalOutcomes }, cancellationToken);

    /// <summary>Providers whose recent success rate drifted from their overall rate.</summary>
    public Task<JsonElement?> DetectDriftAsync(
        IReadOnlyList<RoutingOutcome> chronologicalOutcomes, CancellationToken cancellationToken = default) =>
        InvokeAsync(new { op = "detect_drift", outcomes = chronologicalOutcomes }, cancellationToken);

    /// <summary>Groups near-duplicate texts (compare fan-out outputs, agent responses).</summary>
    public Task<JsonElement?> GroupSimilarAsync(
        IReadOnlyList<string> texts, double threshold = 0.6, CancellationToken cancellationToken = default) =>
        InvokeAsync(new { op = "group_similar", texts, threshold }, cancellationToken);

    private async Task<JsonElement?> InvokeAsync(object request, CancellationToken cancellationToken)
    {
        if (_spokeDirectory is null)
        {
            return null;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = _interpreter,
            WorkingDirectory = _spokeDirectory,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        startInfo.ArgumentList.Add("-m");
        startInfo.ArgumentList.Add("helios_agents");

        using var process = new Process { StartInfo = startInfo };
        try
        {
            process.Start();
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            return null; // no interpreter on PATH — the spoke is simply not installed here
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        try
        {
            await JsonSerializer.SerializeAsync(
                process.StandardInput.BaseStream, request, cancellationToken: timeout.Token)
                .ConfigureAwait(false);
            process.StandardInput.Close();

            var stdout = await process.StandardOutput.ReadToEndAsync(timeout.Token).ConfigureAwait(false);
            await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false);

            using var document = JsonDocument.Parse(stdout);
            if (!document.RootElement.TryGetProperty("ok", out var ok) || !ok.GetBoolean())
            {
                return null;
            }
            return document.RootElement.GetProperty("result").Clone();
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return null; // spoke timeout is advisory-data loss, not an orchestration failure
        }
        catch (IOException)
        {
            return null; // broken pipe: the spoke process died before/while reading the request
        }
        catch (JsonException)
        {
            return null;
        }
        finally
        {
            if (!process.HasExited)
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch (InvalidOperationException)
                {
                }
            }
        }
    }
}
