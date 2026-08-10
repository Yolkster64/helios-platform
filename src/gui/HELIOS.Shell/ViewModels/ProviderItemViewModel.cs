using HELIOS.Shell.Services;

namespace HELIOS.Shell.ViewModels;

/// <summary>
/// Immutable list item for one provider row on the AI Hub dashboard. Rows are replaced
/// wholesale on refresh (the collection mutates, the items do not), so a plain record —
/// no change notification — is enough and x:Bind's default OneTime mode is correct.
/// </summary>
public sealed record ProviderItemViewModel(
    string Name,
    string Kind,
    string? Model,
    string Readiness,
    string? Detail)
{
    public static ProviderItemViewModel From(ProviderStatusDto dto) =>
        new(dto.Name, dto.Kind, dto.Model, dto.Readiness, dto.Detail);

    /// <summary>Model name, or a dash when the provider has no model configured.</summary>
    public string ModelDisplay => string.IsNullOrWhiteSpace(Model) ? "—" : Model;

    /// <summary>Detail hint (e.g. the missing env var for Unconfigured), or empty.</summary>
    public string DetailDisplay => Detail ?? string.Empty;

    public bool HasDetail => !string.IsNullOrWhiteSpace(Detail);
}
