# Deployment Manual v2.5.1

Complete step-by-step guide for deploying Helios Platform v2.5.1, including pre-deployment checklist, USB creation, boot phases, and system configuration.

---

## Pre-Deployment Checklist

Before starting deployment, verify all requirements are met.

### System Requirements

#### Minimum Specifications

| Component | Requirement |
|-----------|-------------|
| **CPU** | 2-core processor 2.0 GHz or higher |
| **RAM** | 4 GB minimum |
| **Disk Space** | 20 GB available for deployment |
| **USB Device** | USB 3.0 drive, 16 GB or larger |
| **Network** | Internet connection (50 Mbps+ recommended) |
| **OS** | Windows 10/11, Linux, or macOS |

#### Recommended Specifications

| Component | Recommendation |
|-----------|-----------------|
| **CPU** | 4-core processor 2.5 GHz or higher |
| **RAM** | 8 GB or more |
| **Disk Space** | 50 GB available |
| **USB Device** | USB 3.1 drive, 32 GB |
| **Network** | 100 Mbps+ for faster downloads |

### Pre-Deployment Checklist

**Complete before proceeding:**

- [ ] Verify system meets minimum requirements
- [ ] Connect reliable internet (50+ Mbps recommended)
- [ ] Back up existing system data
- [ ] Have USB 3.0+ drive (16GB minimum, 32GB recommended)
- [ ] Download v2.5.1 installation package
- [ ] Verify installation media checksum
- [ ] Clear adequate disk space (20GB minimum)
- [ ] Disable antivirus temporarily during deployment
- [ ] Note network adapter MAC address
- [ ] Have profile configuration ready (see "5 Available Profiles")

### Verify Installation Package

**Checksum Verification (Windows):**

```powershell
Get-FileHash -Path "helios-v2.5.1.zip" -Algorithm SHA256
# Expected: a1b2c3d4e5f6...
```

**Checksum Verification (macOS/Linux):**

```bash
sha256sum helios-v2.5.1.zip
# Expected: a1b2c3d4e5f6...
```

---

## USB Wizard Step-by-Step Walkthrough

The USB Wizard guides you through creating bootable deployment media.

### Step 1: Launch USB Wizard

**Windows:**

```powershell
.\helios-usb-wizard.exe
```

**macOS/Linux:**

```bash
./helios-usb-wizard
```

**Expected Output:**

```
====================================
Helios Platform v2.5.1 USB Wizard
====================================

Scanning USB devices...
Found 2 USB devices:
  1. SanDisk Ultra (32 GB) - /dev/sdb
  2. Kingston DataTraveler (16 GB) - /dev/sdc

Select USB device [1-2]:
```

### Step 2: Select USB Device

**Action:**

1. List shows available USB devices
2. Enter the number of your USB device
3. **⚠️ Warning**: This will erase all data on the USB device!
4. Type `yes` to confirm

**Example:**

```
Select USB device [1-2]: 1

⚠️  WARNING: This will erase SanDisk Ultra (32 GB)
   All data will be permanently deleted.

Are you sure? [yes/no]: yes

✓ USB device selected: SanDisk Ultra (32 GB)
```

### Step 3: Select Deployment Profile

Five profiles are available. Select one:

| Profile | Use Case | Size |
|---------|----------|------|
| **Minimal** | Lightweight systems | 8 GB |
| **Standard** | Most deployments | 16 GB |
| **Enterprise** | Large organizations | 24 GB |
| **Development** | Development/testing | 20 GB |
| **Custom** | User-defined | Varies |

**Example:**

```
Available profiles:
  1. Minimal (8 GB) - Lightweight systems
  2. Standard (16 GB) - Default deployment
  3. Enterprise (24 GB) - Large organizations
  4. Development (20 GB) - Development/testing
  5. Custom (Select files)

Select profile [1-5]: 2

✓ Profile selected: Standard
```

### Step 4: Review Configuration

Review deployment configuration before proceeding:

**Example:**

```
====================================
Deployment Configuration Review
====================================

Target USB Device:  SanDisk Ultra (32 GB)
Selected Profile:   Standard (16 GB)
Installation Size:  16 GB
Estimated Time:     ~12 minutes (4x concurrent downloads)

Boot Options:
  - Auto-setup: Enabled
  - Network discovery: Enabled
  - Rollback support: Enabled

Continue with deployment? [yes/no]: yes

✓ Proceeding with USB creation...
```

### Step 5: Monitor Creation Progress

**Progress Display:**

```
Creating bootable USB media...

[████████░░] 45% - 6 minutes 23 seconds remaining
Current file: core-components.zip (3 of 8)
Download speed: 125 MB/s

Last completed:
  ✓ boot-loader.zip
  ✓ drivers.zip
  
Currently downloading:
  ⟳ core-components.zip (45% complete)
```

**Note**: v2.5.1 uses 4-concurrent parallel downloading for 3-4x faster speed.

### Step 6: Completion

**On Success:**

```
✓ USB creation completed successfully!

Media Details:
  Device:      SanDisk Ultra (/dev/sdb)
  Profile:     Standard
  Size:        16 GB
  Created:     2024-01-15 14:32:45
  Status:      Ready for deployment

Next steps:
  1. Keep USB connected
  2. Boot target system from USB
  3. Follow boot-phase setup wizard
  4. System will auto-configure with selected profile

Estimated boot time: 3-5 minutes
```

---

## Boot and Auto-Setup Phases

After creating USB media, boot the target system.

### Phase 1: BIOS/UEFI Boot (1-2 minutes)

**Steps:**

1. Insert USB into target computer
2. Power on and enter boot menu (usually F2, F12, DEL, or ESC)
3. Select USB device as boot drive
4. Press Enter to boot

**Expected Sequence:**

```
BIOS/UEFI Boot Menu
  → Select USB Device
  → Press Enter
  ↓
Helios Bootloader Loading...
```

### Phase 2: Bootloader Phase (1-2 minutes)

**What Happens:**

- Bootloader initializes
- System memory test runs
- USB driver loads
- System preparation

**Screen Display:**

```
╔════════════════════════════════════════╗
║  Helios Platform v2.5.1 Bootloader    ║
╠════════════════════════════════════════╣
║  Memory Test...               ✓ Pass   ║
║  USB Driver Init...           ✓ Pass   ║
║  Filesystem Mount...          ⟳ 60%   ║
║  System Preparation...        Pending  ║
╚════════════════════════════════════════╝
```

### Phase 3: Auto-Setup Phase (3-5 minutes)

Automated system configuration runs with selected profile.

**Profile Deployment Tasks:**

```
Setting up profile: Standard

Deploying system components...
  [████████████░░░░░░░░] 60%
  
Current tasks:
  ✓ Core system files (3.2 GB)
  ✓ Drivers installation (1.8 GB)
  ⟳ UI components (2.1 GB) - 40% complete
  ◌ Services configuration (pending)
```

**Configuration Applied:**

- Selected profile settings loaded
- Network drivers installed
- Security policies applied
- Boot options configured

### Phase 4: Post-Boot Transition

**Display Message:**

```
Auto-setup completed successfully!

System is ready for configuration.
Booting into Helios Management Interface...

Starting GUI...
```

---

## Post-Boot GUI Usage (4 Tabs)

After boot, the Helios Management GUI appears with 4 main tabs.

### Tab 1: USB Wizard

Create additional bootable USB devices or re-create current USB.

**Features:**

- Detect connected USB devices
- Select profile for new USB
- Monitor creation progress
- Verify USB media integrity

**Example Usage:**

```
USB Wizard Tab
─────────────────────────────────────

Connected USB Devices:
  ✓ SanDisk Ultra (32 GB) - Current deployment
  
Create new USB:
  [Select Profile ▼] Standard
  [Select USB Device ▼] Choose device...
  
  [Create USB] [Cancel]
  
Creation Progress:
  [No active operations]
```

### Tab 2: Profiles

Switch between 5 available deployment profiles.

**Features:**

- View active profile details
- Switch to different profile
- Preview profile settings
- Export/import custom profiles

**Example Usage:**

```
Profiles Tab
──────────────────────────────────────

Current Profile: Standard

Available Profiles:
┌─────────────────────────────────┐
│ ✓ Minimal (Active)              │ ← Current
│ ◌ Standard                       │
│ ◌ Enterprise                     │
│ ◌ Development                    │
│ ◌ Custom (New)                   │
└─────────────────────────────────┘

Profile Details: Standard
  Version: v2.5.1
  Size: 16 GB
  Components: 8
  Boot time: 3-5 min
  
  [Switch Profile] [Edit] [Export]
```

### Tab 3: Boot Configuration

Configure boot options and parameters.

**Features:**

- Boot sequence settings
- Network discovery options
- Auto-restart configuration
- Hardware detection settings

**Example Usage:**

```
Boot Configuration Tab
───────────────────────────────────

Boot Options:
  ☑ Auto-restart after update
  ☑ Network discovery enabled
  ☐ Debug mode
  ☑ Hardware auto-detection

Boot Sequence:
  1. USB (if available)
  2. Network boot
  3. Hard disk

Network Configuration:
  DHCP: ☑ Enabled
  Static IP: [192.168.1.100___]
  Gateway: [192.168.1.1_______]
  
  [Apply] [Reset] [Restore Defaults]
```

### Tab 4: System Configuration

Configure system settings and deployment options.

**Features:**

- System name configuration
- Network settings
- Security policies
- Update preferences

**Example Usage:**

```
System Configuration Tab
────────────────────────────────────

System Settings:
  Computer Name: [HELIOS-WS01_____]
  Location: [Building A, Floor 3__]
  
Network Settings:
  Interface: Ethernet
  DHCP: ☑ Enabled
  DNS: 8.8.8.8
  
Security:
  Firewall: ☑ Enabled
  Auto-updates: ☑ Enabled
  Update Schedule: [Daily ▼]
  
Regional Settings:
  Language: [English ▼]
  Timezone: [UTC-5 ▼]
  Date Format: [MM/DD/YYYY ▼]
  
  [Save] [Apply] [Cancel]
```

---

## Profile Switching (5 Profiles)

Switch between profiles to change system configuration.

### Available Profiles

#### 1. Minimal Profile

- **Size**: 8 GB
- **Boot Time**: 2 minutes
- **Use Case**: Lightweight systems, basic functionality
- **Components**: Core only

#### 2. Standard Profile (Default)

- **Size**: 16 GB
- **Boot Time**: 3-5 minutes
- **Use Case**: General-purpose deployments
- **Components**: Core + Drivers + UI + Basic tools

#### 3. Enterprise Profile

- **Size**: 24 GB
- **Boot Time**: 5-8 minutes
- **Use Case**: Large-scale organizational deployments
- **Components**: Everything + Advanced tools + Security packages

#### 4. Development Profile

- **Size**: 20 GB
- **Boot Time**: 5 minutes
- **Use Case**: Development and testing
- **Components**: Everything + SDKs + Debugging tools

#### 5. Custom Profile

- **Size**: User-defined
- **Use Case**: Specialized deployments
- **Components**: User-selected

### How to Switch Profiles

**Using GUI:**

1. Open Helios Management GUI
2. Click "Profiles" tab
3. Select desired profile from list
4. Click "Switch Profile"
5. Confirm profile switch
6. System will restart with new profile

**Using Command Line:**

```powershell
# List available profiles
helios-cli profile list

# Switch to profile
helios-cli profile switch --name "Enterprise"

# Export profile
helios-cli profile export --name "Standard" --output profile.json

# Import profile
helios-cli profile import --input custom-profile.json
```

---

## Update Installation (Online + USB Methods)

Helios v2.5.1 supports two update methods.

### Method 1: Online Update

**Requirements:**

- Internet connection (50+ Mbps recommended)
- 1 GB free disk space

**Steps:**

1. **Check for Updates**

```powershell
helios-cli update check
```

2. **Download Update** (with 4-concurrent parallelization)

```powershell
helios-cli update download --version 2.5.1
# Download speed: 3-4x faster with parallel downloads
```

3. **Install Update**

```powershell
helios-cli update install
# Estimated time: 5-15 minutes depending on update size
```

4. **Verify Installation**

```powershell
helios-cli version
# Output: Helios Platform v2.5.1
```

**Example Output:**

```
Checking for updates...
✓ Update found: v2.5.2 (Released: 2024-02-01)
  Size: 450 MB
  Download speed: 125 MB/s
  Estimated time: 3 minutes 36 seconds

Downloading update... [████████████░░] 75%
  Downloaded: 337.5 MB of 450 MB
  Time remaining: 54 seconds

✓ Download completed
✓ Verifying checksum... Pass
✓ Installing update...
✓ Update installed successfully
✓ Version now: v2.5.2
```

### Method 2: USB Update

**Requirements:**

- USB drive with update media (8+ GB)
- USB 3.0+ for best performance

**Steps:**

1. **Create USB Update Media**

```powershell
.\helios-usb-wizard.exe --update-media
```

2. **Insert USB**
Insert the USB drive with update media into the target system.

3. **Install from USB**

```powershell
helios-cli update install --source usb --device D:
```

4. **Verify**

```powershell
helios-cli version
```

**Advantages:**

- No internet required
- Deploy to multiple systems efficiently
- Faster for large deployments (parallel USB copies)

---

## Recovery Procedures

### Scenario 1: Update Failed

**If Update Installation Fails:**

1. **Automatic Rollback** (v2.5.1 feature)

```
Update installation failed at 65%
Rolling back to previous version...
✓ Rollback completed successfully
Current version: v2.5.1 (previous)
```

2. **Manual Rollback** (if auto-rollback fails)

```powershell
helios-cli update rollback
# Restores to previous known-good version
```

3. **Check Status**

```powershell
helios-cli status
# Verify system is running stable version
```

### Scenario 2: System Won't Boot

**Recovery Steps:**

1. **Boot from Deployment USB**
   - Insert original deployment USB
   - Press boot key (F2, F12, DEL, ESC)
   - Select USB device
   - Wait for recovery environment

2. **Run Repair**

```
Recovery Environment
─────────────────────
Repair Options:
  1. Repair boot sector
  2. Restore system files
  3. Full system restore
  4. Rollback to backup
  
Select option [1-4]: 1
```

3. **Reboot**

```powershell
shutdown /r /t 30 /c "System repair complete. Rebooting..."
```

### Scenario 3: Lost Network Connectivity

**Troubleshooting:**

1. **Verify Network Settings**

```powershell
ipconfig /all
# Check IP configuration

ping 8.8.8.8
# Test internet connectivity
```

2. **Reset Network**

```powershell
helios-cli network reset
# Reinitialize network drivers
```

3. **Configure Network Manually**

```
Helios GUI → System Configuration → Network Settings
  IP Address: 192.168.1.X
  Gateway: 192.168.1.1
  DNS: 8.8.8.8
  [Apply]
```

### Scenario 4: Disk Space Issues

**Cleanup Procedures:**

1. **Check Disk Usage**

```powershell
helios-cli disk status
# Shows usage breakdown
```

2. **Clean Temporary Files**

```powershell
helios-cli clean --type temp
# Frees: ~2-5 GB typically
```

3. **Clean Update Cache**

```powershell
helios-cli clean --type updates
# Frees: ~1-3 GB typically
```

---

## System Specifications & Requirements

### Supported Operating Systems

| OS | Minimum Version | Status |
|----|-----------------|--------|
| Windows | 10 (Build 19041) | ✓ Supported |
| Windows | 11 | ✓ Supported |
| Ubuntu | 20.04 LTS | ✓ Supported |
| CentOS | 8 | ✓ Supported |
| macOS | 10.15 | ✓ Supported |
| macOS | 12+ | ✓ Supported |

### Storage Requirements

| Component | Size | Purpose |
|-----------|------|---------|
| **System Files** | 4 GB | Core operating system |
| **Applications** | 3 GB | Helios Platform tools |
| **Profiles** | 2-6 GB | Deployment profiles |
| **Updates Cache** | 1 GB | Update staging area |
| **Logs** | 0.5 GB | System and application logs |
| **Free Space** | 5+ GB | Working directory |
| **Total** | 16-20 GB | Recommended |

### Supported Hardware

| Hardware | Compatibility |
|----------|----------------|
| **CPU** | x64, ARM64 |
| **USB** | USB 2.0+, USB 3.0+ recommended |
| **Network** | Ethernet, WiFi 5GHz/2.4GHz |
| **Storage** | HDD, SSD, NVMe |

### Network Requirements

| Requirement | Details |
|-------------|---------|
| **Speed** | 10 Mbps minimum, 50+ Mbps recommended |
| **Stability** | <5% packet loss preferred |
| **Latency** | <100ms to update servers |
| **Bandwidth** | ~500 MB per deployment |

---

## Troubleshooting Common Issues

### USB Creation Fails

**Solution:**

1. Try different USB drive
2. Format USB as FAT32/NTFS
3. Check USB 3.0 compatibility
4. Disable antivirus during creation
5. Run with administrator privileges

### Slow Download Speed

**Solution:**

1. Check internet connection: `ping 8.8.8.8`
2. Verify no bandwidth throttling
3. Move closer to WiFi router
4. Use wired Ethernet if possible
5. Check firewall settings

### System Won't Boot from USB

**Solution:**

1. Verify USB is bootable: `helios-cli usb verify`
2. Check BIOS boot order
3. Disable Secure Boot temporarily
4. Try different USB port
5. Use different USB drive

---

## Quick Reference

| Task | Command |
|------|---------|
| Check version | `helios-cli version` |
| Update system | `helios-cli update install` |
| Switch profile | `helios-cli profile switch --name "Enterprise"` |
| Check status | `helios-cli status` |
| View logs | `helios-cli logs view --lines 100` |
| Clean system | `helios-cli clean --type all` |
| Reset network | `helios-cli network reset` |
| Verify USB | `helios-cli usb verify --device D:` |
| Rollback update | `helios-cli update rollback` |
| Get help | `helios-cli help` |

---

Last Updated: 2024  
Deployment Version: v2.5.1
