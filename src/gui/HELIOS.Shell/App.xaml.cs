using HELIOS.Shell.Services;
using HELIOS.Shell.ViewModels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;

namespace HELIOS.Shell;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        Services = ConfigureServices();
        InitializeComponent();
    }

    public static new App Current => (App)Application.Current;
    public IServiceProvider Services { get; }
    public static T GetService<T>() where T : notnull => Current.Services.GetRequiredService<T>();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }

    private static ServiceProvider ConfigureServices()
    {
        var services = new ServiceCollection();
        services.AddSingleton<AIHubApiClient>();
        services.AddTransient<AIHubPageViewModel>();
        services.AddTransient<FabricControlPageViewModel>();
        return services.BuildServiceProvider();
    }
}
