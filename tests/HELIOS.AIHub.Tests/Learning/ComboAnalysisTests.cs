using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

public sealed class ComboAnalysisTests
{
    [Theory]
    [InlineData(0, 0, 0, 1)]
    [InlineData(0, 10, 0, 0.2775327998628892)]
    [InlineData(10, 10, 0.7224672001371107, 1)]
    [InlineData(5, 10, 0.236593090512564, 0.763406909487436)]
    public void Wilson_MatchesReferenceArithmetic(int successes, int attempts, double lower, double upper)
    {
        var interval = ComboAnalysisService.Wilson95(successes, attempts);
        Assert.Equal(lower, interval.Lower, 12);
        Assert.Equal(upper, interval.Upper, 12);
    }

    [Fact]
    public void Wilson_MoreEvidenceNarrowsInterval_WithoutPerfectCertainty()
    {
        var little = ComboAnalysisService.Wilson95(5, 5);
        var more = ComboAnalysisService.Wilson95(50, 50);
        Assert.True(more.Lower > little.Lower);
        Assert.True(more.Lower < 1);
        Assert.Throws<ArgumentOutOfRangeException>(() => ComboAnalysisService.Wilson95(2, 1));
    }

    [Fact]
    public void EmptySnapshot_ReportsUnknownEvidence_NoInventedCandidate()
    {
        var result = Analyze();
        Assert.Empty(result.Candidates);
        Assert.Null(result.WindowStart);
        Assert.Contains(result.EvidenceGaps, g => g.Contains("No organic outcomes"));
        Assert.Contains(result.EvidenceGaps, g => g.Contains("complementarity"));
    }

    [Fact]
    public void UnknownCostsAndQuality_NeverBecomeFreeOrSuccessfulQuality()
    {
        var result = Analyze(Row("a") with { CostUsd = 0, Quality = null });
        var candidate = Assert.Single(result.Candidates);
        Assert.Equal(0, candidate.PositiveCostSamples);
        Assert.Null(candidate.MeanPositiveCostUsd);
        Assert.Null(candidate.MeanQuality);
        Assert.False(candidate.CompleteTradeoffEvidence);
        Assert.Null(candidate.OnObservedParetoFrontier);
    }

    [Fact]
    public void ScopeAndSourcePrecedeWindow_ModelsAndPoolsStaySeparate()
    {
        var rows = new[]
        {
            Row("a"), Row("a") with { OutcomeId = "second", Model = "m2" },
            Row("a") with { OutcomeId = "pool", Pool = "xcore-code" },
            Row("a") with { OutcomeId = "language", Language = "python" },
            Row("a") with { OutcomeId = "task", TaskType = "review" },
            Row("a") with { OutcomeId = "source", Source = "fleet-lane", Timestamp = DateTimeOffset.UtcNow },
        };
        var result = Analyze(rows);
        Assert.Equal(3, result.ScopedOrganicRows);
        Assert.Equal(3, result.Candidates.Count);
        Assert.Equal(1, result.AdvisorySourceRows["fleet-lane"]);
        Assert.DoesNotContain(result.Candidates.SelectMany(c => c.OutcomeIds), id => id == "source");
    }

    [Fact]
    public void RepeatedImportsDeduplicate_ConflictingIdsAreExcluded()
    {
        var result = Analyze(Row("a"), Row("a"),
            Row("b"), Row("b") with { Success = false });
        Assert.Equal(1, result.DuplicateRows);
        Assert.Equal(2, result.ConflictingRows);
        Assert.Equal(1, Assert.Single(result.Candidates).Attempts);
        Assert.Contains(result.EvidenceGaps, g => g.Contains("Conflicting outcome IDs"));
    }

    [Fact]
    public void LegacyRowsRetained_IdentityGapVisible()
    {
        var result = Analyze(Row("a") with { OutcomeId = null }, Row("a") with { OutcomeId = null });
        Assert.Equal(2, Assert.Single(result.Candidates).MissingOutcomeIds);
        Assert.Contains(result.EvidenceGaps, g => g.Contains("cannot be reliably deduplicated"));
    }

    [Fact]
    public void Pareto_RespectsEveryDimension_AndDoesNotCompareIncompleteCandidate()
    {
        var result = Analyze(
            Row("best") with { Quality = .9, CostUsd = .1, LatencyMs = 20 },
            Row("dominated") with { Quality = .8, CostUsd = .2, LatencyMs = 30 },
            Row("tradeoff") with { Quality = 1, CostUsd = .3, LatencyMs = 40 },
            Row("unknown") with { CostUsd = 0 });
        var byProvider = result.Candidates.ToDictionary(c => c.Provider);
        Assert.True(byProvider["best"].OnObservedParetoFrontier);
        Assert.False(byProvider["dominated"].OnObservedParetoFrontier);
        Assert.True(byProvider["tradeoff"].OnObservedParetoFrontier);
        Assert.Null(byProvider["unknown"].OnObservedParetoFrontier);
    }

    [Fact]
    public void LanguageHasNoFallback_AndWindowSelectsNewest()
    {
        var snapshot = Bytes(Row("old"), Row("new") with { Timestamp = Row("old").Timestamp.AddSeconds(1) });
        Assert.Empty(ComboAnalysisService.AnalyzeJsonl(snapshot, "code_generation", "python").Candidates);
        var report = ComboAnalysisService.AnalyzeJsonl(snapshot, "code_generation", limit: 1);
        Assert.True(report.WindowTruncated);
        Assert.Equal("new", Assert.Single(report.Candidates).Provider);
    }

    [Fact]
    public void ExactSnapshotHashAndReportAreDeterministic()
    {
        var snapshot = Bytes(Row("a"));
        var first = ComboAnalysisService.AnalyzeJsonl(snapshot, "code_generation");
        var second = ComboAnalysisService.AnalyzeJsonl(snapshot, "code_generation");
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(snapshot)), first.SnapshotSha256);
        Assert.Equal(JsonSerializer.Serialize(first), JsonSerializer.Serialize(second));
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"success\":true}")]
    [InlineData("null")]
    [InlineData("not-json secret-value")]
    public void MalformedRowsFailClosed_WithoutEchoingContent(string text)
    {
        var error = Assert.Throws<ArgumentException>(() =>
            ComboAnalysisService.AnalyzeJsonl(Encoding.UTF8.GetBytes(text), "code_generation"));
        Assert.Contains("line 1", error.Message);
        Assert.DoesNotContain("secret-value", error.Message);
    }

    [Fact]
    public void DuplicateJsonKeysAndInvalidNumbersAreRejected()
    {
        var text = JsonSerializer.Serialize(Row("a"));
        Assert.Throws<ArgumentException>(() => ComboAnalysisService.AnalyzeJsonl(
            Encoding.UTF8.GetBytes(text.Replace("\"success\":true", "\"success\":false,\"success\":true")), "code_generation"));
        Assert.Throws<ArgumentException>(() => Analyze(Row("a") with { CostUsd = -1 }));
        Assert.Throws<ArgumentException>(() => Analyze(Row("a") with { Quality = 1.1 }));
        Assert.Throws<ArgumentException>(() => ComboAnalysisService.AnalyzeJsonl(Bytes(Row("a")), "code_generation", limit: 0));
        Assert.Throws<ArgumentException>(() => ComboAnalysisService.AnalyzeJsonl(
            Encoding.UTF8.GetBytes(text.Replace("\"source\"", "\"Source\"")), "code_generation"));
    }

    [Fact]
    public void InvalidUtf8AndOversizedSnapshotsFailWithoutDataEcho()
    {
        var invalid = Assert.Throws<ArgumentException>(() =>
            ComboAnalysisService.AnalyzeJsonl(new byte[] { 0xff }, "code_generation"));
        Assert.Contains("not valid UTF-8", invalid.Message);
        Assert.Throws<ArgumentException>(() => ComboAnalysisService.AnalyzeJsonl(
            new byte[ComboAnalysisService.MaxSnapshotBytes + 1], "code_generation"));
    }

    [Fact]
    public void SourceRecordsDoNotCrowdOrganicWindow()
    {
        var rows = Enumerable.Range(0, 5).Select(i => Row("advisory") with
        {
            OutcomeId = "external" + i, Source = "absorption-benchmark",
            Timestamp = Row("a").Timestamp.AddMinutes(i + 1),
        }).Append(Row("organic")).ToArray();
        var result = ComboAnalysisService.AnalyzeJsonl(Bytes(rows), "code_generation", limit: 1);
        Assert.Equal("organic", Assert.Single(result.Candidates).Provider);
        Assert.Equal(5, result.AdvisorySourceRows["absorption-benchmark"]);
        Assert.False(result.WindowTruncated);
    }

    private static ComboAnalysisReport Analyze(params RoutingOutcome[] rows) =>
        ComboAnalysisService.AnalyzeJsonl(Bytes(rows), "code_generation");

    internal static byte[] Bytes(params RoutingOutcome[] rows) =>
        Encoding.UTF8.GetBytes(string.Join('\n', rows.Select(row => JsonSerializer.Serialize(row))));

    internal static RoutingOutcome Row(string provider) => new()
    {
        OutcomeId = provider, TaskType = "code_generation", Provider = provider, Model = "m1",
        Timestamp = DateTimeOffset.Parse("2026-09-09T00:00:00Z"),
        Success = true, LatencyMs = 100, CostUsd = .01, Quality = .8,
    };
}
