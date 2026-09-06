# Troubleshooting Guide v2.5.1

Comprehensive troubleshooting guide for common issues, diagnostic procedures, and solutions for Helios Platform v2.5.1.

---

## Build Failures: Solutions

### Build Error: "Cannot find dependency 'X.dll'"

**Symptoms:**

```
Error: Unable to locate required assembly: SomeComponent.dll
Build failed: MSB3202
```

**Solutions:**

1. **Restore NuGet Packages**

```powershell
cd C:\helios-platform
dotnet restore --force
dotnet build -c Release
```

2. **Clear NuGet Cache**

```powershell
dotnet nuget locals all --clear
dotnet restore
dotnet build
```

3. **Check Internet Connection**

```powershell
Test-Connection nuget.org -Repeat 3
# Must complete successfully
```

**Expected Output:**

```
Restoring packages...
✓ 42 packages restored successfully
✓ Build completed: 14 seconds
```

### Build Error: "Parallel build failed"

**Symptoms:**

```
Error: MSB3202 - Parallel build failed
Timeout waiting for compiler
```

**Solutions:**

1. **Disable Parallel Build**

```powershell
dotnet build -c Release --no-restore --% /m:1
```

2. **Identify Problematic Project**

```powershell
dotnet build -c Release /verbosity:detailed
# Note first failure, build that project alone
```

3. **Update Compiler**

```powershell
dotnet tool update dotnet-sdk
```

### Build Error: "Out of Memory"

**Symptoms:**

```
Error: OutOfMemoryException during compilation
Process terminated: insufficient heap space
```

**Solutions:**

1. **Reduce Parallel Tasks**

```powershell
dotnet build -c Release /m:2  # Reduce from 4 to 2
```

2. **Increase System Virtual Memory**
   - Windows: Settings → System → Advanced → Virtual Memory
   - Set to 10+ GB on SSD

3. **Close Unnecessary Applications**

```powershell
# Check memory usage
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 10
```

4. **Build in Smaller Modules**

```powershell
cd src\Core
dotnet build -c Release

cd ..\UI
dotnet build -c Release
```

---

## USB Creation Failures: Solutions

### USB Error: "Device not found"

**Symptoms:**

```
Error: USB device not detected
Available devices: None
```

**Solutions:**

1. **Physical Connection Check**
   - Disconnect and reconnect USB
   - Try different USB port
   - Try different USB drive
   - Verify USB 3.0+ for faster operations

2. **Rescan Devices**

```powershell
.\helios-usb-wizard.exe --rescan
# Should detect USB device
```

3. **Check Device Manager (Windows)**
   - Right-click Start menu → Device Manager
   - Expand "Disk drives"
   - Look for USB device
   - If yellow warning: right-click → Update driver

### USB Error: "Write to USB failed"

**Symptoms:**

```
Error: Write operation failed at 45%
USB may be read-only or disconnected
```

**Solutions:**

1. **Format USB Drive**

```powershell
# Windows
Format-Volume -DriveLetter D -FileSystem NTFS -Force

# macOS
diskutil eraseDisk JHFS+ Helios /dev/diskX

# Linux
sudo mkfs.ext4 /dev/sdX1
```

2. **Disable Read-Only Mode**
   - USB drive has physical read-only switch
   - Check both sides of USB plug
   - Move switch to unlocked position

3. **Check Disk Permissions (macOS/Linux)**

```bash
# Check write permissions
ls -la /Volumes/USBDRIVE

# Fix permissions
sudo chown -R $USER:$USER /Volumes/USBDRIVE
```

4. **Try Different USB Device**
   - USB drive may be defective
   - Use different drive (minimum 16 GB USB 3.0)

### USB Error: "Insufficient space (X GB needed, Y GB available)"

**Symptoms:**

```
Error: Insufficient disk space
Required: 16.2 GB
Available: 2.8 GB
```

**Solutions:**

1. **Clean USB Drive**

```powershell
# Delete all files
Remove-Item D:\* -Force -Recurse
```

2. **Select Smaller Profile**
   - Minimal: 8 GB
   - Standard: 16 GB
   - Try Minimal if USB is 8-16 GB

3. **Use Larger USB Drive**
   - Minimum: 16 GB USB 3.0
   - Recommended: 32 GB USB 3.1

### USB Error: "Checksum verification failed"

**Symptoms:**

```
Error: Installation media verification failed
Expected checksum: a1b2c3d4...
Calculated checksum: x9y8z7w6...
```

**Solutions:**

1. **Recreate USB Media**

```powershell
.\helios-usb-wizard.exe --force
# Verify option enabled by default
```

2. **Verify Source Download**

```powershell
Get-FileHash helios-v2.5.1.zip -Algorithm SHA256
# Compare with official checksum
```

3. **Redownload Installation Package**
   - Visit official Helios download page
   - Redownload v2.5.1 package
   - Verify checksum again
   - Recreate USB

---

## Boot Issues: Solutions

### Boot Problem: "No bootable media found"

**Symptoms:**

```
No bootable devices found
Press any key to continue...
```

**Solutions:**

1. **Verify USB Bootability**

```powershell
helios-cli usb verify --device D:
# Expected: ✓ USB bootable media verified
```

2. **Check BIOS Boot Order**
   - Enter BIOS/UEFI: Press F2, F12, DEL, or ESC during startup
   - Verify USB is first in boot order
   - Some systems: "Boot to USB" or "External Media"

3. **Try Different USB Port**
   - USB 3.0 ports (usually blue inside)
   - Avoid USB hub, use direct connection
   - Front panel USB if motherboard has them

4. **Disable Secure Boot** (BIOS setting)
   - BIOS → Security → Secure Boot: Disabled
   - Save and reboot

### Boot Problem: "Kernel panic on boot"

**Symptoms:**

```
Kernel panic - not syncing: VFS: Unable to mount root fs
Press any key to continue...
```

**Solutions:**

1. **Boot into Recovery Mode**
   - Insert deployment USB
   - Select "Recovery Mode" at boot menu
   - Run `helios-cli recover` at prompt

2. **Repair Boot Files**

```powershell
helios-cli repair --type boot
# Restores boot sector and bootloader
```

3. **Restore from Backup** (if available)

```powershell
helios-cli restore --backup previous
# Restores to previous known-good state
```

### Boot Problem: "Stuck at bootloader screen"

**Symptoms:**

```
Loading Helios Bootloader...
[Progress bar frozen at 30%]
```

**Solutions:**

1. **Force Reboot**
   - Hold Power button for 10 seconds
   - Wait 30 seconds
   - Power on again

2. **Reset BIOS**
   - Enter BIOS/UEFI setup
   - Select "Load Default Settings"
   - Save and exit

3. **Boot with Different USB Port**
   - USB loading may fail on specific port
   - Try different USB 3.0 port

---

## Update Installation Failures: Rollback Procedure

### Update Error: "Download failed - network timeout"

**Symptoms:**

```
Error: Download failed after 3 retry attempts
Connection timeout: 30 seconds
```

**Solutions:**

1. **Check Network Connection**

```powershell
Test-NetConnection -ComputerName nuget.org -Port 443
ping google.com -Count 4
```

2. **Retry Update Download**

```powershell
helios-cli update download --retry 5
# Retry up to 5 times
```

3. **Use USB Update Method**

```powershell
helios-cli update install --source usb --device D:
# No network required
```

4. **Check Firewall Rules**
   - Windows Defender Firewall: Add Helios to allowed apps
   - Corporate firewall: May block update server
   - Contact network administrator

### Update Error: "Installation failed - insufficient disk space"

**Symptoms:**

```
Error: Installation failed
Required: 2.5 GB
Available: 1.2 GB
```

**Solutions:**

1. **Clean Temporary Files**

```powershell
helios-cli clean --type temp
# Frees typically 2-5 GB
```

2. **Clean Old Updates**

```powershell
helios-cli clean --type updates
# Removes cached update packages
```

3. **Clean System Logs**

```powershell
helios-cli clean --type logs
# Frees typically 0.5-1 GB
```

4. **Full System Cleanup**

```powershell
helios-cli clean --type all
# Comprehensive cleanup: 5-10 GB typical
```

**Expected Output:**

```
Cleaning temporary files... ✓
Cleaning update cache... ✓
Cleaning logs... ✓
Total freed: 8.2 GB
Available disk space: 9.4 GB
```

### Rollback Procedure (If Update Fails)

**Automatic Rollback (v2.5.1 Feature):**

```
Update installation failed at 67%
Rolling back to previous version automatically...

Status:
  Restoring system files... ✓
  Restoring configuration... ✓
  Verifying system integrity... ✓

✓ Rollback completed successfully
Current version: v2.5.1 (previous)
System stable
```

**Manual Rollback:**

```powershell
# 1. Check available backups
helios-cli backup list

# 2. Initiate rollback
helios-cli update rollback --backup 2024-01-15

# 3. Verify
helios-cli version
# Should show previous version
```

**Step-by-Step Manual Recovery:**

```powershell
# Step 1: Stop any running updates
helios-cli update cancel

# Step 2: Rollback
helios-cli update rollback

# Step 3: Verify system
helios-cli status
# Check all subsystems report OK

# Step 4: Reboot
Restart-Computer -Force
```

---

## Performance Issues: Optimization Tips

### Issue: Slow Download Speeds

**Problem:**

```
Download speed: 2 MB/s (expected 50+ MB/s)
```

**Solutions:**

1. **Check Network Speed**

```powershell
# Measure actual speed
Invoke-WebRequest -Uri "http://speedtest.example.com/file.zip" -OutFile speed_test.zip

# Expected: 50+ MB/s
```

2. **Verify Parallel Downloads** (v2.5.1)

```powershell
helios-cli update download --verbose
# Should show 4 concurrent downloads
```

3. **Optimize Network Connection**
   - Use wired Ethernet (not WiFi)
   - Reduce WiFi interference (5GHz band)
   - Move closer to router
   - Restart modem/router

4. **Check for Bandwidth Throttling**

```powershell
# Disable any VPN
# Disable QoS (Quality of Service) if enabled
# Check ISP throttling (run test at different times)
```

### Issue: High Memory Usage During Operations

**Problem:**

```
RAM usage: 6.8 GB (8 GB total - system struggling)
```

**Solutions:**

1. **Reduce Parallel Downloads**

```powershell
helios-cli update download --max-concurrent 2
# Default 4, reduce to 2 or 1
```

2. **Close Unnecessary Applications**

```powershell
# List top memory consumers
Get-Process | Sort-Object WorkingSet -Descending | 
  Select-Object -First 10 Name, WorkingSet
```

3. **Disable Visual Effects** (GUI optimization)

```
Settings → Display → Visual effects: Set to Minimal
```

4. **Increase Virtual Memory**
   - Windows: Right-click Computer → Properties → Advanced → Virtual Memory
   - Set Initial Size: 8 GB
   - Set Maximum Size: 16 GB

### Issue: Slow GUI Rendering

**Problem:**

```
GUI freezes for 800ms when switching tabs
```

**Solutions:**

1. **Verify StringBuilder Optimization** (v2.5.1)
   - GUI should use StringBuilder for string operations
   - Check logs for `StringBuilder enabled: true`

2. **Reduce UI Update Frequency**

```
Settings → Display → Refresh rate: Lower if high
```

3. **Check for UI Bottlenecks**

```powershell
helios-cli profile set --gui-optimization high
```

4. **Disable Hardware Acceleration** (if causes issues)

```
Settings → Display → Hardware acceleration: Disabled
```

---

## Security Concerns: Verification Steps

### Security: Verify Installation Media

**Check USB Media Integrity:**

```powershell
helios-cli usb verify --device D:

# Expected output:
# ✓ USB bootable media verified
# ✓ Checksum validation: PASS
# ✓ File integrity: PASS
# ✓ Security signatures: VALID
```

### Security: Verify Update Signature

**Verify Downloaded Update:**

```powershell
helios-cli update verify --file helios-v2.5.2.zip

# Expected output:
# ✓ Signature verification: PASS
# ✓ Certificate: Valid (Expires: 2025-12-31)
# ✓ Publisher: Helios Platform Inc.
# ✓ Update safe to install
```

### Security: Check System Integrity

**Run Integrity Check:**

```powershell
helios-cli security check

# Output:
# System files integrity: ✓ PASS
# Security policies: ✓ PASS
# Firewall status: ✓ ENABLED
# Antivirus status: ✓ ENABLED
# All checks passed
```

---

## Network Issues: Diagnostics

### Network Problem: "Cannot reach update server"

**Diagnostics:**

```powershell
# 1. Check basic connectivity
ping 8.8.8.8
# Should receive replies

# 2. Check DNS resolution
nslookup updates.helios-platform.com
# Should resolve to IP address

# 3. Test connection to update server
Test-NetConnection -ComputerName updates.helios-platform.com -Port 443
# Should show: TcpTestSucceeded: True

# 4. Traceroute to server
tracert updates.helios-platform.com
# Check for timeout/unreachable hops
```

### Network Problem: "Firewall blocking connections"

**Solutions:**

1. **Check Windows Firewall**

```powershell
# List all rules
Get-NetFirewallRule | Where-Object {$_.DisplayName -like '*Helios*'}

# Add Helios to firewall
New-NetFirewallRule -DisplayName "Helios Platform" `
  -Direction Outbound -Action Allow -Program "C:\Program Files\Helios\helios.exe"
```

2. **Configure Corporate Firewall**
   - Contact IT department
   - Allow domain: `*.helios-platform.com`
   - Allow ports: 80, 443, 8080

3. **Check Antivirus Blocking**

```
Antivirus → Firewall/Network → Add exception for Helios
```

### Network Problem: "VPN blocking updates"

**Solutions:**

1. Temporarily disable VPN
2. Run update download
3. Re-enable VPN afterward

---

## Frequently Asked Questions (FAQ)

### Q1: How do I verify v2.5.1 is correctly installed?

**A:**

```powershell
helios-cli version
# Should output: Helios Platform v2.5.1

helios-cli status
# All components should show: ✓ OK
```

### Q2: Can I rollback from v2.5.1 to v2.5.0?

**A:**
Yes, automatic rollback is supported:

```powershell
helios-cli update rollback --backup v2.5.0
```

### Q3: What's the maximum concurrent downloads?

**A:** Default is 4 concurrent downloads (v2.5.1 optimization). Can be adjusted:

```powershell
helios-cli config set --max-downloads 8
```

### Q4: How long does a typical deployment take?

**A:**

- With deployment USB: 15-20 minutes (includes boot)
- Online update: 5-15 minutes (depends on file sizes)
- Profile switching: 2-3 minutes

### Q5: Can I cancel an update in progress?

**A:**

```powershell
helios-cli update cancel
# System will rollback automatically
```

### Q6: How much bandwidth does an update use?

**A:**

- Minimal profile: ~300 MB
- Standard profile: ~800 MB  
- Enterprise profile: ~1.2 GB
- All profiles include parallel downloads (3-4x faster)

### Q7: What if USB creation is interrupted?

**A:**
You can safely restart:

```powershell
.\helios-usb-wizard.exe --resume
# Resumes from last checkpoint
```

### Q8: How do I update to v2.5.1 from earlier versions?

**A:**

```powershell
# Online
helios-cli update check
helios-cli update download
helios-cli update install

# Or USB
.\helios-usb-wizard.exe --update-media
```

### Q9: Are there breaking changes in v2.5.1?

**A:**
No, v2.5.1 is fully backward compatible with v2.5.0.

### Q10: What if I run out of disk space during update?

**A:**
Clean system first:

```powershell
helios-cli clean --type all  # Frees 5-10 GB
helios-cli update download   # Retry download
```

### Q11: Can I deploy v2.5.1 to multiple systems?

**A:**
Yes, create USB media and use for multiple systems:

```powershell
# Create USB for first system
.\helios-usb-wizard.exe

# Copy USB contents to another USB for second system
# Or use network deployment:
helios-cli deploy --profile Standard --target-ips 192.168.1.100-150
```

### Q12: Does v2.5.1 require system restart?

**A:**
Yes, after major updates:

```powershell
# Automatic restart
helios-cli update install --auto-restart

# Or manual restart later
Restart-Computer -Force
```

---

## Support Resources

| Issue Type | Resource |
|-----------|----------|
| API Questions | See [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) |
| Performance Tuning | See [OPTIMIZATION_GUIDE.md](./OPTIMIZATION_GUIDE.md) |
| Deployment Help | See [DEPLOYMENT_MANUAL.md](./DEPLOYMENT_MANUAL.md) |
| Technical Support | `helios-cli support open` |

---

## Emergency Recovery

**If system is completely unresponsive:**

1. Create recovery USB (if you have another computer)
2. Boot from USB into recovery mode
3. Run: `helios-cli recover --force`
4. System will restore to known-good state

**Contact Support If:**

- Recovery mode won't start
- All rollback attempts fail
- Multiple hardware failures detected
- Unknown error codes (error code starting with E)

---

Last Updated: 2024  
Troubleshooting Version: v2.5.1
