using CommunityToolkit.Mvvm.ComponentModel;
using HELIOS.Shell.Services;

namespace HELIOS.Shell.ViewModels;

/// <summary>Offline examples and installed map metadata. No API client or environment access.</summary>
public partial class WorkbenchPageViewModel : ObservableObject
{
    private readonly GuiWorkbenchCatalog _catalog = GuiWorkbenchCatalog.Load();
    public IReadOnlyList<GuiWorkbenchModule> Modules => _catalog.Modules;
    public bool HasModules => _catalog.IsAvailable;
    public string CatalogStatus => _catalog.Status;
    public string WorkflowDisplay => string.Join("\n", _catalog.Workflows);
    public string ReleaseBoundary => _catalog.ReleaseBoundary;
    public string TestCommand => "pwsh -NoProfile -File ./connect.ps1 test gui";
    public string BuildCommand => "msbuild src/gui/HELIOS.Shell.sln /restore /p:Configuration=Release /p:Platform=x64";
    public IReadOnlyList<string> FixtureNames { get; } = ["Unconfigured", "Ready", "Degraded", "Long text"];

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedModule))]
    private int _selectedModuleIndex;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FixtureHeading))]
    [NotifyPropertyChangedFor(nameof(FixtureState))]
    [NotifyPropertyChangedFor(nameof(FixtureSubtitle))]
    [NotifyPropertyChangedFor(nameof(FixtureDetail))]
    private int _fixtureIndex;

    public GuiWorkbenchModule? SelectedModule => SelectedModuleIndex >= 0 && SelectedModuleIndex < Modules.Count
        ? Modules[SelectedModuleIndex] : null;
    public string FixtureHeading => FixtureIndex == 3
        ? "Sample provider with a deliberately long display name for narrow-window and text-wrapping checks"
        : "Sample provider · local fixture";
    public string FixtureState => FixtureIndex switch { 1 => "Ready", 2 => "Degraded", _ => "Unconfigured" };
    public string FixtureSubtitle => "Example model · no model is loaded or called";
    public string FixtureDetail => FixtureIndex switch
    {
        1 => "Sample success state only. This is not evidence of a working connection or available worker.",
        2 => "Sample timeout state. Check how the same control communicates a recoverable failure without relying on color.",
        3 => "This deliberately long fixture is here to exercise wrapping, scrolling, keyboard access and contrast at smaller window sizes. It is fixed local text and never includes a real provider response, key, account identifier or endpoint.",
        _ => "Sample missing-configuration state. No authentication settings have been read or changed.",
    };
}
