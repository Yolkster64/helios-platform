namespace HELIOS.AIHub.Setup;

public enum UsbSetupProfile { Sysadmin, Developer, Studio, Gamer, Core, AiServer }
public enum UsbFirmwareMode { Unknown, Uefi, Legacy }

/// <summary>Caller-supplied inventory, never discovered or verified by this planner.</summary>
public sealed record UsbDiskInventory
{
    public string DeviceId { get; init; } = "";
    public long CapacityMiB { get; init; }
    public bool? IsRemovable { get; init; }
    public bool? IsSystemDisk { get; init; }
    public bool? IsBootDisk { get; init; }
    public bool? IsReadOnly { get; init; }
}

public sealed record UsbSetupRequest
{
    public UsbSetupProfile Profile { get; init; } = UsbSetupProfile.Core;
    public UsbDiskInventory? TargetDisk { get; init; }
    public UsbFirmwareMode Firmware { get; init; }
    public long MediaSizeMiB { get; init; }
    public long LargestFileMiB { get; init; }
    public bool BackupConfirmed { get; init; }
    public bool ImageVerified { get; init; }
}

public sealed record UsbLayoutSegment(string Name, string FileSystem, long SizeMiB, string Purpose);
public sealed record UsbSetupRequirement(string Area, string Requirement);
public sealed record UsbSetupDiagnostic(string Code, string Message, bool BlocksPlan);

public sealed record UsbSetupPlan(
    string Profile,
    string TargetDeviceId,
    IReadOnlyList<UsbLayoutSegment> MediaLayout,
    IReadOnlyList<UsbSetupRequirement> Requirements,
    IReadOnlyList<UsbSetupDiagnostic> Diagnostics)
{
    public string InventorySource => "caller-supplied; not verified against a live disk";
    public bool IsValid => Diagnostics.All(item => !item.BlocksPlan);
    public string Status => IsValid ? "review-only" : "needs-input";
    // No execution authority or disk-writing adapter exists in this vertical slice.
    public bool CanExecute => false;
}

/// <summary>
/// Pure installation-media planning. No I/O, process execution, credentials, disk
/// enumeration or device writes. Host storage requirements never become USB partitions.
/// </summary>
public sealed class UsbSetupPlanner
{
    public const long MinimumCapacityMiB = 8192;
    public const long MaximumCapacityMiB = 16L * 1024 * 1024;
    public const long MaximumMediaPartitionMiB = 32768; // Conservative HELIOS policy, not a FAT32 filesystem limit.
    private const long LayoutReserveMiB = 8;
    private const long MediaHeadroomMiB = 1024;

    public UsbSetupPlan CreatePlan(UsbSetupRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var diagnostics = new List<UsbSetupDiagnostic>();
        var requirements = new List<UsbSetupRequirement>();
        var layout = new List<UsbLayoutSegment>();
        void Block(string code, string message) => diagnostics.Add(new(code, message, true));
        void Need(string code, string message) => diagnostics.Add(new(code, message, false));

        if (!Enum.IsDefined(typeof(UsbSetupProfile), request.Profile))
            Block("profile.invalid", "Choose Sysadmin, Developer, Studio, Gamer, Core or AI Server.");
        var disk = request.TargetDisk;
        var id = disk?.DeviceId?.Trim() ?? "";
        if (id.Length == 0 || id.Length > 128 || id.Any(char.IsControl)
            || (id.Length is 2 or 3 && char.IsLetter(id[0]) && id[1] == ':'))
            Block("disk.identity", "Supply the exact physical device ID or serial, not a drive letter or volume label.");
        if (disk is null)
        {
            Block("disk.missing", "Supply disk inventory before planning. No disk has been discovered or selected automatically.");
        }
        else
        {
            if (disk.CapacityMiB < MinimumCapacityMiB || disk.CapacityMiB > MaximumCapacityMiB)
                Block("disk.capacity", "Supply a USB capacity between 8 GiB and 16 TiB, measured in MiB.");
            if (disk.IsRemovable != true)
                Block("disk.removable", "The target must be explicitly identified as removable media.");
            if (disk.IsSystemDisk != false)
                Block("disk.system", "The target must be explicitly confirmed not to contain the current system.");
            if (disk.IsBootDisk != false)
                Block("disk.boot", "The target must be explicitly confirmed not to be the current boot disk.");
            if (disk.IsReadOnly != false)
                Block("disk.readonly", "The target's writable status must be supplied and must not be read-only.");
        }
        if (request.Firmware != UsbFirmwareMode.Uefi)
            Block("boot.uefi", "This media proposal supports UEFI only. Confirm UEFI support on the destination computer.");
        if (request.MediaSizeMiB <= 0 || request.MediaSizeMiB > MaximumMediaPartitionMiB - MediaHeadroomMiB)
            Block("media.size", "Supply the complete extracted installer size, between 1 and 31744 MiB. Larger media needs a separately reviewed layout.");
        if (request.LargestFileMiB <= 0 || request.LargestFileMiB > request.MediaSizeMiB)
            Block("media.largest-file", "Supply the largest extracted file size; it must be positive and no larger than the complete media.");
        if (!request.BackupConfirmed)
            Need("backup.required", "Back up the target and verify the backup before a future disk-write review.");
        if (!request.ImageVerified)
            Need("image.required", "Obtain complete official installation media and verify its source and integrity before use.");
        if (request.LargestFileMiB >= 4096)
            Block("media.split-required", "FAT32 cannot hold a file of 4 GiB or more. Verify that oversized files are supported WIM images, split them with the supported image tool and recheck the media; arbitrary large files require another layout.");
        Need("execution.unavailable", "Planning only. A separately reviewed Windows media writer, fresh device inventory and explicit target confirmation are still required.");

        if (!diagnostics.Any(item => item.BlocksPlan))
        {
            var mediaPartition = Math.Max(MinimumCapacityMiB - LayoutReserveMiB, request.MediaSizeMiB + MediaHeadroomMiB);
            if (mediaPartition + LayoutReserveMiB > disk!.CapacityMiB)
                Block("layout.capacity", "The extracted media, 1 GiB working headroom and 8 MiB layout reserve do not fit the supplied USB capacity.");
            else
            {
                layout.Add(new("Layout reserve", "Unallocated", LayoutReserveMiB, "Reserved for partition metadata and alignment; no partition scheme is written."));
                layout.Add(new("Windows installer", "FAT32", mediaPartition, "Proposed UEFI installation media. Copying an ISO file alone does not make it bootable."));
                var remainder = disk.CapacityMiB - mediaPartition - LayoutReserveMiB;
                if (remainder > 0)
                    layout.Add(new("Remaining space", "Unallocated", remainder, "Unassigned in this plan; no personal data or vault secrets are copied to the installer."));
            }
        }

        requirements.Add(new("Recovery", "On the installed computer, inspect the current WinRE image, partition requirements and recovery status before proposing any recovery changes."));
        requirements.Add(new("Vault", "Plan encrypted storage on the installed computer and a separately protected recovery-key destination. No keys or credentials belong on this installer."));
        requirements.Add(new("Sandbox / quarantine", "Use isolated storage on the installed computer. Recovery and quarantine are storage functions, not user profiles."));
        requirements.Add(new("Windows setup", "Check destination hardware, edition, licensing, TPM/Secure Boot and signed driver compatibility against the chosen official Windows release. This planner does not verify those prerequisites."));
        requirements.Add(new("Boot validation", "Validate the final media in an isolated UEFI test environment before use; neither a layout proposal nor a checksum proves it boots."));
        switch (request.Profile)
        {
            case UsbSetupProfile.Sysadmin:
                requirements.Add(new("Sysadmin", "Plan local offline administration and explicit USB-presence controls; do not enable cloud sign-ins by default."));
                break;
            case UsbSetupProfile.Developer:
                requirements.Add(new("Dev Drive", "Reserve at least 50 GB on the installed Windows system for a supported ReFS Dev Drive or local VHD. This is separate from the bootable USB layout."));
                break;
            case UsbSetupProfile.Studio:
                requirements.Add(new("Studio", "Plan dedicated project/sample storage and verified audio interfaces and drivers; no audio tuning is applied."));
                break;
            case UsbSetupProfile.Gamer:
                requirements.Add(new("Gamer", "Plan game-library storage and verified graphics/input drivers; no performance or security setting is changed."));
                break;
            case UsbSetupProfile.AiServer:
                requirements.Add(new("AI Server", "Plan model/cache storage and measured RAM/VRAM capacity. Keep Hermes/XCore workers and cross-provider calls unconfigured until their own runtime checks pass."));
                break;
            case UsbSetupProfile.Core:
                requirements.Add(new("Core", "Plan the minimal desktop and shared HELIOS connection tools; add specialist workspaces only when needed."));
                break;
        }
        return new UsbSetupPlan(ProfileName(request.Profile), id, layout.ToArray(), requirements.ToArray(), diagnostics.ToArray());
    }

    public static string ProfileName(UsbSetupProfile profile) => profile == UsbSetupProfile.AiServer
        ? "AI Server" : Enum.IsDefined(typeof(UsbSetupProfile), profile) ? profile.ToString() : "Unknown";
}
