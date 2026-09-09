using HELIOS.Shell.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HELIOS.Shell.Views;

public sealed partial class ControlHomePage : Page
{
    public ControlHomePage()
    {
        ViewModel = App.GetService<ControlHomePageViewModel>();
        InitializeComponent();
    }

    public ControlHomePageViewModel ViewModel { get; }
    private void OnOpenAIHub(object sender, RoutedEventArgs e) => Frame.Navigate(typeof(AIHubPage));
    private void OnOpenFabric(object sender, RoutedEventArgs e) => Frame.Navigate(typeof(FabricControlPage));
}
