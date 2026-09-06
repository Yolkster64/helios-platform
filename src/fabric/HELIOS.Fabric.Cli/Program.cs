using System.Security.Cryptography;
using System.Text.Json;
using HELIOS.Fabric;

var command = args.FirstOrDefault()?.ToLowerInvariant() ?? "validate";
var root = FindRepositoryRoot(
    args.Skip(1).FirstOrDefault(argument => !argument.StartsWith("--", StringComparison.Ordinal))
    ?? Directory.GetCurrentDirectory());
var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
{
    WriteIndented = true
};

return command switch
{
    "validate" => Validate(root, options),
    "plan" => Plan(root, options),
    "evidence" => Evidence(root, ResolveOutput(args), options),
    "help" or "--help" or "-h" => Help(),
    _ => Unknown(command)
};

static int Validate(string root, JsonSerializerOptions options)
{
    var report = new FabricContractValidator().Validate(root);
    Console.WriteLine(JsonSerializer.Serialize(report, options));
    return report.IsValid ? 0 : 1;
}

static int Plan(string root, JsonSerializerOptions options)
{
    var plan = new FabricActivationPlanBuilder().Build(root);
    Console.WriteLine(JsonSerializer.Serialize(plan, options));
    return plan.ProductionEnabled || plan.ApplyDefault ? 1 : 0;
}

static int Evidence(string root, string output, JsonSerializerOptions options)
{
    var validator = new FabricContractValidator();
    var report = validator.Validate(root);
    var plan = new FabricActivationPlanBuilder().Build(root);
    var payload = new
    {
        schemaVersion = 1,
        generatedAt = DateTimeOffset.UtcNow,
        externalMutationsPerformed = false,
        validation = report,
        activationPlan = plan
    };

    var directory = Path.GetFullPath(output);
    Directory.CreateDirectory(directory);
    var evidencePath = Path.Combine(directory, "helios-fabric-evidence.json");
    var bytes = JsonSerializer.SerializeToUtf8Bytes(payload, options);
    File.WriteAllBytes(evidencePath, bytes);
    var hash = Convert.ToHexStringLower(SHA256.HashData(bytes));
    File.WriteAllText(Path.Combine(directory, "SHA256SUMS"),
        $"{hash}  {Path.GetFileName(evidencePath)}{Environment.NewLine}");

    Console.WriteLine(JsonSerializer.Serialize(new
    {
        status = report.IsValid ? "passed" : "failed",
        evidencePath,
        sha256 = hash,
        externalMutationsPerformed = false
    }, options));
    return report.IsValid ? 0 : 1;
}

static string ResolveOutput(string[] args)
{
    var index = Array.IndexOf(args, "--output");
    return index >= 0 && index + 1 < args.Length
        ? args[index + 1]
        : Path.Combine(Directory.GetCurrentDirectory(), "artifacts", "helios-fabric");
}

static string FindRepositoryRoot(string startingPath)
{
    var current = new DirectoryInfo(Path.GetFullPath(startingPath));
    while (current is not null)
    {
        if (File.Exists(Path.Combine(current.FullName, "config", "fabric", "helios-fabric.v1.json")))
        {
            return current.FullName;
        }

        current = current.Parent;
    }

    throw new DirectoryNotFoundException(
        $"Could not find config/fabric/helios-fabric.v1.json from '{startingPath}'.");
}

static int Help()
{
    Console.WriteLine("HELIOS Fabric CLI");
    Console.WriteLine("  validate [repository-root]");
    Console.WriteLine("  plan [repository-root]");
    Console.WriteLine("  evidence [repository-root] [--output path]");
    Console.WriteLine("This CLI performs no external or machine mutation.");
    return 0;
}

static int Unknown(string command)
{
    Console.Error.WriteLine($"Unknown command '{command}'. Run 'help'.");
    return 2;
}
