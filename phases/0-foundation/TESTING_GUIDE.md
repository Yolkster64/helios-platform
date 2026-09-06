# HELIOS Phase 0: Testing Guide

How to verify that Phase 0 (Foundation) completed successfully and the system is ready for Phase 1.

---

## Quick Verification Checklist

Print or bookmark this section for quick testing:

```
QUICK CHECK (takes 2 minutes):

☐ Windows 11 is installed
☐ C: drive exists and has Windows files
☐ D: drive exists and is empty (or has folders)
☐ Folders exist in C:\HELIOS\
☐ Folders exist in D:\Users\
☐ PowerShell runs as Administrator
☐ No error messages on startup

If all checked: Phase 0 COMPLETE ✓
If any unchecked: Run DETAILED TESTS below
```

---

## Detailed Testing Procedures

### Test 1: Windows 11 Installation Verification

**Purpose**: Verify Windows 11 is properly installed

**How To Check**:

**Method 1 - Settings**:

1. Click Start button (Windows icon)
2. Type "winver"
3. Press Enter
4. Look for: "Windows 11" and build number (e.g., "Build 22621.xxxx")

**Expected Result**:

```
Windows 11
Version: 23H2 or similar
Build: 22621.xxxx or higher
```

**Method 2 - Command Line**:

```powershell
# Run in PowerShell
wmic os get caption, version, buildnumber
```

**Expected Output**:

```
Caption            Version  BuildNumber
Microsoft Windows 11 10.0    22621
```

**Method 3 - File Explorer**:

1. Click File Explorer (folder icon)
2. Right-click "This PC"
3. Click "Properties"
4. Look for "Windows 11" mentioned

**If Test Fails**:

- Windows 11 not detected as installed
- Solution: Rerun windows-installer.ps1 from USB

**Status**: ✓ PASS / ✗ FAIL

---

### Test 2: Drive Letter Verification

**Purpose**: Verify C: and D: drives exist and have correct sizes

**How To Check**:

**Method 1 - File Explorer**:

1. Open File Explorer
2. Click "This PC" (left sidebar)
3. Look for "C:" and "D:" drives

**Expected Result**:

```
C: [System] - Windows installed (with files)
D: [Data]   - Empty or with folders (not main OS)
```

**Method 2 - PowerShell**:

```powershell
# Run as Administrator
Get-Volume | Select-Object DriveLetter, FileSystemType, SizeRemaining, Size

# Or simpler:
diskpart
list volume
exit
```

**Expected Output**:

```
DriveLetter FileSystemType Size          SizeRemaining
C           NTFS           150000000000  50000000000
D           NTFS           350000000000  350000000000
```

*Note: Numbers will vary based on your actual disk sizes*

**Method 3 - Properties Check**:

1. Right-click C: drive in File Explorer
2. Click Properties
3. Verify: System drive, NTFS format, ~25-30 GB used
4. Repeat for D: drive
5. Verify: Empty or mostly empty, NTFS format

**If Test Fails**:

- D: drive missing: Run partition-manager.ps1
- C: drive missing: Windows not installed properly
- Wrong size: Run partition-manager.ps1 again

**Status**: ✓ PASS / ✗ FAIL

---

### Test 3: Folder Structure Verification

**Purpose**: Verify all required folders created in correct locations

**How To Check**:

**C: Drive Folders**:

```powershell
# Run in PowerShell
# Check if these exist:
Test-Path "C:\HELIOS\phases\0-foundation"          # Should be TRUE
Test-Path "C:\HELIOS\tools"                         # Should be TRUE
Test-Path "C:\HELIOS\config"                        # Should be TRUE
Test-Path "C:\HELIOS\logs"                          # Should be TRUE
Test-Path "C:\HELIOS\backups"                       # Should be TRUE
Test-Path "C:\HELIOS\docs"                          # Should be TRUE

# Output TRUE for all
```

**Expected Output**:

```
True
True
True
True
True
True
```

**D: Drive Folders**:

```powershell
# Check if these exist:
Test-Path "D:\Users\ADMIN\Documents"                # Should be TRUE
Test-Path "D:\Users\ADMIN\Downloads"                # Should be TRUE
Test-Path "D:\Users\ADMIN\Pictures"                 # Should be TRUE
Test-Path "D:\Backups"                              # Should be TRUE
Test-Path "D:\Projects"                             # Should be TRUE
Test-Path "D:\Archive"                              # Should be TRUE

# All should output TRUE
```

**Visual Check**:

1. Open File Explorer
2. Click on C: drive
3. Should see "HELIOS" folder
4. Double-click HELIOS
5. Should see: phases, tools, config, logs, backups, docs
6. Repeat for D: drive
7. Should see: Users, Backups, Projects, Archive

**Count Check**:

```powershell
# Count main folders on C:\HELIOS\
(Get-ChildItem C:\HELIOS\ -Directory).Count   # Should be 6+

# Count main folders on D:\
(Get-ChildItem D:\ -Directory).Count           # Should be 4+
```

**If Test Fails**:

- Folders missing: Run storage-setup.ps1
- Wrong location: Check folder paths (C: vs D:)
- Permission error: Run PowerShell as Administrator

**Status**: ✓ PASS / ✗ FAIL

---

### Test 4: Disk Partition Layout Verification

**Purpose**: Verify partitions are correctly set up

**How To Check**:

**Method 1 - Disk Management GUI**:

1. Right-click Start button
2. Click "Disk Management"
3. Look at disk layout:
   - Should show C: partition (system)
   - Should show D: partition (data)
   - May show recovery partition (hidden)
   - All should be NTFS format

**Method 2 - PowerShell**:

```powershell
# Show all partitions
Get-Partition | Select-Object DriveLetter, Type, Size, FileSystem

# Should show:
# - C: drive (NTFS, ~150 GB)
# - D: drive (NTFS, remaining space)
# - Recovery partition (no letter, small)
```

**Expected Output**:

```
DriveLetter Type Size         FileSystem
C           IFS  160000000000 NTFS
D           IFS  350000000000 NTFS
            IFS  525000000    NTFS
```

**Method 3 - File Explorer**:

1. Right-click "This PC"
2. Click "Manage"
3. Click "Storage" on left
4. Click "Disks and volumes"
5. Verify partition layout shown

**If Test Fails**:

- Recovery partition missing: Not critical, can be created
- Partition sizes wrong: Run partition-manager.ps1 again
- File system wrong: Should be NTFS (not FAT32)

**Status**: ✓ PASS / ✗ FAIL

---

### Test 5: System Baseline Configuration Verification

**Purpose**: Verify system baseline settings applied

**How To Check**:

**Check Windows Features Enabled**:

```powershell
# Run as Administrator
dism /online /get-features /format=table | findstr /i "hyper-v sandbox wsl virtual-machine"

# Should show "Enable" or "Enabled" for each
```

**Expected Output** (similar to):

```
Hyper-V                          Enabled
Containers                       Enabled
VirtualMachinePlatform          Enabled
WindowsSubsystemForLinux         Enabled
```

**Check Services Running**:

```powershell
# Check if security services are running
Get-Service WinDefend, WindowsUpdate, mpssvc | Select-Object Name, Status

# Should show Status: Running for all
```

**Expected Output**:

```
Name             Status
WinDefend        Running
WindowsUpdate    Running
mpssvc           Running
```

**Check Power Settings**:

```powershell
# Check current power plan
powercfg /getactivescheme

# Should show "High Performance" plan
```

**Expected Output**:

```
Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (High performance)
```

**Check File Explorer Settings**:

1. Open File Explorer
2. Click View menu (top)
3. Should see "Hidden items" checked
4. Should see "File name extensions" checked

**Check Windows Security**:

1. Click Start
2. Type "Windows Security"
3. Press Enter
4. Should show "Virus & threat protection: Protected"

**Check Registry Changes**:

```powershell
# Sample check - system baseline should have modified registry
# This is complex; easier to just verify features/services above
# If features and services are correct, registry is likely correct

# View baseline log for confirmation:
Get-Content C:\HELIOS\logs\phase0\system-baseline-*.log | tail -20
```

**If Test Fails**:

- Features not enabled: Run system-baseline.ps1 again
- Services not running: Check for errors in logs
- Power plan wrong: Change manually in Settings > Power

**Status**: ✓ PASS / ✗ FAIL

---

### Test 6: Admin Access & PowerShell Verification

**Purpose**: Verify admin access works and PowerShell is ready

**How To Check**:

**Method 1 - Check Admin Status**:

```powershell
# Run this in PowerShell
# If it returns "True", you have admin access
[bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")

# Should output: True
```

**Method 2 - Run as Admin**:

1. Right-click PowerShell icon
2. Click "Run as Administrator"
3. If prompt appears, click "Yes"
4. PowerShell should say "Administrator:" in title bar

**Method 3 - Check PowerShell Version**:

```powershell
# Check version
$PSVersionTable

# Should show: PSVersion 5.1 or 7.x (7 is newer)
```

**Expected Output**:

```
Name                           Value
----                           -----
PSVersion                      5.1
PSEdition                      Desktop
WSManStackVersion              3.0
...
```

**If Test Fails**:

- Not running as admin: Right-click PowerShell, Run as Administrator
- Wrong version: Install PowerShell 7 (not required, but recommended)

**Status**: ✓ PASS / ✗ FAIL

---

### Test 7: Phase 0 Scripts Presence Verification

**Purpose**: Verify all Phase 0 scripts are in correct locations

**How To Check**:

```powershell
# Check if all scripts exist
Test-Path "C:\HELIOS\phases\0-foundation\README.md"              # Should be TRUE
Test-Path "C:\HELIOS\phases\0-foundation\PLAIN_ENGLISH_GUIDE.md" # Should be TRUE
Test-Path "C:\HELIOS\phases\0-foundation\FILE_ARCHITECTURE.md"   # Should be TRUE
Test-Path "C:\HELIOS\phases\0-foundation\SCRIPTS_INDEX.md"       # Should be TRUE
Test-Path "C:\HELIOS\phases\0-foundation\TESTING_GUIDE.md"       # Should be TRUE
Test-Path "C:\HELIOS\phases\0-foundation\scripts\usb-creator.ps1"              # TRUE
Test-Path "C:\HELIOS\phases\0-foundation\scripts\partition-manager.ps1"        # TRUE
Test-Path "C:\HELIOS\phases\0-foundation\scripts\storage-setup.ps1"            # TRUE
Test-Path "C:\HELIOS\phases\0-foundation\scripts\system-baseline.ps1"          # TRUE

# All should output TRUE
```

**File Explorer Check**:

1. Open File Explorer
2. Navigate to: C:\HELIOS\phases\0-foundation\
3. Should see files: README.md, PLAIN_ENGLISH_GUIDE.md, etc.
4. Should see folder: scripts\
5. Open scripts\ folder
6. Should see files: usb-creator.ps1, partition-manager.ps1, etc.

**If Test Fails**:

- Scripts missing: Copy from original source location
- Wrong location: Move to C:\HELIOS\phases\0-foundation\

**Status**: ✓ PASS / ✗ FAIL

---

### Test 8: Phase 0 Logs Verification

**Purpose**: Verify logs were created and contain no critical errors

**How To Check**:

**Check Logs Exist**:

```powershell
# List all Phase 0 logs
Get-ChildItem C:\HELIOS\logs\phase0\ -Filter "*.log"

# Should show log files from each script
```

**Expected Output** (similar to):

```
Directory: C:\HELIOS\logs\phase0

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a---           1/15/2024 10:30 AM       123456 partition-manager-20240115-103000.log
-a---           1/15/2024 10:20 AM       456789 storage-setup-20240115-102000.log
-a---           1/15/2024 10:10 AM       789012 system-baseline-20240115-101000.log
```

**Check for Errors in Logs**:

```powershell
# Search logs for ERROR or FAIL
Get-ChildItem C:\HELIOS\logs\phase0\*.log | ForEach-Object {
    Select-String -Path $_.FullName -Pattern "ERROR|FAIL|Exception" -ErrorAction SilentlyContinue
}

# Should output NOTHING (no errors)
```

**View Specific Log**:

```powershell
# Read most recent log
Get-ChildItem C:\HELIOS\logs\phase0\*.log | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 | 
    Get-Content
```

**Check Log Size**:

```powershell
# Logs should exist and have reasonable size (not empty)
Get-ChildItem C:\HELIOS\logs\phase0\*.log | 
    Select-Object Name, Length
    
# Should show file size > 1000 bytes for each
```

**If Test Fails**:

- No logs found: Scripts haven't been run yet
- Logs show errors: Check error messages and re-run script
- Logs empty: Script may have failed to start

**Status**: ✓ PASS / ✗ FAIL

---

### Test 9: Internet & Windows Update Verification

**Purpose**: Verify internet connectivity and Windows Update working

**How To Check**:

**Test Internet Connectivity**:

```powershell
# Ping a reliable server
Test-Connection 8.8.8.8 -Count 1 -ErrorAction SilentlyContinue

# Should show response, not timeout
# Or simpler:
Test-Connection google.com
```

**Expected Output**:

```
Source        Destination     IPV4Address      IPV6Address Status
------        -----------     -----------      ----------- ------
MYCOMPUTER    8.8.8.8         8.8.8.8                      Success
```

**Test Windows Update**:

```powershell
# Check if Windows Update is enabled and working
Get-Service WUAuServ | Select-Object Name, Status, StartType

# Should show: Status = Running, StartType = Automatic
```

**Check Update History**:

1. Click Start
2. Type "Update"
3. Click "Check for updates"
4. Should show recent updates installed

**Visual Check**:

1. Settings > System > About
2. Should show Windows is up to date (or updates available)

**If Test Fails**:

- No internet: Check WiFi/Ethernet connection
- Updates failing: Restart computer and try again
- Service disabled: Run system-baseline.ps1 again

**Status**: ✓ PASS / ✗ FAIL

---

## Complete Testing Procedure

**Run all tests in this order**:

1. ✓ Windows 11 Installation Test
2. ✓ Drive Letter Test
3. ✓ Folder Structure Test
4. ✓ Partition Layout Test
5. ✓ System Baseline Test
6. ✓ Admin Access Test
7. ✓ Scripts Presence Test
8. ✓ Logs Verification Test
9. ✓ Internet & Updates Test

**Time Estimate**: 10-15 minutes to run all tests

---

## Phase 0 Completion Checklist

### Must Have (Critical)

```
☐ Windows 11 installed
☐ C: drive present and formatted NTFS
☐ D: drive present and formatted NTFS
☐ C:\HELIOS\ folder structure created
☐ D:\Users\ folder structure created
☐ Admin PowerShell access working
☐ No critical errors in logs
```

### Should Have (Recommended)

```
☐ Windows Update running
☐ Internet connection working
☐ Backup of system created
☐ All Phase 0 logs generated
☐ System restore point created
☐ Hyper-V or other features enabled
```

### Nice To Have (Optional)

```
☐ Antivirus enabled
☐ BitLocker support enabled
☐ OneDrive configured
☐ All scripts documented
```

---

## Test Results Summary Table

| Test | Status | Result | Time |
|------|--------|--------|------|
| Windows 11 Install | ✓/✗ | PASS/FAIL | 1 min |
| Drive Letters | ✓/✗ | PASS/FAIL | 1 min |
| Folder Structure | ✓/✗ | PASS/FAIL | 2 min |
| Partition Layout | ✓/✗ | PASS/FAIL | 1 min |
| System Baseline | ✓/✗ | PASS/FAIL | 2 min |
| Admin Access | ✓/✗ | PASS/FAIL | 1 min |
| Scripts Present | ✓/✗ | PASS/FAIL | 1 min |
| Logs Exist | ✓/✗ | PASS/FAIL | 2 min |
| Internet/Updates | ✓/✗ | PASS/FAIL | 4 min |
| **TOTAL** | | | **15 min** |

---

## If Tests Fail

### Problem: Windows 11 not detected

**Cause**: Installation incomplete or incorrect OS

**Solution**:

1. Restart computer
2. Re-run Windows installer from USB
3. Verify Windows installation completed fully

### Problem: D: drive missing

**Cause**: Partitioning not done

**Solution**:

```powershell
# Run partition manager
cd C:\HELIOS\phases\0-foundation\scripts
.\partition-manager.ps1
# Follow prompts to create D: drive
```

### Problem: HELIOS folders missing

**Cause**: Storage setup not run

**Solution**:

```powershell
# Run storage setup
cd C:\HELIOS\phases\0-foundation\scripts
.\storage-setup.ps1
# Creates all required folders
```

### Problem: Admin access denied

**Cause**: PowerShell not running as administrator

**Solution**:

1. Right-click PowerShell icon
2. Select "Run as Administrator"
3. Click "Yes" on prompt
4. Retry command

### Problem: Logs show errors

**Cause**: Script encountered problem

**Solution**:

1. Read error message in log carefully
2. Check File_Architecture.md for correct paths
3. Re-run the failing script
4. Check internet connection
5. Try disabling antivirus temporarily (carefully!)

### Problem: Internet not working

**Cause**: Network not configured

**Solution**:

1. Check WiFi/Ethernet connection
2. Open Settings > Network & Internet
3. Check network is enabled
4. Test with: `ping 8.8.8.8`

---

## Next Steps After Passing All Tests

Once Phase 0 is verified complete:

1. **Create Backup**: Back up D: drive to external storage
2. **Document**: Note down drive sizes and configuration
3. **Verify Again**: Run quick checklist one more time
4. **Move to Phase 1**: Proceed to Phase 1 customization

---

## Testing Automation Script

**Optional**: Create a script to run all tests automatically

```powershell
# Save as: Test-Phase0.ps1

# Run as Administrator

Write-Host "HELIOS Phase 0 Testing..." -ForegroundColor Green
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Windows 11
if (Get-WmiObject -Class Win32_OperatingSystem | Where-Object Caption -match "Windows 11") {
    Write-Host "[✓] Windows 11 installed" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[✗] Windows 11 NOT found" -ForegroundColor Red
    $testsFailed++
}

# Test 2: C: drive
if (Test-Path "C:\" ) {
    Write-Host "[✓] C: drive present" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[✗] C: drive missing" -ForegroundColor Red
    $testsFailed++
}

# Test 3: D: drive
if (Test-Path "D:\") {
    Write-Host "[✓] D: drive present" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[✗] D: drive missing" -ForegroundColor Red
    $testsFailed++
}

# Test 4: HELIOS folders
if (Test-Path "C:\HELIOS\") {
    Write-Host "[✓] HELIOS folder structure present" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[✗] HELIOS folder missing" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host ""
Write-Host "Results: $testsPassed passed, $testsFailed failed" -ForegroundColor Cyan

if ($testsFailed -eq 0) {
    Write-Host "Phase 0 COMPLETE ✓" -ForegroundColor Green
} else {
    Write-Host "Phase 0 INCOMPLETE - See failed tests above" -ForegroundColor Red
}
```

---

**Phase 0 is complete when all critical tests pass!**

Once verified, you're ready to move to Phase 1: Customization.
