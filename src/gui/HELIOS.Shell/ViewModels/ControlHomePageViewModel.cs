using System.Runtime.InteropServices;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using HELIOS.Shell.Services;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;

namespace HELIOS.Shell.ViewModels;

public partial class ControlHomePageViewModel : ObservableObject
{
    private readonly ControlProjectLinks _links = ControlProjectLinks.Load();

    public ControlHomePageViewModel()
    {
        _statusMessage = _links.IsAvailable
            ? "One project, one shared setup path. Choose your next step."
            : "Some project links are unavailable. Restore config/control-project.json and rebuild the shell.";
    }

    [ObservableProperty] private string _statusMessage;
    public string CheckCommand => "pwsh -NoProfile -File ./connect.ps1 status";
    public bool HasRepository => _links.Repository is not null;
    public bool HasLinear => _links.Linear is not null;
    public bool HasSlack => _links.Slack is not null;

    [RelayCommand] private Task OpenRepositoryAsync() => OpenAsync(_links.Repository, "GitHub");
    [RelayCommand] private Task OpenLinearAsync() => OpenAsync(_links.Linear, "HELIOS project");
    [RelayCommand] private Task OpenSlackAsync() => OpenAsync(_links.Slack, "Slack canvas");
    [RelayCommand] private Task OpenGuideAsync() => OpenAsync(_links.Guide, "setup guide");

    [RelayCommand]
    private void CopyCheck()
    {
        try
        {
            var package = new DataPackage();
            package.SetText(CheckCommand);
            Clipboard.SetContent(package);
            StatusMessage = "Check copied. Run it from the repository folder in PowerShell 7; it reports local configuration without signing in.";
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or ArgumentException)
        {
            StatusMessage = "Clipboard unavailable. Select and copy the check command below.";
        }
    }

    private async Task OpenAsync(Uri? uri, string label)
    {
        if (uri is null)
        {
            StatusMessage = "This project link is unavailable in the installed manifest.";
            return;
        }
        try
        {
            StatusMessage = await Launcher.LaunchUriAsync(uri)
                ? $"Opened {label}." : $"Could not open {label}. Check your default browser.";
        }
        catch (Exception ex) when (ex is COMException or InvalidOperationException or ArgumentException)
        {
            StatusMessage = $"Could not open {label}. Check your default browser.";
        }
    }
}
