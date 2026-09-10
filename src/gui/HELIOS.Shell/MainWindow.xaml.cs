using HELIOS.Shell.Helpers;
using HELIOS.Shell.Views;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Graphics;

namespace HELIOS.Shell;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "HELIOS Shell";
        AppWindow.Resize(new SizeInt32(1280, 800));
        if (Content is FrameworkElement root) ReadinessVisuals.Attach(root);
        ContentFrame.Navigate(typeof(AIHubPage));
        Nav.SelectedItem = AIHubNavItem;
    }

    private void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem { Tag: string tag }) return;
        var pageType = tag switch
        {
            "aihub" => typeof(AIHubPage),
            "fabric" => typeof(FabricControlPage),
            _ => null,
        };
        if (pageType is not null && ContentFrame.CurrentSourcePageType != pageType)
            ContentFrame.Navigate(pageType);
    }
}
