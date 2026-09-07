using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
using HELIOS.AIHub.Learning;
using HELIOS.AIHub.Native;
using Xunit;

namespace HELIOS.AIHub.Tests;

public class AIHubServiceTests
{
    private static AIHubOptions EchoOnlyOptions() => new()
    {
        CliAgents = new List<CliAgentOptions>
        {
            new() { Name = "echo-agent", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
            new() { Name = "ghost-agent", Command = "no-such-cmd-xyz", ArgsTemplate = "{prompt}" },
        },
        Routing = new RoutingOptions
        {
            DefaultChain = new List<string> { "ghost-agent", "echo-agent" },
            TaskRouting = new Dictionary<string, List<string>>
            {
                ["echo_task"] = new() { "echo-agent" },
            },
        },
    };

    [Fact]
    public async Task AskAsync_UnknownProvider_ListsKnownOnes()
    {
        var hub = new AIHubService(EchoOnlyOptions());

        var result = await hub.AskAsync("q", provider: "nope");

        Assert.False(result.Success);
        Assert.Contains("Unknown provider 'nope'", result.Error);
        Assert.Contains("echo-agent", result.Error);
    }

    [Fact]
    public async Task RouteAsync_FallsThroughUnconfigured_ToWorkingProvider()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var hub = new AIHubService(EchoOnlyOptions());

        // Default chain: ghost-agent (unconfigured → soft failure) then echo-agent.
        var result = await hub.RouteAsync(taskType: null, "ping");

        Assert.True(result.Success, result.Error);
        Assert.Equal("echo-agent", result.Provider);
        Assert.Equal("ping", result.Text);
    }

    [Fact]
    public async Task RouteAsync_ExhaustedChain_ReportsEachProvidersRealReason()
    {
        var options = EchoOnlyOptions();
        options.Routing.DefaultChain = new List<string> { "ghost-agent" };
        var hub = new AIHubService(options);

        var result = await hub.RouteAsync(taskType: null, "ping");

        // The unconfigured hint must reach the caller, not "provider reported failure".
        Assert.False(result.Success);
        Assert.Contains("ghost-agent: CLI 'no-such-cmd-xyz' not found on PATH", result.Error);
        Assert.DoesNotContain("provider reported failure", result.Error);
    }

    [Fact]
    public async Task RouteAsync_UnknownTaskTypeWithEmptyDefault_ReturnsActionableError()
    {
        var options = EchoOnlyOptions();
        options.Routing.DefaultChain = new List<string> { "not-registered" };
        var hub = new AIHubService(options);

        var result = await hub.RouteAsync(taskType: null, "q");

        Assert.False(result.Success);
        Assert.Contains("defaultChain", result.Error);
    }

    [Fact]
    public async Task CompareAsync_ReturnsOneResultPerProvider()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var hub = new AIHubService(EchoOnlyOptions());

        var results = await hub.CompareAsync("ping", new[] { "echo-agent", "unknown-x" });

        Assert.Equal(2, results.Count);
        Assert.True(results.Single(r => r.Provider == "echo-agent").Success);
        Assert.False(results.Single(r => r.Provider == "unknown-x").Success);
    }

    [Fact]
    public async Task TandemAsync_RunsWholeChainConcurrently_AndReportsWinner()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var options = EchoOnlyOptions();
        // Give both a real chance to succeed so tandem has more than one result to pick from.
        options.Routing.TaskRouting["echo_task"] = new List<string> { "echo-agent", "ghost-agent" };
        var hub = new AIHubService(options);

        var tandem = await hub.TandemAsync("echo_task", "ping");

        Assert.Equal(2, tandem.Results.Count);
        Assert.NotNull(tandem.Winner);
        Assert.Equal("echo-agent", tandem.Winner!.Provider);
        Assert.True(tandem.Winner.Success);
    }

    [Fact]
    public async Task TandemAsync_EmptyChain_ReturnsNoResultsAndNoWinner()
    {
        var options = EchoOnlyOptions();
        options.Routing.DefaultChain = new List<string>(); // no fallback either
        var hub = new AIHubService(options);

        var tandem = await hub.TandemAsync("no_such_task", "ping");

        Assert.Empty(tandem.Results);
        Assert.Null(tandem.Winner);
    }

    [Fact]
    public void GetStatus_ReportsReadinessAndHints()
    {
        var hub = new AIHubService(EchoOnlyOptions());

        var status = hub.GetStatus();

        var ghost = status.Single(p => p.Name == "ghost-agent");
        Assert.Equal(ProviderReadiness.Unconfigured, ghost.Readiness);
        Assert.Contains("not found on PATH", ghost.Detail);
        Assert.All(status, p => Assert.Equal("cli", p.Kind));
    }

    [Fact]
    public async Task TandemAsync_FiltersProviderWhosePromptExceedsContextWindow()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var options = new AIHubOptions
        {
            CliAgents = new List<CliAgentOptions>
            {
                new() { Name = "small-agent", Command = "echo", ArgsTemplate = "{prompt}", Model = "tiny-model", TimeoutSeconds = 10 },
                new() { Name = "big-agent", Command = "echo", ArgsTemplate = "{prompt}", Model = "huge-model", TimeoutSeconds = 10 },
            },
            Routing = new RoutingOptions
            {
                DefaultChain = new List<string> { "small-agent", "big-agent" },
            },
        };
        var catalog = new ModelCatalog(new List<ModelProfile>
        {
            new() { Provider = "small-agent", Model = "tiny-model", ContextTokens = 100 },
            new() { Provider = "big-agent", Model = "huge-model", ContextTokens = 1_000_000 },
        });
        var hub = new AIHubService(options, catalog: catalog);

        // ~500 estimated tokens either way (byte-count heuristic or native estimator):
        // fits big-agent's window (995,904 usable) but not small-agent's (75 usable).
        var prompt = new string('a', 2000);

        var tandem = await hub.TandemAsync("unrouted_task", prompt);

        Assert.Single(tandem.Results);
        Assert.Equal("big-agent", tandem.Results[0].Provider);
    }

    [Fact]
    public async Task TandemAsync_AllProvidersExceedWindow_FallsBackToFullChain()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var options = new AIHubOptions
        {
            CliAgents = new List<CliAgentOptions>
            {
                new() { Name = "small-agent", Command = "echo", ArgsTemplate = "{prompt}", Model = "tiny-model", TimeoutSeconds = 10 },
            },
            Routing = new RoutingOptions
            {
                DefaultChain = new List<string> { "small-agent" },
            },
        };
        var catalog = new ModelCatalog(new List<ModelProfile>
        {
            new() { Provider = "small-agent", Model = "tiny-model", ContextTokens = 100 },
        });
        var hub = new AIHubService(options, catalog: catalog);

        // Losing the only candidate is worse than trying it anyway — filterFits must
        // return the chain unfiltered when nothing fits.
        var tandem = await hub.TandemAsync("unrouted_task", new string('a', 2000));

        Assert.Single(tandem.Results);
        Assert.Equal("small-agent", tandem.Results[0].Provider);
    }

    [Fact]
    public void FlagDuplicates_LeavesUniqueResultsUnmarked()
    {
        var results = new[]
        {
            new ChatResult(true, "The quick brown fox jumps over the lazy dog", "a", "m", TimeSpan.Zero),
            new ChatResult(true, "Completely unrelated text about ocean tides and weather patterns", "b", "m", TimeSpan.Zero),
        };

        var flagged = AIHubService.FlagDuplicates(results);

        Assert.All(flagged, r => Assert.Null(r.DuplicateOfProvider));
    }

    [Fact]
    public void FlagDuplicates_SkipsFailedAndBlankResults_WithoutThrowing()
    {
        var results = new[]
        {
            new ChatResult(false, null, "a", "m", TimeSpan.Zero, Error: "boom"),
            new ChatResult(true, "   ", "b", "m", TimeSpan.Zero),
        };

        var flagged = AIHubService.FlagDuplicates(results);

        Assert.Equal(2, flagged.Count);
        Assert.All(flagged, r => Assert.Null(r.DuplicateOfProvider));
    }

    /// <summary>
    /// True when the C++ spoke is loadable (built via scripts/build/build-native.sh and
    /// copied to output). Native-path tests no-op without it so local keyless/toolless
    /// runs stay green; CI asserts the library's presence so they always run there.
    /// </summary>
    private static bool NativeLibraryPresent()
    {
        try
        {
            NativeMethods.AbiVersion();
            return true;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
    }

    [Fact]
    public void NativeLibrary_WhenPresent_ReportsExpectedAbiVersion()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        Assert.Equal(NativeMethods.ExpectedAbiVersion, NativeMethods.AbiVersion());
    }

    [Fact]
    public void FlagDuplicates_WithNativeLibrary_MarksDuplicateOfEarlierProvider()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        var results = new[]
        {
            new ChatResult(true, "The quick brown fox jumps over the lazy dog", "a", "m", TimeSpan.Zero),
            new ChatResult(true, "Completely unrelated text about ocean tides and weather patterns", "b", "m", TimeSpan.Zero),
            new ChatResult(true, "the QUICK brown fox jumps over the LAZY dog", "c", "m", TimeSpan.Zero),
        };

        var flagged = AIHubService.FlagDuplicates(results);

        Assert.Null(flagged[0].DuplicateOfProvider);
        Assert.Null(flagged[1].DuplicateOfProvider);
        Assert.Equal("a", flagged[2].DuplicateOfProvider);
    }

    [Fact]
    public void FlagDuplicates_HashCollisionOnShortReplies_IsNotADuplicate()
    {
        if (!NativeLibraryPresent())
        {
            return;
        }

        // "no" and "approved" land in the same 64-bucket hash slot, so their vectors
        // are identical — the token-level verification must keep them apart.
        var results = new[]
        {
            new ChatResult(true, "no", "a", "m", TimeSpan.Zero),
            new ChatResult(true, "approved", "b", "m", TimeSpan.Zero),
        };

        var flagged = AIHubService.FlagDuplicates(results);

        Assert.Null(flagged[0].DuplicateOfProvider);
        Assert.Null(flagged[1].DuplicateOfProvider);
    }

    [Fact]
    public void HashedFrequencyVector_IsDeterministic_AndOrderAndCaseInsensitive()
    {
        var a = new float[8];
        var b = new float[8];

        AIHubService.HashedFrequencyVector("Hello world, hello WORLD!", a);
        AIHubService.HashedFrequencyVector("world hello, World hello", b);

        Assert.Equal(a, b);
    }

    [Fact]
    public void HashedFrequencyVector_DifferentTextProducesDifferentVector()
    {
        var a = new float[16];
        var b = new float[16];

        AIHubService.HashedFrequencyVector("apples and oranges are fruit", a);
        AIHubService.HashedFrequencyVector("quantum entanglement in superconductors", b);

        Assert.NotEqual(a, b);
    }

    [Fact]
    public void HashedFrequencyVector_EmptyText_StaysZero()
    {
        var vector = new float[8];

        AIHubService.HashedFrequencyVector(" ... !!! ", vector);

        Assert.All(vector, v => Assert.Equal(0f, v));
    }

    /// <summary>Two echo agents plus adaptive routing on, so injected history steers order.</summary>
    private static AIHubOptions AdaptiveEchoOptions() => new()
    {
        CliAgents = new List<CliAgentOptions>
        {
            new() { Name = "alpha", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
            new() { Name = "beta", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
        },
        Routing = new RoutingOptions
        {
            TaskRouting = new Dictionary<string, List<string>>
            {
                ["echo_task"] = new() { "alpha", "beta" },
            },
        },
        Learning = new LearningOptions { Enabled = true, AdaptiveRouting = true, HistoryWindow = 200 },
    };

    /// <summary>
    /// 6 alpha failures + 5 beta successes: both over the linear confidence threshold
    /// (5 attempts) yet under the neural learner's 12-sample minimum, so the learned
    /// order is deterministic with or without the native library.
    /// </summary>
    private static List<RoutingOutcome> HistoryFavoringBeta(string? source)
    {
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 6; i++)
        {
            history.Add(FakeLearningStore.Outcome("echo_task", "alpha", success: false, source));
        }
        for (var i = 0; i < 5; i++)
        {
            history.Add(FakeLearningStore.Outcome("echo_task", "beta", success: true, source));
        }
        return history;
    }

    [Fact]
    public async Task TandemAsync_AdaptiveRouting_LearnsFromOrganicHistory()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // Control for the fleet-lane test below: the same signal UNTAGGED must reorder,
        // proving the exclusion assertion is not vacuously green.
        var store = new FakeLearningStore(HistoryFavoringBeta(source: null));
        var hub = new AIHubService(AdaptiveEchoOptions(), learning: store);

        var tandem = await hub.TandemAsync("echo_task", "ping");

        Assert.NotNull(tandem.Winner);
        Assert.Equal("beta", tandem.Winner!.Provider);
    }

    [Fact]
    public async Task RouteAsync_AdaptiveRouting_LanguageEvidence_SurvivesAnotherLanguageFloodingTheWindow()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // The 200 newest outcomes (one whole history window) are python and favour
        // alpha; the fsharp evidence favouring beta lies entirely outside that shared
        // window. Because the store scopes before it caps, the fsharp route still
        // learns beta first — a shared window scoped afterwards would see no fsharp
        // evidence and keep the configured order (alpha).
        var history = new List<RoutingOutcome>();
        for (var i = 0; i < 200; i++)
        {
            var alphaWins = i % 2 == 0;
            history.Add(FakeLearningStore.Outcome("echo_task", alphaWins ? "alpha" : "beta", success: alphaWins)
                with { Language = "python" });
        }
        history.AddRange(HistoryFavoringBeta(source: null).Select(o => o with { Language = "fsharp" }));
        var store = new FakeLearningStore(history);
        var hub = new AIHubService(AdaptiveEchoOptions(), learning: store);

        var routed = await hub.RouteAsync(new HubRouteRequest("echo_task", "ping", Language: "fsharp"));

        Assert.True(routed.Success, routed.Error);
        Assert.Equal("beta", routed.Provider);
    }

    [Fact]
    public async Task RouteAsync_AdaptiveRouting_LanguagelessRoute_IgnoresOtherLanguagesEvidence()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // Every record carries a language, so a language-less route has no evidence of
        // its own and keeps the configured order — it never borrows another language's.
        var history = HistoryFavoringBeta(source: null).Select(o => o with { Language = "fsharp" }).ToList();
        var hub = new AIHubService(AdaptiveEchoOptions(), learning: new FakeLearningStore(history));

        var routed = await hub.RouteAsync(new HubRouteRequest("echo_task", "ping"));

        Assert.True(routed.Success, routed.Error);
        Assert.Equal("alpha", routed.Provider);
    }

    [Fact]
    public async Task TandemAsync_AdaptiveRouting_IgnoresFleetLaneRecords()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // Identical signal tagged source=fleet-lane: lane outcomes are not provider
        // outcomes and must never steer chains, so the configured order (alpha first)
        // decides the winner.
        var store = new FakeLearningStore(HistoryFavoringBeta(source: "fleet-lane"));
        var hub = new AIHubService(AdaptiveEchoOptions(), learning: store);

        var tandem = await hub.TandemAsync("echo_task", "ping");

        Assert.NotNull(tandem.Winner);
        Assert.Equal("alpha", tandem.Winner!.Provider);
    }

    /// <summary>Two echo agents; the fsharp-qualified chain reverses the bare order.</summary>
    private static AIHubOptions LanguageEchoOptions() => new()
    {
        CliAgents = new List<CliAgentOptions>
        {
            new() { Name = "alpha", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
            new() { Name = "beta", Command = "echo", ArgsTemplate = "{prompt}", TimeoutSeconds = 10 },
        },
        Routing = new RoutingOptions
        {
            TaskRouting = new Dictionary<string, List<string>>
            {
                ["echo_task"] = new() { "alpha", "beta" },
                ["echo_task:fsharp"] = new() { "beta", "alpha" },
            },
        },
        Learning = new LearningOptions { Enabled = true },
    };

    [Fact]
    public async Task RouteAsync_WithLanguage_UsesQualifiedChain_AndRecordsNormalizedLanguage()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var store = new FakeLearningStore();
        var hub = new AIHubService(LanguageEchoOptions(), learning: store);

        var result = await hub.RouteAsync(new HubRouteRequest("echo_task", "ping", Language: " F# "));

        Assert.True(result.Success, result.Error);
        Assert.Equal("beta", result.Provider);
        var outcome = Assert.Single(store.Recorded);
        Assert.Equal("echo_task", outcome.TaskType);
        Assert.Equal("fsharp", outcome.Language);
    }

    [Fact]
    public async Task RouteAsync_WithoutLanguage_UsesBareChain_AndRecordsNoLanguage()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var store = new FakeLearningStore();
        var hub = new AIHubService(LanguageEchoOptions(), learning: store);

        // The pre-language overload: identical chain, identical record shape.
        var result = await hub.RouteAsync("echo_task", "ping");

        Assert.True(result.Success, result.Error);
        Assert.Equal("alpha", result.Provider);
        var outcome = Assert.Single(store.Recorded);
        Assert.Null(outcome.Language);
    }

    [Fact]
    public async Task RouteAsync_LanguageWithoutQualifiedChain_FallsBackToBareChain_ButStillRecordsLanguage()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        var store = new FakeLearningStore();
        var hub = new AIHubService(LanguageEchoOptions(), learning: store);

        var result = await hub.RouteAsync(new HubRouteRequest("echo_task", "ping", Language: "python"));

        Assert.True(result.Success, result.Error);
        Assert.Equal("alpha", result.Provider);
        // The evidence belongs to the (echo_task, python) key even though the bare chain
        // served it — that is what a future echo_task:python chain will learn from.
        Assert.Equal("python", Assert.Single(store.Recorded).Language);
    }

    [Fact]
    public async Task RouteAsync_QualifiedKeyAsTaskType_IsCanonicalized_BeforeChainLookupAndRecording()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // helios_task_routing_get, /v1/routing and helios-ai routing list the table's
        // keys verbatim, so a caller may pass "echo_task:fsharp" as the task type with
        // no language. Served as-is it would walk the qualified chain but record
        // TaskType="echo_task:fsharp", Language=null — a second evidence bucket the
        // (taskType, language) learning reads never see. It must split into
        // ("echo_task", "fsharp") before the lookup, the record and the learning read.
        var store = new FakeLearningStore();
        var hub = new AIHubService(LanguageEchoOptions(), learning: store);

        var result = await hub.RouteAsync(new HubRouteRequest("echo_task:fsharp", "ping"));

        Assert.True(result.Success, result.Error);
        Assert.Equal("beta", result.Provider); // the fsharp-qualified chain, exactly as before
        var outcome = Assert.Single(store.Recorded);
        Assert.Equal("echo_task", outcome.TaskType);
        Assert.Equal("fsharp", outcome.Language);
    }

    [Fact]
    public async Task RouteAsync_QualifiedLookingTaskType_WithoutAMatchingKey_IsLeftAlone()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // No "echo_task:python" chain exists, so the string is an ordinary (unknown)
        // task type: the default chain serves it and the outcome records it verbatim,
        // exactly as before — canonicalization never invents a language.
        var options = LanguageEchoOptions();
        options.Routing.DefaultChain = new List<string> { "alpha" };
        var store = new FakeLearningStore();
        var hub = new AIHubService(options, learning: store);

        var result = await hub.RouteAsync(new HubRouteRequest("echo_task:python", "ping"));

        Assert.True(result.Success, result.Error);
        Assert.Equal("alpha", result.Provider);
        var outcome = Assert.Single(store.Recorded);
        Assert.Equal("echo_task:python", outcome.TaskType);
        Assert.Null(outcome.Language);
    }

    [Fact]
    public async Task RouteAsync_AdaptiveRouting_LearnsOnlyFromMatchingLanguageHistory()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // The beta-favoring signal tagged language=fsharp reorders an fsharp route …
        var history = HistoryFavoringBeta(source: null).Select(o => o with { Language = "fsharp" }).ToList();
        var hub = new AIHubService(AdaptiveEchoOptions(), learning: new FakeLearningStore(history));

        var fsharp = await hub.RouteAsync(new HubRouteRequest("echo_task", "ping", Language: "fsharp"));
        Assert.True(fsharp.Success, fsharp.Error);
        Assert.Equal("beta", fsharp.Provider);

        // … but neither a language-less route nor another language's route: with no
        // matching (or language-less) evidence the configured order stands.
        var bare = await hub.RouteAsync("echo_task", "ping");
        Assert.Equal("alpha", bare.Provider);
        var python = await hub.RouteAsync(new HubRouteRequest("echo_task", "ping", Language: "python"));
        Assert.Equal("alpha", python.Provider);
    }

    [Fact]
    public async Task TandemAsync_AdaptiveRouting_IgnoresLanguageTaggedHistory()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        // Tandem is language-less: the same signal tagged fsharp must not steer it, so
        // the configured order (alpha first) decides the winner.
        var history = HistoryFavoringBeta(source: null).Select(o => o with { Language = "fsharp" }).ToList();
        var hub = new AIHubService(AdaptiveEchoOptions(), learning: new FakeLearningStore(history));

        var tandem = await hub.TandemAsync("echo_task", "ping");

        Assert.NotNull(tandem.Winner);
        Assert.Equal("alpha", tandem.Winner!.Provider);
    }

    [Fact]
    public void ShippedConfig_BuildsHub_WithAllProvidersRegistered()
    {
        var path = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.NotNull(path);

        var hub = new AIHubService(AIHubOptions.Load(path!));
        var status = hub.GetStatus();

        // 8 API providers + 5 CLI agents from config/aihub.json.
        Assert.Equal(13, status.Count);
        // Nothing requiring secrets should be Ready in a keyless environment.
        Assert.Equal(ProviderReadiness.Unconfigured,
            status.Single(p => p.Name == "anthropic").Readiness);
        // anthropic-foundry keys off ANTHROPIC_FOUNDRY_RESOURCE (unset in CI), so it must
        // surface as Unconfigured with a hint naming that variable — never Ready via the
        // Entra fallback and never an exception. An operator who has run
        // Connect-ClaudeFoundry.ps1 locally legitimately has it set; skip only that check.
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ANTHROPIC_FOUNDRY_RESOURCE")))
        {
            var foundry = status.Single(p => p.Name == "anthropic-foundry");
            Assert.Equal(ProviderReadiness.Unconfigured, foundry.Readiness);
            Assert.Contains("ANTHROPIC_FOUNDRY_RESOURCE", foundry.Detail);
        }
    }
}
