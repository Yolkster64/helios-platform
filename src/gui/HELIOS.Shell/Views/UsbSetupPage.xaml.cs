using HELIOS.Shell.ViewModels;
using Microsoft.UI.Xaml.Controls;

namespace HELIOS.Shell.Views;

public sealed partial class UsbSetupPage : Page
{
    public UsbSetupPage()
    {
        ViewModel = App.GetService<UsbSetupPageViewModel>();
        InitializeComponent();
    }

    public UsbSetupPageViewModel ViewModel { get; }
}
