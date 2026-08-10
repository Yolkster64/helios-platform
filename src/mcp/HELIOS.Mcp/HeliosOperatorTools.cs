using System.ComponentModel;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using HELIOS.AIHub.Configuration;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>
/// Durable, user-controlled operating context shared by Claude Code, Codex, Copilot,
/// ChatGPT, and Hermes/XCore. State is kept under the gitignored .helios/operator folder;
/// no model-specific hidden memory or credential value is written.
/// </summary>
[McpServerToolType]
public static class HeliosOperatorTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    [McpServerTool(Name = "helios_operator_profile_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Read the inspectable HELIOS operator profile (preferred Azure location, naming prefix, default tags, and assistant surfaces). Returns defaults when no profile has been saved. Never reads secrets.")]
    public static string GetProfile()
    {
        try
        {
            return JsonSerializer.Serialize(OperatorContextStore.CreateDefault().GetProfile(), JsonOptions);
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or JsonException or InvalidDataException or UnauthorizedAccessException)
        {
            throw new McpException($"Unable to read the HELIOS operator profile: {exception.Message}");
        }
    }

    [McpServerTool(Name = "helios_operator_profile_save", ReadOnly = false, Idempotent = true, OpenWorld = false)]
    [Description("Create or update the inspectable HELIOS operator profile under .helios/operator/profile.json. Omitted fields keep their current value; an empty string clears that field. Tags and assistant surfaces are validated, and secret-looking names or values are rejected.")]
    public static async Task<string> SaveProfile(
        [Description("Optional display name to remember for generated labels and receipts; omit to keep it.")] string? displayName = null,
        [Description("Preferred Azure location such as southcentralus; omit to keep it.")] string? preferredAzureLocation = null,
        [Description("Lowercase Azure-safe naming prefix such as helios-jp; omit to keep it.")] string? namingPrefix = null,
        [Description("JSON object of default Azure tags, for example {\"project\":\"helios\",\"owner\":\"jp\"}; omit to keep it.")] string? defaultTagsJson = null,
        [Description("Comma-separated assistant surfaces such as chatgpt,codex,claude-code,copilot,hermes,xcore; omit to keep them.")] string? assistantSurfaces = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var profile = await OperatorContextStore.CreateDefault().SaveProfileAsync(
                displayName,
                preferredAzureLocation,
                namingPrefix,
                defaultTagsJson,
                assistantSurfaces,
                cancellationToken);
            return JsonSerializer.Serialize(profile, JsonOptions);
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or JsonException or InvalidDataException or UnauthorizedAccessException)
        {
            throw new McpException($"Unable to save the HELIOS operator profile: {exception.Message}");
        }
    }

    [McpServerTool(Name = "helios_operator_context_sync", ReadOnly = false, Idempotent = false, OpenWorld = true)]
    [Description("Capture the shared HELIOS repo/CLI context and append a sanitized journal receipt. Optionally reads the authenticated Azure CLI subscription, resource groups, resources, locations, and tags, then records a delta from the prior snapshot. It never applies, deletes, or changes Azure resources and never stores tokens or raw CLI output.")]
    public static async Task<string> SyncContext(
        [Description("Calling surface label: claude-code, codex, chatgpt, copilot, github-cli, azure-cli, hermes, xcore, or manual.")] string surface = "manual",
        [Description("Read the current Azure CLI account and resource groups. Requires an existing az login or Cloud Shell session.")] bool includeAzure = false,
        [Description("Also inventory up to 500 Azure resources for change detection. Requires includeAzure=true.")] bool includeResources = false,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var snapshot = await OperatorContextStore.CreateDefault().SyncAsync(
                surface,
                includeAzure,
                includeResources,
                cancellationToken);
            return JsonSerializer.Serialize(snapshot, JsonOptions);
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or JsonException or InvalidDataException or UnauthorizedAccessException)
        {
            throw new McpException($"Unable to synchronize HELIOS operator context: {exception.Message}");
        }
    }

    [McpServerTool(Name = "helios_operator_next_steps_get", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Return deterministic next-step proposals from the last saved HELIOS operator context. Suggestions share the same repository/Azure evidence across assistants; this tool performs no model call or cloud mutation.")]
    public static string GetNextSteps()
    {
        try
        {
            var store = OperatorContextStore.CreateDefault();
            var snapshot = store.GetLatestContext();
            return JsonSerializer.Serialize(
                new
                {
                    snapshotAvailable = snapshot is not null,
                    contextPath = ".helios/operator/context.json",
                    nextSteps = snapshot?.NextSteps ?? store.BuildNextSteps(
                        store.GetProfile(),
                        RepositorySnapshot.Empty,
                        AzureSnapshot.NotRequested,
                        OperatorContextStore.DetectCliAvailability()),
                },
                JsonOptions);
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or JsonException or InvalidDataException or UnauthorizedAccessException)
        {
            throw new McpException($"Unable to read HELIOS next steps: {exception.Message}");
        }
    }
}

internal sealed class OperatorContextStore
{
    private const int MaxResourceGroups = 200;
    private const int MaxResources = 500;
    private const int MaxTags = 32;
    private static readonly Regex SafeSurface = new("^[a-z0-9][a-z0-9-]{0,47}$", RegexOptions.CultureInvariant);
    private static readonly Regex SafeLocation = new("^[a-z0-9][a-z0-9-]{1,49}$", RegexOptions.CultureInvariant);
    private static readonly Regex SafePrefix = new("^[a-z0-9](?:[a-z0-9-]{0,22}[a-z0-9])?$", RegexOptions.CultureInvariant);
    private static readonly Regex SensitiveName = new(
        "(^|[-_.])(secret|password|passwd|token|credential|api[-_]?key|private[-_]?key)($|[-_.])",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex SensitiveValue = new(
        "(^|[^a-z0-9])(sk-[a-z0-9_-]{12,}|gh[pousr]_[a-z0-9]{12,}|accountkey=|sharedaccesssignature=|eyj[a-z0-9_-]+\\.eyj[a-z0-9_-]+\\.)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };
    private static readonly JsonSerializerOptions JsonLineOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private readonly ICommandRunner _runner;
    private readonly Func<DateTimeOffset> _clock;
    private readonly Func<IReadOnlyDictionary<string, bool>> _cliDetector;

    internal OperatorContextStore(
        string repoRoot,
        ICommandRunner? runner = null,
        Func<DateTimeOffset>? clock = null,
        Func<IReadOnlyDictionary<string, bool>>? cliDetector = null)
    {
        RepoRoot = Path.GetFullPath(repoRoot);
        if (!File.Exists(Path.Combine(RepoRoot, "config", "aihub.json")))
        {
            throw new InvalidDataException($"'{RepoRoot}' is not a HELIOS checkout (config/aihub.json is missing).");
        }

        OperatorDirectory = Path.Combine(RepoRoot, ".helios", "operator");
        _runner = runner ?? new SystemCommandRunner();
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
        _cliDetector = cliDetector ?? DetectCliAvailability;
    }

    internal string RepoRoot { get; }
    internal string OperatorDirectory { get; }
    internal string ProfilePath => Path.Combine(OperatorDirectory, "profile.json");
    internal string ContextPath => Path.Combine(OperatorDirectory, "context.json");
    internal string JournalPath => Path.Combine(OperatorDirectory, "journal.jsonl");

    internal static OperatorContextStore CreateDefault() => new(ResolveRepoRoot());

    internal static string ResolveRepoRoot()
    {
        foreach (var variable in new[] { "HELIOS_REPO_ROOT", "CLAUDE_PROJECT_DIR" })
        {
            var candidate = Environment.GetEnvironmentVariable(variable);
            if (!string.IsNullOrWhiteSpace(candidate))
            {
                var fullPath = Path.GetFullPath(candidate);
                if (File.Exists(Path.Combine(fullPath, "config", "aihub.json")))
                {
                    return fullPath;
                }
            }
        }

        var configPath = AIHubOptions.FindConfigFile()
            ?? throw new InvalidDataException(
                "HELIOS repo root not found. Start the client in the helios-platform checkout or set HELIOS_REPO_ROOT.");
        return Directory.GetParent(Path.GetDirectoryName(configPath)!)!.FullName;
    }

    internal OperatorProfile GetProfile()
    {
        if (!File.Exists(ProfilePath))
        {
            return OperatorProfile.Default;
        }

        var profile = JsonSerializer.Deserialize<OperatorProfile>(File.ReadAllText(ProfilePath), JsonOptions)
            ?? throw new InvalidDataException("The HELIOS operator profile deserialized to null.");
        return NormalizeLoadedProfile(profile);
    }

    internal async Task<OperatorProfile> SaveProfileAsync(
        string? displayName,
        string? preferredAzureLocation,
        string? namingPrefix,
        string? defaultTagsJson,
        string? assistantSurfaces,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(OperatorDirectory);
        await using var fileLock = await AcquireLockAsync(cancellationToken);
        var current = GetProfile();
        var next = new OperatorProfile(
            SchemaVersion: 1,
            DisplayName: UpdateOptional(current.DisplayName, displayName, "displayName", 100),
            PreferredAzureLocation: UpdateLocation(current.PreferredAzureLocation, preferredAzureLocation),
            NamingPrefix: UpdatePrefix(current.NamingPrefix, namingPrefix),
            DefaultTags: defaultTagsJson is null ? current.DefaultTags : ParseProfileTags(defaultTagsJson),
            AssistantSurfaces: assistantSurfaces is null
                ? current.AssistantSurfaces
                : ParseAssistantSurfaces(assistantSurfaces),
            UpdatedAtUtc: _clock());

        await WriteJsonAtomicallyAsync(ProfilePath, next, cancellationToken);
        await AppendJournalLineAsync(
            new OperatorJournalEntry(
                SchemaVersion: 1,
                CapturedAtUtc: _clock(),
                Event: "profile-saved",
                Surface: "operator-profile",
                ContextSha256: null,
                RepositoryHead: null,
                AzureSubscriptionId: null,
                ResourceGroupCount: null,
                ResourceCount: null,
                ChangeSummary: null),
            cancellationToken);
        return next;
    }

    internal OperatorContextSnapshot? GetLatestContext()
    {
        if (!File.Exists(ContextPath))
        {
            return null;
        }

        return JsonSerializer.Deserialize<OperatorContextSnapshot>(File.ReadAllText(ContextPath), JsonOptions)
            ?? throw new InvalidDataException("The HELIOS operator context deserialized to null.");
    }

    internal async Task<OperatorContextSnapshot> SyncAsync(
        string surface,
        bool includeAzure,
        bool includeResources,
        CancellationToken cancellationToken)
    {
        surface = NormalizeSurface(surface);
        if (includeResources && !includeAzure)
        {
            throw new ArgumentException("includeResources requires includeAzure=true.");
        }

        var cli = _cliDetector();
        var repository = await CaptureRepositoryAsync(cancellationToken);
        var azure = includeAzure
            ? await CaptureAzureAsync(includeResources, cli, cancellationToken)
            : AzureSnapshot.NotRequested;

        Directory.CreateDirectory(OperatorDirectory);
        await using var fileLock = await AcquireLockAsync(cancellationToken);
        var prior = GetLatestContext();
        var profile = GetProfile();
        var changes = BuildChanges(prior?.Azure, azure);
        var nextSteps = BuildNextSteps(profile, repository, azure, cli);

        var snapshot = new OperatorContextSnapshot(
            SchemaVersion: 1,
            CapturedAtUtc: _clock(),
            Surface: surface,
            Repository: repository,
            Profile: profile,
            CliAvailability: cli,
            Azure: azure,
            Changes: changes,
            NextSteps: nextSteps);

        await WriteJsonAtomicallyAsync(ContextPath, snapshot, cancellationToken);
        var contextJson = JsonSerializer.Serialize(snapshot, JsonOptions);
        var digest = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(contextJson))).ToLowerInvariant();
        await AppendJournalLineAsync(
            new OperatorJournalEntry(
                SchemaVersion: 1,
                CapturedAtUtc: snapshot.CapturedAtUtc,
                Event: "context-synced",
                Surface: surface,
                ContextSha256: digest,
                RepositoryHead: repository.HeadSha,
                AzureSubscriptionId: azure.SubscriptionId,
                ResourceGroupCount: azure.ResourceGroups.Count,
                ResourceCount: azure.Resources.Count,
                ChangeSummary: changes.Summary),
            cancellationToken);
        return snapshot;
    }

    internal IReadOnlyList<OperatorNextStep> BuildNextSteps(
        OperatorProfile profile,
        RepositorySnapshot repository,
        AzureSnapshot azure,
        IReadOnlyDictionary<string, bool> cli)
    {
        var steps = new List<OperatorNextStep>();

        if (string.IsNullOrWhiteSpace(profile.PreferredAzureLocation) || string.IsNullOrWhiteSpace(profile.NamingPrefix))
        {
            steps.Add(new OperatorNextStep(
                "complete-profile",
                "Save naming and location defaults",
                "HELIOS can generate consistent resource groups, tags, and variables after the preferred Azure location and naming prefix are explicit.",
                "Call helios_operator_profile_save.",
                "none"));
        }

        if (!IsCliAvailable(cli, "dotnet"))
        {
            steps.Add(new OperatorNextStep(
                "install-dotnet",
                "Install the .NET 8 SDK",
                "The shared HELIOS MCP/CLI surface runs on .NET 8.",
                "Install .NET 8, then run dotnet build HELIOS.sln -c Release.",
                "none"));
        }

        if (repository.IsMainBranch)
        {
            steps.Add(new OperatorNextStep(
                "create-task-branch",
                "Create a task branch",
                "Keep Claude, Codex, Copilot, and Hermes changes reviewable through one PR instead of writing directly to main.",
                "git switch -c <task-branch>",
                "none"));
        }
        else if (repository.IsDirty)
        {
            steps.Add(new OperatorNextStep(
                "review-local-diff",
                "Review the current local diff",
                "The saved repository context contains uncommitted work; preserve unrelated changes before another agent continues.",
                "git status --short && git diff --check",
                "review"));
        }

        if (azure.Status == "cli-unavailable")
        {
            steps.Add(new OperatorNextStep(
                "open-cloud-shell",
                "Open Azure Cloud Shell",
                "Cloud Shell already has Azure CLI and durable storage, so it is the shortest path to an authenticated inventory.",
                "Open https://shell.azure.com and run the HELIOS context sync again.",
                "none"));
        }
        else if (azure.Status == "not-authenticated")
        {
            steps.Add(new OperatorNextStep(
                "azure-sign-in",
                "Sign in to Azure",
                "The Azure CLI exists but has no active account; HELIOS cannot truthfully choose a subscription or inventory resource groups yet.",
                "az login",
                "none"));
        }
        else if (azure.Status == "ready")
        {
            steps.Add(new OperatorNextStep(
                "review-azure-plan",
                "Generate the next Azure what-if",
                $"The saved inventory covers {azure.ResourceGroups.Count} resource group(s) and {azure.Resources.Count} resource(s); use that evidence to produce the smallest Bicep plan.",
                "Follow infra/README.md and save the what-if output before apply.",
                "review"));
        }

        if (!IsCliAvailable(cli, "claude") && !IsCliAvailable(cli, "codex") && !IsCliAvailable(cli, "copilot"))
        {
            steps.Add(new OperatorNextStep(
                "connect-agent-cli",
                "Connect one coding-agent CLI",
                "The API hub is available, but no local Claude Code, Codex, or Copilot CLI was detected for repository work.",
                "Install and authenticate the CLI you prefer; config/aihub.json already contains the adapters.",
                "none"));
        }

        return steps;
    }

    internal static IReadOnlyDictionary<string, bool> DetectCliAvailability()
    {
        var result = new SortedDictionary<string, bool>(StringComparer.Ordinal)
        {
            ["az"] = CommandExists("az"),
            ["claude"] = CommandExists("claude"),
            ["codex"] = CommandExists("codex"),
            ["copilot"] = CommandExists("copilot"),
            ["dotnet"] = CommandExists("dotnet"),
            ["gh"] = CommandExists("gh"),
            ["hermes"] = CommandExists("hermes"),
        };
        return result;
    }

    private async Task<RepositorySnapshot> CaptureRepositoryAsync(CancellationToken cancellationToken)
    {
        if (!CommandExists("git"))
        {
            return RepositorySnapshot.Empty with { Status = "git-unavailable" };
        }

        var branch = await RunGitValueAsync(new[] { "branch", "--show-current" }, cancellationToken);
        var head = await RunGitValueAsync(new[] { "rev-parse", "HEAD" }, cancellationToken);
        var remote = await RunGitValueAsync(new[] { "remote", "get-url", "origin" }, cancellationToken);
        var status = await _runner.RunAsync(
            "git",
            new[] { "-C", RepoRoot, "status", "--porcelain=v1" },
            TimeSpan.FromSeconds(10),
            cancellationToken);

        return new RepositorySnapshot(
            Status: head is null ? "not-a-git-checkout" : "ready",
            Repository: NormalizeRepositoryName(remote),
            Branch: branch,
            HeadSha: head,
            IsDirty: status.Started && status.ExitCode == 0 && !string.IsNullOrWhiteSpace(status.StandardOutput),
            IsMainBranch: string.Equals(branch, "main", StringComparison.OrdinalIgnoreCase));
    }

    private async Task<string?> RunGitValueAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var allArgs = new List<string> { "-C", RepoRoot };
        allArgs.AddRange(args);
        var result = await _runner.RunAsync("git", allArgs, TimeSpan.FromSeconds(10), cancellationToken);
        return result.Started && result.ExitCode == 0
            ? NullIfEmpty(result.StandardOutput.Trim())
            : null;
    }

    private async Task<AzureSnapshot> CaptureAzureAsync(
        bool includeResources,
        IReadOnlyDictionary<string, bool> cli,
        CancellationToken cancellationToken)
    {
        if (!IsCliAvailable(cli, "az"))
        {
            return AzureSnapshot.CliUnavailable;
        }

        var accountResult = await _runner.RunAsync(
            "az",
            new[]
            {
                "account", "show", "--only-show-errors", "--output", "json",
                "--query", "{id:id,name:name,tenantId:tenantId,state:state}",
            },
            TimeSpan.FromSeconds(20),
            cancellationToken);
        if (!accountResult.Started || accountResult.ExitCode != 0)
        {
            var error = SanitizeError(accountResult.StandardError);
            var status = error.Contains("login", StringComparison.OrdinalIgnoreCase)
                || error.Contains("subscription", StringComparison.OrdinalIgnoreCase)
                ? "not-authenticated"
                : "error";
            return AzureSnapshot.Failed(status, error);
        }

        using var accountDocument = JsonDocument.Parse(accountResult.StandardOutput);
        var account = accountDocument.RootElement;
        var subscriptionId = GetString(account, "id");
        var subscriptionName = GetString(account, "name");
        var tenantId = GetString(account, "tenantId");

        var groupsResult = await _runner.RunAsync(
            "az",
            new[]
            {
                "group", "list", "--only-show-errors", "--output", "json",
                "--query", $"[0:{MaxResourceGroups + 1}].{{name:name,location:location,provisioningState:properties.provisioningState,tags:tags}}",
            },
            TimeSpan.FromSeconds(30),
            cancellationToken);
        if (!groupsResult.Started || groupsResult.ExitCode != 0)
        {
            return AzureSnapshot.Failed("error", SanitizeError(groupsResult.StandardError)) with
            {
                SubscriptionId = subscriptionId,
                SubscriptionName = subscriptionName,
                TenantId = tenantId,
            };
        }

        var groups = ParseResourceGroups(groupsResult.StandardOutput, out var groupsTruncated);
        IReadOnlyList<AzureResourceSnapshot> resources = Array.Empty<AzureResourceSnapshot>();
        var resourcesTruncated = false;
        if (includeResources)
        {
            var resourcesResult = await _runner.RunAsync(
                "az",
                new[]
                {
                    "resource", "list", "--only-show-errors", "--output", "json",
                    "--query", $"[0:{MaxResources + 1}].{{id:id,name:name,type:type,location:location,resourceGroup:resourceGroup,tags:tags}}",
                },
                TimeSpan.FromSeconds(45),
                cancellationToken);
            if (!resourcesResult.Started || resourcesResult.ExitCode != 0)
            {
                return new AzureSnapshot(
                    Status: "partial",
                    SubscriptionId: subscriptionId,
                    SubscriptionName: subscriptionName,
                    TenantId: tenantId,
                    ResourceGroups: groups,
                    ResourceGroupsTruncated: groupsTruncated,
                    Resources: Array.Empty<AzureResourceSnapshot>(),
                    ResourcesIncluded: true,
                    ResourcesTruncated: false,
                    ErrorHint: $"Resource groups were saved, but resource inventory failed: {SanitizeError(resourcesResult.StandardError)}");
            }

            resources = ParseResources(resourcesResult.StandardOutput, out resourcesTruncated);
        }

        return new AzureSnapshot(
            Status: "ready",
            SubscriptionId: subscriptionId,
            SubscriptionName: subscriptionName,
            TenantId: tenantId,
            ResourceGroups: groups,
            ResourceGroupsTruncated: groupsTruncated,
            Resources: resources,
            ResourcesIncluded: includeResources,
            ResourcesTruncated: resourcesTruncated,
            ErrorHint: null);
    }

    private static IReadOnlyList<AzureResourceGroupSnapshot> ParseResourceGroups(string json, out bool truncated)
    {
        using var document = JsonDocument.Parse(json);
        var items = document.RootElement.EnumerateArray().ToArray();
        truncated = items.Length > MaxResourceGroups;
        return items.Take(MaxResourceGroups)
            .Select(item => new AzureResourceGroupSnapshot(
                Name: GetString(item, "name") ?? "unknown",
                Location: GetString(item, "location"),
                ProvisioningState: GetString(item, "provisioningState"),
                Tags: ParseAzureTags(item)))
            .OrderBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static IReadOnlyList<AzureResourceSnapshot> ParseResources(string json, out bool truncated)
    {
        using var document = JsonDocument.Parse(json);
        var items = document.RootElement.EnumerateArray().ToArray();
        truncated = items.Length > MaxResources;
        return items.Take(MaxResources)
            .Select(item => new AzureResourceSnapshot(
                Id: GetString(item, "id"),
                Name: GetString(item, "name") ?? "unknown",
                Type: GetString(item, "type") ?? "unknown",
                Location: GetString(item, "location"),
                ResourceGroup: GetString(item, "resourceGroup"),
                Tags: ParseAzureTags(item)))
            .OrderBy(item => item.ResourceGroup, StringComparer.OrdinalIgnoreCase)
            .ThenBy(item => item.Type, StringComparer.OrdinalIgnoreCase)
            .ThenBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static SortedDictionary<string, string> ParseAzureTags(JsonElement item)
    {
        var tags = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!item.TryGetProperty("tags", out var tagElement) || tagElement.ValueKind != JsonValueKind.Object)
        {
            return tags;
        }

        foreach (var property in tagElement.EnumerateObject().Take(MaxTags))
        {
            var value = property.Value.ValueKind == JsonValueKind.String
                ? property.Value.GetString() ?? string.Empty
                : property.Value.ToString();
            tags[Truncate(property.Name, 128)] = SensitiveName.IsMatch(property.Name) || SensitiveValue.IsMatch(value)
                ? "<redacted>"
                : Truncate(value, 256);
        }
        return tags;
    }

    private static OperatorChangeSet BuildChanges(AzureSnapshot? prior, AzureSnapshot current)
    {
        if (prior is null || prior.Status != "ready" || current.Status != "ready"
            || prior.ResourceGroupsTruncated || current.ResourceGroupsTruncated)
        {
            return OperatorChangeSet.NotComparable;
        }

        var priorGroups = prior.ResourceGroups.ToDictionary(group => group.Name, StringComparer.OrdinalIgnoreCase);
        var currentGroups = current.ResourceGroups.ToDictionary(group => group.Name, StringComparer.OrdinalIgnoreCase);
        var groupsAdded = currentGroups.Keys.Except(priorGroups.Keys, StringComparer.OrdinalIgnoreCase).Order().ToArray();
        var groupsRemoved = priorGroups.Keys.Except(currentGroups.Keys, StringComparer.OrdinalIgnoreCase).Order().ToArray();
        var groupsChanged = currentGroups.Keys.Intersect(priorGroups.Keys, StringComparer.OrdinalIgnoreCase)
            .Where(key => !ResourceGroupEquals(currentGroups[key], priorGroups[key]))
            .Order()
            .ToArray();

        var resourcesComparable = !prior.ResourcesTruncated && !current.ResourcesTruncated
            && prior.ResourcesIncluded && current.ResourcesIncluded;
        var resourcesAdded = Array.Empty<string>();
        var resourcesRemoved = Array.Empty<string>();
        var resourcesChanged = Array.Empty<string>();
        if (resourcesComparable)
        {
            var oldResources = prior.Resources.ToDictionary(ResourceKey, StringComparer.OrdinalIgnoreCase);
            var newResources = current.Resources.ToDictionary(ResourceKey, StringComparer.OrdinalIgnoreCase);
            resourcesAdded = newResources.Keys.Except(oldResources.Keys, StringComparer.OrdinalIgnoreCase).Order().ToArray();
            resourcesRemoved = oldResources.Keys.Except(newResources.Keys, StringComparer.OrdinalIgnoreCase).Order().ToArray();
            resourcesChanged = newResources.Keys.Intersect(oldResources.Keys, StringComparer.OrdinalIgnoreCase)
                .Where(key => !ResourceEquals(newResources[key], oldResources[key]))
                .Order()
                .ToArray();
        }

        var summary = $"resourceGroups +{groupsAdded.Length}/-{groupsRemoved.Length}/~{groupsChanged.Length}; "
            + (resourcesComparable
                ? $"resources +{resourcesAdded.Length}/-{resourcesRemoved.Length}/~{resourcesChanged.Length}"
                : "resources not compared");
        return new OperatorChangeSet(
            Comparable: true,
            ResourceGroupsAdded: groupsAdded,
            ResourceGroupsRemoved: groupsRemoved,
            ResourceGroupsChanged: groupsChanged,
            ResourcesComparable: resourcesComparable,
            ResourcesAdded: resourcesAdded,
            ResourcesRemoved: resourcesRemoved,
            ResourcesChanged: resourcesChanged,
            Summary: summary);
    }

    private static string ResourceKey(AzureResourceSnapshot resource) =>
        $"{resource.ResourceGroup ?? "<none>"}|{resource.Type}|{resource.Name}";

    private static bool ResourceGroupEquals(AzureResourceGroupSnapshot left, AzureResourceGroupSnapshot right) =>
        string.Equals(left.Location, right.Location, StringComparison.OrdinalIgnoreCase)
        && string.Equals(left.ProvisioningState, right.ProvisioningState, StringComparison.OrdinalIgnoreCase)
        && TagsEqual(left.Tags, right.Tags);

    private static bool ResourceEquals(AzureResourceSnapshot left, AzureResourceSnapshot right) =>
        string.Equals(left.Id, right.Id, StringComparison.OrdinalIgnoreCase)
        && string.Equals(left.Location, right.Location, StringComparison.OrdinalIgnoreCase)
        && TagsEqual(left.Tags, right.Tags);

    private static bool TagsEqual(
        IReadOnlyDictionary<string, string> left,
        IReadOnlyDictionary<string, string> right) =>
        left.Count == right.Count
        && left.All(pair => right.TryGetValue(pair.Key, out var value)
            && string.Equals(pair.Value, value, StringComparison.Ordinal));

    private static OperatorProfile NormalizeLoadedProfile(OperatorProfile profile)
    {
        var tags = profile.DefaultTags ?? new SortedDictionary<string, string>();
        return new OperatorProfile(
            SchemaVersion: 1,
            DisplayName: UpdateOptional(null, profile.DisplayName, "displayName", 100),
            PreferredAzureLocation: UpdateLocation(null, profile.PreferredAzureLocation),
            NamingPrefix: UpdatePrefix(null, profile.NamingPrefix),
            DefaultTags: ValidateProfileTags(tags),
            AssistantSurfaces: (profile.AssistantSurfaces ?? Array.Empty<string>())
                .Select(NormalizeSurface)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Order(StringComparer.OrdinalIgnoreCase)
                .ToArray(),
            UpdatedAtUtc: profile.UpdatedAtUtc);
    }

    private static string? UpdateOptional(string? current, string? candidate, string fieldName, int maxLength)
    {
        if (candidate is null)
        {
            return current;
        }
        candidate = candidate.Trim();
        if (candidate.Length == 0)
        {
            return null;
        }
        if (candidate.Length > maxLength || candidate.Any(char.IsControl))
        {
            throw new ArgumentException($"{fieldName} must be at most {maxLength} printable characters.");
        }
        return candidate;
    }

    private static string? UpdateLocation(string? current, string? candidate)
    {
        var value = UpdateOptional(current, candidate, "preferredAzureLocation", 50);
        if (value is not null && !SafeLocation.IsMatch(value))
        {
            throw new ArgumentException("preferredAzureLocation must use lowercase letters, digits, and hyphens.");
        }
        return value;
    }

    private static string? UpdatePrefix(string? current, string? candidate)
    {
        var value = UpdateOptional(current, candidate, "namingPrefix", 24);
        if (value is not null && !SafePrefix.IsMatch(value))
        {
            throw new ArgumentException("namingPrefix must be 1-24 lowercase letters, digits, or hyphens and cannot end with a hyphen.");
        }
        return value;
    }

    private static SortedDictionary<string, string> ParseProfileTags(string json)
    {
        JsonObject tags;
        try
        {
            tags = JsonNode.Parse(json) as JsonObject
                ?? throw new ArgumentException("defaultTagsJson must be a JSON object.");
        }
        catch (JsonException exception)
        {
            throw new ArgumentException($"defaultTagsJson is invalid JSON: {exception.Message}");
        }

        if (tags.Count > MaxTags)
        {
            throw new ArgumentException($"defaultTagsJson may contain at most {MaxTags} tags.");
        }

        var values = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, node) in tags)
        {
            if (node is null)
            {
                values[key] = string.Empty;
                continue;
            }
            if (node is not JsonValue jsonValue || !jsonValue.TryGetValue<string>(out var value))
            {
                throw new ArgumentException($"Tag '{key}' must be a JSON string.");
            }
            values[key] = value ?? string.Empty;
        }
        return ValidateProfileTags(values);
    }

    private static SortedDictionary<string, string> ValidateProfileTags(
        IReadOnlyDictionary<string, string> tags)
    {
        if (tags.Count > MaxTags)
        {
            throw new ArgumentException($"defaultTagsJson may contain at most {MaxTags} tags.");
        }

        var result = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, value) in tags)
        {
            if (key.Length is < 1 or > 128 || key.Any(char.IsControl))
            {
                throw new ArgumentException("Tag names must be 1-128 printable characters.");
            }
            if (value.Length > 256 || value.Any(char.IsControl))
            {
                throw new ArgumentException($"Tag '{key}' must be at most 256 printable characters.");
            }
            if (SensitiveName.IsMatch(key) || SensitiveValue.IsMatch(value))
            {
                throw new ArgumentException($"Tag '{key}' looks credential-like; store secret values in Key Vault, not the operator profile.");
            }
            result[key] = value;
        }
        return result;
    }

    private static string[] ParseAssistantSurfaces(string csv)
    {
        var values = csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(NormalizeSurface)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (values.Length > 16)
        {
            throw new ArgumentException("assistantSurfaces may contain at most 16 values.");
        }
        return values;
    }

    private static string NormalizeSurface(string surface)
    {
        surface = (surface ?? string.Empty).Trim().ToLowerInvariant();
        if (!SafeSurface.IsMatch(surface))
        {
            throw new ArgumentException("surface must be 1-48 lowercase letters, digits, or hyphens.");
        }
        return surface;
    }

    private static bool IsCliAvailable(IReadOnlyDictionary<string, bool> availability, string command) =>
        availability.TryGetValue(command, out var available) && available;

    private async Task<FileStream> AcquireLockAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(OperatorDirectory);
        var lockPath = Path.Combine(OperatorDirectory, ".write.lock");
        for (var attempt = 0; attempt < 80; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException) when (attempt < 79)
            {
                await Task.Delay(50, cancellationToken);
            }
        }
        throw new IOException("Timed out waiting for the HELIOS operator-context lock.");
    }

    private static async Task WriteJsonAtomicallyAsync<T>(string path, T value, CancellationToken cancellationToken)
    {
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        try
        {
            await File.WriteAllTextAsync(
                temporaryPath,
                JsonSerializer.Serialize(value, JsonOptions) + Environment.NewLine,
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
                cancellationToken);
            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    private async Task AppendJournalLineAsync(OperatorJournalEntry entry, CancellationToken cancellationToken)
    {
        var line = JsonSerializer.Serialize(entry, JsonLineOptions) + Environment.NewLine;
        await File.AppendAllTextAsync(
            JournalPath,
            line,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
            cancellationToken);
    }

    private static bool CommandExists(string command)
    {
        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var extensions = OperatingSystem.IsWindows()
            ? (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT;.COM")
                .Split(';', StringSplitOptions.RemoveEmptyEntries)
            : new[] { string.Empty };
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var extension in extensions)
            {
                try
                {
                    if (File.Exists(Path.Combine(directory.Trim(), command + extension)))
                    {
                        return true;
                    }
                }
                catch (ArgumentException)
                {
                    // Ignore malformed PATH entries and continue probing the rest.
                }
            }
        }
        return false;
    }

    private static string? NormalizeRepositoryName(string? remote)
    {
        if (string.IsNullOrWhiteSpace(remote))
        {
            return null;
        }
        remote = remote.Trim().TrimEnd('/');
        var marker = remote.IndexOf("github.com", StringComparison.OrdinalIgnoreCase);
        if (marker < 0)
        {
            return "non-github-remote";
        }

        var repository = remote[(marker + "github.com".Length)..].TrimStart(':', '/');
        if (repository.EndsWith(".git", StringComparison.OrdinalIgnoreCase))
        {
            repository = repository[..^4];
        }
        var parts = repository.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length == 2 ? $"{parts[0]}/{parts[1]}" : "non-github-remote";
    }

    private static string SanitizeError(string? error)
    {
        var text = Regex.Replace(error ?? string.Empty, "[\\r\\n\\t]+", " ").Trim();
        if (SensitiveValue.IsMatch(text))
        {
            return "Azure CLI returned a credential-like error; details were redacted.";
        }
        return string.IsNullOrWhiteSpace(text) ? "Azure CLI command failed without an error message." : Truncate(text, 500);
    }

    private static string Truncate(string value, int length) => value.Length <= length ? value : value[..length];
    private static string? NullIfEmpty(string value) => value.Length == 0 ? null : value;
    private static string? GetString(JsonElement item, string propertyName) =>
        item.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}

internal interface ICommandRunner
{
    Task<CommandResult> RunAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}

internal sealed class SystemCommandRunner : ICommandRunner
{
    public async Task<CommandResult> RunAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = fileName,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        Process? process;
        try
        {
            process = Process.Start(startInfo);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return CommandResult.NotStarted;
        }
        if (process is null)
        {
            return CommandResult.NotStarted;
        }

        using (process)
        using (var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
        {
            timeoutCts.CancelAfter(timeout);
            var stdoutTask = process.StandardOutput.ReadToEndAsync(CancellationToken.None);
            var stderrTask = process.StandardError.ReadToEndAsync(CancellationToken.None);
            try
            {
                await process.WaitForExitAsync(timeoutCts.Token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                TryKill(process);
                await Task.WhenAll(stdoutTask, stderrTask);
                return new CommandResult(true, -1, stdoutTask.Result, "Command timed out.");
            }
            catch
            {
                TryKill(process);
                throw;
            }

            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            return new CommandResult(true, process.ExitCode, stdout, stderr);
        }
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
            // The process exited between HasExited and Kill.
        }
    }
}

internal sealed record CommandResult(bool Started, int ExitCode, string StandardOutput, string StandardError)
{
    internal static readonly CommandResult NotStarted = new(false, -1, string.Empty, "Command is not installed.");
}

internal sealed record OperatorProfile(
    int SchemaVersion,
    string? DisplayName,
    string? PreferredAzureLocation,
    string? NamingPrefix,
    SortedDictionary<string, string> DefaultTags,
    string[] AssistantSurfaces,
    DateTimeOffset? UpdatedAtUtc)
{
    internal static readonly OperatorProfile Default = new(
        SchemaVersion: 1,
        DisplayName: null,
        PreferredAzureLocation: null,
        NamingPrefix: null,
        DefaultTags: new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase),
        AssistantSurfaces: new[] { "chatgpt", "claude-code", "codex", "copilot", "hermes", "xcore" },
        UpdatedAtUtc: null);
}

internal sealed record OperatorContextSnapshot(
    int SchemaVersion,
    DateTimeOffset CapturedAtUtc,
    string Surface,
    RepositorySnapshot Repository,
    OperatorProfile Profile,
    IReadOnlyDictionary<string, bool> CliAvailability,
    AzureSnapshot Azure,
    OperatorChangeSet Changes,
    IReadOnlyList<OperatorNextStep> NextSteps);

internal sealed record RepositorySnapshot(
    string Status,
    string? Repository,
    string? Branch,
    string? HeadSha,
    bool IsDirty,
    bool IsMainBranch)
{
    internal static readonly RepositorySnapshot Empty = new("not-captured", null, null, null, false, false);
}

internal sealed record AzureSnapshot(
    string Status,
    string? SubscriptionId,
    string? SubscriptionName,
    string? TenantId,
    IReadOnlyList<AzureResourceGroupSnapshot> ResourceGroups,
    bool ResourceGroupsTruncated,
    IReadOnlyList<AzureResourceSnapshot> Resources,
    bool ResourcesIncluded,
    bool ResourcesTruncated,
    string? ErrorHint)
{
    internal static readonly AzureSnapshot NotRequested = Empty("not-requested", null);
    internal static readonly AzureSnapshot CliUnavailable = Empty("cli-unavailable", "Azure CLI was not found on PATH.");
    internal static AzureSnapshot Failed(string status, string error) => Empty(status, error);
    private static AzureSnapshot Empty(string status, string? error) => new(
        status,
        null,
        null,
        null,
        Array.Empty<AzureResourceGroupSnapshot>(),
        false,
        Array.Empty<AzureResourceSnapshot>(),
        false,
        false,
        error);
}

internal sealed record AzureResourceGroupSnapshot(
    string Name,
    string? Location,
    string? ProvisioningState,
    SortedDictionary<string, string> Tags);

internal sealed record AzureResourceSnapshot(
    string? Id,
    string Name,
    string Type,
    string? Location,
    string? ResourceGroup,
    SortedDictionary<string, string> Tags);

internal sealed record OperatorChangeSet(
    bool Comparable,
    IReadOnlyList<string> ResourceGroupsAdded,
    IReadOnlyList<string> ResourceGroupsRemoved,
    IReadOnlyList<string> ResourceGroupsChanged,
    bool ResourcesComparable,
    IReadOnlyList<string> ResourcesAdded,
    IReadOnlyList<string> ResourcesRemoved,
    IReadOnlyList<string> ResourcesChanged,
    string Summary)
{
    internal static readonly OperatorChangeSet NotComparable = new(
        false,
        Array.Empty<string>(),
        Array.Empty<string>(),
        Array.Empty<string>(),
        false,
        Array.Empty<string>(),
        Array.Empty<string>(),
        Array.Empty<string>(),
        "No comparable prior Azure snapshot.");
}

internal sealed record OperatorNextStep(
    string Id,
    string Title,
    string Reason,
    string Action,
    string Approval);

internal sealed record OperatorJournalEntry(
    int SchemaVersion,
    DateTimeOffset CapturedAtUtc,
    string Event,
    string Surface,
    string? ContextSha256,
    string? RepositoryHead,
    string? AzureSubscriptionId,
    int? ResourceGroupCount,
    int? ResourceCount,
    string? ChangeSummary);
