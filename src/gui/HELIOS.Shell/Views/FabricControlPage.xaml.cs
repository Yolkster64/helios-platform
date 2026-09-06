using HELIOS.Shell.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HELIOS.Shell.Views;

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
            ViewModel.RefreshCommand.Execute(null);
    }
}
