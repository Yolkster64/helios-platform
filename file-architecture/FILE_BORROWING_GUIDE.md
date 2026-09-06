# FILE BORROWING GUIDE - Cross-Phase Dependencies

Advanced guide for reusing components and files from one phase in another.

## When to Borrow Files

### Use Cases

1. **Accelerated Deployment**: Apply Phase 1 security in Phase 0
2. **Custom Stack**: Combine policies from multiple phases
3. **Development**: Test AI models early
4. **Remediation**: Re-apply individual phases

---

## Phase 1 AppLocker into Phase 0

### Files to Copy

```
Source (Phase 1):
C:\ProgramData\HELIOS\Security\Policies\AppLocker-Rules.xml

Destination (Phase 0):
C:\ProgramData\HELIOS\Foundation\Security-Policies\AppLocker-Rules.xml
```

### Registry to Copy

```
Source:
HKLM:\Software\Policies\Microsoft\Windows\SrpV2\

Destination (Phase 0 baseline):
HKLM:\Software\HELIOS\Foundation\AppLocker-Baseline\
```

### Steps

1. Export AppLocker from Phase 1 system:

```powershell
Get-AppLockerPolicy -Effective -Xml | Out-File `
  "C:\ProgramData\HELIOS\Security\Policies\AppLocker-Rules.xml"
```

2. Copy to Phase 0 installation media

3. Apply in Phase0-Foundation.ps1:

```powershell
if (Test-Path "C:\HELIOS-Source\AppLocker-Rules.xml") {
    Set-AppLockerPolicy -XmlPolicy "C:\HELIOS-Source\AppLocker-Rules.xml"
}
```

4. Verify:

```powershell
Get-AppLockerPolicy -Effective | Format-Table
```

---

## Phase 1 Firewall Rules into Phase 0

### Files to Copy

```
Source (Phase 1):
C:\Windows\System32\drivers\etc\hosts

Destination (Phase 0):
C:\ProgramData\HELIOS\Foundation\Network-Policies\hosts.baseline
```

### Steps

1. Export firewall configuration:

```powershell
reg export "HKLM\System\CurrentControlSet\Services\SharedAccess" `
  "C:\ProgramData\HELIOS\Foundation\Firewall-Registry.reg"
```

2. Include in Phase0-Registry-Setup.ps1

3. Apply before Phase 1 runs

---

## Phase 3 AI Models into Phase 2

### Files to Copy

```
Source (Phase 3):
C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\*

Destination (Phase 2 testing):
C:\ProgramData\HELIOS\Optimization\AI-Models-Test\*
```

### Steps

1. Staging AI models in Phase 2:

```powershell
$phase3Models = "C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models"
$phase2Test = "C:\ProgramData\HELIOS\Optimization\AI-Models-Test"

if (Test-Path $phase3Models) {
    Copy-Item -Path "$phase3Models\*" -Destination $phase2Test -Recurse -Force
}
```

2. Reference in Phase 2 optimization profiles:

```json
{
  "threat_detection_enabled": true,
  "ai_model_path": "C:\ProgramData\HELIOS\Optimization\AI-Models-Test\threat-detection-v4.1.model"
}
```

---

## Phase 2 Cleanup Rules into Phase 1

### Files to Copy

```
Source (Phase 2):
C:\ProgramData\HELIOS\Optimization\Cleanup\Cleanup-Rules.cfg

Destination (Phase 1 security):
C:\ProgramData\HELIOS\Security\Cleanup-Rules-Backup.cfg
```

### Purpose

- Preserve system state for forensics
- Avoid cleaning logs before security audit

### Steps

1. Export Phase 2 cleanup config:

```powershell
Copy-Item "C:\ProgramData\HELIOS\Optimization\Cleanup\Cleanup-Rules.cfg" `
  "C:\ProgramData\HELIOS\Security\Cleanup-Rules-Backup.cfg" -Force
```

2. Modify to preserve security data:

```
[EXCLUSION]
Pattern=Security.evtx
Pattern=audit.db
Pattern=quarantine\*
```

---

## Vault (Phase 1) into Dashboa (Phase 3)

### What to Borrow

```
Source (Phase 1):
C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\Vault.db
C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\certificates\*

Destination (Phase 3 Dashboard):
Dashboard references vault location via registry
```

### Registry Reference

```
HKLM:\Software\HELIOS\Paths\VaultLocation = 
  "C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault"
```

### Steps

1. Dashboard reads vault location from registry:

```csharp
// In Dashboard code
string vaultPath = Registry.LocalMachine.OpenSubKey(
  @"Software\HELIOS\Paths").GetValue("VaultLocation").ToString();
```

2. No copying needed - Dashboard automatically uses existing vault

---

## Performance Baselines (Phase 2) into Reporting (Phase 3)

### Files to Copy

```
Source (Phase 2):
C:\ProgramData\HELIOS\Optimization\Baselines\Baseline-Pre-Optimization.snapshot
C:\ProgramData\HELIOS\Optimization\Baselines\Performance-Trends.csv

Destination (Phase 3 Reports):
C:\ProgramData\HELIOS\Capability\Reports\Baseline-Reference-Data\
```

### Steps

1. Copy performance baselines:

```powershell
$source = "C:\ProgramData\HELIOS\Optimization\Baselines"
$dest = "C:\ProgramData\HELIOS\Capability\Reports\Baseline-Reference-Data"

Copy-Item -Path "$source\*" -Destination $dest -Recurse -Force
```

2. Reports reference this data for comparisons

3. Dashboard shows improvements:

```
Before Optimization (from Phase 2 baseline):
  Boot Time: 45 seconds
  Memory Usage: 6200 MB

After Optimization (Phase 2 snapshots):
  Boot Time: 25 seconds (44% improvement)
  Memory Usage: 4100 MB (34% improvement)
```

---

## System Baselines (Phase 0) into Security (Phase 1)

### What to Borrow

```
Source (Phase 0):
C:\ProgramData\HELIOS\Foundation\Baselines\System-Baseline.snapshot
C:\ProgramData\HELIOS\Foundation\Baselines\Registry-Baseline.hiv

Destination (Phase 1 analysis):
C:\ProgramData\HELIOS\Security\Baseline-Reference\
```

### Purpose

- Detect what changed during Phase 1
- Identify unauthorized modifications

### Steps

1. Copy Phase 0 baselines:

```powershell
$phase0 = "C:\ProgramData\HELIOS\Foundation\Baselines"
$phase1 = "C:\ProgramData\HELIOS\Security"

Copy-Item "$phase0\*" "$phase1\Baseline-Reference\" -Recurse
```

2. Phase 1 compares current state to baseline:

```powershell
# During Phase 1 security scan
Compare-SystemState -Baseline "$phase1\Baseline-Reference\System-Baseline.snapshot" `
  -Current (Get-SystemSnapshot)
```

---

## Profiles (Phase 2) into AI Analysis (Phase 3)

### What to Borrow

```
Source (Phase 2):
C:\ProgramData\HELIOS\Optimization\Profiles\Active-Profile.txt
C:\ProgramData\HELIOS\Optimization\Profiles\Default-Profile.opt

Destination (Phase 3 AI):
AI models read profile to tune analysis sensitivity
```

### Registry Reference

```
HKLM:\Software\HELIOS\Analysis-Settings\DefaultProfile = 
  "Enterprise-High-Security"
```

### Steps

1. AI reads active profile from registry:

```csharp
// Phase 3 AI Console
string activeProfile = RegistryKey.OpenSubKey(
  @"Software\HELIOS\Optimization").GetValue("ActiveProfile").ToString();
```

2. AI adjusts threat detection sensitivity based on profile:

```json
{
  "profile": "Enterprise-High-Security",
  "ai_sensitivity": 0.95,
  "threat_threshold": 0.8
}
```

---

## Workflow Definitions (Phase 3) into Scheduler (Phase 2)

### What to Borrow

```
Source (Phase 3):
C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\*.workflow

Destination (Phase 2 scheduler):
C:\Windows\System32\Tasks\HELIOS\
```

### Purpose

- Run workflows via Windows Task Scheduler
- Ensure reliable execution even if Phase 3 not running

### Steps

1. Export workflows as scheduled tasks:

```powershell
$workflows = Get-ChildItem "C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows"

foreach ($wf in $workflows) {
    $taskName = $wf.BaseName
    $taskPath = "C:\Windows\System32\Tasks\HELIOS\$taskName.xml"
    
    Copy-Item $wf.FullName $taskPath -Force
}
```

2. Register with Task Scheduler:

```powershell
Register-ScheduledTask -TaskPath "\HELIOS\" -Xml (
  Get-Content "C:\Windows\System32\Tasks\HELIOS\Daily-Security-Scan.xml"
)
```

---

## Logs (All Phases) into Central Repository

### What to Copy

```
Source (Each Phase):
Phase 0: C:\ProgramData\HELIOS\Logs\Phase0.log
Phase 1: C:\ProgramData\HELIOS\Logs\Phase1.log
Phase 2: C:\ProgramData\HELIOS\Logs\Phase2.log
Phase 3: C:\ProgramData\HELIOS\Logs\Phase3.log

Destination (Aggregated):
C:\ProgramData\HELIOS\Database\audit.db
```

### Steps

1. Consolidate logs into central database:

```powershell
$phases = @("Phase0", "Phase1", "Phase2", "Phase3")

foreach ($phase in $phases) {
    $logFile = "C:\ProgramData\HELIOS\Logs\${phase}.log"
    
    # Parse and insert into audit.db
    Import-LogsToDatabase -LogFile $logFile -Database audit.db
}
```

---

## Registry Cross-References

### View All Borrow Points

```
HKLM:\Software\HELIOS\Paths\
├── Foundation = "C:\ProgramData\HELIOS\Foundation"
├── Security = "C:\ProgramData\HELIOS\Security"
├── Optimization = "C:\ProgramData\HELIOS\Optimization"
├── Capability = "C:\ProgramData\HELIOS\Capability"
├── Database = "C:\ProgramData\HELIOS\Database"
├── VaultLocation = "C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault"
└── Dashboard = "C:\Program Files\HELIOS\Dashboard"
```

### Registry Queries for Borrowing

```powershell
# Find where Phase 1 vault is located
$vaultPath = (Get-ItemProperty HKLM:\Software\HELIOS\Paths).VaultLocation

# Find AI model location
$aiPath = (Get-ItemProperty HKLM:\Software\HELIOS\Capability\AI-Settings).ModelPath

# Find active profile
$profile = (Get-ItemProperty HKLM:\Software\HELIOS\Optimization\Profiles)."Active-Profile"

# Find database location
$dbPath = (Get-ItemProperty HKLM:\Software\HELIOS\Paths).Database
```

---

## Best Practices for Borrowing

### Do's

- Always backup original files before borrowing
- Document what you borrowed and why
- Test in non-production first
- Verify compatibility between phases
- Update registry paths if moving files

### Don'ts

- Don't borrow encrypted files without keys
- Don't modify borrowed files
- Don't exceed file system limits
- Don't break phase dependencies
- Don't remove borrow sources until satisfied

---

## Rollback Borrowed Components

### If Borrow Fails

```powershell
# Restore original
Copy-Item "C:\ProgramData\HELIOS\Foundation\Backups\AppLocker-Rules.xml.bak" `
  "C:\ProgramData\HELIOS\Security\Policies\AppLocker-Rules.xml" -Force

# Clear invalid registry
Remove-Item "HKLM:\Software\HELIOS\Foundation\AppLocker-Baseline" -Force -Recurse

# Reapply original phase
& "C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase1-Security.ps1"
```

---

## Examples by Use Case

### Custom Enterprise Build

Borrow from all phases to create security-first system:

- Phase 0: Foundation
- \+ Phase 1: AppLocker rules (borrow)
- \+ Phase 1: Firewall (borrow)
- \+ Phase 2: Service optimization (borrow)
- \+ Phase 3: AI monitoring (borrow)

Result: Full system in single Phase 0 deployment

### Fast Testing

Test Phase 3 AI without full Phase 3 deployment:

- Phase 1: Run normally (security enabled)
- Borrow: Phase 3 AI models into Phase 1
- Run threat scans with Phase 3 AI models
- Don't deploy full Phase 3 UI yet

Result: AI threat detection working before dashboard ready

### Graduated Rollout

Deploy to different user groups:

- Group 1: Phase 0 + Phase 1 (borrow)
- Group 2: Phase 0 + Phase 1 + Phase 2 (borrow)
- Group 3: Full Phase 0-3 (no borrowing)

Result: Phased rollout with early access to specific features
