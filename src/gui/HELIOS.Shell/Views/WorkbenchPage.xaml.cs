using System.Runtime.InteropServices;
using HELIOS.Shell.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HELIOS.Shell.Views;

public sealed partial class WorkbenchPage : Page
{
    private bool _initialized;

    public WorkbenchPage()
    {
        ViewModel = App.GetService<WorkbenchPageViewModel>();
        InitializeComponent();
        _initialized = true;
        ApplyPreviewTheme();
    }

    public WorkbenchPageViewModel ViewModel { get; }

    private void OnOpenModule(object sender, RoutedEventArgs args)
    {
        // Installed metadata supplies labels, never a type name, command or URI to execute.
        var page = ViewModel.SelectedModule?.Id switch
        {
            "home" => typeof(ControlHomePage),
            "aihub" => typeof(AIHubPage),
            "fabric" => typeof(FabricControlPage),
            "usb" => typeof(UsbSetupPage),
            _ => null,
        };
        if (page is not null) Frame.Navigate(page);
        else ThemePackChoice.Focus(FocusState.Programmatic);
    }

    private void OnPreviewThemeChanged(object sender, SelectionChangedEventArgs args)
    {
        if (_initialized) ApplyPreviewTheme();
    }

    private void ApplyPreviewTheme()
    {
        var pack = ThemePackChoice.SelectedIndex switch
        {
            1 => "Tokens.GitHubDark.xaml",
            2 => "Tokens.SolarLight.xaml",
            3 => "Tokens.HighContrast.xaml",
            _ => "Tokens.xaml",
        };
        try
        {
            var tokens = new ResourceDictionary { Source = new Uri($"ms-appx:///Themes/{pack}") };
            PreviewHost.Resources.MergedDictionaries.Clear();
            PreviewHost.Resources.MergedDictionaries.Add(tokens);
            PreviewHost.RequestedTheme = PreviewThemeChoice.SelectedIndex switch
            {
                1 => ElementTheme.Light,
                2 => ElementTheme.Dark,
                _ => ElementTheme.Default,
            };
            PreviewNotice.Text = "Palette applied to this sample surface only. Use a Windows contrast theme for a full accessibility check.";
        }
        catch (Exception ex) when (ex is COMException or ArgumentException or InvalidOperationException)
        {
            PreviewNotice.Text = "The packaged preview palette could not be loaded. Rebuild the Windows shell and check its theme resources.";
        }
    }

    private void OnSampleAction(object sender, RoutedEventArgs args)
        => SampleActionStatus.Text = "Sample action completed locally. No runtime action was requested.";
}
