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
    [Description("Create or update the inspectable HELIOS operator profile under .helios/operator/profile.json. Omitted fields keep their current value; an empty string clears that field. A save that leaves the effective profile unchanged is a no-op (no rewrite, no journal entry). All fields are validated, and secret-looking names or values are rejected.")]
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
    [Description("Capture the shared HELIOS repo/CLI context and append a sanitized journal receipt. Optionally reads the authenticated Azure CLI subscription, resource groups, resources, locations, and tags, then records a delta from the prior snapshot; a sync without Azure, or whose Azure capture fails, carries the last ready inventory forward unchanged (the failure is reported in azureCaptureFailure) so the comparison baseline survives. It never applies, deletes, or changes Azure resources and never stores tokens or raw CLI output.")]
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
    [Description("Return deterministic next-step proposals recomputed from the current operator profile and the last saved HELIOS context evidence (repository, Azure). Suggestions share the same evidence across assistants; this tool performs no model call or cloud mutation.")]
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
                    nextSteps = store.GetCurrentNextSteps(),
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
    internal static readonly TimeSpan GitCommandTimeout = TimeSpan.FromSeconds(10);
    internal static readonly TimeSpan AzureAccountTimeout = TimeSpan.FromSeconds(20);
    internal static readonly TimeSpan AzureGroupListTimeout = TimeSpan.FromSeconds(30);
    internal static readonly TimeSpan AzureResourceListTimeout = TimeSpan.FromSeconds(45);
    // A healthy lock holder can legitimately run four git commands plus all three Azure
    // reads while holding the lock, so the waiter budget is derived from those same
    // timeouts (plus margin) rather than a magic number that could silently drift.
    internal static readonly TimeSpan LockWaitBudget =
        4 * GitCommandTimeout + AzureAccountTimeout + AzureGroupListTimeout + AzureResourceListTimeout
        + TimeSpan.FromSeconds(15);
    private static readonly Regex SafeSurface = new("^[a-z0-9][a-z0-9-]{0,47}$", RegexOptions.CultureInvariant);
    private static readonly Regex SafeLocation = new("^[a-z0-9][a-z0-9-]{1,49}$", RegexOptions.CultureInvariant);
    private static readonly Regex SafePrefix = new("^[a-z0-9](?:[a-z0-9-]{0,22}[a-z0-9])?$", RegexOptions.CultureInvariant);
    private static readonly Regex SensitiveName = new(
        "(^|[-_.])(secret|password|passwd|token|credential|api[-_]?key|private[-_]?key)($|[-_.])",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex CredentialNameBoundary = new(
        "(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])",
        RegexOptions.CultureInvariant);
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
    private byte[]? _tagSalt;

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
            DefaultTags: defaultTagsJson is null
                ? current.DefaultTags
                : string.IsNullOrWhiteSpace(defaultTagsJson)
                    ? new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                    : ParseProfileTags(defaultTagsJson),
            AssistantSurfaces: assistantSurfaces is null
                ? current.AssistantSurfaces
                : ParseAssistantSurfaces(assistantSurfaces),
            UpdatedAtUtc: _clock());

        if (ProfilesEquivalent(current, next))
        {
            // Idempotent contract: an effective no-op neither rewrites the profile nor
            // appends a journal entry, so repeated identical saves leave no extra trace.
            return current;
        }

        var profileBytes = await WriteJsonAtomicallyAsync(ProfilePath, next, cancellationToken);
        var profileDigest = Convert.ToHexString(SHA256.HashData(profileBytes)).ToLowerInvariant();
        // The profile write is committed: complete the receipt even if the request is
        // canceled now, so the durable profile can never exist without its journal entry.
        await AppendJournalLineAsync(
            new OperatorJournalEntry(
                SchemaVersion: 1,
                CapturedAtUtc: _clock(),
                Event: "profile-saved",
                Surface: "operator-profile",
                ContextSha256: null,
                ProfileSha256: profileDigest,
                RepositoryBranch: null,
                RepositoryHead: null,
                AzureSubscriptionId: null,
                AzureCaptureStatus: null,
                ResourceGroupCount: null,
                ResourceCount: null,
                ChangeSummary: null),
            CancellationToken.None);
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

        // Hold the cross-process lock across capture, compare, and write: if capture ran
        // before the lock, a slower process could acquire the lock last and overwrite a
        // newer context with older evidence, reporting reversed deltas.
        await using var fileLock = await AcquireLockAsync(cancellationToken);
        var cli = _cliDetector();
        var repository = await CaptureRepositoryAsync(cancellationToken);
        var capturedAzure = includeAzure
            ? await CaptureAzureAsync(includeResources, cli, cancellationToken)
            : null;

        var prior = GetLatestContext();
        var profile = GetProfile();
        // The stored Azure field is the durable comparison baseline: only a fresh ready
        // capture replaces it. A repo-only sync or a failed capture (error,
        // not-authenticated, cli-unavailable, partial) carries the last ready inventory
        // forward; a failed capture is surfaced separately via AzureCaptureFailure.
        var priorReadyBaseline = prior?.Azure is { Status: "ready" } baseline ? baseline : null;
        var azure = capturedAzure is { Status: "ready" }
            ? WithCarriedResourceBaseline(capturedAzure, priorReadyBaseline)
            : priorReadyBaseline ?? capturedAzure ?? AzureSnapshot.NotRequested;
        var changes = capturedAzure is null
            ? OperatorChangeSet.NotRequested
            : BuildChanges(priorReadyBaseline, capturedAzure);
        var nextSteps = BuildNextSteps(
            profile,
            repository,
            capturedAzure ?? azure,
            cli,
            azureEvidenceCurrent: capturedAzure is { Status: "ready" },
            resourcesEvidenceCurrent: capturedAzure is { Status: "ready", ResourcesIncluded: true });

        var snapshot = new OperatorContextSnapshot(
            SchemaVersion: 1,
            CapturedAtUtc: _clock(),
            Surface: surface,
            Repository: repository,
            Profile: profile,
            CliAvailability: cli,
            Azure: azure,
            AzureCaptureFailure: capturedAzure is null or { Status: "ready" } ? null : capturedAzure,
            AzureCaptureStatus: capturedAzure?.Status,
            AzureCaptureIncludedResources: capturedAzure is { Status: "ready", ResourcesIncluded: true },
            Changes: changes,
            NextSteps: nextSteps);

        // Hash exactly the bytes written to disk so `sha256sum context.json` matches
        // the journal receipt.
        var contextBytes = await WriteJsonAtomicallyAsync(ContextPath, snapshot, cancellationToken);
        var digest = Convert.ToHexString(SHA256.HashData(contextBytes)).ToLowerInvariant();
        // The context write is committed: complete the receipt with CancellationToken.None
        // so a canceled request can never leave a durable context without a journal entry.
        await AppendJournalLineAsync(
            new OperatorJournalEntry(
                SchemaVersion: 1,
                CapturedAtUtc: snapshot.CapturedAtUtc,
                Event: "context-synced",
                Surface: surface,
                ContextSha256: digest,
                ProfileSha256: null,
                RepositoryBranch: repository.Branch,
                RepositoryHead: repository.HeadSha,
                AzureSubscriptionId: azure.SubscriptionId,
                // The attempted capture's own status (null = Azure not requested). The
                // counts below describe the STORED baseline, which may be carried
                // forward — this field is what proves whether fresh Azure evidence was
                // actually available at this receipt.
                AzureCaptureStatus: capturedAzure?.Status,
                ResourceGroupCount: azure.ResourceGroups.Count,
                ResourceCount: azure.Resources.Count,
                ChangeSummary: changes.Summary),
            CancellationToken.None);
        return snapshot;
    }

    /// <summary>
    /// Next steps for the read-time tool: profile-dependent suggestions are rebuilt from
    /// the CURRENT profile (a profile save must retire "complete-profile" immediately),
    /// while repository/Azure evidence is reused from the last saved snapshot.
    /// </summary>
    internal IReadOnlyList<OperatorNextStep> GetCurrentNextSteps()
    {
        var snapshot = GetLatestContext();
        var profile = GetProfile();
        return snapshot is null
            ? BuildNextSteps(
                profile,
                RepositorySnapshot.Empty,
                AzureSnapshot.NotRequested,
                _cliDetector(),
                azureEvidenceCurrent: false,
                resourcesEvidenceCurrent: false)
            : BuildNextSteps(
                profile,
                snapshot.Repository,
                snapshot.AzureCaptureFailure ?? snapshot.Azure,
                snapshot.CliAvailability,
                azureEvidenceCurrent: snapshot.AzureCaptureStatus == "ready",
                resourcesEvidenceCurrent: snapshot.AzureCaptureIncludedResources);
    }

    internal IReadOnlyList<OperatorNextStep> BuildNextSteps(
        OperatorProfile profile,
        RepositorySnapshot repository,
        AzureSnapshot azure,
        IReadOnlyDictionary<string, bool> cli,
        bool azureEvidenceCurrent,
        bool resourcesEvidenceCurrent)
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
        else if (repository.IsDetachedHead)
        {
            steps.Add(new OperatorNextStep(
                "create-task-branch",
                "Create a task branch",
                "The checkout is on a detached HEAD; commits made here are easy to lose and invisible to review until they live on a branch.",
                "git switch -c <task-branch>",
                "none"));
        }

        // Independent of the branch-state proposal: a dirty checkout on main or a
        // detached HEAD must still get the diff-review step, or uncommitted unrelated
        // changes would be carried into the new task branch unreviewed.
        if (repository.IsDirty == true)
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
            if (!azureEvidenceCurrent)
            {
                // A carried-forward baseline is delta evidence, not planning evidence:
                // never recommend generating a plan from an inventory of unknown age.
                var capturedAt = azure.CapturedAtUtc is { } at
                    ? at.ToString("u", System.Globalization.CultureInfo.InvariantCulture)
                    : "an earlier sync";
                steps.Add(new OperatorNextStep(
                    "refresh-azure-inventory",
                    "Refresh the Azure inventory",
                    $"The saved inventory is carried forward from {capturedAt} and was not re-captured in the latest sync; do not plan against it without refreshing.",
                    "Re-run helios_operator_context_sync with includeAzure=true first.",
                    "none"));
            }
            else if (azure.SubscriptionState is not null
                && !string.Equals(azure.SubscriptionState, "Enabled", StringComparison.OrdinalIgnoreCase))
            {
                steps.Add(new OperatorNextStep(
                    "review-subscription-state",
                    "Review the subscription state",
                    $"az reports the subscription state as '{azure.SubscriptionState}'; the read plane may still answer, but this is not deployment-ready evidence.",
                    "Resolve the subscription state (billing/policy) in the Azure portal before planning any deployment.",
                    "review"));
            }
            else if (!azure.ResourcesIncluded)
            {
                // Not-queried is not the same as empty: never present an absent resource
                // inventory as "0 resource(s)".
                steps.Add(new OperatorNextStep(
                    "inventory-resources",
                    "Capture the resource inventory",
                    $"Resource groups are inventoried ({azure.ResourceGroups.Count}{(azure.ResourceGroupsTruncated ? "+" : string.Empty)}), but resources were not queried; a truthful plan needs resource-level evidence.",
                    "Re-run helios_operator_context_sync with includeAzure=true and includeResources=true.",
                    "none"));
            }
            else if (!resourcesEvidenceCurrent)
            {
                // Groups are fresh but the resource inventory was carried forward from an
                // earlier resource-inclusive sync: it is delta evidence, not plan evidence.
                steps.Add(new OperatorNextStep(
                    "refresh-resource-inventory",
                    "Refresh the resource inventory",
                    "Resource groups are current, but the resource inventory is carried forward from an earlier sync; do not plan against it without refreshing.",
                    "Re-run helios_operator_context_sync with includeAzure=true and includeResources=true.",
                    "none"));
            }
            else
            {
                steps.Add(new OperatorNextStep(
                    "review-azure-plan",
                    "Generate the next Azure what-if",
                    $"The saved inventory covers {azure.ResourceGroups.Count}{(azure.ResourceGroupsTruncated ? "+" : string.Empty)} resource group(s) and {azure.Resources.Count}{(azure.ResourcesTruncated ? "+" : string.Empty)} resource(s); use that evidence to produce the smallest Bicep plan.",
                    "Follow infra/README.md and save the what-if output before apply.",
                    "review"));
            }
        }
        else if (azure.Status == "partial")
        {
            steps.Add(new OperatorNextStep(
                "retry-resource-inventory",
                "Retry the resource inventory",
                azure.ErrorHint ?? "Resource groups were captured, but the resource inventory failed.",
                "Re-run helios_operator_context_sync with includeAzure=true and includeResources=true.",
                "none"));
        }
        else if (azure.Status == "error")
        {
            steps.Add(new OperatorNextStep(
                "retry-azure-inventory",
                "Retry the Azure inventory",
                azure.ErrorHint ?? "The Azure CLI returned an error during capture.",
                "Check az account show / az group list manually, then re-run helios_operator_context_sync with includeAzure=true.",
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
        // Availability is derived from the injected runner (Started == false means the
        // command could not launch), never from a static PATH probe, so tests can fake it.
        var head = await RunGitAsync(new[] { "rev-parse", "HEAD" }, cancellationToken);
        if (!head.Started)
        {
            return RepositorySnapshot.Empty with { Status = "git-unavailable" };
        }

        var headSha = head.ExitCode == 0 ? NullIfEmpty(head.StandardOutput.Trim()) : null;
        if (headSha is null)
        {
            return RepositorySnapshot.Empty with { Status = "not-a-git-checkout" };
        }

        var branchResult = await RunGitAsync(new[] { "branch", "--show-current" }, cancellationToken);
        var branch = branchResult.Started && branchResult.ExitCode == 0
            ? NullIfEmpty(branchResult.StandardOutput.Trim())
            : null;
        // Detached HEAD is a successful branch query with empty output — distinct from a
        // failed query, and it needs its own task-branch safeguard downstream.
        var isDetachedHead = branchResult.Started && branchResult.ExitCode == 0 && branch is null;
        var isMainBranch = string.Equals(branch, "main", StringComparison.OrdinalIgnoreCase);
        // Branch metadata flows into context.json, the journal, and tool output, so a
        // credential-looking branch name (e.g. incident/sk-...) gets the same keyed
        // fingerprint redaction as profile fields and Azure tags.
        if (branch is not null && SensitiveValue.IsMatch(branch))
        {
            branch = RedactValue(branch);
        }
        var remote = await RunGitValueAsync(new[] { "remote", "get-url", "origin" }, cancellationToken);
        var status = await RunGitAsync(new[] { "status", "--porcelain=v1" }, cancellationToken);

        return new RepositorySnapshot(
            Status: "ready",
            Repository: NormalizeRepositoryName(remote),
            Branch: branch,
            HeadSha: headSha,
            // null = status capture failed; never claim a clean checkout without evidence.
            IsDirty: status.Started && status.ExitCode == 0
                ? !string.IsNullOrWhiteSpace(status.StandardOutput)
                : null,
            IsMainBranch: isMainBranch,
            IsDetachedHead: isDetachedHead);
    }

    private Task<CommandResult> RunGitAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var allArgs = new List<string> { "-C", RepoRoot };
        allArgs.AddRange(args);
        return _runner.RunAsync("git", allArgs, GitCommandTimeout, cancellationToken);
    }

    private async Task<string?> RunGitValueAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await RunGitAsync(args, cancellationToken);
        return result.Started && result.ExitCode == 0
            ? NullIfEmpty(result.StandardOutput.Trim())
            : null;
    }

    private async Task<AzureSnapshot> CaptureAzureAsync(
        bool includeResources,
        IReadOnlyDictionary<string, bool> cli,
        CancellationToken cancellationToken)
    {
        var capturedAtUtc = _clock();
        if (!IsCliAvailable(cli, "az"))
        {
            return AzureSnapshot.CliUnavailable with { CapturedAtUtc = capturedAtUtc };
        }

        var accountResult = await _runner.RunAsync(
            "az",
            new[]
            {
                "account", "show", "--only-show-errors", "--output", "json",
                "--query", "{id:id,name:name,tenantId:tenantId,state:state}",
            },
            AzureAccountTimeout,
            cancellationToken);
        if (!accountResult.Started || accountResult.ExitCode != 0)
        {
            var error = SanitizeError(accountResult.StandardError);
            var status = error.Contains("login", StringComparison.OrdinalIgnoreCase)
                || error.Contains("subscription", StringComparison.OrdinalIgnoreCase)
                ? "not-authenticated"
                : "error";
            return AzureSnapshot.Failed(status, error) with { CapturedAtUtc = capturedAtUtc };
        }

        using var accountDocument = JsonDocument.Parse(accountResult.StandardOutput);
        var account = accountDocument.RootElement;
        var subscriptionId = GetString(account, "id");
        var subscriptionName = GetString(account, "name");
        var tenantId = GetString(account, "tenantId");
        var subscriptionState = GetString(account, "state");

        var groupsResult = await _runner.RunAsync(
            "az",
            new[]
            {
                "group", "list", "--only-show-errors", "--output", "json",
                "--query", $"[0:{MaxResourceGroups + 1}].{{name:name,location:location,provisioningState:properties.provisioningState,tags:tags}}",
            },
            AzureGroupListTimeout,
            cancellationToken);
        if (!groupsResult.Started || groupsResult.ExitCode != 0)
        {
            return AzureSnapshot.Failed("error", SanitizeError(groupsResult.StandardError)) with
            {
                SubscriptionId = subscriptionId,
                SubscriptionName = subscriptionName,
                TenantId = tenantId,
                SubscriptionState = subscriptionState,
                CapturedAtUtc = capturedAtUtc,
            };
        }

        var groups = ParseResourceGroups(groupsResult.StandardOutput, out var groupsTruncated);
        var tagSaltId = GetTagSaltId();
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
                AzureResourceListTimeout,
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
                    ErrorHint: $"Resource groups were saved, but resource inventory failed: {SanitizeError(resourcesResult.StandardError)}",
                    SubscriptionState: subscriptionState,
                    CapturedAtUtc: capturedAtUtc,
                    TagSaltId: tagSaltId);
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
            ErrorHint: null,
            SubscriptionState: subscriptionState,
            CapturedAtUtc: capturedAtUtc,
            TagSaltId: tagSaltId);
    }

    /// <summary>
    /// Replaces a sensitive tag value with a deterministic keyed fingerprint,
    /// "&lt;redacted:xxxxxxxxxxxx&gt;", so an unchanged secret compares equal across syncs
    /// while a rotated secret surfaces as a change — without ever storing the value. The
    /// key is a random per-checkout salt kept next to the context files (same local
    /// trust domain), so the marker is safe to share and resists offline guessing.
    /// </summary>
    private string RedactValue(string value)
    {
        var digest = HMACSHA256.HashData(GetOrCreateTagSalt(), Encoding.UTF8.GetBytes(value));
        return $"<redacted:{Convert.ToHexString(digest.AsSpan(0, 6)).ToLowerInvariant()}>";
    }

    private string GetTagSaltId() =>
        Convert.ToHexString(SHA256.HashData(GetOrCreateTagSalt()).AsSpan(0, 4)).ToLowerInvariant();

    private byte[] GetOrCreateTagSalt()
    {
        if (_tagSalt is not null)
        {
            return _tagSalt;
        }

        // Captures run under the cross-process lock, so first-time creation is race-safe.
        var saltPath = Path.Combine(OperatorDirectory, "tag-salt.bin");
        if (File.Exists(saltPath))
        {
            var existing = File.ReadAllBytes(saltPath);
            if (existing.Length >= 16)
            {
                _tagSalt = existing;
                return existing;
            }
        }

        Directory.CreateDirectory(OperatorDirectory);
        var salt = RandomNumberGenerator.GetBytes(32);
        File.WriteAllBytes(saltPath, salt);
        _tagSalt = salt;
        return salt;
    }

    private IReadOnlyList<AzureResourceGroupSnapshot> ParseResourceGroups(string json, out bool truncated)
    {
        using var document = JsonDocument.Parse(json);
        var items = document.RootElement.EnumerateArray().ToArray();
        truncated = items.Length > MaxResourceGroups;
        return items.Take(MaxResourceGroups)
            .Select(item => new AzureResourceGroupSnapshot(
                Name: GetString(item, "name") ?? "unknown",
                Location: GetString(item, "location"),
                ProvisioningState: GetString(item, "provisioningState"),
                Tags: ParseAzureTags(item, out var tagsTruncated),
                TagsTruncated: tagsTruncated))
            .OrderBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private IReadOnlyList<AzureResourceSnapshot> ParseResources(string json, out bool truncated)
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
                Tags: ParseAzureTags(item, out var tagsTruncated),
                TagsTruncated: tagsTruncated))
            .OrderBy(item => item.ResourceGroup, StringComparer.OrdinalIgnoreCase)
            .ThenBy(item => item.Type, StringComparer.OrdinalIgnoreCase)
            .ThenBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private SortedDictionary<string, string> ParseAzureTags(JsonElement item, out bool truncated)
    {
        truncated = false;
        var tags = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!item.TryGetProperty("tags", out var tagElement) || tagElement.ValueKind != JsonValueKind.Object)
        {
            return tags;
        }

        var properties = tagElement.EnumerateObject().ToArray();
        truncated = properties.Length > MaxTags;
        foreach (var property in properties.Take(MaxTags))
        {
            var value = property.Value.ValueKind == JsonValueKind.String
                ? property.Value.GetString() ?? string.Empty
                : property.Value.ToString();
            // A cut-off name or value can no longer prove "unchanged" (and two long names
            // sharing a prefix would collapse into one entry), so flag it like the
            // tag-count truncation above.
            truncated |= property.Name.Length > 128 || value.Length > 256;
            tags[Truncate(property.Name, 128)] = IsSensitiveName(property.Name) || SensitiveValue.IsMatch(value)
                ? RedactValue(value)
                : Truncate(value, 256);
        }
        return tags;
    }

    /// <summary>
    /// A groups-only ready capture must not drop the last resource inventory: the prior
    /// ready, resource-inclusive baseline (same subscription and tenant) is carried into
    /// the stored snapshot until another resource-inclusive ready capture replaces it —
    /// the same pattern used when a failed capture carries the whole baseline forward.
    /// </summary>
    private static AzureSnapshot WithCarriedResourceBaseline(AzureSnapshot fresh, AzureSnapshot? priorReady)
    {
        if (fresh.ResourcesIncluded
            || priorReady is not { ResourcesIncluded: true }
            || priorReady.SubscriptionId is null || priorReady.TenantId is null
            || !string.Equals(priorReady.SubscriptionId, fresh.SubscriptionId, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(priorReady.TenantId, fresh.TenantId, StringComparison.OrdinalIgnoreCase))
        {
            return fresh;
        }

        return fresh with
        {
            Resources = priorReady.Resources,
            ResourcesIncluded = true,
            ResourcesTruncated = priorReady.ResourcesTruncated,
        };
    }

    private static OperatorChangeSet BuildChanges(AzureSnapshot? prior, AzureSnapshot current)
    {
        if (prior is null || prior.Status != "ready" || current.Status != "ready"
            || prior.ResourceGroupsTruncated || current.ResourceGroupsTruncated
            // A subscription or tenant switch between syncs would masquerade as mass
            // adds/removes; require the same non-null identity on both sides.
            || prior.SubscriptionId is null || prior.TenantId is null
            || !string.Equals(prior.SubscriptionId, current.SubscriptionId, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(prior.TenantId, current.TenantId, StringComparison.OrdinalIgnoreCase)
            // Items whose tag maps were truncated cannot prove "unchanged".
            || prior.ResourceGroups.Any(group => group.TagsTruncated)
            || current.ResourceGroups.Any(group => group.TagsTruncated)
            // Redaction fingerprints are keyed by the per-checkout salt: captures made
            // under different salts (e.g. tag-salt.bin lost in a partial restore) would
            // read as every redacted tag changing at once, so they are not comparable.
            || prior.TagSaltId is null
            || !string.Equals(prior.TagSaltId, current.TagSaltId, StringComparison.OrdinalIgnoreCase))
        {
            return OperatorChangeSet.NotComparable;
        }

        var priorGroups = prior.ResourceGroups.ToDictionary(group => group.Name, StringComparer.OrdinalIgnoreCase);
        var currentGroups = current.ResourceGroups.ToDictionary(group => group.Name, StringComparer.OrdinalIgnoreCase);
        var groupsAdded = currentGroups.Keys.Except(priorGroups.Keys, StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray();
        var groupsRemoved = priorGroups.Keys.Except(currentGroups.Keys, StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray();
        var groupsChanged = currentGroups.Keys.Intersect(priorGroups.Keys, StringComparer.OrdinalIgnoreCase)
            .Where(key => !ResourceGroupEquals(currentGroups[key], priorGroups[key]))
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var resourcesComparable = !prior.ResourcesTruncated && !current.ResourcesTruncated
            && prior.ResourcesIncluded && current.ResourcesIncluded
            && !prior.Resources.Any(resource => resource.TagsTruncated)
            && !current.Resources.Any(resource => resource.TagsTruncated);
        var resourcesAdded = Array.Empty<string>();
        var resourcesRemoved = Array.Empty<string>();
        var resourcesChanged = Array.Empty<string>();
        if (resourcesComparable)
        {
            var oldResources = BuildResourceIndex(prior.Resources);
            var newResources = BuildResourceIndex(current.Resources);
            resourcesAdded = newResources.Keys.Except(oldResources.Keys, StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray();
            resourcesRemoved = oldResources.Keys.Except(newResources.Keys, StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray();
            resourcesChanged = newResources.Keys.Intersect(oldResources.Keys, StringComparer.OrdinalIgnoreCase)
                .Where(key => !ResourceEquals(newResources[key], oldResources[key]))
                .Order(StringComparer.OrdinalIgnoreCase)
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

    /// <summary>
    /// Keys primarily by the Azure resource ID, which is unique — child/extension
    /// resources under different parents can legitimately share resourceGroup+type+leaf
    /// name, so the composite is only a fallback when the ID is absent.
    /// </summary>
    private static string ResourceKey(AzureResourceSnapshot resource) =>
        resource.Id ?? $"{resource.ResourceGroup ?? "<none>"}|{resource.Type}|{resource.Name}";

    private static Dictionary<string, AzureResourceSnapshot> BuildResourceIndex(
        IReadOnlyList<AzureResourceSnapshot> resources)
    {
        // Last-wins indexer instead of ToDictionary: a residual duplicate key (only
        // possible for ID-less entries) must never abort the whole context update.
        var index = new Dictionary<string, AzureResourceSnapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (var resource in resources)
        {
            index[ResourceKey(resource)] = resource;
        }
        return index;
    }

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
        if (SensitiveValue.IsMatch(candidate))
        {
            throw new ArgumentException($"{fieldName} looks credential-like; store secret values in Key Vault, not the operator profile.");
        }
        return candidate;
    }

    private static bool ProfilesEquivalent(OperatorProfile left, OperatorProfile right) =>
        string.Equals(left.DisplayName, right.DisplayName, StringComparison.Ordinal)
        && string.Equals(left.PreferredAzureLocation, right.PreferredAzureLocation, StringComparison.Ordinal)
        && string.Equals(left.NamingPrefix, right.NamingPrefix, StringComparison.Ordinal)
        && TagsEqual(left.DefaultTags, right.DefaultTags)
        && left.AssistantSurfaces.SequenceEqual(right.AssistantSurfaces, StringComparer.Ordinal);

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
            if (IsSensitiveName(key) || SensitiveValue.IsMatch(value))
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

    /// <summary>
    /// Matches punctuation-delimited credential-like names, their camelCase forms, and
    /// acronym-to-word transitions (clientSecret, sasToken, SASToken) by inserting a
    /// separator at case boundaries.
    /// </summary>
    private static bool IsSensitiveName(string name) =>
        SensitiveName.IsMatch(name) || SensitiveName.IsMatch(CredentialNameBoundary.Replace(name, "-"));

    private async Task<FileStream> AcquireLockAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(OperatorDirectory);
        var lockPath = Path.Combine(OperatorDirectory, ".write.lock");
        // Sync holds this lock across its full git/Azure capture, so wait at least the
        // worst-case capture window; the OS releases the handle if the holder dies.
        var stopwatch = Stopwatch.StartNew();
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException)
            {
                if (stopwatch.Elapsed >= LockWaitBudget)
                {
                    throw new IOException("Timed out waiting for the HELIOS operator-context lock.");
                }
                await Task.Delay(100, cancellationToken);
            }
        }
    }

    /// <summary>Writes the serialized value atomically and returns the exact bytes written.</summary>
    private static async Task<byte[]> WriteJsonAtomicallyAsync<T>(string path, T value, CancellationToken cancellationToken)
    {
        var payload = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value, JsonOptions) + Environment.NewLine);
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        try
        {
            await File.WriteAllBytesAsync(temporaryPath, payload, cancellationToken);
            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
        return payload;
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

    private static bool CommandExists(string command) => ResolveCommandPath(command) is not null;

    /// <summary>
    /// Resolves a command name to the full path of the file that PATH (and PATHEXT on
    /// Windows) discovery would find, including its real extension — so callers can see
    /// that "az" is actually az.cmd and launch it accordingly. Returns null when absent.
    /// </summary>
    internal static string? ResolveCommandPath(string command)
    {
        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
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
                    var candidate = Path.Combine(directory.Trim(), command + extension);
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
                catch (ArgumentException)
                {
                    // Ignore malformed PATH entries and continue probing the rest.
                }
            }
        }
        return null;
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
        var startInfo = CreateStartInfo(
            fileName,
            arguments,
            OperatingSystem.IsWindows() ? OperatorContextStore.ResolveCommandPath(fileName) : null);

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

    /// <summary>
    /// Builds the launch configuration. On Windows, PATH/PATHEXT discovery can resolve a
    /// command like "az" to a batch shim (az.cmd) that CreateProcess cannot start
    /// directly with shell execution disabled, so batch shims are launched via
    /// "cmd.exe /d /c &lt;resolved path&gt;". Arguments always go through ArgumentList
    /// (never string concatenation); all HELIOS capture arguments are fixed literals —
    /// no repository or Azure data flows into a command line. resolvedWindowsPath is
    /// null on non-Windows platforms, which keeps their behavior unchanged.
    /// </summary>
    internal static ProcessStartInfo CreateStartInfo(
        string fileName,
        IReadOnlyList<string> arguments,
        string? resolvedWindowsPath)
    {
        var startInfo = new ProcessStartInfo
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        if (resolvedWindowsPath is not null
            && (resolvedWindowsPath.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase)
                || resolvedWindowsPath.EndsWith(".bat", StringComparison.OrdinalIgnoreCase)))
        {
            startInfo.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            startInfo.ArgumentList.Add("/d");
            startInfo.ArgumentList.Add("/c");
            startInfo.ArgumentList.Add(resolvedWindowsPath);
        }
        else
        {
            startInfo.FileName = resolvedWindowsPath ?? fileName;
        }
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        return startInfo;
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
    IReadOnlyList<OperatorNextStep> NextSteps,
    // Non-null only when an Azure capture was requested but did not return ready; the
    // Azure field then still holds the carried-forward last ready baseline.
    AzureSnapshot? AzureCaptureFailure = null,
    // Status of THIS sync's Azure capture attempt (null = not requested). "ready" is the
    // only value under which the stored Azure inventory is current planning evidence.
    string? AzureCaptureStatus = null,
    // True only when THIS sync's capture was ready AND resource-inclusive; a carried
    // resource inventory keeps ResourcesIncluded=true on the baseline but is not current.
    bool AzureCaptureIncludedResources = false);

internal sealed record RepositorySnapshot(
    string Status,
    string? Repository,
    string? Branch,
    string? HeadSha,
    bool? IsDirty,
    bool IsMainBranch,
    bool IsDetachedHead = false)
{
    internal static readonly RepositorySnapshot Empty = new("not-captured", null, null, null, null, false);
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
    string? ErrorHint,
    // az account show state (Enabled/Disabled/Warned/...); anything other than Enabled
    // means the inventory is readable but NOT deployment-ready evidence. Null = unknown
    // (older snapshots).
    string? SubscriptionState = null,
    // When this inventory was actually captured from az. A baseline carried forward
    // across later syncs keeps its original timestamp, so staleness stays visible.
    DateTimeOffset? CapturedAtUtc = null,
    // Identity (first 8 hex of SHA-256) of the redaction salt used for this capture's
    // tag fingerprints. Captures made under different salts are not comparable — a
    // regenerated salt would otherwise read as every redacted tag changing at once.
    string? TagSaltId = null)
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
    SortedDictionary<string, string> Tags,
    bool TagsTruncated = false);

internal sealed record AzureResourceSnapshot(
    string? Id,
    string Name,
    string Type,
    string? Location,
    string? ResourceGroup,
    SortedDictionary<string, string> Tags,
    bool TagsTruncated = false);

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

    internal static readonly OperatorChangeSet NotRequested = NotComparable with
    {
        Summary = "Azure inventory was not requested in this sync; the last ready inventory, if any, was carried forward.",
    };
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
    string? ProfileSha256,
    string? RepositoryBranch,
    string? RepositoryHead,
    string? AzureSubscriptionId,
    string? AzureCaptureStatus,
    int? ResourceGroupCount,
    int? ResourceCount,
    string? ChangeSummary);
