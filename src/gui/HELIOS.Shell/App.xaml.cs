using HELIOS.Shell.Services;
using HELIOS.Shell.ViewModels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;

namespace HELIOS.Shell;

/// <summary>
/// Application entry point. Owns the DI container (per the winui3-shell skill: view models
/// get services via constructor injection, composed here — no service-locator lookups in
/// code-behind beyond the one page-level <see cref="GetService{T}"/> call that WinUI's
/// parameterless-ctor Frame navigation forces).
/// </summary>
public partial class App : Application
{
    private Window? _window;

    public App()
    {
        Services = ConfigureServices();
        InitializeComponent();
    }

    /// <summary>The current <see cref="App"/> instance, typed.</summary>
    public static new App Current => (App)Application.Current;

    /// <summary>Application-scoped services, built once at startup.</summary>
    public IServiceProvider Services { get; }

    /// <summary>Resolves a registered service; used by pages to obtain their view model.</summary>
    public static T GetService<T>() where T : notnull => Current.Services.GetRequiredService<T>();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }

    private static ServiceProvider ConfigureServices()
    {
        var services = new ServiceCollection();

        // Shell rule (GUI_THEME_ANALYSIS.md): platform work remains behind service/view-model
        // boundaries. AI Hub uses the thin REST client; Fabric Control renders only local
        // readiness metadata and launches governed operator surfaces/commands.
        services.AddSingleton<AIHubApiClient>();

        // Transient: each page instance gets its own VM. AIHubPageViewModel is constructed
        // on the UI thread so it can capture the page's DispatcherQueue.
        services.AddTransient<AIHubPageViewModel>();
        services.AddTransient<FabricControlPageViewModel>();

        return services.BuildServiceProvider();
    }
}
