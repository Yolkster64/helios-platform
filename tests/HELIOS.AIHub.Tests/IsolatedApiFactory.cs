using HELIOS.AIHub.Configuration;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace HELIOS.AIHub.Tests;

/// <summary>
/// Boots the API against a private COPY of the shipped <c>config/aihub.json</c> placed
/// under a temp directory. <see cref="AIHubOptions.Load"/> anchors the root-relative
/// <c>learning.localPath</c> to the config root, so the copy's learning store is the
/// empty <c>&lt;temp&gt;/.helios/learning/outcomes.jsonl</c> — never the checkout's own
/// store, which every local <c>helios-ai</c> run appends to and which otherwise made
/// "no outcomes yet" assertions depend on what the developer ran last. Providers stay
/// Unconfigured exactly as with the shipped file: keyless and offline, like CI. The
/// Python spoke is located from the app directory, not the config, so it is unaffected.
/// </summary>
public sealed class IsolatedApiFactory : WebApplicationFactory<Program>
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(), "helios-api-tests-" + Guid.NewGuid().ToString("N"));

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        var shipped = AIHubOptions.FindConfigFile(AppContext.BaseDirectory)
                      ?? throw new InvalidOperationException(
                          "config/aihub.json was not found above the test directory.");
        var configDir = Path.Combine(_root, "config");
        Directory.CreateDirectory(configDir);
        var copy = Path.Combine(configDir, "aihub.json");
        File.Copy(shipped, copy, overwrite: true);

        // Program.cs reads builder.Configuration["aihub-config"] before AIHUB_CONFIG and
        // the directory walk — the same key the CLI's --aihub-config switch sets.
        builder.ConfigureAppConfiguration((_, configuration) =>
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["aihub-config"] = copy,
            }));
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (!disposing)
        {
            return;
        }
        try
        {
            Directory.Delete(_root, recursive: true);
        }
        catch (IOException)
        {
            // Best-effort cleanup of a temp directory; never fail a test run over it.
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
