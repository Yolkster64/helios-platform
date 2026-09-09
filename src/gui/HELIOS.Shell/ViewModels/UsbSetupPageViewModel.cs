using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using HELIOS.AIHub.Setup;

namespace HELIOS.Shell.ViewModels;

public sealed record UsbPlanRow(string Title, string Detail);

public partial class UsbSetupPageViewModel(UsbSetupPlanner planner) : ObservableObject
{
    public IReadOnlyList<string> Profiles { get; } = Enum.GetValues<UsbSetupProfile>()
        .Select(UsbSetupPlanner.ProfileName).ToArray();
    public ObservableCollection<UsbPlanRow> Layout { get; } = [];
    public ObservableCollection<UsbPlanRow> Requirements { get; } = [];
    public ObservableCollection<UsbPlanRow> Diagnostics { get; } = [];

    [ObservableProperty] private int _profileIndex = (int)UsbSetupProfile.Core;
    [ObservableProperty] private string _deviceId = "";
    [ObservableProperty] private string _capacityMiB = "";
    [ObservableProperty] private string _mediaSizeMiB = "";
    [ObservableProperty] private string _largestFileMiB = "";
    [ObservableProperty] private bool _isRemovable;
    [ObservableProperty] private bool _isNotSystemDisk;
    [ObservableProperty] private bool _isNotBootDisk;
    [ObservableProperty] private bool _isWritable;
    [ObservableProperty] private bool _uefiConfirmed;
    [ObservableProperty] private bool _backupConfirmed;
    [ObservableProperty] private bool _imageVerified;
    [ObservableProperty] private string _planState = "Enter the USB details, then preview the plan. No connected disks have been scanned.";
    [ObservableProperty] private bool _hasPlan;

    [RelayCommand]
    private void Preview()
    {
        var plan = planner.CreatePlan(new UsbSetupRequest
        {
            Profile = (UsbSetupProfile)ProfileIndex,
            TargetDisk = new UsbDiskInventory
            {
                DeviceId = DeviceId,
                CapacityMiB = ParseSize(CapacityMiB),
                IsRemovable = IsRemovable ? true : null,
                IsSystemDisk = IsNotSystemDisk ? false : null,
                IsBootDisk = IsNotBootDisk ? false : null,
                IsReadOnly = IsWritable ? false : null,
            },
            Firmware = UefiConfirmed ? UsbFirmwareMode.Uefi : UsbFirmwareMode.Unknown,
            MediaSizeMiB = ParseSize(MediaSizeMiB),
            LargestFileMiB = ParseSize(LargestFileMiB),
            BackupConfirmed = BackupConfirmed,
            ImageVerified = ImageVerified,
        });
        Layout.Clear();
        Requirements.Clear();
        Diagnostics.Clear();
        foreach (var segment in plan.MediaLayout)
            Layout.Add(new($"{segment.Name} · {segment.SizeMiB:N0} MiB · {segment.FileSystem}", segment.Purpose));
        foreach (var item in plan.Requirements)
            Requirements.Add(new(item.Area, item.Requirement));
        foreach (var item in plan.Diagnostics)
            Diagnostics.Add(new(item.BlocksPlan ? "Needs input" : "Before future use", item.Message));
        HasPlan = true;
        PlanState = plan.IsValid
            ? $"{plan.Profile} media proposal for {plan.TargetDeviceId}. Review only; device details remain unverified."
            : "The plan needs more information. Review the missing details below; no media layout is available yet.";
    }

    protected override void OnPropertyChanged(PropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (e.PropertyName is nameof(ProfileIndex) or nameof(DeviceId) or nameof(CapacityMiB)
            or nameof(MediaSizeMiB) or nameof(LargestFileMiB) or nameof(IsRemovable)
            or nameof(IsNotSystemDisk) or nameof(IsNotBootDisk) or nameof(IsWritable)
            or nameof(UefiConfirmed) or nameof(BackupConfirmed) or nameof(ImageVerified))
        {
            // A changed disk or profile must not leave an old proposal on screen.
            Layout.Clear();
            Requirements.Clear();
            Diagnostics.Clear();
            HasPlan = false;
            PlanState = "Details changed. Preview again to refresh the proposal; no disk is being changed.";
        }
    }

    private static long ParseSize(string text) => long.TryParse(text, NumberStyles.None,
        CultureInfo.InvariantCulture, out var value) ? value : 0;
}
