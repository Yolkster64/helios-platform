using HELIOS.AIHub.Learning;
using Xunit;

namespace HELIOS.AIHub.Tests.Learning;

/// <summary>
/// Pins how learned-routing evidence is keyed on (taskType, language): a language-less
/// route sees only language-less records (every legacy record included), a
/// language-qualified route sees its own language's records and falls back to the
/// language-less ones — never to another language's.
/// </summary>
public sealed class LanguageScopedHistoryTests
{
    private static RoutingOutcome Outcome(string provider, string? language) =>
        FakeLearningStore.Outcome("code_generation", provider, success: true) with { Language = language };

    private static readonly IReadOnlyList<RoutingOutcome> Mixed = new[]
    {
        Outcome("legacy-a", language: null),
        Outcome("fsharp-a", "fsharp"),
        Outcome("legacy-b", language: null),
        Outcome("python-a", "python"),
        Outcome("fsharp-b", "fsharp"),
    };

    [Fact]
    public void ForLanguage_Null_KeepsOnlyLanguagelessRecords_InOrder()
    {
        var scoped = ChainReorderEngine.ForLanguage(Mixed, language: null);

        Assert.Equal(new[] { "legacy-a", "legacy-b" }, scoped.Select(o => o.Provider));
    }

    [Fact]
    public void ForLanguage_Match_KeepsOnlyThatLanguage_InOrder()
    {
        var scoped = ChainReorderEngine.ForLanguage(Mixed, "fsharp");

        Assert.Equal(new[] { "fsharp-a", "fsharp-b" }, scoped.Select(o => o.Provider));
    }

    [Fact]
    public void ForLanguage_NoMatch_FallsBackToLanguagelessRecords_NeverAnotherLanguage()
    {
        var scoped = ChainReorderEngine.ForLanguage(Mixed, "cpp");

        Assert.Equal(new[] { "legacy-a", "legacy-b" }, scoped.Select(o => o.Provider));
    }

    [Fact]
    public void ForLanguage_NoMatchAndNoLanguageless_IsEmpty()
    {
        var onlyOtherLanguages = new[] { Outcome("fsharp-a", "fsharp"), Outcome("python-a", "python") };

        Assert.Empty(ChainReorderEngine.ForLanguage(onlyOtherLanguages, "cpp"));
    }

    [Fact]
    public void ForLanguage_IsExactOnTheNormalizedKey()
    {
        // Records carry the normalized key; scoping never re-normalizes, so a caller
        // must normalize before asking (AIHubService does). "F#" matches nothing and,
        // with no language-less records to fall back to, yields no evidence at all.
        var onlyNormalized = new[] { Outcome("fsharp-a", "fsharp") };

        Assert.Empty(ChainReorderEngine.ForLanguage(onlyNormalized, "F#"));
        Assert.Single(ChainReorderEngine.ForLanguage(onlyNormalized, "fsharp"));
    }

    [Fact]
    public void LearningKey_QualifiesOnlyWhenALanguageIsPresent()
    {
        Assert.Equal("code_generation", ChainReorderEngine.LearningKey("code_generation", null));
        Assert.Equal("code_generation:fsharp", ChainReorderEngine.LearningKey("code_generation", "fsharp"));
    }
}
