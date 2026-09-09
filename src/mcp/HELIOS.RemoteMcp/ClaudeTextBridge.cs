using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.RemoteMcp;

public sealed record ClaudeTextResult(bool Success, string State, string? Text = null)
{
    public string Provider => "claude-code";
    public bool ExistingWebSessionAttached => false;
}

/// <summary>A fresh text-only Claude invocation, not a command runner or session proxy.</summary>
public sealed class ClaudeTextBridge(RemoteMcpOptions options)
{
    internal const int MaxPromptBytes = 16 * 1024;
    internal const int MaxOutputChars = 128 * 1024;
    private readonly SemaphoreSlim _singleRequest = new(1, 1);

    public async Task<ClaudeTextResult> AskAsync(string prompt, CancellationToken cancellationToken)
    {
        if (!options.ClaudeEnabled) return new(false, "disabled");
        if (string.IsNullOrWhiteSpace(prompt) || Encoding.UTF8.GetByteCount(prompt) > MaxPromptBytes)
            throw new McpException("prompt must contain 1 to 16384 UTF-8 bytes.");
        if (!await _singleRequest.WaitAsync(0, cancellationToken)) return new(false, "busy");
        string? workDirectory = null;
        try
        {
            // Keep user/project instructions and checkout contents out of this one-turn lane.
            workDirectory = Directory.CreateTempSubdirectory("helios-claude-text-").FullName;
            return await RunAsync(BuildStartInfo(options.ClaudeExecutable!, workDirectory), prompt,
                TimeSpan.FromSeconds(90), cancellationToken);
        }
        finally
        {
            if (workDirectory is not null)
            {
                try { Directory.Delete(workDirectory, recursive: true); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            _singleRequest.Release();
        }
    }

    internal static ProcessStartInfo BuildStartInfo(string executable, string workingDirectory)
    {
        var start = new ProcessStartInfo
        {
            FileName = executable, WorkingDirectory = workingDirectory,
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
        };
        // A fixed argv is the whole execution contract. No caller-supplied model, path,
        // settings, resume ID, command, plugin, tool, or extra argument is accepted.
        foreach (var arg in new[]
        {
            "--print", "--output-format", "json", "--input-format", "text",
            "--restricted", "--safe-mode", "--tools", "", "--disallowedTools", "mcp__*",
            "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
            "--setting-sources", "", "--settings", "{\"disableAllHooks\":true,\"autoMemoryEnabled\":false}",
            "--disable-slash-commands", "--no-chrome", "--no-session-persistence",
            "--max-turns", "1", "--permission-mode", "dontAsk",
        }) start.ArgumentList.Add(arg);

        FilterEnvironment(start);
        return start;
    }

    internal static void FilterEnvironment(ProcessStartInfo start)
    {
        // The parent may hold Slack, GitHub, Azure, OpenAI or database credentials.
        // The Claude process receives only OS essentials and explicit Claude login inputs.
        var allowed = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "SYSTEMROOT", "WINDIR",
            "TMP", "TEMP", "TMPDIR", "LANG", "LC_ALL", "PATH",
            "CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN",
        };
        foreach (var name in start.Environment.Keys.ToArray())
            if (!allowed.Contains(name)) start.Environment.Remove(name);
        start.Environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1";
        start.Environment["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1";
        start.Environment["DISABLE_AUTOUPDATER"] = "1";
    }

    // Internal seam accepts an inert test process; HTTP callers never receive it.
    internal static async Task<ClaudeTextResult> RunAsync(ProcessStartInfo start, string prompt,
        TimeSpan timeout, CancellationToken cancellationToken)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(timeout);
        Process? process = null;
        try
        {
            process = Process.Start(start);
            if (process is null) return new(false, "unavailable");
            var stdout = ReadBoundedAsync(process.StandardOutput, deadline);
            var stderr = ReadBoundedAsync(process.StandardError, deadline);
            var io = WriteAndWaitAsync(process, prompt, deadline.Token);
            await Task.WhenAll(stdout, stderr, io);
            if (process.ExitCode != 0) return new(false, "claude_failed_check_local_sign_in_and_supported_version");
            using var doc = JsonDocument.Parse(stdout.Result);
            if (doc.RootElement.ValueKind != JsonValueKind.Object ||
                (doc.RootElement.TryGetProperty("is_error", out var error) && error.ValueKind == JsonValueKind.True) ||
                !doc.RootElement.TryGetProperty("result", out var result) || result.ValueKind != JsonValueKind.String)
                return new(false, "invalid_claude_result");
            return new(true, "completed", result.GetString());
        }
        catch (OutputLimitException) { return new(false, "output_limit"); }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new(false, "timeout_or_output_limit");
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException or InvalidOperationException or JsonException)
        {
            return new(false, "unavailable_or_invalid_result");
        }
        finally
        {
            if (process is not null)
            {
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception) { }
                process.Dispose();
            }
        }
    }

    private static async Task WriteAndWaitAsync(Process process, string prompt, CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteAsync(prompt.AsMemory(), cancellationToken);
        await process.StandardInput.FlushAsync(cancellationToken);
        process.StandardInput.Close();
        await process.WaitForExitAsync(cancellationToken);
    }

    private static async Task<string> ReadBoundedAsync(StreamReader reader, CancellationTokenSource deadline)
    {
        var output = new StringBuilder();
        var buffer = new char[4096];
        while (true)
        {
            var read = await reader.ReadAsync(buffer.AsMemory(), deadline.Token);
            if (read == 0) return output.ToString();
            if (output.Length + read > MaxOutputChars)
            {
                deadline.Cancel();
                throw new OutputLimitException();
            }
            output.Append(buffer, 0, read);
        }
    }

    private sealed class OutputLimitException : Exception { }
}

[McpServerToolType]
public sealed class RemoteClaudeTools(ClaudeTextBridge bridge, RemoteMcpOptions options, IHttpContextAccessor http)
{
    [McpServerTool(Name = "helios_claude_ask", ReadOnly = false, Idempotent = false, OpenWorld = true)]
    [Description("Send a text prompt to a fresh local Claude Code invocation using the host's existing Claude login. Consumes that account's usage. Model tools, MCP and session persistence are disabled, customizations use safe mode, and managed host policy still applies. Cannot attach a claude.ai session. Requires operator opt-in and claude.invoke scope in Entra mode.")]
    public async Task<string> Ask([Description("Text to send to Claude, at most 16384 UTF-8 bytes. Include any source text you want reviewed explicitly.")] string prompt,
        CancellationToken cancellationToken = default)
    {
        if (options.UsesEntra && (http.HttpContext is not { } context || !options.HasScope(context.User, options.ClaudeScope)))
            throw new McpException("The claude.invoke delegated scope is required.");
        return JsonSerializer.Serialize(await bridge.AskAsync(prompt, cancellationToken));
    }
}
