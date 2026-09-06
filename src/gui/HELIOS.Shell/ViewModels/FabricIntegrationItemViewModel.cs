namespace HELIOS.Shell.ViewModels;

/// <summary>
/// Immutable readiness row for one HELIOS Fabric integration. The shell never stores
/// credential values; it displays only the readiness state and a sanitized detail.
/// </summary>
public sealed record FabricIntegrationItemViewModel(
    string Name,
    string Readiness,
    string Detail,
    string Scope);
