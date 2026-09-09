using HELIOS.AIHub.Setup;
using Xunit;

namespace HELIOS.AIHub.Tests.Setup;

public class UsbSetupPlannerTests
{
    private readonly UsbSetupPlanner _planner = new();
    private static UsbSetupRequest ValidRequest() => new()
    {
        Profile = UsbSetupProfile.Core,
        TargetDisk = new UsbDiskInventory
        {
            DeviceId = "usb-test-serial",
            CapacityMiB = 32768,
            IsRemovable = true,
            IsSystemDisk = false,
            IsBootDisk = false,
            IsReadOnly = false,
        },
        Firmware = UsbFirmwareMode.Uefi,
        MediaSizeMiB = 6000,
        LargestFileMiB = 3000,
        BackupConfirmed = true,
        ImageVerified = true,
    };

    [Theory]
    [InlineData(UsbSetupProfile.Sysadmin, "Sysadmin")]
    [InlineData(UsbSetupProfile.Developer, "Developer")]
    [InlineData(UsbSetupProfile.Studio, "Studio")]
    [InlineData(UsbSetupProfile.Gamer, "Gamer")]
    [InlineData(UsbSetupProfile.Core, "Core")]
    [InlineData(UsbSetupProfile.AiServer, "AI Server")]
    public void ProfilesProduceAdvisoryMediaAndSeparateHostRequirements(UsbSetupProfile profile, string label)
    {
        var plan = _planner.CreatePlan(ValidRequest() with { Profile = profile });
        Assert.True(plan.IsValid);
        Assert.False(plan.CanExecute);
        Assert.Equal("review-only", plan.Status);
        Assert.Equal(label, plan.Profile);
        Assert.Equal(32768, plan.MediaLayout.Sum(part => part.SizeMiB));
        Assert.All(plan.MediaLayout, part => Assert.True(part.SizeMiB > 0));
        Assert.Single(plan.MediaLayout, part => part.FileSystem == "FAT32");
        Assert.DoesNotContain(plan.MediaLayout, part => part.Name.Contains("Vault") || part.FileSystem == "ReFS");
        Assert.Contains(plan.Requirements, item => item.Area == "Recovery");
        Assert.Contains(plan.Requirements, item => item.Area == "Vault");
        Assert.Contains(plan.Requirements, item => item.Area == "Sandbox / quarantine");
        Assert.Contains(plan.Diagnostics, item => item.Code == "execution.unavailable");
    }

    [Fact]
    public void UnknownInventoryIsNeverAssumedSafe()
    {
        var plan = _planner.CreatePlan(new UsbSetupRequest());
        Assert.False(plan.IsValid);
        Assert.False(plan.CanExecute);
        Assert.Equal("needs-input", plan.Status);
        Assert.Empty(plan.MediaLayout);
        Assert.Contains(plan.Diagnostics, item => item.Code == "disk.missing");
        Assert.Contains(plan.Diagnostics, item => item.Code == "boot.uefi");
    }

    [Theory]
    [InlineData("disk.removable")]
    [InlineData("disk.system")]
    [InlineData("disk.boot")]
    [InlineData("disk.readonly")]
    public void UnconfirmedOrUnsafeDiskPropertiesBlockPlan(string expected)
    {
        foreach (var unknown in new[] { true, false })
        {
            var request = ValidRequest();
            var disk = request.TargetDisk!;
            disk = expected switch
            {
                "disk.removable" => disk with { IsRemovable = unknown ? null : false },
                "disk.system" => disk with { IsSystemDisk = unknown ? null : true },
                "disk.boot" => disk with { IsBootDisk = unknown ? null : true },
                _ => disk with { IsReadOnly = unknown ? null : true },
            };
            var plan = _planner.CreatePlan(request with { TargetDisk = disk });
            Assert.False(plan.IsValid);
            Assert.Empty(plan.MediaLayout);
            Assert.Contains(plan.Diagnostics, item => item.Code == expected && item.BlocksPlan);
        }
    }

    [Theory]
    [InlineData(UsbFirmwareMode.Unknown)]
    [InlineData(UsbFirmwareMode.Legacy)]
    [InlineData((UsbFirmwareMode)99)]
    public void OnlyExplicitUefiIsSupported(UsbFirmwareMode firmware)
    {
        var plan = _planner.CreatePlan(ValidRequest() with { Firmware = firmware });
        Assert.False(plan.IsValid);
        Assert.Empty(plan.MediaLayout);
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("C:")]
    [InlineData("C:\\")]
    [InlineData("disk\n1")]
    public void MissingOrAmbiguousDeviceIdBlocksPlan(string id)
    {
        var request = ValidRequest();
        var plan = _planner.CreatePlan(request with { TargetDisk = request.TargetDisk! with { DeviceId = id } });
        Assert.False(plan.IsValid);
        Assert.Contains(plan.Diagnostics, item => item.Code == "disk.identity");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(8191)]
    [InlineData(long.MaxValue)]
    public void InvalidDiskCapacityDoesNotOverflowOrProduceLayout(long capacity)
    {
        var request = ValidRequest();
        var plan = _planner.CreatePlan(request with { TargetDisk = request.TargetDisk! with { CapacityMiB = capacity } });
        Assert.False(plan.IsValid);
        Assert.Empty(plan.MediaLayout);
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(6000, 0)]
    [InlineData(6000, 6001)]
    [InlineData(long.MaxValue, 1)]
    [InlineData(31745, 1)]
    public void InvalidMediaDimensionsBlockLayout(long total, long largest)
    {
        var plan = _planner.CreatePlan(ValidRequest() with { MediaSizeMiB = total, LargestFileMiB = largest });
        Assert.False(plan.IsValid);
        Assert.Empty(plan.MediaLayout);
    }

    [Theory]
    [InlineData(4096)]
    [InlineData(5000)]
    public void FilesThatCannotFitFat32MustBeResolvedBeforeGeometryIsAccepted(long size)
    {
        var plan = _planner.CreatePlan(ValidRequest() with { LargestFileMiB = size });
        Assert.False(plan.IsValid);
        Assert.Empty(plan.MediaLayout);
        Assert.Contains(plan.Diagnostics, item => item.Code == "media.split-required" && item.BlocksPlan);
    }

    [Fact]
    public void ExactFitIncludesLayoutReserveAndExcessMediaIsRejected()
    {
        var request = ValidRequest();
        request = request with
        {
            TargetDisk = request.TargetDisk! with { CapacityMiB = 8192 },
            MediaSizeMiB = 7160,
        };
        var exact = _planner.CreatePlan(request);
        Assert.True(exact.IsValid);
        Assert.Equal(8192, exact.MediaLayout.Sum(part => part.SizeMiB));
        Assert.DoesNotContain(exact.MediaLayout, part => part.Name == "Remaining space");
        var overflow = _planner.CreatePlan(request with { MediaSizeMiB = 7161 });
        Assert.False(overflow.IsValid);
        Assert.Empty(overflow.MediaLayout);
        Assert.Contains(overflow.Diagnostics, item => item.Code == "layout.capacity");
    }

    [Fact]
    public void MissingBackupAndImageChecksRemainVisibleWithoutClaimingExecution()
    {
        var plan = _planner.CreatePlan(ValidRequest() with { BackupConfirmed = false, ImageVerified = false });
        Assert.True(plan.IsValid); // Only the geometry and caller data are valid.
        Assert.False(plan.CanExecute);
        Assert.Contains(plan.Diagnostics, item => item.Code == "backup.required");
        Assert.Contains(plan.Diagnostics, item => item.Code == "image.required");
        Assert.Contains("not verified", plan.InventorySource);
    }

    [Fact]
    public void DeveloperDevDriveIsAnInstalledSystemRequirementOnly()
    {
        var plan = _planner.CreatePlan(ValidRequest() with { Profile = UsbSetupProfile.Developer });
        var requirement = Assert.Single(plan.Requirements, item => item.Area == "Dev Drive");
        Assert.Contains("50 GB", requirement.Requirement);
        Assert.DoesNotContain(plan.MediaLayout, item => item.FileSystem == "ReFS");
    }

    [Fact]
    public void InvalidProfileCannotReturnValidPlan()
    {
        var plan = _planner.CreatePlan(ValidRequest() with { Profile = (UsbSetupProfile)123 });
        Assert.False(plan.IsValid);
        Assert.Empty(plan.MediaLayout);
        Assert.Equal("Unknown", plan.Profile);
    }
}
