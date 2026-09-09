using System.Text.Json.Serialization;

namespace HELIOS.AIHub.Fleet;

public sealed record FleetReadinessFinding(
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("severity")] string Severity,
    [property: JsonPropertyName("pool")] string? Pool,
    [property: JsonPropertyName("message")] string Message);

/// <summary>A required verification step, not an executable task or an approval.</summary>
public sealed record FleetActivationStage(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("dependsOn")] IReadOnlyList<string> DependsOn,
    [property: JsonPropertyName("requiredEvidence")] string RequiredEvidence);

public sealed record FleetPlacementReadiness
{
    [JsonPropertyName("location")]
    public required string Location { get; init; }

    [JsonPropertyName("configuredCeiling")]
    public int? ConfiguredCeiling { get; init; }

    [JsonPropertyName("transport")]
    public required string Transport { get; init; }

    [JsonPropertyName("transportState")]
    public required string TransportState { get; init; }

    [JsonPropertyName("identityRequirement")]
    public required string IdentityRequirement { get; init; }

    [JsonPropertyName("runtimeVerified")]
    public bool RuntimeVerified => false;

    // Always serialize unknown, including through callers that ignore null properties.
    [JsonPropertyName("verifiedWorkers"), JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public int? VerifiedWorkers => null;
}

public sealed record FleetPoolReadiness
{
    [JsonPropertyName("pool")]
    public required string Pool { get; init; }

    [JsonPropertyName("board")]
    public required string Board { get; init; }

    [JsonPropertyName("mode")]
    public required string Mode { get; init; }

    [JsonPropertyName("configuredWorkerSlots")]
    public int ConfiguredWorkerSlots { get; init; }

    /// <summary>Recommended aggregate bound; not a claim that every runtime enforces it.</summary>
    [JsonPropertyName("configuredConcurrencyCeiling")]
    public int? ConfiguredConcurrencyCeiling { get; init; }

    [JsonPropertyName("taskTypes")]
    public required IReadOnlyList<string> TaskTypes { get; init; }

    [JsonPropertyName("providerChain")]
    public required IReadOnlyList<string> ProviderChain { get; init; }

    [JsonPropertyName("declaredTools")]
    public required IReadOnlyList<string> DeclaredTools { get; init; }

    [JsonPropertyName("declaredSkills")]
    public required IReadOnlyList<string> DeclaredSkills { get; init; }

    [JsonPropertyName("declaredAgents")]
    public required IReadOnlyList<string> DeclaredAgents { get; init; }

    [JsonPropertyName("placements")]
    public required IReadOnlyList<FleetPlacementReadiness> Placements { get; init; }
}

public sealed record FleetReadinessReport
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion => 1;

    [JsonPropertyName("mode")]
    public string Mode => "offline-advisory";

    [JsonPropertyName("runtimeVerified")]
    public bool RuntimeVerified => false;

    [JsonPropertyName("verifiedConcurrentWorkers"), JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public int? VerifiedConcurrentWorkers => null;

    [JsonPropertyName("configurationValid")]
    public bool ConfigurationValid => Findings.All(f => f.Severity != "error");

    [JsonPropertyName("configuredConcurrencyCeiling"), JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public int? ConfiguredConcurrencyCeiling => ConfigurationValid && Pools.All(p => p.ConfiguredConcurrencyCeiling.HasValue)
        ? Pools.Sum(p => p.ConfiguredConcurrencyCeiling!.Value)
        : null;

    [JsonPropertyName("pools")]
    public required IReadOnlyList<FleetPoolReadiness> Pools { get; init; }

    [JsonPropertyName("findings")]
    public required IReadOnlyList<FleetReadinessFinding> Findings { get; init; }

    [JsonPropertyName("activationStages")]
    public required IReadOnlyList<FleetActivationStage> ActivationStages { get; init; }

    [JsonPropertyName("advisory")]
    public string Advisory => "Configured ceilings are planning limits, not measured capacity or a launch request. " +
        "Local/cloud ceilings share each pool's aggregate limit and must not be added. " +
        "No process, account, queue, identity, provider, knowledge store or learning backend was probed. " +
        "No workers were started, secrets read, models called or resources changed.";
}

/// <summary>
/// Offline fleet preflight over the reviewed topology. This has no runtime evidence input:
/// a declaration or caller-supplied boolean cannot manufacture verified worker capacity.
/// Live status and correlated task receipts must be obtained from their actual adapters.
/// </summary>
public static class FleetReadinessService
{
    private const int MaximumPools = 64;

    public static FleetReadinessReport Plan(FleetTopology topology)
    {
        ArgumentNullException.ThrowIfNull(topology);
        var findings = new List<FleetReadinessFinding>();
        var pools = new List<FleetPoolReadiness>();
        if (topology.Version != 2)
        {
            findings.Add(new("topology-version", "error", null,
                $"Readiness binds topology version 2; received {topology.Version}."));
        }
        var configured = topology.Pools ?? Array.Empty<FleetPool>();
        if (configured.Count is 0 or > MaximumPools)
        {
            findings.Add(new("pool-count", "error", null,
                $"Readiness requires between 1 and {MaximumPools} pools; received {configured.Count}."));
            return Report(pools, findings);
        }

        // PowerShell fleet lookup (-eq) and topology validation compare identifiers
        // without case. Do not count an alias as independent capacity or ownership.
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var boards = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var pool in configured)
        {
            if (pool is null)
            {
                findings.Add(new("null-pool", "error", null, "A pool entry is null."));
                continue;
            }
            if (string.IsNullOrWhiteSpace(pool.Name) || !names.Add(pool.Name))
            {
                findings.Add(new("pool-name", "error", pool.Name, "Pool names must be present and unique."));
            }
            pools.Add(PlanPool(pool, topology.Defaults, boards, findings));
        }
        return Report(pools, findings);
    }

    private static FleetPoolReadiness PlanPool(
        FleetPool pool, FleetDefaults? defaults, HashSet<string> boards,
        List<FleetReadinessFinding> findings)
    {
        var errorCount = findings.Count(f => f.Severity == "error");
        // Lane settings use object fallback, matching start-fleet/scale-fleet;
        // autoscaling uses member-level merging. Board resolution is deliberately
        // separate: start-fleet reads only the pool's board, falling back to its name.
        var hermes = pool.HermesFleet ?? defaults?.HermesFleet;
        var board = string.IsNullOrWhiteSpace(pool.HermesFleet?.Board) ? pool.Name : pool.HermesFleet.Board;
        if (!boards.Add(board))
        {
            findings.Add(new("board-collision", "error", pool.Name,
                "Two pools resolve to the same board; establish isolated task ownership before activation."));
        }

        var size = pool.PoolSize ?? defaults?.PoolSize ?? 1;
        var laneLimit = hermes?.MaxConcurrentLanes ?? 0;
        var autoscaling = pool.Autoscaling ?? defaults?.Autoscaling;
        var mode = pool.Autoscaling?.Mode ?? defaults?.Autoscaling?.Mode ?? "local";
        var minLocal = pool.Autoscaling?.MinLocalLanes ?? defaults?.Autoscaling?.MinLocalLanes ?? 1;
        var maxLocal = pool.Autoscaling?.MaxLocalLanes ?? defaults?.Autoscaling?.MaxLocalLanes ?? minLocal;
        var maxBurst = pool.Autoscaling?.MaxBurstLanes ?? defaults?.Autoscaling?.MaxBurstLanes ?? 0;
        var burstTarget = pool.Autoscaling?.BurstTarget ?? defaults?.Autoscaling?.BurstTarget;

        if (size is < 1 or > 64 || laneLimit < 0 || minLocal is < 0 or > 64 ||
            maxLocal is < 0 or > 64 || maxBurst is < 0 or > 256)
        {
            findings.Add(new("capacity-range", "error", pool.Name,
                "Worker/local capacities must fit 1–64/0–64; burst capacity 0–256; lane limit cannot be negative."));
        }
        if (mode is not ("local" or "hybrid" or "cloud"))
        {
            findings.Add(new("placement-mode", "error", pool.Name, "Placement mode must be local, hybrid or cloud."));
        }
        if (autoscaling is not null && mode != "cloud" && minLocal > maxLocal)
        {
            findings.Add(new("local-capacity-order", "error", pool.Name,
                "minLocalLanes exceeds maxLocalLanes; repair the policy instead of inventing capacity."));
        }
        if (pool.TaskTypes is null || pool.TaskTypes.Count == 0 || pool.TaskTypes.Any(string.IsNullOrWhiteSpace) ||
            pool.ProviderChain is null || pool.ProviderChain.Count == 0 || pool.ProviderChain.Any(string.IsNullOrWhiteSpace))
        {
            findings.Add(new("routing-contract", "error", pool.Name,
                "At least one non-empty task type and provider are required; configuration does not verify provider login."));
        }

        var valid = errorCount == findings.Count(f => f.Severity == "error");
        int? ceiling = valid ? Math.Min(size, laneLimit > 0 ? laneLimit : size) : null;
        int? local = ceiling.HasValue ? mode == "cloud" ? 0 : Math.Min(ceiling.Value, autoscaling is null ? size : maxLocal) : null;
        int? cloud = ceiling.HasValue ? mode == "local" ? 0 : Math.Min(ceiling.Value, maxBurst) : null;
        var requestedLocal = mode == "cloud" ? 0 : maxLocal;
        if (valid && autoscaling is not null && mode != "local" && (long)requestedLocal + maxBurst > ceiling)
        {
            findings.Add(new("aggregate-capacity", "warning", pool.Name,
                "Independent local/burst maxima exceed the aggregate pool ceiling. A future dispatcher must enforce a shared cap; " +
                "the current VMSS scale hook does not prove this."));
        }
        if (mode != "local" && maxBurst > 0)
        {
            findings.Add(new("cloud-transport", "warning", pool.Name,
                "Authenticated cross-host task/result transport and real Hermes bootstrap are not implemented by the VMSS capacity hook."));
            if (!string.Equals(burstTarget, "vmss", StringComparison.OrdinalIgnoreCase))
            {
                findings.Add(new("burst-target-mismatch", "warning", pool.Name,
                    $"Topology burstTarget is '{burstTarget ?? "unspecified"}', but scale-fleet.ps1 implements a VMSS capacity hook. " +
                    "An ARC controller is not established by that hook."));
            }
        }
        if (pool.Skills?.Contains("winui3-shell", StringComparer.Ordinal) == true ||
            pool.TaskTypes?.Any(t => t is "native_optimization" or "rendering" or "gui_authoring") == true)
        {
            findings.Add(new("native-toolchain", "info", pool.Name,
                "Verify the selected host's Windows SDK/MSVC and required GPU capabilities; skill names are not installed toolchains."));
        }

        return new FleetPoolReadiness
        {
            Pool = pool.Name,
            Board = board,
            Mode = mode,
            ConfiguredWorkerSlots = size,
            ConfiguredConcurrencyCeiling = ceiling,
            TaskTypes = pool.TaskTypes ?? Array.Empty<string>(),
            ProviderChain = pool.ProviderChain ?? Array.Empty<string>(),
            DeclaredTools = pool.Tools ?? Array.Empty<string>(),
            DeclaredSkills = pool.Skills ?? Array.Empty<string>(),
            DeclaredAgents = pool.Agents ?? Array.Empty<string>(),
            Placements = new[]
            {
                new FleetPlacementReadiness
                {
                    Location = "local", ConfiguredCeiling = local,
                    Transport = "same-host board JSON plus claim lock",
                    TransportState = local == 0 ? "disabled-by-policy" : "implemented-not-verified",
                    IdentityRequirement = "Host process identity (PID plus start time), native client sign-in, and explicit tool restrictions.",
                },
                new FleetPlacementReadiness
                {
                    Location = "cloud", ConfiguredCeiling = cloud,
                    Transport = "authenticated cross-host task/result queue",
                    TransportState = cloud == 0 ? "disabled-by-policy" : "not-implemented",
                    IdentityRequirement = "Separate runtime managed identity with narrowly scoped provider/Key Vault/data grants; " +
                        "GitHub deployment OIDC does not authenticate a worker.",
                },
            },
        };
    }

    private static FleetReadinessReport Report(
        IReadOnlyList<FleetPoolReadiness> pools, IReadOnlyList<FleetReadinessFinding> findings) => new()
        {
            Pools = pools, Findings = findings,
            ActivationStages = BuildStages(pools),
        };

    private static IReadOnlyList<FleetActivationStage> BuildStages(IReadOnlyList<FleetPoolReadiness> pools)
    {
        var local = pools.Any(p => p.Placements.Any(x => x.Location == "local" && x.ConfiguredCeiling > 0));
        var cloud = pools.Any(p => p.Placements.Any(x => x.Location == "cloud" && x.ConfiguredCeiling > 0));
        var stages = new List<FleetActivationStage>
            {
                new FleetActivationStage("context", Array.Empty<string>(),
                    "Reviewed source SHA, issue, correlation UUID, task owner and shared skill hash; an isolated worktree per writer."),
                new FleetActivationStage("knowledge", new[] { "context" },
                    "Source citations/hashes, classification and redaction decision for each knowledge input; prototypes are tagged simulation."),
                new FleetActivationStage("provider-and-tools", new[] { "context" },
                    "Actual native provider sign-in, host toolchain and enforced tool grants; names in the topology only declare capabilities."),
            };
        if (local)
        {
            stages.AddRange(new[]
            {
                new FleetActivationStage("local-board", new[] { "context" },
                    "Per-pool board and claim-lock path on the same host; task claim/expiry protocol verified."),
                new FleetActivationStage("local-worker", new[] { "local-board", "provider-and-tools" },
                    "Real Hermes process with PID/start-time identity and matching run/pool; a stub or reused PID is insufficient."),
                new FleetActivationStage("local-task-receipt", new[] { "local-worker", "knowledge" },
                    "A correlated real task claim and completion with source SHA, provider, result and terminal status."),
            });
        }
        if (cloud)
        {
            stages.AddRange(new[]
            {
                new FleetActivationStage("cloud-target", new[] { "context" },
                    "Reviewed tenant/subscription/resource group, one IaC owner, protected-environment deployment and returned resource receipt."),
                new FleetActivationStage("cloud-identity-and-transport", new[] { "cloud-target", "provider-and-tools" },
                    "Runtime managed identity and scoped grants; authenticated queue claim/result round-trip across hosts without secret values."),
                new FleetActivationStage("cloud-task-receipt", new[] { "cloud-identity-and-transport", "knowledge" },
                    "Real Hermes bootstrap, host/worker identity and correlated task completion; VMSS capacity or an empty instance-local board is insufficient."),
            });
        }
        foreach (var location in new[] { "local", "cloud" })
        {
            if ((location == "local" && !local) || (location == "cloud" && !cloud))
            {
                continue;
            }
            stages.Add(new FleetActivationStage($"{location}-organic-evaluation", new[] { $"{location}-task-receipt" },
                    "Organic provider outcomes with task/language scope and actual measurements. Keep fleet-lane, synthetic and absorption outcomes tagged; " +
                    "missing cost or quality is unknown. Learned recommendations remain advisory."));
        }
        return stages;
    }
}
