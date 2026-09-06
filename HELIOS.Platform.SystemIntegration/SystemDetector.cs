using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management;
using System.Linq;
using Microsoft.Win32;

namespace HELIOS.Platform.SystemIntegration;

/// <summary>
/// Detects and analyzes Windows system configuration, hardware, and partitions.
/// </summary>
public class SystemDetector
{
    /// <summary>
    /// Gets system partition information.
    /// </summary>
    public static SystemPartitionInfo GetPartitionInfo()
    {
        var info = new SystemPartitionInfo();
        var systemRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? "C:\\";
        
        try
        {
            var partitions = DriveInfo.GetDrives();
            foreach (var drive in partitions)
            {
                if (drive.DriveType == DriveType.Fixed)
                {
                    info.Partitions.Add(new PartitionDetails
                    {
                        DriveLetter = drive.Name.TrimEnd('\\'),
                        TotalSize = drive.TotalSize,
                        AvailableSpace = drive.AvailableFreeSpace,
                        FileSystem = drive.DriveFormat,
                        IsSystemDrive = string.Equals(
                            Path.GetPathRoot(drive.Name),
                            systemRoot,
                            StringComparison.OrdinalIgnoreCase),
                        VolumeLabel = drive.VolumeLabel
                    });
                }
            }
        }
        catch (Exception ex)
        {
            info.ErrorMessage = $"Error detecting partitions: {ex.Message}";
        }

        return info;
    }

    /// <summary>
    /// Detects Windows license information.
    /// </summary>
    public static LicenseInfo GetLicenseInfo()
    {
        var info = new LicenseInfo();
        
        try
        {
            using (var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                if (key != null)
                {
                    info.WindowsVersion = key.GetValue("CurrentVersion")?.ToString() ?? "Unknown";
                    info.BuildNumber = key.GetValue("CurrentBuildNumber")?.ToString() ?? "Unknown";
                    info.ProductName = key.GetValue("ProductName")?.ToString() ?? "Unknown";
                    info.EditionId = key.GetValue("EditionID")?.ToString() ?? "Unknown";
                }
            }

            // Get license status via WMI (licensed products with a partial key)
            using (var searcher = new ManagementObjectSearcher(
                       @"\\.\root\cimv2",
                       "SELECT LicenseStatus FROM SoftwareLicensingProduct WHERE PartialProductKey IS NOT NULL"))
            {
                foreach (var item in searcher.Get())
                {
                    var status = item.GetPropertyValue("LicenseStatus")?.ToString();
                    info.LicenseStatus = ConvertLicenseStatus(status);
                    break;
                }
            }
        }
        catch (Exception ex)
        {
            info.ErrorMessage = $"Error detecting license: {ex.Message}";
        }

        return info;
    }

    /// <summary>
    /// Detects connected network adapters.
    /// </summary>
    public static DeviceInfo GetNetworkDevices()
    {
        var info = new DeviceInfo { DeviceType = "Network Adapters" };
        
        try
        {
            using (var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = 1"))
            {
                foreach (var item in searcher.Get())
                {
                    info.Devices.Add(new Device
                    {
                        Name = item.GetPropertyValue("Description")?.ToString() ?? "Unknown",
                        Status = item.GetPropertyValue("IPAddress") != null ? "Connected" : "Disconnected",
                        Type = "Network Adapter"
                    });
                }
            }
        }
        catch (Exception ex)
        {
            info.ErrorMessage = $"Error detecting network devices: {ex.Message}";
        }

        return info;
    }

    /// <summary>
    /// Detects storage devices.
    /// </summary>
    public static DeviceInfo GetStorageDevices()
    {
        var info = new DeviceInfo { DeviceType = "Storage Devices" };
        
        try
        {
            using (var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_DiskDrive"))
            {
                foreach (var item in searcher.Get())
                {
                    info.Devices.Add(new Device
                    {
                        Name = item.GetPropertyValue("Model")?.ToString() ?? "Unknown",
                        Status = item.GetPropertyValue("Status")?.ToString() ?? "Unknown",
                        Type = "Disk Drive",
                        Size = item.GetPropertyValue("Size")?.ToString() ?? "Unknown"
                    });
                }
            }
        }
        catch (Exception ex)
        {
            info.ErrorMessage = $"Error detecting storage: {ex.Message}";
        }

        return info;
    }

    /// <summary>
    /// Gets printer information.
    /// </summary>
    public static DeviceInfo GetPrinters()
    {
        var info = new DeviceInfo { DeviceType = "Printers" };
        
        try
        {
            using (var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_Printer"))
            {
                foreach (var item in searcher.Get())
                {
                    info.Devices.Add(new Device
                    {
                        Name = item.GetPropertyValue("Name")?.ToString() ?? "Unknown",
                        Status = item.GetPropertyValue("PrinterStatus")?.ToString() ?? "Unknown",
                        Type = "Printer"
                    });
                }
            }
        }
        catch (Exception ex)
        {
            info.ErrorMessage = $"Error detecting printers: {ex.Message}";
        }

        return info;
    }

    /// <summary>
    /// Checks system requirements for HELIOS installation.
    /// </summary>
    public static SystemRequirementsCheck CheckSystemRequirements()
    {
        var check = new SystemRequirementsCheck();
        var osVersion = Environment.OSVersion;

        check.IsWindows11OrLater = osVersion.Version.Major >= 10 && osVersion.Version.Build >= 22000;
        check.OSVersion = $"{osVersion.VersionString}";

        var partitionInfo = GetPartitionInfo();
        var requiredSpace = 5L * 1024 * 1024 * 1024; // 5 GB
        check.HasSufficientDiskSpace = partitionInfo.Partitions
            .Any(p => p.IsSystemDrive && p.AvailableSpace >= requiredSpace);

        check.AvailableRAM = GetTotalRAM();
        check.HasMinimumRAM = check.AvailableRAM >= 4; // 4 GB minimum

        check.IsAdministrator = IsRunningAsAdministrator();
        check.IsPassed = check.IsWindows11OrLater && check.HasSufficientDiskSpace && 
                         check.HasMinimumRAM && check.IsAdministrator;

        return check;
    }

    /// <summary>
    /// Gets total system RAM in GB.
    /// </summary>
    public static double GetTotalRAM()
    {
        try
        {
            using (var searcher = new ManagementObjectSearcher("SELECT TotalVisibleMemorySize FROM Win32_OperatingSystem"))
            {
                foreach (var item in searcher.Get())
                {
                    if (ulong.TryParse(item.GetPropertyValue("TotalVisibleMemorySize")?.ToString(), out var ram))
                    {
                        return ram / (1024.0 * 1024.0); // Convert KB to GB
                    }
                }
            }
        }
        catch { }

        return 0;
    }

    /// <summary>
    /// Checks if process is running with administrator privileges.
    /// </summary>
    public static bool IsRunningAsAdministrator()
    {
        try
        {
            var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(identity);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    private static string ConvertLicenseStatus(string? status) => status switch
    {
        "0" => "Unlicensed",
        "1" => "Licensed",
        "2" => "Out of Grace Period",
        "3" => "Out of Tolerance",
        _ => status ?? "Unknown"
    };
}

/// <summary>
/// System partition information.
/// </summary>
public class SystemPartitionInfo
{
    public List<PartitionDetails> Partitions { get; set; } = new();
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Partition details.
/// </summary>
public class PartitionDetails
{
    public string? DriveLetter { get; set; }
    public long TotalSize { get; set; }
    public long AvailableSpace { get; set; }
    public string? FileSystem { get; set; }
    public bool IsSystemDrive { get; set; }
    public string? VolumeLabel { get; set; }
}

/// <summary>
/// License information.
/// </summary>
public class LicenseInfo
{
    public string? WindowsVersion { get; set; }
    public string? BuildNumber { get; set; }
    public string? ProductName { get; set; }
    public string? EditionId { get; set; }
    public string? LicenseStatus { get; set; }
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Device information collection.
/// </summary>
public class DeviceInfo
{
    public string? DeviceType { get; set; }
    public List<Device> Devices { get; set; } = new();
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Individual device details.
/// </summary>
public class Device
{
    public string? Name { get; set; }
    public string? Status { get; set; }
    public string? Type { get; set; }
    public string? Size { get; set; }
}

/// <summary>
/// System requirements check result.
/// </summary>
public class SystemRequirementsCheck
{
    public bool IsWindows11OrLater { get; set; }
    public string? OSVersion { get; set; }
    public bool HasSufficientDiskSpace { get; set; }
    public double AvailableRAM { get; set; }
    public bool HasMinimumRAM { get; set; }
    public bool IsAdministrator { get; set; }
    public bool IsPassed { get; set; }
}
