using Xunit;
// The API host declares a global-namespace Program (for WebApplicationFactory) that
// shadows the CLI's under a plain using directive, so the CLI entry point is aliased.
using CliProgram = HELIOS.AIHub.Cli.Program;

namespace HELIOS.AIHub.Tests.Cli;

/// <summary>
/// The route command's option validation through the real entry point
/// (<see cref="HELIOS.AIHub.Cli.Program.Main"/>) against a minimal config. A misspelled option
/// (--langauge) used to be parsed, stored and never read, so the request silently
/// routed without its language; it is a usage error now, and --provider — an ask
/// option — gets the pointer at ask. Nothing here routes: both commands fail on their
/// arguments before a provider or the learning store is touched.
/// </summary>
public sealed class RouteCommandTests : IDisposable
{
    private readonly string _configDir = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
    private readonly string _configPath;

    public RouteCommandTests()
    {
        Directory.CreateDirectory(_configDir);
        _configPath = Path.Combine(_configDir, "aihub.json");
        // No provider and no learning: the hub builds without touching the network or
        // the filesystem beside the config.
        File.WriteAllText(_configPath, """{ "providers": {}, "learning": { "enabled": false } }""");
    }

    public void Dispose() => Directory.Delete(_configDir, recursive: true);

    [Fact]
    public async Task Route_MisspelledLanguageOption_IsAUsageError_NamingTheOption()
    {
        var (exitCode, stderr) = await RunAsync("route", "general_query", "x", "--langauge", "fsharp");

        Assert.Equal(1, exitCode);
        Assert.Contains("Unknown option '--langauge' for route.", stderr);
        Assert.Contains("Usage: helios-ai route <task-type>", stderr);
        Assert.DoesNotContain("helios-ai ask", stderr); // the ask pointer is for --provider only
    }

    [Fact]
    public async Task Route_ProviderOption_IsAUsageError_PointingAtAsk()
    {
        var (exitCode, stderr) = await RunAsync("route", "general_query", "x", "--provider", "openai");

        Assert.Equal(1, exitCode);
        Assert.Contains("Unknown option '--provider' for route.", stderr);
        Assert.Contains("helios-ai ask \"<prompt>\" --provider P", stderr);
    }

    /// <summary>
    /// Runs the entry point with the temp config appended, capturing stderr. Console
    /// redirection is process-wide, so the capture is restored in a finally and the
    /// assertions are substring checks that another test's stray output cannot break.
    /// </summary>
    private async Task<(int ExitCode, string Stderr)> RunAsync(params string[] args)
    {
        var original = Console.Error;
        var captured = new StringWriter();
        Console.SetError(captured);
        try
        {
            var exitCode = await CliProgram.Main(args.Concat(new[] { "--config", _configPath }).ToArray());
            return (exitCode, captured.ToString());
        }
        finally
        {
            Console.SetError(original);
        }
    }
}
