using HELIOS.Shell.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HELIOS.Shell.Views;

/// <summary>
/// HELIOS Fabric operator surface. State and commands live in the view model; this
/// code-behind only resolves the VM for Frame navigation and triggers the first refresh.
/// </summary>
public sealed partial class FabricControlPage : Page
{
    public FabricControlPage()
    {
        ViewModel = App.GetService<FabricControlPageViewModel>();
        InitializeComponent();
        Loaded += OnLoaded;
    }

    public FabricControlPageViewModel ViewModel { get; }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Loaded -= OnLoaded;
        if (ViewModel.RefreshCommand.CanExecute(null))
        {
            ViewModel.RefreshCommand.Execute(null);
        }
    }
}
