using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace HELIOS.Platform.ShellExtension;

/// <summary>
/// COM shell extension for context menu integration.
/// </summary>
[ComVisible(true)]
[Guid("12345678-1234-1234-1234-123456789012")]
[ClassInterface(ClassInterfaceType.None)]
public class ContextMenuExtension : IContextMenu
{
    private string? _selectedFile;
    private const uint IDCMD_OPEN_HELIOS = 0;
    private const uint CMF_DEFAULTONLY = 0x00000001;
    private const uint GCS_HELPTEXTA = 0x00000001;
    private const uint GCS_HELPTEXTW = 0x00000005;

    public int QueryContextMenu(IntPtr hMenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags)
    {
        if ((uFlags & CMF_DEFAULTONLY) != 0)
            return 0;

        // Add "Open with HELIOS" menu item
        var result = ShellContextMenuHelper.InsertMenu(
            hMenu,
            indexMenu,
            idCmdFirst + IDCMD_OPEN_HELIOS,
            "Open with HELIOS Platform");

        return result ? 1 : 0;
    }

    public int InvokeCommand(IntPtr pici)
    {
        var invoke = (CMINVOKECOMMANDINFO)Marshal.PtrToStructure(
            pici,
            typeof(CMINVOKECOMMANDINFO))!;

        var verbValue = unchecked((ulong)invoke.lpVerb.ToInt64());
        var isNumericVerb = ((verbValue >> 16) == 0);
        if (isNumericVerb && LOWORD((uint)verbValue) == IDCMD_OPEN_HELIOS)
        {
            LaunchWithHelios(_selectedFile);
            return 0;
        }

        return 1;
    }

    public int GetCommandString(UIntPtr idCmd, uint uFlags, IntPtr pReserved, IntPtr pszName, uint cchMax)
    {
        if (idCmd != (UIntPtr)IDCMD_OPEN_HELIOS)
            return 1;

        const string description = "Open file with HELIOS Platform";
        if (uFlags == GCS_HELPTEXTW && pszName != IntPtr.Zero)
        {
            var maxChars = Math.Max(0, (int)cchMax - 1);
            var helpText = description[..Math.Min(description.Length, maxChars)] + '\0';
            Marshal.Copy(helpText.ToCharArray(), 0, pszName, helpText.Length);
        }
        else if (uFlags == GCS_HELPTEXTA && pszName != IntPtr.Zero)
        {
            var bytes = System.Text.Encoding.ASCII.GetBytes(description);
            var count = Math.Min(bytes.Length, Math.Max(0, (int)cchMax - 1));
            Marshal.Copy(bytes, 0, pszName, count);
            Marshal.WriteByte(pszName, count, 0);
        }

        return 0;
    }

    public void SetFilePath(string filePath) => _selectedFile = filePath;

    private void LaunchWithHelios(string? filePath)
    {
        try
        {
            var heliosPath = GetHeliosInstallPath();
            if (string.IsNullOrEmpty(heliosPath)) return;

            var startInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = System.IO.Path.Combine(heliosPath, "HELIOS.Platform.exe"),
                UseShellExecute = true
            };
            if (!string.IsNullOrWhiteSpace(filePath))
            {
                startInfo.ArgumentList.Add("--open");
                startInfo.ArgumentList.Add(filePath);
            }

            System.Diagnostics.Process.Start(startInfo);
        }
        catch { /* Silently fail */ }
    }

    private string? GetHeliosInstallPath()
    {
        try
        {
            using (var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\HELIOS Platform"))
            {
                return key?.GetValue("InstallPath")?.ToString();
            }
        }
        catch { }
        return null;
    }

    private uint LOWORD(uint value) => value & 0xFFFF;
}

/// <summary>
/// Interface for context menu operations.
/// </summary>
[ComImport]
[Guid("000214e4-0000-0000-c000-000000000046")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IContextMenu
{
    [PreserveSig]
    int QueryContextMenu(IntPtr hMenu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint uFlags);

    [PreserveSig]
    int InvokeCommand(IntPtr pici);

    [PreserveSig]
    int GetCommandString(UIntPtr idCmd, uint uFlags, IntPtr pReserved, IntPtr pszName, uint cchMax);
}

/// <summary>
/// COM invocation info structure.
/// </summary>
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct CMINVOKECOMMANDINFO
{
    public uint cbSize;
    public uint fMask;
    public IntPtr hwnd;
    public IntPtr lpVerb;
    public IntPtr lpParameters;
    public IntPtr lpDirectory;
    public int nShow;
}

/// <summary>
/// Shell context menu helper utilities.
/// </summary>
public static class ShellContextMenuHelper
{
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool InsertMenuW(IntPtr hMenu, uint uPosition, uint uFlags, UIntPtr uIDNewItem, string lpNewItem);

    private const uint MF_BYPOSITION = 0x400;
    private const uint MF_STRING = 0x0;

    public static bool InsertMenu(IntPtr hMenu, uint position, uint id, string text)
    {
        try
        {
            return InsertMenuW(hMenu, position, MF_BYPOSITION | MF_STRING, (UIntPtr)id, text);
        }
        catch
        {
            return false;
        }
    }
}

/// <summary>
/// Registry-based context menu registration manager.
/// </summary>
public class ContextMenuRegistration
{
    private const string RegistryPath = @"Software\Classes\*\shell\HELIOS";
    private const string CLSID = "12345678-1234-1234-1234-123456789012";

    /// <summary>
    /// Registers the context menu extension.
    /// </summary>
    public static bool Register()
    {
        try
        {
            using (var key = Registry.CurrentUser.CreateSubKey(RegistryPath))
            {
                key.SetValue("", "Open with HELIOS");
                key.SetValue("Icon", "\"C:\\Program Files\\HELIOS Platform\\HELIOS.ico\"");

                using (var cmdKey = key.CreateSubKey("command"))
                {
                    cmdKey.SetValue("", $"\"%ProgramFiles%\\HELIOS Platform\\HELIOS.Platform.exe\" \"%1\"");
                }
            }

            // Register COM class
            RegisterCOMClass();
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Unregisters the context menu extension.
    /// </summary>
    public static bool Unregister()
    {
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(RegistryPath, false);
            UnregisterCOMClass();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void RegisterCOMClass()
    {
        try
        {
            var clsidPath = $@"Software\Classes\CLSID\{{{CLSID}}}";
            using (var key = Registry.CurrentUser.CreateSubKey(clsidPath))
            {
                key.SetValue("", "HELIOS Context Menu");
                using (var inproc = key.CreateSubKey("InprocServer32"))
                {
                    inproc.SetValue("", "HELIOS.Platform.ShellExtension.dll");
                    inproc.SetValue("ThreadingModel", "Apartment");
                }
            }
        }
        catch { }
    }

    private static void UnregisterCOMClass()
    {
        try
        {
            var clsidPath = $@"Software\Classes\CLSID\{{{CLSID}}}";
            Registry.CurrentUser.DeleteSubKeyTree(clsidPath, false);
        }
        catch { }
    }
}

/// <summary>
/// File association manager.
/// </summary>
public class FileAssociationManager
{
    private const string HeliosProgId = "HELIOS.Platform.File";
    private const string HeliosExeName = "HELIOS.Platform.exe";

    /// <summary>
    /// Associates file extension with HELIOS.
    /// </summary>
    public static bool AssociateExtension(string extension, string? description = null)
    {
        try
        {
            var extPath = $@"Software\Classes\{extension}";
            using (var key = Registry.CurrentUser.CreateSubKey(extPath))
            {
                key.SetValue("", HeliosProgId);
            }

            // Create ProgID
            var progIdPath = $@"Software\Classes\{HeliosProgId}";
            using (var key = Registry.CurrentUser.CreateSubKey(progIdPath))
            {
                key.SetValue("", description ?? "HELIOS Platform File");
                using (var cmdKey = key.CreateSubKey(@"shell\open\command"))
                {
                    cmdKey.SetValue("", $"\"%ProgramFiles%\\HELIOS Platform\\{HeliosExeName}\" \"%1\"");
                }
            }

            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Registers protocol handler.
    /// </summary>
    public static bool RegisterProtocol(string protocol)
    {
        try
        {
            var protPath = $@"Software\Classes\{protocol}";
            using (var key = Registry.CurrentUser.CreateSubKey(protPath))
            {
                key.SetValue("", $"HELIOS {protocol.ToUpper()} Protocol");
                key.SetValue("URL Protocol", "");
                using (var cmdKey = key.CreateSubKey(@"shell\open\command"))
                {
                    cmdKey.SetValue("", $"\"%ProgramFiles%\\HELIOS Platform\\{HeliosExeName}\" \"%1\"");
                }
            }

            return true;
        }
        catch
        {
            return false;
        }
    }
}
