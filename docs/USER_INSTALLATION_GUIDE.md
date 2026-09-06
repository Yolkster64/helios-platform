# HELIOS Platform - Installation Guide

**From USB Installer to Production Deployment**

---

## 📋 Table of Contents

1. [Pre-Installation Requirements](#pre-installation-requirements)
2. [USB Installation Method](#usb-installation-method)
3. [Network Installation Method](#network-installation-method)
4. [Post-Installation Setup](#post-installation-setup)
5. [Initial Configuration](#initial-configuration)
6. [Verification & Testing](#verification--testing)
7. [Troubleshooting](#troubleshooting)

---

## Pre-Installation Requirements

### Hardware Requirements

**Minimum**:

- CPU: 4 cores
- RAM: 16 GB
- Storage: 100 GB SSD (recommended)
- Network: 1 Gbps connection

**Recommended for Production**:

- CPU: 8+ cores
- RAM: 32 GB or more
- Storage: 500 GB SSD
- Network: 10 Gbps connection
- Redundant power supply

### Software Requirements

**Supported Operating Systems**:

- Windows Server 2019 or newer
- Windows Server 2022
- Linux (Ubuntu 20.04 LTS or newer)
- RHEL 8.0 or newer

**Required Software**:

- .NET 8.0 Runtime or later
- Docker (optional, for containerized deployment)
- Azure CLI (for Azure integration)
- PowerShell 7+ (Windows)

### Network Requirements

- **Firewall Access**: Ports 443 (HTTPS), 8080 (HTTP), 5432 (DB)
- **Internet Access**: Required for Azure services
- **DNS Resolution**: Must resolve Azure endpoints
- **Outbound HTTPS**: Unrestricted

### Credentials Required

Before starting, gather:

- **Azure Subscription ID**
- **Azure Service Principal credentials** (or use managed identity)
- **Admin username and password** for initial setup
- **SSL Certificate** (for HTTPS endpoints)

---

## USB Installation Method

### Step 1: Prepare USB Drive

**What happens**: Format and prepare a USB drive for installation media.

**On Windows**:

```powershell
# 1. Insert USB drive (8GB minimum)
# 2. Open PowerShell as Administrator
# 3. List drives
Get-Disk | Where-Object BusType -eq USB

# 4. Format the USB (replace X with drive number)
# ⚠️ WARNING: This erases all data on the USB
Format-Volume -DriveLetter G -FileSystem NTFS -NewFileSystemLabel "HELIOS-Install"
```

**On Linux**:

```bash
# 1. Insert USB drive
# 2. Identify the device
lsblk

# 3. Unmount if mounted
sudo umount /dev/sdX

# 4. Format the USB
sudo mkfs.ntfs -L HELIOS-Install /dev/sdX
```

### Step 2: Copy Installation Files

**What happens**: Download and copy HELIOS Platform installation files to the USB drive.

**File Structure to Create**:

```
USB Drive:/
├── HELIOS-Platform/
│   ├── installer/
│   │   ├── setup.exe (Windows) or setup.sh (Linux)
│   │   ├── prerequisites.ps1
│   │   └── config-template.json
│   ├── README.txt
│   ├── SYSTEM_REQUIREMENTS.txt
│   └── LICENSE.txt
├── Drivers/ (if needed)
└── Updates/ (latest patches)
```

**Download Installation Files**:

```powershell
# Windows
# Option 1: From GitHub Release
# Visit: https://github.com/M0nado/helios-platform/releases
# Download: HELIOS-Platform-v1.0.0-win-x64.zip
# Extract to USB drive

# Option 2: Using PowerShell
$url = "https://github.com/M0nado/helios-platform/releases/download/v1.0.0/HELIOS-Platform-v1.0.0-win-x64.zip"
Invoke-WebRequest -Uri $url -OutFile "G:\HELIOS-Installer.zip"
Expand-Archive -Path "G:\HELIOS-Installer.zip" -DestinationPath "G:\HELIOS-Platform"
```

### Step 3: Boot from USB

**What happens**: System boots from USB instead of internal drive.

**On Physical Server**:

1. Insert USB drive
2. Power on the system
3. Press boot menu key during startup (usually F12, ESC, or DEL - check your server manual)
4. Select USB drive from boot menu
5. System boots into HELIOS Pre-Installation Environment

**What you'll see**:

```
╔════════════════════════════════════════════╗
║  HELIOS Platform Installation Environment  ║
║          Version 1.0.0 (2026-04)           ║
╚════════════════════════════════════════════╝

Initializing system...
- Detecting hardware: ✓
- Loading drivers: ✓
- Mounting USB: ✓

Ready to begin installation.
Press ENTER to continue...
```

### Step 4: Run Installer

**What happens**: Installer runs pre-flight checks and guides you through setup.

**Steps**:

#### 4a. Pre-Flight Checks

The installer verifies your system meets requirements:

```
Checking System Requirements...
✓ CPU Cores: 8 (required: 4)
✓ RAM: 32 GB (required: 16 GB)
✓ Storage: 500 GB available (required: 100 GB)
✓ Network: Connected (1 Gbps)
✓ Ports available: 443, 8080, 5432
⚠ Windows Firewall: Will be configured

All checks passed! Proceeding...
```

#### 4b. User Input

You'll be prompted for:

```
═══════════════════════════════════════════════
HELIOS Platform Setup - User Configuration
═══════════════════════════════════════════════

1. Deployment Tier
   [ ] Basic (Single server, 100k operations/day)
   [ ] Professional (HA, 1M operations/day)
   [X] Enterprise (Multi-region, unlimited)

2. Server Name
   Enter server name: [HELIOS-PROD-01]

3. Installation Path
   Default: C:\Program Files\HELIOS
   Custom: [C:\HELIOS]

4. Admin Credentials
   Username: [admin]
   Password: ••••••••
   Confirm:  ••••••••

5. Network Configuration
   Hostname: [helios-prod-01.company.local]
   IP Address: [Auto-DHCP] or [192.168.1.10]
   
6. Azure Configuration
   Subscription ID: [xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx]
   Tenant ID: [xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx]
   Client ID: [xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx]
   Client Secret: ••••••••

Ready to install? [Y/N]: Y
```

#### 4c. Installation Progress

The system will:

1. **Extract Files** (2-3 min)
2. **Install Dependencies** (5-10 min)
3. **Configure Services** (3-5 min)
4. **Set Up Database** (2-3 min)
5. **Initialize Security** (3-5 min)
6. **Deploy Components** (5-10 min)

**What you'll see**:

```
Installation Progress...

[████████░░] 40%  Installing .NET Runtime
[██████████] 50%  Configuring Database
[██████████] 60%  Setting up Security Layer
[██████████] 70%  Deploying Services
[██████████] 80%  Initializing AI Components
[██████████] 90%  Running Verification Tests
[██████████] 100% Installation Complete!

✓ Installation finished successfully
✓ Total time: 28 minutes
✓ Server is ready for deployment
```

### Step 5: Remove USB & Reboot

**What happens**: System reboots from installed OS.

```powershell
# Remove USB drive when prompted
# System will reboot into Windows/Linux with HELIOS installed

# You'll see:
"Installation complete. Please remove USB drive and press ENTER to reboot..."

# After reboot:
# Windows: HELIOS Service starts automatically
# Linux: systemctl start helios
```

---

## Network Installation Method

### Alternative: Download & Install from Network

**For servers without USB drive support**:

#### Using PowerShell (Windows)

```powershell
# 1. Download installer
$url = "https://releases.helios-platform.com/v1.0.0/setup.exe"
$installer = "C:\Temp\helios-setup.exe"
Invoke-WebRequest -Uri $url -OutFile $installer

# 2. Run installer with options
& $installer `
  -DeploymentTier "Professional" `
  -ServerName "HELIOS-PROD-01" `
  -InstallPath "C:\HELIOS" `
  -AzureSubscription "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -AdminUsername "admin" `
  -AdminPassword "SecurePassword123!" `
  -Unattended

# 3. Monitor progress
Get-Process helios-setup | Wait-Process
```

#### Using Bash (Linux)

```bash
#!/bin/bash

# 1. Download installer
curl -O https://releases.helios-platform.com/v1.0.0/setup.sh
chmod +x setup.sh

# 2. Run installer
./setup.sh \
  --deployment-tier=Professional \
  --server-name=HELIOS-PROD-01 \
  --install-path=/opt/helios \
  --azure-subscription=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --admin-username=admin \
  --admin-password=SecurePassword123! \
  --unattended

# 3. Wait for completion
tail -f /var/log/helios-installation.log
```

---

## Post-Installation Setup

### What Happens After Installation

After the installer completes, the following is automatically configured:

**1. Services Registered**

```
Windows:
✓ HELIOS Platform Service (started)
✓ HELIOS Background Jobs (started)
✓ HELIOS Monitoring Agent (started)

Linux:
✓ helios.service (enabled & started)
✓ helios-monitoring.service (enabled)
✓ helios-cleanup.timer (enabled)
```

**2. Database Initialized**

```
✓ SQL Server or PostgreSQL database created
✓ Schema tables populated
✓ Indexes created
✓ Stored procedures compiled
```

**3. Security Configured**

```
✓ SSL/TLS certificates installed
✓ Firewall rules applied
✓ Default admin account created
✓ Audit logging enabled
```

**4. Network Services Started**

```
✓ HTTP server listening on port 8080
✓ HTTPS server listening on port 443
✓ WebSocket server listening on port 8443
✓ API Gateway running
```

### Initial Login

**First Time Login**:

```
1. Open web browser
2. Navigate to: https://localhost (or https://server-ip)

3. Login with credentials:
   Username: admin
   Password: [the password you set during installation]

4. First time prompt:
   - Change admin password
   - Accept license agreement
   - Configure basic settings
```

**What you'll see**:

```
╔════════════════════════════════════════════╗
║  HELIOS Platform - Welcome Screen          ║
╚════════════════════════════════════════════╝

Welcome to HELIOS Platform v1.0.0

□ I have read and accept the license agreement
□ I understand the system requirements

[Configure Now]  [Skip & Continue]

After accepting, you'll be directed to the Dashboard.
```

---

## Initial Configuration

### Step 1: Configure Admin Settings

**Location**: Settings → Administration → System

```
System Configuration:

Server Name:              HELIOS-PROD-01
Server ID:                [UNIQUE_ID_GENERATED]
Deployment Tier:          Professional
Time Zone:                America/New_York
NTP Server:               time.windows.com
Syslog Server:            [optional]
```

### Step 2: Configure Azure Integration

**Location**: Settings → Cloud Integration → Azure

```
Azure Configuration:

Subscription ID:          xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Tenant ID:               xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Managed Identity:        [option to enable]
Key Vault:               helios-keyvault-prod

Storage Accounts:
- helios-storage-prod    [Connected ✓]
- helios-backup-prod     [Connected ✓]

Cosmos DB:
- helios-cosmos-prod     [Connected ✓]
```

### Step 3: Configure Network & Security

**Location**: Settings → Network & Security

```
Network Configuration:

Hostname:                 helios-prod-01.company.local
DNS Servers:              8.8.8.8, 8.8.4.4
Domain:                   company.local
Static IP:                192.168.1.10
Gateway:                  192.168.1.1
Subnet Mask:              255.255.255.0

Security:

SSL Certificate:          [Valid until 2025-12-31]
Firewall Mode:            Enabled
Port Rules:
  - 443: HTTPS (allowed)
  - 8080: HTTP (allowed)
  - 5432: PostgreSQL (restricted to local)
  - 22: SSH (restricted to admin subnet)
```

### Step 4: Configure Backup & Disaster Recovery

**Location**: Settings → Backup & Recovery

```
Backup Configuration:

Schedule:                 Daily at 2:00 AM
Retention Policy:         30 days
Backup Location:          Azure Blob Storage
Encryption:               AES-256

Disaster Recovery:

DR Site:                  [Secondary site configured]
Replication:              Continuous
RTO (Recovery Time):      15 minutes
RPO (Data Loss):          5 minutes

Last Backup:              2026-04-16 02:00:00
Status:                   ✓ Successful
```

---

## Verification & Testing

### Step 1: Verify Installation

**Run Health Check**:

```powershell
# Windows
PS> $healthCheck = Invoke-WebRequest `
  -Uri "https://localhost/api/health" `
  -SkipCertificateCheck

PS> $healthCheck.Content | ConvertFrom-Json | Format-Table

# Output:
Status          ✓ Healthy
Version         1.0.0
Uptime          2 days, 14 hours
Memory Usage    45% (14.4 GB / 32 GB)
Storage         12% (60 GB / 500 GB)
Database        ✓ Connected
Services        ✓ All running (8/8)
```

### Step 2: Run Diagnostic Tests

**Location**: Tools → Diagnostics

```
Diagnostic Tests:

System Tests:
  ✓ CPU Performance:        Passed (Score: 8.5/10)
  ✓ Memory:                 Passed (32 GB available)
  ✓ Storage I/O:            Passed (450 MB/s read)
  ✓ Network:                Passed (1 Gbps, 0% packet loss)

Service Tests:
  ✓ API Gateway:            Responding (200 OK)
  ✓ Auth Service:           Responding (200 OK)
  ✓ Analytics:              Responding (200 OK)
  ✓ AI Integration:         Responding (200 OK)

Database Tests:
  ✓ Connection:             Established
  ✓ Query Performance:       275 ms avg query time
  ✓ Backup Status:          Last backup 2 hours ago
  ✓ Replication:            Healthy (5s lag)

Security Tests:
  ✓ SSL/TLS:                Valid certificate
  ✓ Firewall:               All rules configured
  ✓ Authentication:         Active
  ✓ Audit Logging:          Enabled

Overall Status: ✓ PASSED (100% healthy)
```

### Step 3: Test Core Functionality

**Test 1: API Gateway**

```bash
# Test basic API connectivity
curl -k https://localhost/api/health

# Response:
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2026-04-16T23:31:37Z"
}
```

**Test 2: Authentication**

```bash
# Get auth token
TOKEN=$(curl -k -X POST https://localhost/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}' \
  | jq -r '.token')

echo $TOKEN
```

**Test 3: Create Test Data**

```bash
# Create a test resource
curl -k -X POST https://localhost/api/resources \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Resource",
    "type": "test",
    "config": {}
  }'
```

---

## Troubleshooting

### Common Installation Issues

#### Issue 1: Installation Fails at "Setting Up Database"

**Symptoms**:

```
[████████░░] 50% Setting up Database
ERROR: Connection failed to database server
Installation aborted.
```

**Solutions**:

1. **Check SQL Server is running**:

   ```powershell
   # Windows
   Get-Service MSSQLSERVER | Start-Service
   
   # Linux (PostgreSQL)
   sudo systemctl start postgresql
   ```

2. **Verify network connectivity**:

   ```powershell
   Test-NetConnection -ComputerName localhost -Port 5432
   ```

3. **Check firewall**:

   ```powershell
   Get-NetFirewallRule -DisplayName "*SQL*"
   ```

#### Issue 2: Azure Configuration Fails

**Symptoms**:

```
Authentication failed to Azure subscription
Error: Invalid credentials
```

**Solutions**:

1. **Verify credentials**:

   ```powershell
   az login --service-principal `
     -u $CLIENT_ID `
     -p $CLIENT_SECRET `
     --tenant $TENANT_ID
   ```

2. **Check permissions**:
   - Verify Service Principal has "Contributor" role
   - Check subscription access

3. **Validate credentials format**:
   - Client ID must be a valid UUID
   - Client Secret must be URL-encoded

#### Issue 3: Services Won't Start After Reboot

**Symptoms**:

```
HELIOS Platform service failed to start
Error: "The service did not respond to the start or control request in a timely fashion"
```

**Solutions**:

```powershell
# 1. Check service status
Get-Service HELIOS*

# 2. View error logs
Get-EventLog -LogName Application -Source HELIOS -Newest 10

# 3. Restart dependencies
Restart-Service -Name "HELIOS Platform Service" -Force

# 4. If still failing, check disk space
Get-Volume | Where-Object DriveLetter -eq C

# 5. Clear temporary files
Remove-Item -Path "C:\HELIOS\temp\*" -Recurse -Force
```

#### Issue 4: High Memory Usage After Installation

**Symptoms**:

```
Memory usage: 95% (30.4 GB / 32 GB)
System is slow
```

**Solutions**:

1. **Adjust memory limits** (Settings → Performance):

   ```
   Max Memory for Services:    24 GB
   Cache Size:                 4 GB
   Buffer Pool:                2 GB
   ```

2. **Enable memory compression**:

   ```powershell
   Enable-MMAgent -OperationAPI
   ```

3. **Clear application cache**:

   ```powershell
   Remove-Item -Path "C:\HELIOS\cache\*" -Recurse -Force
   ```

---

## Uninstallation

**If you need to remove HELIOS Platform**:

### Windows

```powershell
# 1. Stop services
Stop-Service -Name "HELIOS*" -Force

# 2. Run uninstaller
& "C:\Program Files\HELIOS\uninstall.exe"

# 3. Or use Control Panel
# Settings → Apps → Apps & Features → HELIOS Platform → Uninstall

# 4. Remove residual files (optional)
Remove-Item -Path "C:\HELIOS\" -Recurse -Force
Remove-Item -Path "C:\Program Files\HELIOS" -Recurse -Force
```

### Linux

```bash
# 1. Stop services
sudo systemctl stop helios

# 2. Remove package
sudo apt remove helios-platform  # Ubuntu/Debian
sudo yum remove helios-platform  # RHEL/CentOS

# 3. Remove data (optional)
sudo rm -rf /opt/helios
sudo rm -rf /var/lib/helios
```

---

## Next Steps

After successful installation and verification:

1. **Read**: [USER_DEPLOYMENT_GUIDE.md](USER_DEPLOYMENT_GUIDE.md)
   - Deploy your first application
   - Configure settings for production

2. **Configure**: [USER_OPERATIONS_GUIDE.md](USER_OPERATIONS_GUIDE.md)
   - Daily operations
   - Monitoring & alerts
   - Maintenance tasks

3. **Learn Advanced**: [USER_ADVANCED_GUIDE.md](USER_ADVANCED_GUIDE.md)
   - Custom configurations
   - Advanced security settings
   - Performance tuning

4. **Get Help**: [USER_TROUBLESHOOTING.md](USER_TROUBLESHOOTING.md)
   - Common issues
   - Support resources
   - Emergency procedures

---

## Support & Resources

- **Documentation**: [docs/NAVIGATION.md](NAVIGATION.md)
- **Tutorials**: Video guides available at helios-platform.com
- **Support**: support@helios-platform.com
- **Community**: GitHub Issues & Discussions

---

**Happy installing! 🚀**

*Last Updated: April 2026*  
*Version: 1.0.0*
