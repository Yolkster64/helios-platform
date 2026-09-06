# Plain English Guide to Phase 1 Security Scripts

This guide explains each security component in plain language - what it does, why you need it, and how to use it.

---

## 1. AppLocker Setup (Program Execution Control)

### What It Does

AppLocker is like a bouncer at a nightclub - it checks every program that tries to run and only lets through the ones on the "approved list." Without AppLocker, any program (including malware) can run anything.

**Example**: Your system tries to launch Firefox. AppLocker checks: "Is Firefox on the approved list?" If yes, Firefox runs. If no, AppLocker stops it.

### Why You Need It

- **Stops Malware**: Even if malware gets on your disk, AppLocker prevents it from running
- **Controls Bloatware**: Unwanted programs can't auto-launch
- **Audit Trail**: Every blocked program is logged so you can see attack attempts
- **Reduces Risk**: Limits damage if someone gets access to your account

**Example Problem Without AppLocker**:
A malicious PDF contains a hidden executable. When you open the PDF, it tries to launch `malware.exe` in the background. Without AppLocker, malware.exe runs silently. With AppLocker, it's blocked and logged.

### How To Run

```powershell
# 1. Run PowerShell as Administrator
Start-Process powershell -Verb RunAs

# 2. Navigate to Phase 1 scripts
cd "C:\Users\ADMIN\helios-platform\phases\1-security\scripts"

# 3. Execute the AppLocker script
.\01-applocker-setup.ps1

# 4. When prompted, approve the standard Windows programs
# The script will ask you to confirm each category
```

### What It Changes

**Files Modified**:

- `C:\Windows\System32\drivers\etc\hosts` - May add safe-list entries
- Group Policy Objects (Computer Configuration → Windows Settings → Security Settings)

**Registry Changes**:

```
HKLM:\Software\Policies\Microsoft\Windows\SrpV2
├── AppIdExt (AppLocker extension)
├── EnforceReputationBasedTrustForExecutables
└── Executable Rules (whitelisted programs)
```

**New Files Created**:

- `C:\ProgramData\AppLocker\` - AppLocker policy storage
- `C:\Users\ADMIN\helios-platform\phases\1-security\applocker-whitelist.xml` - Your approved programs list

**Visible Changes**:

- Nothing obvious at first
- Program launches may pause for 2-3 seconds (validation time)
- Blocked programs show error dialog: "This program has been blocked by your administrator"

### How To Undo

```powershell
# Disable AppLocker enforcement
Set-AppLockerPolicy -PolicyObject $null -Enforce None -ErrorAction SilentlyContinue

# Or through Group Policy:
# 1. Press Win+R, type "gpedit.msc"
# 2. Navigate to: Computer Configuration → Windows Settings → Security Settings → Application Control Policies → AppLocker
# 3. Right-click each rule and select "Disable"
```

### Before/After State

**Before AppLocker**:

```
User wants to run Firefox
    ↓
Windows checks: "Is this signed?" (Windows SmartScreen, if enabled)
    ↓
Firefox launches (or malware disguised as Firefox)
```

**After AppLocker**:

```
User wants to run Firefox
    ↓
AppLocker checks: "Is Firefox on the approved list?"
    ↓
  YES → Firefox launches
  NO → Blocked, logged, administrator notified
```

**Example Scenarios**:

| Program | Before | After | Log Entry |
|---------|--------|-------|-----------|
| Firefox (if whitelisted) | Runs | Runs | N/A |
| Unknown PDF reader | Runs | Blocked | "Blocked: Unknown.exe at 2:45 PM" |
| Windows Notepad | Runs | Runs | N/A |
| Malware.exe | Runs (dangerous!) | Blocked | "Blocked: Malware.exe at 3:12 PM" |

### Performance Impact

- **System Startup**: +5-10 seconds (AppLocker policy loading)
- **Program Launch**: +1-3 seconds (first launch validation)
- **Memory**: +20-50 MB (AppLocker service)

### Troubleshooting

**"A program I need is blocked"**:

1. Find the program's EXE file
2. Get its file hash or publisher certificate
3. Run: `.\01-applocker-add-exception.ps1 "C:\Path\To\Program.exe"`
4. Restart the program

**"AppLocker won't enable"**:

1. Check Group Policy is running: `gpresult /h report.html`
2. Verify Enterprise Services is installed
3. Reboot the system
4. Try again

---

## 2. Firewall Configuration (Network Security)

### What It Does

Windows Firewall acts like a security gate for your network - it decides which data packets are allowed in and out. By default, Windows Firewall is permissive. Phase 1 makes it restrictive - only known-good traffic gets through.

**Example**: Your system gets infected with malware. The malware tries to send your passwords to an attacker in China. The hardened firewall blocks this outbound connection.

### Why You Need It

- **Blocks Data Theft**: Malware can't send your data to attackers
- **Prevents Remote Access**: Hackers can't remotely control your PC
- **Controls Lateral Movement**: Restricts access between your PC and network
- **Audit Trail**: Every blocked connection is logged

**Example Problem Without Hardening**:
Ransomware gets on your PC. It tries to scan the network for other victims and find backup servers to destroy. An unsecured firewall allows all outbound traffic, so the ransomware spreads.

### How To Run

```powershell
# 1. Run PowerShell as Administrator
Start-Process powershell -Verb RunAs

# 2. Navigate to Phase 1 scripts
cd "C:\Users\ADMIN\helios-platform\phases\1-security\scripts"

# 3. Execute the Firewall script
.\02-firewall-hardening.ps1

# 4. Restart system when prompted
Restart-Computer -Force
```

### What It Changes

**Files Modified**:

- No configuration files (it's all in the registry and service)

**Registry Changes**:

```
HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy
├── StandardProfile (standard user firewall rules)
├── DomainProfile (if domain-connected)
└── PublicProfile (Wi-Fi networks)

HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules
├── {Inbound rules}
├── {Outbound rules}
└── {Rules for each service}
```

**Firewall Rules Added**:

- Block: All inbound connections (except whitelisted)
- Block: All outbound connections to high-risk ports (445, 139, 135 - SMB/RPC)
- Allow: Windows Update servers
- Allow: Microsoft telemetry (controlled)
- Allow: DNS requests (for domain resolution)

**Visible Changes**:

- Windows Defender Firewall notification area shows changes
- Network discovery is disabled (can't browse network)
- File sharing between PCs is blocked
- Some programs may lose network access (requires manual approval)

### How To Undo

```powershell
# Reset to default firewall rules
netsh advfirewall reset

# Or through Windows Settings:
# 1. Settings → Privacy & Security → Windows Security
# 2. Click "Firewall & network protection"
# 3. Click "Restore firewalls to default"
```

### Before/After State

**Before Firewall Hardening**:

```
Malware.exe on your PC
    ↓
Tries to connect to attacker.com on port 443
    ↓
Firewall checks: "Is this blocked?" → No explicit rule
    ↓
Connection allowed (default permissive)
    ↓
Your passwords get stolen
```

**After Firewall Hardening**:

```
Malware.exe on your PC
    ↓
Tries to connect to attacker.com on port 443
    ↓
Firewall checks: "Is this allowed?" → Only whitelisted connections
    ↓
Connection blocked, logged
    ↓
Your data stays safe
```

**Blocked Ports Reference**:

| Port | Service | Why Blocked | Effect |
|------|---------|------------|--------|
| 135-139 | RPC/NetBIOS | Lateral movement | Network PCs hidden |
| 445 | SMB (file sharing) | Ransomware spreading | Can't share drives |
| 3389 | RDP (remote access) | Remote control | Hackers can't connect |
| 3306 | MySQL | Lateral movement | Database servers hidden |
| 5432 | PostgreSQL | Lateral movement | Database servers hidden |
| 27017 | MongoDB | Lateral movement | Database servers hidden |

**Allowed Outbound Connections**:

- DNS (port 53) - Domain name resolution
- HTTP/HTTPS (ports 80, 443) - Web browsing
- Windows Update (specific Microsoft IPs)
- NTP (port 123) - Time synchronization

### Performance Impact

- **Network Speed**: Negligible (< 1%)
- **Latency**: None (firewall is kernel-level)
- **Memory**: +10-20 MB (firewall service)

### Troubleshooting

**"I can't access the network"**:

1. Open Windows Defender Firewall with Advanced Security (firewall.cpl)
2. Click "Inbound Rules"
3. Look for your application
4. If blocked, right-click → Properties → Change to "Allow"

**"Internet is slow"**:

1. Check if excessive outbound blocking is happening
2. Review firewall logs: `Get-WinEvent -LogName "Security"`
3. Some rule may be too broad; adjust if needed

---

## 3. Vault Encryption (Sensitive Data Protection)

### What It Does

The Vault is a special encrypted folder where your most sensitive data lives - passwords, API keys, certificates, SSH keys, financial information. Even if someone steals your hard drive, they can't read Vault contents without the encryption key.

**Example**: Your laptop is stolen. Thief pulls out the hard drive and connects it to another computer. They can see your Documents folder, but the Vault is encrypted and unreadable - passwords stay secret.

### Why You Need It

- **Data at Rest Protection**: Encrypts sensitive files on disk
- **Theft Resilience**: Stolen disks are useless without the encryption key
- **Regulatory Compliance**: Meets GDPR, HIPAA, PCI-DSS encryption requirements
- **Peace of Mind**: Sleep at night knowing passwords are protected

**Example Problem Without Encryption**:
Your laptop is stolen at an airport. The thief connects the hard drive to their PC and copies your entire Documents folder, including password files and financial records. Game over.

### How To Run

```powershell
# 1. Run PowerShell as Administrator
Start-Process powershell -Verb RunAs

# 2. Navigate to Phase 1 scripts
cd "C:\Users\ADMIN\helios-platform\phases\1-security\scripts"

# 3. Execute the Vault setup script
.\03-vault-encryption-setup.ps1

# 4. Choose encryption method when prompted:
#    - BitLocker (stronger, requires TPM)
#    - VeraCrypt (portable, needs recovery key)
```

### What It Changes

**Files Created**:

- `C:\Users\ADMIN\Vault\` - Main vault directory (or `C:\Vault` for system vault)
- `C:\Users\ADMIN\Vault\.encrypted` - Encryption metadata
- `C:\Users\ADMIN\Vault\Passwords\` - Passwords and API keys
- `C:\Users\ADMIN\Vault\Certificates\` - SSL certs, SSH keys
- `C:\Users\ADMIN\Vault\Financial\` - Bank account info, tax records
- `C:\Users\ADMIN\Vault\Recovery-Key.txt` - SAVE THIS SOMEWHERE SAFE!

**Registry Changes**:

```
HKLM:\System\CurrentControlSet\Control\FileSystem
├── NtfsEncryptionEnabled (set to 1)
└── EncryptionSupported (checked)

HLKM:\Software\Microsoft\Windows\CurrentVersion\Encryption
└── VaultEncryption
    ├── EncryptionMethod (BitLocker or VeraCrypt)
    ├── EncryptionKeyBackup (recovery key location)
    └── EncryptedFolders (paths being encrypted)
```

**Visible Changes**:

- Vault folder has a lock icon 🔒
- First access to vault takes 10-15 seconds (decryption)
- Blue lock icon appears on encrypted files
- TPM chip LED may blink during first access (if BitLocker used)

### How To Undo

```powershell
# Decrypt the vault (keeps files, removes encryption)
Disable-BitLocker -MountPoint "C:\Users\ADMIN\Vault"

# Monitor decryption progress
Get-BitLockerVolume -MountPoint "C:\Users\ADMIN\Vault"

# Or manually decrypt folder:
# 1. Right-click Vault folder
# 2. Properties → Advanced
# 3. Uncheck "Encrypt contents to secure data"
# 4. Click OK → Apply to all files
```

### Before/After State

**Before Vault Encryption**:

```
Hard drive stolen
    ↓
Thief connects drive to another PC
    ↓
Thief opens C:\Users\ADMIN\Vault\Passwords\passwords.txt
    ↓
All passwords visible in plain text
    ↓
Bank accounts, email, social media - all compromised
```

**After Vault Encryption**:

```
Hard drive stolen
    ↓
Thief connects drive to another PC
    ↓
Thief tries to open C:\Users\ADMIN\Vault\Passwords\passwords.txt
    ↓
File is encrypted, unreadable
    ↓
Attacker needs encryption key to proceed (good luck!)
```

**Vault Structure**:

```
C:\Users\ADMIN\Vault\
├── .encrypted (metadata file)
├── Recovery-Key.txt (PRINT THIS AND STORE SAFELY!)
├── Passwords/
│   ├── personal-accounts.txt (Gmail, personal email)
│   ├── work-accounts.txt (Office 365, GitHub)
│   └── api-keys.txt (API tokens, secrets)
├── Certificates/
│   ├── ssh-keys/ (Private SSH keys)
│   ├── ssl-certs/ (SSL certificates)
│   └── gpg-keys/ (GPG encryption keys)
├── Financial/
│   ├── banking-info.txt (Bank account numbers)
│   ├── tax-records.zip (Tax returns, receipts)
│   └── crypto-wallets.txt (Wallet seeds, keys)
└── Sensitive/
    ├── health-records/ (Medical info)
    ├── legal-docs/ (Contracts, agreements)
    └── personal-data/ (ID scans, passport)
```

### Performance Impact

- **Access Speed**: First access +10-15 seconds (decryption), then normal
- **Disk Space**: +0.5-1% (encryption overhead/metadata)
- **CPU**: +5% when accessing encrypted files

### Troubleshooting

**"I forgot my encryption password"**:

1. Use Recovery Key (hopefully you saved it!)
2. If no recovery key, data is likely unrecoverable (that's how encryption works)
3. Restore from backup

**"Vault is locked and won't open"**:

1. Restart the PC (BitLocker key is cached in memory)
2. Try again
3. If still locked, use recovery key: `manage-bde -recovery -status`

**"Some programs can't access vault files"**:

1. Vault files need special permissions
2. Either move file out of vault, or
3. Give specific program permission: Right-click → Properties → Security → Edit → Add program

---

## 4. Quarantine System (Threat Isolation)

### What It Does

The Quarantine is an isolated, encrypted folder where suspicious files go to die. If malware is detected or a file looks suspicious, instead of deleting it (which might damage important files), it's moved here where it can't harm anything.

**Example**: Windows Defender detects `mysterious-download.exe` as malware. Instead of deleting it, it's moved to `C:\Vault\Quarantine\` where it's encrypted, isolated, and harmless.

### Why You Need It

- **Safe Containment**: Malware is isolated and can't execute
- **Evidence Preservation**: Infected files kept for analysis
- **Recovery Option**: If it was a false positive, files can be restored
- **Prevents Spreading**: Stops malware from affecting other files

**Example Problem Without Quarantine**:
Antivirus detects malware and auto-deletes it. But it was actually a legitimate program that got corrupted. You've lost important software and have to reinstall everything.

### How To Run

```powershell
# 1. Run PowerShell as Administrator
Start-Process powershell -Verb RunAs

# 2. Navigate to Phase 1 scripts
cd "C:\Users\ADMIN\helios-platform\phases\1-security\scripts"

# 3. Execute the Quarantine setup script
.\04-quarantine-system-init.ps1

# 4. When prompted, choose quarantine size:
#    - 1 GB (default, handles most cases)
#    - 5 GB (for frequent threats)
#    - 10 GB (if you get a lot of malware)
```

### What It Changes

**Files Created**:

- `C:\Vault\Quarantine\` - Main quarantine directory
- `C:\Vault\Quarantine\Active\` - Current quarantined files
- `C:\Vault\Quarantine\Archive\` - Old quarantined files (organized by date)
- `C:\Vault\Quarantine\Log.txt` - Log of all quarantined items
- `C:\Vault\Quarantine\Recovery\` - Files queued for restoration

**Registry Changes**:

```
HKLM:\Software\Microsoft\Windows Security\WindowsDefender\Quarantine
├── QuarantinePath (C:\Vault\Quarantine)
├── MaxQuarantineSize (1-10 GB)
├── DeleteQuarantineAfterDays (180 days)
└── EnableQuarantine (1 = enabled)
```

**Visible Changes**:

- New folder at `C:\Vault\Quarantine\`
- Antivirus now moves files here instead of deleting
- Can browse quarantined files in Windows Security app

### How To Undo

```powershell
# Clear all quarantined files
Remove-Item -Path "C:\Vault\Quarantine\Active\*" -Recurse

# Disable quarantine (not recommended)
Remove-Item -Path "C:\Vault\Quarantine" -Recurse -Force
```

### Before/After State

**Before Quarantine System**:

```
Malware.exe detected by antivirus
    ↓
Antivirus auto-deletes (default behavior)
    ↓
Turned out to be false positive
    ↓
Important software now missing
    ↓
Have to reinstall from scratch
```

**After Quarantine System**:

```
Malware.exe detected by antivirus
    ↓
Antivirus moves to C:\Vault\Quarantine\Active\
    ↓
File is encrypted and isolated
    ↓
If false positive, restore from quarantine
    ↓
If real malware, stays safely isolated
```

**Quarantine File Organization**:

```
C:\Vault\Quarantine\
├── Active/
│   ├── Malware.exe (encrypted, can't run)
│   ├── Suspicious-Script.vbs (isolated)
│   └── Infected-Document.docx (isolated)
├── Archive/
│   ├── 2026-04-12/ (daily backups)
│   │   ├── Old-Malware.exe
│   │   └── Previous-Threat.zip
│   └── 2026-04-11/
│       └── Older-Threat.exe
├── Recovery/
│   └── (empty until you restore something)
└── Log.txt (detailed quarantine history)
```

### Performance Impact

- **Disk Space**: Quarantine uses allocated space (1-10 GB)
- **Antivirus Speed**: No impact (quarantine is post-detection)
- **System Performance**: None (isolated folder)

### Troubleshooting

**"Quarantine folder is full"**:

1. Check `C:\Vault\Quarantine\Archive\`
2. Delete old files (older than 90 days)
3. Increase quarantine size: Edit script and rerun

**"I need to restore a quarantined file"**:

1. Open Windows Security app
2. Go to Virus & threat protection → Quarantine
3. Select file → Restore
4. File moves back to original location

---

## 5. User Account Protection (Account Tiers)

### What It Does

Creates three account tiers with different security levels and permissions. This limits the damage if an account gets compromised - an attacker with a "Restricted" account can't disable security features or install malware system-wide.

**Example**: Your "Restricted" user account gets compromised. Attacker can browse your documents but can't install software, change firewall rules, or affect the system. They're trapped in a sandbox.

### Why You Need It

- **Privilege Separation**: Everyday work uses Limited account, damage is limited
- **Admin Protection**: True admin account rarely used, rarely compromised
- **Ransomware Containment**: Can't encrypt system files from limited account
- **Compliance**: Meets Zero Trust principles (least privilege)

**Example Problem Without Account Tiers**:
You log in with admin account and browse the web. Malware runs with admin privileges. It disables your antivirus, opens backdoors, and encrypts your files. Game over.

### How To Run

```powershell
# 1. Run PowerShell as Administrator
Start-Process powershell -Verb RunAs

# 2. Navigate to Phase 1 scripts
cd "C:\Users\ADMIN\helios-platform\phases\1-security\scripts"

# 3. Execute the User Account script
.\05-user-account-protection.ps1

# 4. Follow prompts to create accounts:
#    - Admin account (for system changes only)
#    - Standard account (everyday use)
#    - Restricted account (browsing, low-risk activities)
```

### What It Changes

**Accounts Created**:

| Account | Permission Level | Use Case | Can Do | Cannot Do |
|---------|-----------------|----------|--------|-----------|
| **ADMIN-Master** | Full administrator | System maintenance only | Everything | Nothing is restricted |
| **Standard-User** | Power user | Everyday use, work | Install approved programs, modify own files | Change system settings, modify firewall |
| **Restricted-Guest** | Limited user | Web browsing, email | Read documents, run approved apps | Install anything, access system folders |

**Registry Changes**:

```
HKLM:\SAM\SAM\Domains\Account\Users
├── 000001F5 (ADMIN-Master account)
├── 000003ED (Standard-User account)
└── 000003EE (Restricted-Guest account)

HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList
├── Administrator group membership updated
├── Power Users group created
└── Restricted group created
```

**Local Groups Modified**:

```
BUILTIN\Administrators (ADMIN-Master added)
BUILTIN\PowerUsers (Standard-User added)
BUILTIN\Users (Restricted-Guest added)
BUILTIN\Guests (empty, not used)
```

**Visible Changes**:

- Login screen shows three accounts
- Each account has different desktop/start menu
- Some programs ask for admin password when limited account tries to use them
- Settings app shows "Some of these settings are managed by your administrator"

### How To Undo

```powershell
# Delete accounts (data is kept)
Remove-LocalUser -Name "Restricted-Guest"
Remove-LocalUser -Name "Standard-User"
Remove-LocalUser -Name "ADMIN-Master"

# Or through GUI:
# Settings → Accounts → Other people → Select account → Remove
```

### Before/After State

**Before Account Tiers**:

```
You log in (admin account)
    ↓
Browse the web
    ↓
Malware downloads
    ↓
Malware runs with admin privileges
    ↓
All security features disabled
    ↓
Ransomware encrypts all files
```

**After Account Tiers**:

```
You log in (restricted account)
    ↓
Browse the web
    ↓
Malware downloads
    ↓
Malware tries to run with restricted privileges
    ↓
Security features won't let it make system changes
    ↓
Malware trapped in sandbox, limited damage
```

**Permission Comparison**:

| Action | Admin | Standard | Restricted |
|--------|-------|----------|-----------|
| Install system software | ✅ | ❌ Ask | ❌ Block |
| Modify firewall rules | ✅ | ❌ | ❌ |
| Change time/date | ✅ | ❌ | ❌ |
| Install printer | ✅ | ✅ Ask | ❌ Ask admin |
| Install app to user folder | ✅ | ✅ | ✅ |
| Browse web | ✅ | ✅ | ✅ |
| Open Document folder | ✅ | ✅ | ✅ |
| Access Program Files | ✅ | ✅ | 🔒 Read-only |
| Disable antivirus | ✅ | ❌ | ❌ |

### Performance Impact

- **Login Time**: +3-5 seconds (extra account checks)
- **Memory**: +50-100 MB (additional user profiles)
- **Disk Space**: +2-5 GB (separate user profiles)

### Troubleshooting

**"I need to install a program but I'm on Restricted account"**:

1. Switch to Standard or Admin account
2. Install there
3. Switch back to Restricted
4. Approved program now available to all accounts

**"I forgot admin password"**:

1. Boot into Windows Recovery
2. Open Command Prompt as Admin
3. Run: `net user ADMIN-Master newpassword`
4. Reboot

---

## 6. Threat Detection (Active Scanning)

### What It Does

Enables and integrates multiple threat detection engines:

- **Windows Defender**: Built-in antivirus scanning
- **Malwarebytes**: Specialized anti-malware engine
- **Scheduled Scans**: Automatic daily/weekly threat checks
- **Real-time Protection**: Active scanning as files are accessed

**Example**: You download a file that looks normal but contains malware. Windows Defender + Malwarebytes automatically scan it, detect the threat, and quarantine it before you can open it.

### Why You Need It

- **Zero-Day Protection**: Catch threats day 1 of release
- **Active Defense**: Don't wait for antivirus to find you - it finds threats automatically
- **Multiple Engines**: If one misses, the other catches it
- **Regular Updates**: Threat definitions updated multiple times per day

**Example Problem Without Detection**:
New ransomware variant is released. You download an infected document. Without active scanning, the malware silently encrypts your files. By the time you notice, it's too late.

### How To Run

```powershell
# 1. Run PowerShell as Administrator
Start-Process powershell -Verb RunAs

# 2. Navigate to Phase 1 scripts
cd "C:\Users\ADMIN\helios-platform\phases\1-security\scripts"

# 3. Execute the Threat Detection script
.\06-threat-detection-config.ps1

# 4. Choose scan settings when prompted:
#    - Frequency: Daily (most secure), Weekly (standard), Monthly (minimal)
#    - Depth: Quick (15 min), Full (1-2 hours), Custom
```

### What It Changes

**Files Created**:

- `C:\Windows\System32\drivers\etc\hosts` - Blocked malware domains
- `C:\ProgramData\Microsoft\Windows Defender\Definition Updates\` - Threat database
- `C:\Vault\ThreatScans\` - Scan reports and history

**Registry Changes**:

```
HKLM:\Software\Microsoft\Windows Defender
├── DisableRealtimeMonitoring (set to 0 = enabled)
├── DisableBehaviorMonitoring (set to 0 = enabled)
├── HighThreatDefaultAction (QuarantineRemove)
├── ModerateThreatDefaultAction (Quarantine)
└── LowThreatDefaultAction (Quarantine)

HKLM:\Software\Policies\Microsoft\Windows Defender
├── RealTimeProtection enabled
├── ScheduledScanTime (2:00 AM)
├── ScheduledScanDay (Monday-Friday)
└── MalwareScansEnabled (1)
```

**Services Started**:

- `WinDefend` - Windows Defender service
- `WdNisSvc` - Windows Defender Network Inspection Service
- `Sense` - Windows Defender Advanced Threat Protection

**Visible Changes**:

- Windows Security app shows "Threat & Virus Protection: Managed"
- Scan progress bar appears at 2:00 AM (or your set time)
- Notifications when threats are detected
- Green checkmark in system tray

### How To Undo

```powershell
# Disable Windows Defender
Set-MpPreference -DisableRealtimeMonitoring $true

# Uninstall Malwarebytes
Get-Package "Malwarebytes" | Uninstall-Package

# Or disable scanning:
Set-MpPreference -ScanScheduleDay Never
```

### Before/After State

**Before Threat Detection**:

```
You download infected file
    ↓
File sits on disk, undetected
    ↓
You open it
    ↓
Malware runs
    ↓
Your PC is now compromised
```

**After Threat Detection**:

```
You download infected file
    ↓
Windows Defender scans: "This is malware"
    ↓
File is immediately quarantined
    ↓
You never open it
    ↓
Your PC stays clean
```

**Threat Detection Workflow**:

```
File enters system
    ↓
Real-time Protection (Defender) checks
    ├─ Signature match? (known malware)
    ├─ Behavior suspicious? (new malware)
    └─ Heuristic analysis (pattern matching)
    ↓
  THREAT FOUND
    ├─ Quarantine immediately
    ├─ Log incident
    └─ Notify administrator
    ↓
  CLEAN
    └─ Allow file to proceed
```

**Scan Schedule**:

| Scan Type | Frequency | Duration | Coverage |
|-----------|-----------|----------|----------|
| **Real-time** | Continuous | Instant | Files being accessed |
| **Quick Scan** | Daily 2:00 AM | 15 min | Common malware locations |
| **Full Scan** | Weekly Sunday | 1-2 hours | All files, all drives |
| **Custom Scan** | On-demand | Variable | Specific folders/drives |

### Performance Impact

- **Real-time Scanning**: +5-15% CPU when files accessed
- **Scheduled Scan**: +50% CPU during 2:00 AM scan window
- **Disk I/O**: +10% during scans
- **Memory**: +100-200 MB (Defender service)

### Troubleshooting

**"Scan is taking too long"**:

1. Close other programs
2. Switch to Quick Scan instead of Full
3. Let it complete (don't interrupt)

**"False positives - clean files marked as threats"**:

1. Check Windows Security → Threat History
2. Select file → Actions → Restore
3. File is restored to original location

**"Malwarebytes won't install"**:

1. Ensure Windows Defender isn't blocking installation
2. Try installing in Safe Mode
3. Download latest version from malwarebytes.com

---

## Integration: How All 6 Components Work Together

The real power of Phase 1 is how these components layer together:

```
┌─ Threat Detection (real-time scanning) ─┐
│     ↓ (detects malware)                 │
├─→ Quarantine (isolates threat)          │
│     ↓ (threat is contained)             │
├─→ Firewall (blocks outbound calls home) │
│     ↓ (malware is silenced)             │
├─→ AppLocker (prevents execution)        │
│     ↓ (malware can't run)               │
├─→ User Account (limited damage)         │
│     ↓ (can't change system)             │
└─→ Vault (data stays encrypted)          │
        ↓ (sensitive data safe)           │
        SYSTEM PROTECTED ✅               │
```

---

## Quick Reference

| Component | Protects Against | Run Command |
|-----------|-----------------|-------------|
| AppLocker | Malware execution | `.\01-applocker-setup.ps1` |
| Firewall | Network threats | `.\02-firewall-hardening.ps1` |
| Vault | Data theft | `.\03-vault-encryption-setup.ps1` |
| Quarantine | Malware spread | `.\04-quarantine-system-init.ps1` |
| User Accounts | Privilege escalation | `.\05-user-account-protection.ps1` |
| Threat Detection | New malware | `.\06-threat-detection-config.ps1` |

---

**Last Updated**: April 12, 2026  
**Version**: 1.0  
**For Questions**: See TESTING_GUIDE.md or PLAIN_ENGLISH_GUIDE.md
