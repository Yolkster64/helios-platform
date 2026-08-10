using HELIOS.AIHub.Abstractions;
using HELIOS.AIHub.Configuration;
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

    [Fact]
    public void ShippedConfig_BuildsHub_WithAllProvidersRegistered()
    {
        var path = AIHubOptions.FindConfigFile(AppContext.BaseDirectory);
        Assert.NotNull(path);

        var hub = new AIHubService(AIHubOptions.Load(path!));
        var status = hub.GetStatus();

        // 6 API providers + 5 CLI agents from config/aihub.json.
        Assert.Equal(11, status.Count);
        // Nothing requiring secrets should be Ready in a keyless environment.
        Assert.Equal(ProviderReadiness.Unconfigured,
            status.Single(p => p.Name == "anthropic").Readiness);
    }
}
