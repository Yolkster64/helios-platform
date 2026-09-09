using HELIOS.AIHub.Setup;
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
        var workbench = Environment.GetCommandLineArgs().Skip(1).Contains("--workbench", StringComparer.Ordinal);
        _window = new MainWindow(workbench);
        _window.Activate();
    }

    private static ServiceProvider ConfigureServices()
    {
        var services = new ServiceCollection();

        // Shell rule (GUI_THEME_ANALYSIS.md): no logic in the shell. The only service is
        // the thin REST client over helios-ai-api; the hub itself stays out of process.
        // USB planning shares pure contracts only; it has no I/O or device adapter.
        services.AddSingleton<AIHubApiClient>();
        services.AddSingleton<UsbSetupPlanner>();

        // Transient: each page instance gets its own VM, constructed on the UI thread so
        // it can capture the page's DispatcherQueue.
        services.AddTransient<AIHubPageViewModel>();
        services.AddTransient<ControlHomePageViewModel>();
        services.AddTransient<FabricControlPageViewModel>();
        services.AddTransient<UsbSetupPageViewModel>();
        services.AddTransient<WorkbenchPageViewModel>();

        return services.BuildServiceProvider();
    }
}
