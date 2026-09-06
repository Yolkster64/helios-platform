using HELIOS.Fabric;

namespace HELIOS.Fabric.Tests;

public sealed class FabricContractValidatorTests
{
    [Fact]
    public void Live_repository_contract_is_valid()
    {
        var report = new FabricContractValidator().Validate(FindRepositoryRoot());

        Assert.True(report.IsValid,
            string.Join(Environment.NewLine, report.Findings.Select(finding =>
                $"{finding.Code}: {finding.Message} ({finding.Path})")));
        Assert.NotEmpty(report.FileHashes);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "config", "fabric", "helios-fabric.v1.json")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Repository root not found from test output path.");
    }
}
