# Phase 1 Testing Guide

Comprehensive testing procedures to verify Phase 1 security implementations.

---

## Pre-Testing Checklist

Before running tests, ensure:

- [ ] All Phase 1 scripts completed successfully
- [ ] System restarted after setup
- [ ] Have admin access
- [ ] Saved Vault recovery key in safe location
- [ ] All three user accounts created and tested
- [ ] Each component individually verified

---

## Test Suite 1: AppLocker Verification

### Test 1.1: Verify AppLocker is Enabled

```powershell
Get-AppLockerPolicy -Effective | Format-List
```

**Expected Result**: Shows RuleCollections with Executable rules defined
**Pass/Fail**: PASS if rules exist, FAIL if no policy set

### Test 1.2: Whitelisted Programs Run

```powershell
Start-Process notepad.exe

# Wait 5 seconds, verify opens

Start-Process calc.exe

# Wait 5 seconds, verify opens

```

**Expected Result**: Both programs launch without errors
**Pass/Fail**: PASS if both open, FAIL if blocked

### Test 1.3: Event Logs Recorded

```powershell
Get-WinEvent -LogName Application -MaxEvents 50 |
    Where-Object { \.Message -like '*AppLocker*' }
```

**Expected Result**: Recent AppLocker events shown
**Pass/Fail**: PASS if events exist, FAIL if none found

---

## Test Suite 2: Firewall Verification

### Test 2.1: Firewall Enabled

```powershell
Get-NetFirewallProfile -All | Format-Table Name, Enabled
```

**Expected Result**: All profiles show Enabled: True
**Pass/Fail**: PASS if all enabled, FAIL if any disabled

### Test 2.2: Dangerous Ports Blocked

```powershell
Get-NetFirewallRule -Direction Inbound -Action Block |
    Format-Table DisplayName -AutoSize
```

**Expected Result**: Rules for ports 3389, 445, 135 shown
**Pass/Fail**: PASS if dangerous ports blocked, FAIL if open

### Test 2.3: DNS Resolution Works

```powershell
Resolve-DnsName -Name google.com
```

**Expected Result**: Returns valid IP addresses
**Pass/Fail**: PASS if resolves, FAIL if blocked

---

## Test Suite 3: Vault Encryption

### Test 3.1: Vault Directory Exists

```powershell
Test-Path C:\Users\ADMIN\Vault
```

**Expected Result**: Returns True
**Pass/Fail**: PASS if exists, FAIL if missing

### Test 3.2: Vault is Encrypted

```powershell
(Get-Item C:\Users\ADMIN\Vault -Force).Attributes
```

**Expected Result**: Shows Encrypted in attributes
**Pass/Fail**: PASS if encrypted, FAIL if plaintext

### Test 3.3: Recovery Key Present

```powershell
Test-Path C:\Users\ADMIN\Vault\Recovery-Key.txt
```

**Expected Result**: Returns True (file exists)
**Pass/Fail**: PASS if file present, FAIL if missing

### Test 3.4: Subdirectories Exist

```powershell
Get-ChildItem C:\Users\ADMIN\Vault -Directory | Select-Object Name
```

**Expected Result**: Shows Passwords, Certificates, Financial, Quarantine, Sensitive
**Pass/Fail**: PASS if all created, FAIL if any missing

---

## Test Suite 4: Quarantine System

### Test 4.1: Quarantine Directory Exists

```powershell
Test-Path C:\Vault\Quarantine
```

**Expected Result**: Returns True
**Pass/Fail**: PASS if exists, FAIL if missing

### Test 4.2: Quarantine Structure Complete

```powershell
Get-ChildItem C:\Vault\Quarantine -Directory | Select-Object Name
```

**Expected Result**: Shows Active, Archive, Recovery, Metadata directories
**Pass/Fail**: PASS if all directories present, FAIL if any missing

### Test 4.3: Quarantine Logging

```powershell
Test-Path C:\Vault\Quarantine\Log.txt
```

**Expected Result**: Returns True
**Pass/Fail**: PASS if log file exists, FAIL if missing

---

## Test Suite 5: User Account Protection

### Test 5.1: All Accounts Exist

```powershell
Get-LocalUser | Format-Table Name, Enabled
```

**Expected Result**: Shows ADMIN-Master, Standard-User, Restricted-Guest
**Pass/Fail**: PASS if all three present, FAIL if any missing

### Test 5.2: Admin Group Configured

```powershell
Get-LocalGroupMember -Group Administrators | Select-Object Name
```

**Expected Result**: Shows ADMIN-Master
**Pass/Fail**: PASS if correct user in group, FAIL if wrong membership

### Test 5.3: Login as Each Account

Manually test:

- Login as ADMIN-Master (admin only)
- Login as Standard-User (everyday use)
- Login as Restricted-Guest (limited)

**Expected Result**: Each account logs in with appropriate permissions
**Pass/Fail**: PASS if all login correctly, FAIL if permission issues

---

## Test Suite 6: Threat Detection

### Test 6.1: Windows Defender Enabled

```powershell
Get-MpPreference | Select-Object DisableRealtimeMonitoring
```

**Expected Result**: DisableRealtimeMonitoring = False
**Pass/Fail**: PASS if enabled, FAIL if disabled

### Test 6.2: Defender Service Running

```powershell
Get-Service -Name WinDefend | Select-Object Status
```

**Expected Result**: Status = Running
**Pass/Fail**: PASS if running, FAIL if stopped

### Test 6.3: Threat Definitions Recent

```powershell
Get-MpComputerStatus | Select-Object AntivirusSignatureVersion
```

**Expected Result**: Recent version number (within days)
**Pass/Fail**: PASS if recent, FAIL if outdated

### Test 6.4: Real-Time Protection Active

```powershell
Get-MpPreference | Select-Object RealtimeMonitoringEnabled
```

**Expected Result**: RealtimeMonitoringEnabled = True
**Pass/Fail**: PASS if enabled, FAIL if disabled

---

## Performance Impact Tests

### Test P.1: System Startup Time

**Procedure**:

1. Restart computer and note time
2. Wait until fully booted and responsive
3. Calculate elapsed time
4. Compare to baseline (should be 30-60 seconds longer)

**Expected Result**: +30-60 seconds acceptable
**Pass/Fail**: PASS if within acceptable range

### Test P.2: Program Launch Time

**Procedure**: Time launch of Firefox, Word, Chrome

```powershell
Measure-Command { Start-Process firefox }
```

**Expected Result**: +1-3 seconds acceptable for first run
**Pass/Fail**: PASS if acceptable, FAIL if excessive delays

### Test P.3: Memory Usage

```powershell
Get-Process | Measure-Object -Property WorkingSet -Sum
```

**Expected Result**: +200-300 MB overhead acceptable
**Pass/Fail**: PASS if reasonable, FAIL if excessive

---

## Security Incident Simulation Tests

### Sim 1: Malware Execution Blocked

Try to run unsigned/unknown executable

**Expected Result**: Blocked by AppLocker with error message
**Pass/Fail**: PASS if blocked, FAIL if runs

### Sim 2: Network Attack Simulation

Try to connect to blocked port (3389 RDP)

**Expected Result**: Connection refused/timeout
**Pass/Fail**: PASS if blocked, FAIL if connects

### Sim 3: Vault Data Protection

Try to read Vault files as different user

**Expected Result**: Access denied (encryption)
**Pass/Fail**: PASS if protected, FAIL if readable

### Sim 4: Privilege Escalation Prevention

From Restricted account, try to install software or modify system

**Expected Result**: Access denied
**Pass/Fail**: PASS if prevented, FAIL if allowed

---

## Rollback Verification

### Test R.1: AppLocker Rollback Works

```powershell
.\01-applocker-rollback.ps1
Get-AppLockerPolicy -Effective
```

**Expected Result**: No rules defined after rollback
**Pass/Fail**: PASS if rules removed, FAIL if rules remain

### Test R.2: Firewall Rollback Works

```powershell
.\02-firewall-rollback.ps1
Get-NetFirewallProfile -Name StandardProfile |
    Select-Object DefaultInboundAction, DefaultOutboundAction
```

**Expected Result**: Returns to default (Allow) policies
**Pass/Fail**: PASS if reset, FAIL if still restrictive

### Test R.3: Vault Rollback Works

```powershell
.\03-vault-decryption.ps1
(Get-Item C:\Users\ADMIN\Vault).Attributes
```

**Expected Result**: Encrypted attribute removed
**Pass/Fail**: PASS if decrypted, FAIL if still encrypted

---

## Known Issues and Workarounds

### AppLocker Issues

- **Program blocked unexpectedly**:
  Run: .\01-applocker-add-exception.ps1 \"C:\Path\To\Program.exe\"

- **AppLocker won't enable**:
  1. Check: gpresult /h report.html
  2. Restart: Restart-Computer
  3. Try again

### Firewall Issues

- **Network broken after hardening**:
  Run: .\02-firewall-rollback.ps1
  Then reapply more carefully

- **Specific program no internet**:
  Add outbound rule: New-NetFirewallRule -Direction Out -Action Allow -Program \"C:\Program.exe\"

### Vault Issues

- **Can't open Vault**:
  1. Restart PC (key cached in memory)
  2. Try again

- **Forgot Vault password**:
  Use Recovery Key: manage-bde -recovery -status

### Quarantine Issues

- **Quarantine full**:
  Delete old archives: Remove-Item C:\Vault\Quarantine\Archive\* -Recurse
  Or increase size: .\04-quarantine-system-init.ps1 -QuarantineSize 10GB

---

## Final Verification Checklist

- [ ] Test Suite 1 (AppLocker): All tests PASS
- [ ] Test Suite 2 (Firewall): All tests PASS
- [ ] Test Suite 3 (Vault): All tests PASS
- [ ] Test Suite 4 (Quarantine): All tests PASS
- [ ] Test Suite 5 (User Accounts): All tests PASS
- [ ] Test Suite 6 (Threat Detection): All tests PASS
- [ ] Performance tests within acceptable range
- [ ] Incident simulations all contained
- [ ] Rollback procedures work correctly
- [ ] Event logs complete and accessible
- [ ] Documentation reviewed by team
- [ ] Team trained on new security setup
- [ ] Backup of recovery keys stored safely
- [ ] Phase 1 Security COMPLETE

---

Last Updated: April 12, 2026
Version: 1.0
Maintained By: HELIOS Platform Team
