using System.ComponentModel;
using System.Text;
using System.Text.Json;
using HELIOS.AIHub.Learning;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace HELIOS.Mcp;

/// <summary>Caller-supplied evidence, one pure calculator, no file/store/provider access.</summary>
[McpServerToolType]
public static class HeliosComboAnalysisTools
{
    public const int MaxEvidenceBytes = 32 * 1024;

    [McpServerTool(Name = "helios_combo_analyze", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Offline AIHub outcome analysis: provenance, success uncertainty and observed quality/cost/latency tradeoffs. Accepts JSONL evidence supplied by the caller, never reads host files or calls a provider. Source-tagged synthetic/advisory rows do not train or rank live providers. Pairwise combo performance stays unknown without paired evidence.")]
    public static string Analyze(
        [Description("Exported outcome JSONL text, at most 32 KiB UTF-8. Do not include prompts, secrets or private correspondence.")] string outcomesJsonl,
        [Description("Exact bare task type to analyze, for example code_review.")] string taskType,
        [Description("Exact optional language scope; omission selects unqualified outcomes.")] string? language = null,
        [Description("Newest matching organic outcomes to analyze, 1 to 200.")] int limit = 200)
    {
        if (outcomesJsonl is null || outcomesJsonl.Length > MaxEvidenceBytes ||
            Encoding.UTF8.GetByteCount(outcomesJsonl) > MaxEvidenceBytes || limit is < 1 or > 200)
            throw new McpException("Use at most 32 KiB of outcome evidence and a limit from 1 to 200.");
        try
        {
            var report = ComboAnalysisService.AnalyzeJsonl(Encoding.UTF8.GetBytes(outcomesJsonl), taskType, language, limit);
            return JsonSerializer.Serialize(report);
        }
        catch (Exception ex) when (ex is ArgumentException or JsonException or InvalidDataException)
        {
            throw new McpException("Outcome evidence or task/language scope is invalid; inspect the local combo-analysis guide.");
        }
    }
}
