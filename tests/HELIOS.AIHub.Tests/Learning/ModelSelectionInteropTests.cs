using HELIOS.AIHub.Domain;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

public class ModelSelectionInteropTests
{
    private static readonly string[] Providers = ["frontier-provider", "cheap-provider", "fast-provider"];
    private static readonly string[] Models = ["big-model", "cheap-model", "quick-model"];
    private static readonly string[] Classes = ["frontier", "specialist", "fast"];
    private static readonly int[] ContextTokens = [500_000, 128_000, 64_000];
    private static readonly double[] InputCost = [15.0, 0.5, 0.1];
    private static readonly double[] OutputCost = [75.0, 2.0, 0.4];
    private static readonly string[] Speeds = ["slow", "medium", "fast"];
    private static readonly string[] Strengths =
        ["code_review,architecture_design", "code_review,code_generation", "code_review,inline_completion"];

    [Fact]
    public void SelectBestProvider_Cost_PicksCheapest()
    {
        var result = ModelSelectionInterop.SelectBestProvider(
            "code_review", "cost", Providers, Models, Classes, ContextTokens, InputCost, OutputCost, Speeds, Strengths);
        Assert.Equal("fast-provider", result);
    }

    [Fact]
    public void SelectBestProvider_Latency_PicksFastest()
    {
        var result = ModelSelectionInterop.SelectBestProvider(
            "code_review", "latency", Providers, Models, Classes, ContextTokens, InputCost, OutputCost, Speeds, Strengths);
        Assert.Equal("fast-provider", result);
    }

    [Fact]
    public void SelectBestProvider_Quality_PicksFrontier()
    {
        var result = ModelSelectionInterop.SelectBestProvider(
            "code_review", "quality", Providers, Models, Classes, ContextTokens, InputCost, OutputCost, Speeds, Strengths);
        Assert.Equal("frontier-provider", result);
    }

    [Fact]
    public void SelectBestProvider_UnknownTaskType_ReturnsEmpty()
    {
        var result = ModelSelectionInterop.SelectBestProvider(
            "no_such_task", "balanced", Providers, Models, Classes, ContextTokens, InputCost, OutputCost, Speeds, Strengths);
        Assert.Equal("", result);
    }

    [Fact]
    public void SelectBestProvider_RespectsTaskTypeStrengthFilter()
    {
        // architecture_design is only in frontier-provider's strengths.
        var result = ModelSelectionInterop.SelectBestProvider(
            "architecture_design", "cost", Providers, Models, Classes, ContextTokens, InputCost, OutputCost, Speeds, Strengths);
        Assert.Equal("frontier-provider", result);
    }
}
