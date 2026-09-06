using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace HELIOS.Fabric;

public enum FabricFindingSeverity
{
    Information,
    Warning,
    Error
}

public sealed record FabricValidationFinding(
    FabricFindingSeverity Severity,
    string Code,
    string Message,
    string? Path = null);

public sealed record FabricContractValidationReport(
    string RepositoryRoot,
    DateTimeOffset GeneratedAt,
    IReadOnlyList<FabricValidationFinding> Findings,
    IReadOnlyDictionary<string, string> FileHashes)
{
    public bool IsValid => Findings.All(finding => finding.Severity != FabricFindingSeverity.Error);
}

/// <summary>Side-effect-free validator for the canonical HELIOS fabric files.</summary>
public sealed partial class FabricContractValidator
{
    private static readonly string[] RequiredFiles =
    [
        "config/fabric/helios-fabric.v1.json",
        "config/connectors/helios-fabric.connections.v1.json",
        "config/agents/helios-fabric-roles.v1.json",
        "config/providers/helios-model-providers.v1.json",
        "config/devops/azure-devops-wif.v1.json",
        "config/sharepoint/governance-publication.v1.json",
        "config/collaboration/slack-linear-routing.v1.json",
        "config/github/repository-topology.v1.json",
        "config/github/environments.v1.json",
        "config/github/runners.v1.json",
        "config/claude/helios-claude-policy.v1.json"
    ];

    public FabricContractValidationReport Validate(string repositoryRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(repositoryRoot);
        var root = Path.GetFullPath(repositoryRoot);
        var findings = new List<FabricValidationFinding>();
        var hashes = new SortedDictionary<string, string>(StringComparer.Ordinal);
        var documents = new Dictionary<string, JsonDocument>(StringComparer.Ordinal);

        try
        {
            foreach (var relativePath in RequiredFiles)
            {
                var fullPath = Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar));
                if (!File.Exists(fullPath))
                {
                    findings.Add(Error("FABRIC001", "Required fabric file is missing.", relativePath));
                    continue;
                }

                var bytes = File.ReadAllBytes(fullPath);
                hashes[relativePath] = Convert.ToHexStringLower(SHA256.HashData(bytes));
                try
                {
                    documents[relativePath] = JsonDocument.Parse(bytes);
                }
                catch (JsonException exception)
                {
                    findings.Add(Error("FABRIC002", $"Invalid JSON: {exception.Message}", relativePath));
                }

                var text = Encoding.UTF8.GetString(bytes);
                if (LikelyCredentialRegex().IsMatch(text))
                {
                    findings.Add(Error("FABRIC003", "A likely credential value is embedded in a fabric file.", relativePath));
                }
            }

            ValidateAuthority(documents, findings);
            ValidateSafety(documents, findings);
            ValidateConnections(documents, findings);
            ValidateRoles(documents, findings);
            ValidateProviders(documents, findings);
            ValidateCrossPlaneTargets(documents, findings);
        }
        finally
        {
            foreach (var document in documents.Values)
            {
                document.Dispose();
            }
        }

        return new FabricContractValidationReport(
            root,
            DateTimeOffset.UtcNow,
            findings,
            hashes);
    }

    private static void ValidateAuthority(
        IReadOnlyDictionary<string, JsonDocument> documents,
        ICollection<FabricValidationFinding> findings)
    {
        if (!TryRoot(documents, "config/fabric/helios-fabric.v1.json", out var root))
        {
            return;
        }

        CheckString(root, "currentAuthority", "repository", "Yolkster64/helios-platform", "FABRIC010", findings);
        CheckString(root, "targetTopology", "coreRepository", "Yolkster64/helios-control", "FABRIC011", findings);
        CheckString(root, "targetTopology", "guiRepository", "Yolkster64/helios-gui", "FABRIC012", findings);
        CheckString(root, "desktop", "framework", "WinUI 3", "FABRIC013", findings);
        CheckString(root, "desktop", "xamlNamespace", "Microsoft.UI.Xaml", "FABRIC014", findings);
        CheckString(root, "desktop", "compositionNamespace", "Microsoft.UI.Composition", "FABRIC015", findings);
    }

    private static void ValidateSafety(
        IReadOnlyDictionary<string, JsonDocument> documents,
        ICollection<FabricValidationFinding> findings)
    {
        if (!TryRoot(documents, "config/fabric/helios-fabric.v1.json", out var root) ||
            !root.TryGetProperty("safety", out var safety))
        {
            return;
        }

        string[] falseKeys =
        [
            "productionEnabled", "applyDefault", "automaticRepositoryMerge",
            "automaticAzureDeployment", "automaticTenantConsent", "automaticRbacMutation",
            "automaticSecretWrite", "automaticDiskOrFirmwareMutation"
        ];

        foreach (var key in falseKeys)
        {
            if (!safety.TryGetProperty(key, out var value) || value.ValueKind != JsonValueKind.False)
            {
                findings.Add(Error("FABRIC020", $"Safety flag '{key}' must be false.",
                    "config/fabric/helios-fabric.v1.json"));
            }
        }
    }

    private static void ValidateConnections(
        IReadOnlyDictionary<string, JsonDocument> documents,
        ICollection<FabricValidationFinding> findings)
    {
        ValidateUniqueRows(
            documents,
            "config/connectors/helios-fabric.connections.v1.json",
            "connections",
            "id",
            "FABRIC030",
            findings,
            row => HasNonEmpty(row, "authority") && HasNonEmpty(row, "writePolicy") && HasNonEmpty(row, "healthCheck"));
    }

    private static void ValidateRoles(
        IReadOnlyDictionary<string, JsonDocument> documents,
        ICollection<FabricValidationFinding> findings)
    {
        ValidateUniqueRows(
            documents,
            "config/agents/helios-fabric-roles.v1.json",
            "roles",
            "id",
            "FABRIC040",
            findings,
            row => HasNonEmptyArray(row, "allowed") && HasNonEmptyArray(row, "denied"));
    }

    private static void ValidateProviders(
        IReadOnlyDictionary<string, JsonDocument> documents,
        ICollection<FabricValidationFinding> findings)
    {
        ValidateUniqueRows(
            documents,
            "config/providers/helios-model-providers.v1.json",
            "providers",
            "id",
            "FABRIC050",
            findings,
            row => HasNonEmptyArray(row, "modes") && HasNonEmptyArray(row, "allowed") && HasNonEmptyArray(row, "denied"));
    }

    private static void ValidateCrossPlaneTargets(
        IReadOnlyDictionary<string, JsonDocument> documents,
        ICollection<FabricValidationFinding> findings)
    {
        if (!TryRoot(documents, "config/fabric/helios-fabric.v1.json", out var fabric) ||
            !TryRoot(documents, "config/collaboration/slack-linear-routing.v1.json", out var collaboration) ||
            !TryRoot(documents, "config/sharepoint/governance-publication.v1.json", out var sharePoint) ||
            !TryRoot(documents, "config/devops/azure-devops-wif.v1.json", out var devOps))
        {
            return;
        }

        var fabricSlack = fabric.GetProperty("collaboration").GetProperty("slack");
        var routeSlack = collaboration.GetProperty("slack");
        CompareString(fabricSlack, routeSlack, "workspaceId", "FABRIC060", findings);
        CompareString(fabricSlack, routeSlack, "conversationId", "FABRIC061", findings);

        var fabricSharePoint = fabric.GetProperty("collaboration").GetProperty("sharePoint");
        CompareString(fabricSharePoint, sharePoint, "hostname", "FABRIC062", findings);
        CompareString(fabricSharePoint, sharePoint, "sitePath", "FABRIC063", findings);

        var targetCore = fabric.GetProperty("targetTopology").GetProperty("coreRepository").GetString();
        var devOpsTarget = devOps.GetProperty("repositoryTarget").GetString();
        if (!StringComparer.Ordinal.Equals(targetCore, devOpsTarget))
        {
            findings.Add(Error("FABRIC064", "Azure DevOps repository target differs from the fabric core target."));
        }

        if (devOps.GetProperty("permissions").GetProperty("deploymentAuthority").GetBoolean())
        {
            findings.Add(Error("FABRIC065", "Azure DevOps must not be an independent deployment authority."));
        }
    }

    private static void ValidateUniqueRows(
        IReadOnlyDictionary<string, JsonDocument> documents,
        string path,
        string arrayName,
        string idName,
        string code,
        ICollection<FabricValidationFinding> findings,
        Func<JsonElement, bool> rowValidator)
    {
        if (!TryRoot(documents, path, out var root) ||
            !root.TryGetProperty(arrayName, out var rows) ||
            rows.ValueKind != JsonValueKind.Array)
        {
            findings.Add(Error(code, $"Array '{arrayName}' is missing.", path));
            return;
        }

        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var row in rows.EnumerateArray())
        {
            var id = row.TryGetProperty(idName, out var idElement) ? idElement.GetString() : null;
            if (string.IsNullOrWhiteSpace(id) || !ids.Add(id))
            {
                findings.Add(Error(code, $"Missing or duplicate {idName}: '{id}'.", path));
            }

            if (!rowValidator(row))
            {
                findings.Add(Error(code, $"Entry '{id}' is missing required policy fields.", path));
            }
        }
    }

    private static bool TryRoot(
        IReadOnlyDictionary<string, JsonDocument> documents,
        string path,
        out JsonElement root)
    {
        if (documents.TryGetValue(path, out var document))
        {
            root = document.RootElement;
            return true;
        }

        root = default;
        return false;
    }

    private static void CheckString(
        JsonElement root,
        string objectName,
        string propertyName,
        string expected,
        string code,
        ICollection<FabricValidationFinding> findings)
    {
        if (!root.TryGetProperty(objectName, out var owner) ||
            !owner.TryGetProperty(propertyName, out var value) ||
            !StringComparer.Ordinal.Equals(value.GetString(), expected))
        {
            findings.Add(Error(code, $"{objectName}.{propertyName} must equal '{expected}'."));
        }
    }

    private static void CompareString(
        JsonElement left,
        JsonElement right,
        string property,
        string code,
        ICollection<FabricValidationFinding> findings)
    {
        var leftValue = left.TryGetProperty(property, out var leftElement) ? leftElement.GetString() : null;
        var rightValue = right.TryGetProperty(property, out var rightElement) ? rightElement.GetString() : null;
        if (!StringComparer.Ordinal.Equals(leftValue, rightValue))
        {
            findings.Add(Error(code, $"Cross-plane property '{property}' differs."));
        }
    }

    private static bool HasNonEmpty(JsonElement row, string property) =>
        row.TryGetProperty(property, out var value) &&
        value.ValueKind == JsonValueKind.String &&
        !string.IsNullOrWhiteSpace(value.GetString());

    private static bool HasNonEmptyArray(JsonElement row, string property) =>
        row.TryGetProperty(property, out var value) &&
        value.ValueKind == JsonValueKind.Array &&
        value.GetArrayLength() > 0;

    private static FabricValidationFinding Error(string code, string message, string? path = null) =>
        new(FabricFindingSeverity.Error, code, message, path);

    [GeneratedRegex(@"\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})\b", RegexOptions.CultureInvariant)]
    private static partial Regex LikelyCredentialRegex();
}
