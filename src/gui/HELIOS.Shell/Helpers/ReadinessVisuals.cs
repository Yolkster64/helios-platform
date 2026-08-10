using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace HELIOS.Shell.Helpers;

/// <summary>
/// x:Bind function targets mapping a provider readiness string (the wire form of
/// HELIOS.AIHub's <c>ProviderReadiness</c>) to the semantic token brushes in
/// Themes/Tokens.xaml. Lives outside the view models so they stay free of XAML types.
/// </summary>
/// <remarks>
/// The lookup resolves against the theme active at bind time; rows are rebuilt on every
/// refresh, so a stale brush survives at most one refresh after a theme change. Live
/// re-resolution (ThemeResource inside per-state templates) is a PR6 polish item.
/// </remarks>
public static class ReadinessVisuals
{
    public static Brush BrushFor(string readiness) =>
        (Brush)Application.Current.Resources[readiness switch
        {
            "Ready" => "ProviderReadyBrush",
            "Degraded" => "ProviderDegradedBrush",
            _ => "ProviderUnconfiguredBrush",
        }];
}
