using HELIOS.Shell.Helpers;
using HELIOS.Shell.Views;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
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

        ContentFrame.Navigate(typeof(ControlHomePage));
        Nav.SelectedItem = HomeNavItem;
    }

    private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem { Tag: string tag })
        {
            return;
        }

        var page = tag switch
        {
            "home" => typeof(ControlHomePage),
            "aihub" => typeof(AIHubPage),
            "fabric" => typeof(FabricControlPage),
            _ => null,
        };
        if (page is not null && ContentFrame.CurrentSourcePageType != page)
        {
            ContentFrame.Navigate(page);
        }
    }

    private void OnContentFrameNavigated(object sender, NavigationEventArgs args)
    {
        // Home shortcuts and navigation-pane clicks share one selection state.
        Nav.SelectedItem = args.SourcePageType == typeof(ControlHomePage) ? HomeNavItem
            : args.SourcePageType == typeof(FabricControlPage) ? FabricNavItem : AIHubNavItem;
    }
}
