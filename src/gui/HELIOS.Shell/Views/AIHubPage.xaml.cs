using HELIOS.Shell.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HELIOS.Shell.Views;

/// <summary>
/// AI Hub provider dashboard — the AIHubWindow revival (GUI_THEME_ANALYSIS.md). All state
/// lives in <see cref="ViewModel"/>; this code-behind only resolves it (Frame navigation
/// requires a parameterless ctor, so constructor injection stops at the page boundary)
/// and kicks the initial refresh.
/// </summary>
public sealed partial class AIHubPage : Page
{
    public AIHubPage()
    {
        // Resolved on the UI thread, so the VM can capture this page's DispatcherQueue.
        ViewModel = App.GetService<AIHubPageViewModel>();
        InitializeComponent();
        Loaded += OnLoaded;
    }

    /// <summary>Get-only, typed root for x:Bind (winui3-shell skill).</summary>
    public AIHubPageViewModel ViewModel { get; }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Loaded -= OnLoaded; // initial refresh only once per page instance
        if (ViewModel.RefreshCommand.CanExecute(null))
        {
            ViewModel.RefreshCommand.Execute(null);
        }
    }
}
