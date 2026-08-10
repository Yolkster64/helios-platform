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

        // Land on the dashboard: select the nav item and navigate the frame directly
        // (SelectionChanged does not fire for a programmatic pre-layout selection on
        // all WinUI versions, so don't rely on it for the initial page).
        Nav.SelectedItem = AIHubNavItem;
        ContentFrame.Navigate(typeof(AIHubPage));
    }

    private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem { Tag: string tag })
        {
            return;
        }

        // Only the AI Hub page exists in this bootstrap; Routing/Fleet items are disabled.
        if (tag == "aihub" && ContentFrame.CurrentSourcePageType != typeof(AIHubPage))
        {
            ContentFrame.Navigate(typeof(AIHubPage));
        }
    }
}
