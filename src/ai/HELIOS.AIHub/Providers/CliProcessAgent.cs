using System.Diagnostics;
using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// The cross-LLM shell primitive: fronts an external agent CLI (claude, codex, copilot,
/// gh, hermes) as a provider. Arguments come from a template with {prompt}/{model}
/// placeholders; the prompt is always passed as a single argv element — never through a
/// shell — so there is no quoting or injection surface.
/// </summary>
public sealed class CliProcessAgent : ProviderAgentBase
{
    private readonly CliAgentOptions _options;
    private readonly bool _commandOnPath;

    public CliProcessAgent(CliAgentOptions options)
        : base(options.Name, $"{options.Name} (CLI)", options.Model)
    {
        _options = options;
        _commandOnPath = IsOnPath(options.Command);
    }

    public override ProviderReadiness Readiness =>
        _commandOnPath ? ProviderReadiness.Ready : ProviderReadiness.Unconfigured;

    public override string? ConfigurationHint =>
        _commandOnPath ? null : $"CLI '{_options.Command}' not found on PATH — install it to enable this agent.";

    protected override async Task<ChatResult> ChatCoreAsync(ChatRequest request, CancellationToken cancellationToken)
    {
        var model = request.Model ?? DefaultModel ?? string.Empty;
        var startInfo = new ProcessStartInfo
        {
            FileName = _options.Command,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (var arg in BuildArguments(request.Prompt, model))
        {
            startInfo.ArgumentList.Add(arg);
        }

        var stopwatch = Stopwatch.StartNew();
        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Failed to start '{_options.Command}'.");

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(_options.TimeoutSeconds));
        try
        {
            await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
                // Process already exited between the timeout and the kill.
            }
            return new ChatResult(false, null, Provider, model, stopwatch.Elapsed,
                Error: $"'{_options.Command}' timed out after {_options.TimeoutSeconds}s.");
        }

        var stdout = await stdoutTask.ConfigureAwait(false);
        var stderr = await stderrTask.ConfigureAwait(false);

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
            return new ChatResult(false, null, Provider, model, stopwatch.Elapsed,
                Error: $"'{_options.Command}' exited {process.ExitCode}: {Tail(detail, 500)}");
        }

        return new ChatResult(true, stdout.Trim(), Provider, model, stopwatch.Elapsed);
    }

    private IEnumerable<string> BuildArguments(string prompt, string model)
    {
        foreach (var token in _options.ArgsTemplate.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            yield return token
                .Replace("{prompt}", prompt, StringComparison.Ordinal)
                .Replace("{model}", model, StringComparison.Ordinal);
        }
    }

    private static bool IsOnPath(string command)
    {
        if (string.IsNullOrWhiteSpace(command))
        {
            return false;
        }

        var paths = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        var extensions = OperatingSystem.IsWindows()
            ? (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT").Split(';')
            : new[] { string.Empty };

        return paths.Any(dir => extensions.Any(ext => File.Exists(Path.Combine(dir, command + ext.ToLowerInvariant()))
                                                      || File.Exists(Path.Combine(dir, command + ext))));
    }

    private static string Tail(string text, int maxLength) =>
        text.Length <= maxLength ? text : text[^maxLength..];
}
