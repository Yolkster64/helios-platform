using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HELIOS.Shell.Controls;

/// <summary>Shared presentation only. The caller supplies status; this control performs no probes.</summary>
public sealed partial class StatusCard : UserControl
{
    public StatusCard()
    {
        InitializeComponent();
        Loaded += (_, _) => UpdateVisuals();
        ActualThemeChanged += (_, _) => UpdateVisuals();
    }

    public static readonly DependencyProperty HeadingProperty = DependencyProperty.Register(
        nameof(Heading), typeof(string), typeof(StatusCard), new PropertyMetadata(""));
    public static readonly DependencyProperty SubtitleProperty = DependencyProperty.Register(
        nameof(Subtitle), typeof(string), typeof(StatusCard), new PropertyMetadata(""));
    public static readonly DependencyProperty DetailProperty = DependencyProperty.Register(
        nameof(Detail), typeof(string), typeof(StatusCard), new PropertyMetadata("", OnVisualChanged));
    public static readonly DependencyProperty StateProperty = DependencyProperty.Register(
        nameof(State), typeof(string), typeof(StatusCard), new PropertyMetadata("Unconfigured", OnVisualChanged));

    public string Heading { get => (string)GetValue(HeadingProperty); set => SetValue(HeadingProperty, value); }
    public string Subtitle { get => (string)GetValue(SubtitleProperty); set => SetValue(SubtitleProperty, value); }
    public string Detail { get => (string)GetValue(DetailProperty); set => SetValue(DetailProperty, value); }
    public string State { get => (string)GetValue(StateProperty); set => SetValue(StateProperty, value); }

    private static void OnVisualChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
        => ((StatusCard)sender).UpdateVisuals();

    private void UpdateVisuals()
    {
        if (DetailText is null) return;
        DetailText.Visibility = string.IsNullOrWhiteSpace(Detail) ? Visibility.Collapsed : Visibility.Visible;
        VisualStateManager.GoToState(this, State is "Ready" or "Degraded" ? State : "Unconfigured", false);
    }
}
