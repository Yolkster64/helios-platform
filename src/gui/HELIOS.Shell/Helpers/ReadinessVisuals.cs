using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace HELIOS.Shell.Helpers;

/// <summary>
/// x:Bind function targets mapping a provider readiness string (the wire form of
/// HELIOS.AIHub's <c>ProviderReadiness</c>) to the semantic token brushes in
/// Themes/Tokens.xaml. Lives outside the view models so they stay free of XAML types.
/// </summary>
/// <remarks>
/// Stale-brush fix (GUI_UPGRADE_PLAN.md P1): <see cref="BrushFor"/> returns shared
/// mutable <see cref="SolidColorBrush"/> instances instead of snapshotting whatever
/// brush the theme dictionary held at bind time. <see cref="Attach"/> subscribes to the
/// visual root's <see cref="FrameworkElement.ActualThemeChanged"/> and to
/// <see cref="AccessibilitySettings.HighContrastChanged"/> (high-contrast toggles do
/// not change ActualTheme) and re-resolves the token colors into those instances, so
/// every bound element — including default OneTime x:Bind rows — recolors immediately
/// on a theme or contrast change with no refresh needed.
/// The same contract covers the P6 theme packs: after swapping the merged token
/// dictionary, call <see cref="Refresh(ElementTheme)"/> so no brush survives a pack
/// switch stale.
/// </remarks>
public static class ReadinessVisuals
{
    private static readonly SolidColorBrush Ready = new();
    private static readonly SolidColorBrush Degraded = new();
    private static readonly SolidColorBrush Unconfigured = new();
    // Cached once: contrast mode is a per-query property, and ActualTheme never
    // reports it (only Light/Dark), so ResolveColor asks this directly.
    private static readonly AccessibilitySettings Accessibility = new();
    private static bool _resolvedOnce;

    /// <summary>Shared, theme-tracking brush for a readiness state.</summary>
    public static Brush BrushFor(string readiness)
    {
        if (!_resolvedOnce)
        {
            // Defensive: bindings evaluated before Attach ran still get token colors
            // (resolved against the Default dictionary rather than a blank brush).
            Refresh(ElementTheme.Default);
        }

        return readiness switch
        {
            "Ready" => Ready,
            "Degraded" => Degraded,
            _ => Unconfigured,
        };
    }

    /// <summary>
    /// Binds the shared brushes to <paramref name="root"/>'s actual theme for the
    /// lifetime of the app. Call once from the main window on its content root
    /// (Window itself is not a FrameworkElement in WinUI 3).
    /// </summary>
    public static void Attach(FrameworkElement root)
    {
        root.ActualThemeChanged += OnActualThemeChanged;
        // A runtime high-contrast toggle does not raise ActualThemeChanged
        // (ActualTheme stays Light/Dark), so without this second subscription the
        // shared brushes would keep the previous palette until the next theme
        // change or restart (review finding). HighContrastChanged arrives off the
        // UI thread in desktop apps — marshal through the root's DispatcherQueue
        // before mutating brushes that live UI elements are painting with.
        Accessibility.HighContrastChanged += (_, _) =>
            root.DispatcherQueue.TryEnqueue(() => Refresh(root.ActualTheme));
        Refresh(root.ActualTheme);
    }

    /// <summary>
    /// Re-resolves the token colors for <paramref name="theme"/> into the shared
    /// brushes. Also the P6 pack-switch hook: swap the merged token dictionary, then
    /// call this so no brush survives the switch stale.
    /// </summary>
    public static void Refresh(ElementTheme theme)
    {
        Ready.Color = ResolveColor("ProviderReadyBrush", theme);
        Degraded.Color = ResolveColor("ProviderDegradedBrush", theme);
        Unconfigured.Color = ResolveColor("ProviderUnconfiguredBrush", theme);
        _resolvedOnce = true;
    }

    private static void OnActualThemeChanged(FrameworkElement sender, object args) =>
        Refresh(sender.ActualTheme);

    private static Color ResolveColor(string key, ElementTheme theme)
    {
        // WinUI theme-dictionary keys: "Light", "Default" (== dark), and
        // "HighContrast". ActualTheme only ever reports Light/Dark, so contrast mode
        // must be detected explicitly via AccessibilitySettings — without this the
        // HighContrast dictionary is unreachable (review finding: the app-level
        // fallback resolves the merged default, not the contrast dictionary).
        var themeKey = Accessibility.HighContrast
            ? "HighContrast"
            : theme == ElementTheme.Light ? "Light" : "Default";
        if (TryResolveFromThemeDictionaries(Application.Current.Resources, themeKey, key, out var color))
        {
            return color;
        }

        return Application.Current.Resources.TryGetValue(key, out var value)
            && value is SolidColorBrush brush ? brush.Color : default;
    }

    private static bool TryResolveFromThemeDictionaries(
        ResourceDictionary dictionary, string themeKey, string key, out Color color)
    {
        if (dictionary.ThemeDictionaries.TryGetValue(themeKey, out var themeCandidate)
            && themeCandidate is ResourceDictionary themeDictionary
            && themeDictionary.TryGetValue(key, out var value)
            && value is SolidColorBrush brush)
        {
            color = brush.Color;
            return true;
        }

        foreach (var merged in dictionary.MergedDictionaries)
        {
            if (TryResolveFromThemeDictionaries(merged, themeKey, key, out color))
            {
                return true;
            }
        }

        color = default;
        return false;
    }
}
