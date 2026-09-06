using HELIOS.Shell.Helpers;
using HELIOS.Shell.Views;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Graphics;

namespace HELIOS.Shell;

/// <summary>
/// Shell window: NavigationView on the left, a Frame hosting the pages. Windowing goes
/// through <see cref="Window.AppWindow"/> per the winui3-shell skill.
/// </summary>
public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        Title = "HELIOS Shell";
        AppWindow.Resize(new SizeInt32(1280, 800));

        // Stale-brush fix (GUI_UPGRADE_PLAN.md P1): keep the readiness brushes in sync
        // with the live theme. Window is not a FrameworkElement in WinUI 3, so the
        // subscription goes on the content root (the NavigationView).
        if (Content is FrameworkElement root)
        {
            ReadinessVisuals.Attach(root);
        }

        // Land on the provider dashboard. Fabric Control is available as the next
        // operator surface without replacing the existing AI Hub default.
        ContentFrame.Navigate(typeof(AIHubPage));
        Nav.SelectedItem = AIHubNavItem;
    }

    private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem { Tag: string tag })
        {
            return;
        }

        var pageType = tag switch
        {
            "aihub" => typeof(AIHubPage),
            "fabric" => typeof(FabricControlPage),
            _ => null,
        };

        if (pageType is not null && ContentFrame.CurrentSourcePageType != pageType)
        {
            ContentFrame.Navigate(pageType);
        }
    }
}
