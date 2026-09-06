# QUICK LOOKUP TABLE - Component to Location Index

Quick reference table to find where any HELIOS component is located.

## Alphabetical Component Index

| Component | Location | Phase | Size | Type |
|-----------|----------|-------|------|------|
| Analysis Database | C:\ProgramData\HELIOS\Database\master.db | 3 | 100-500 MB | File |
| AI Models (Threat Detection) | C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\threat-detection-v4.1.model | 3 | 150 MB | File |
| AI Models (Behavior Analysis) | C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\behavior-analysis-v5.0.model | 3 | 200 MB | File |
| AI Models (All) | C:\ProgramData\HELIOS\Capability\AI-Models\ | 3 | 1-1.5 GB | Directory |
| AppLocker Rules | HKLM:\Software\Policies\Microsoft\Windows\SrpV2\ | 1 | <1 MB | Registry |
| Audit Database | C:\ProgramData\HELIOS\Database\audit.db | 3 | 50-200 MB | File |
| Backup (Database Daily) | C:\ProgramData\HELIOS\Database\Backups\master-YYYY-MM-DD.db.backup | 3 | 100-500 MB | File |
| Baseline (Hardware) | C:\ProgramData\HELIOS\Foundation\Baselines\Hardware-Inventory.json | 0 | ~5 MB | File |
| Baseline (Performance) | C:\ProgramData\HELIOS\Optimization\Baselines\Baseline-Pre-Optimization.snapshot | 2 | 5-10 MB | File |
| Baseline (Registry) | C:\ProgramData\HELIOS\Foundation\Baselines\Registry-Baseline.hiv | 0 | ~20 MB | File |
| Baseline (System) | C:\ProgramData\HELIOS\Foundation\Baselines\System-Baseline.snapshot | 0 | ~50 MB | File |
| Bootable USB Creator | C:\ProgramData\HELIOS\Foundation\USBCreator\Creator.exe | 0 | ~10 MB | Exe |
| Cache Inventory | C:\ProgramData\HELIOS\Optimization\Cache\Cache-Inventory.db | 2 | 10-50 MB | Database |
| Certificate (User) | C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\certificates\user-cert.pfx | 1 | ~5-10 KB | File |
| Cleanup Rules | C:\ProgramData\HELIOS\Optimization\Cleanup\Cleanup-Rules.cfg | 2 | ~100-200 KB | File |
| Dashboard Application | C:\Program Files\HELIOS\Dashboard\Dashboard.exe | 3 | ~50 MB | Exe |
| Dashboard Config | C:\Program Files\HELIOS\Dashboard\Dashboard.config | 3 | ~10 KB | File |
| Daily Report | C:\ProgramData\HELIOS\Capability\Reports\Daily-Reports\Daily-Report-YYYY-MM-DD.pdf | 3 | 5-20 MB | Pdf |
| Daily Optimization Task | C:\Windows\System32\Tasks\HELIOS\Daily-Optimization.xml | 2 | ~20 KB | Xml |
| Database (Main) | C:\ProgramData\HELIOS\Database\master.db | 3 | 100-500 MB | Database |
| Diagnostic Log (Phase 0) | C:\ProgramData\HELIOS\Logs\Phase0.log | 0 | 10-50 MB | Log |
| Diagnostic Log (Phase 1) | C:\ProgramData\HELIOS\Logs\Phase1.log | 1 | 50-100 MB | Log |
| Diagnostic Log (Phase 2) | C:\ProgramData\HELIOS\Logs\Phase2.log | 2 | 50-200 MB | Log |
| Diagnostic Log (Phase 3) | C:\ProgramData\HELIOS\Logs\Phase3.log | 3 | 100-200 MB | Log |
| Email Notifier Plugin | C:\Program Files\HELIOS\Dashboard\Plugins\CorePlugins\EmailNotifier.dll | 3 | ~2 MB | Dll |
| Encryption Key (Master) | C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\keys\encryption-key.bin | 1 | ~1 KB | File |
| Endpoint Analysis | C:\ProgramData\HELIOS\Security\Analysis\Analysis-Results.json | 1 | ~5-10 MB | Json |
| Event Log (Security) | C:\Windows\System32\winevt\Logs\Security.evtx | 1 | 100-500 MB | Evtx |
| Event Log (System) | C:\Windows\System32\winevt\Logs\System.evtx | 1 | 100-500 MB | Evtx |
| Firewall Rules | HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\ | 1 | <1 MB | Registry |
| Firewall Rules (Export) | C:\ProgramData\HELIOS\Security\Policies\Firewall-Rules.xml | 1 | ~50 KB | Xml |
| High Performance Profile | C:\ProgramData\HELIOS\Optimization\Profiles\Performance-Profile.opt | 2 | ~30 KB | File |
| Hosts File (Modified) | C:\Windows\System32\drivers\etc\hosts | 1 | ~10-50 KB | File |
| Hourly Monitor Task | C:\Windows\System32\Tasks\HELIOS\Hourly-Monitor.xml | 2 | ~20 KB | Xml |
| Incident Report | C:\ProgramData\HELIOS\Capability\Reports\Incident-Reports\Incident-YYYY-MM-DD-###.pdf | 3 | 5-10 MB | Pdf |
| Installation Script (Foundation) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase0-Foundation.ps1 | 0 | ~100 KB | Ps1 |
| Installation Script (Security) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase1-Security.ps1 | 1 | ~150 KB | Ps1 |
| Installation Script (Optimization) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase2-Optimization.ps1 | 2 | ~150 KB | Ps1 |
| Installation Script (Capability) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase3-Capability.ps1 | 3 | ~150 KB | Ps1 |
| ISO Template (Base) | C:\ProgramData\HELIOS\Foundation\USBCreator\ISO-Templates\HELIOS-Base.iso | 0 | ~800 MB | Iso |
| ISO Template (Secure) | C:\ProgramData\HELIOS\Foundation\USBCreator\ISO-Templates\HELIOS-Secure.iso | 0 | ~1 GB | Iso |
| ISO Template (Full) | C:\ProgramData\HELIOS\Foundation\USBCreator\ISO-Templates\HELIOS-Full.iso | 0 | ~2 GB | Iso |
| Log (Cleanup Operations) | C:\ProgramData\HELIOS\Logs\Cleanup-Operations.log | 2 | 10-50 MB | Log |
| Log (Dashboard Startup) | C:\Program Files\HELIOS\Dashboard\Logs\Dashboard.log | 3 | ~5 MB | Log |
| Log (Installation History) | C:\ProgramData\HELIOS\Logs\Installation-History.csv | 0 | ~1 MB | Csv |
| Log (Vault Operations) | C:\ProgramData\HELIOS\Logs\Vault-Operations.log | 1 | 5-20 MB | Log |
| Log (Workflow Execution) | C:\ProgramData\HELIOS\Logs\Workflow-Execution.log | 3 | 10-50 MB | Log |
| Malware Classifier Model | C:\ProgramData\HELIOS\Capability\AI-Models\Specialized-Models\Malware-Classifier\model.bin | 3 | 140 MB | File |
| Model (Behavior Analysis) | C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\behavior-analysis-v5.0.model | 3 | 200 MB | File |
| Model (Performance Anomaly) | C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\performance-anomaly-v3.2.model | 3 | 120 MB | File |
| Model (System Health) | C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\system-health-v2.1.model | 3 | 80 MB | File |
| Model (Threat Detection) | C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\threat-detection-v4.1.model | 3 | 150 MB | File |
| Model (Pattern Recognition) | C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\pattern-recognition-v3.5.model | 3 | 100 MB | File |
| Monitor Service Executable | C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe | 2 | ~5 MB | Exe |
| Monitor Service (Registry) | HKLM:\SYSTEM\CurrentControlSet\Services\HELIOSMonitor\ | 2 | <1 MB | Registry |
| Monthly Report | C:\ProgramData\HELIOS\Capability\Reports\Monthly-Reports\Monthly-Report-YYYY-MM.pdf | 3 | 5-20 MB | Pdf |
| Optimization Service Executable | C:\Program Files\HELIOS\Optimizer\HELIOSOptimizer.exe | 2 | ~5 MB | Exe |
| Optimization Service (Registry) | HKLM:\SYSTEM\CurrentControlSet\Services\HELIOSOptimizer\ | 2 | <1 MB | Registry |
| Partition Configuration | C:\ProgramData\HELIOS\Foundation\Baselines\Partitions\Standard-GPT.cfg | 0 | ~5 KB | File |
| Performance Analyzer Module | C:\Program Files\HELIOS\Dashboard\Modules\PerformanceAnalyzer\PerformanceAnalyzer.dll | 3 | ~10 MB | Dll |
| Performance Baseline | C:\ProgramData\HELIOS\Optimization\Baselines\Baseline-Post-Optimization.snapshot | 2 | 5-10 MB | File |
| Performance Trends | C:\ProgramData\HELIOS\Optimization\Baselines\Performance-Trends.csv | 2 | 20-50 MB | Csv |
| Policy (Default Optimization) | C:\ProgramData\HELIOS\Optimization\Profiles\Default-Profile.opt | 2 | ~20 KB | File |
| Profile (Analysis - Quick Scan) | C:\ProgramData\HELIOS\Capability\Profiles\Analysis-Profiles\Quick-Scan.profile | 3 | ~10 KB | File |
| Profile (Analysis - Deep) | C:\ProgramData\HELIOS\Capability\Profiles\Analysis-Profiles\Deep-Analysis.profile | 3 | ~10 KB | File |
| Profile (Enterprise Security) | C:\ProgramData\HELIOS\Capability\Profiles\System-Profiles\Enterprise-High-Security.profile | 3 | ~30 KB | File |
| Profile (Home User) | C:\ProgramData\HELIOS\Capability\Profiles\System-Profiles\Home-User.profile | 3 | ~20 KB | File |
| Profile (AI Aggressive) | C:\ProgramData\HELIOS\Capability\Profiles\AI-Profiles\AI-Aggressive-Detection.profile | 3 | ~15 KB | File |
| Quarantine Database | C:\ProgramData\HELIOS\Security\Quarantine\Quarantine.db | 1 | 10-50 MB | Database |
| Quarantine (Active Files) | C:\ProgramData\HELIOS\Security\Quarantine\Active\ | 1 | 5-100+ MB | Directory |
| Quarantine (Archive) | C:\ProgramData\HELIOS\Security\Quarantine\Archive\ | 1 | 10-100 MB | Directory |
| Registry (AppLocker) | HKLM:\Software\Policies\Microsoft\Windows\SrpV2\ | 1 | <1 MB | Hive |
| Registry (HELIOS Foundation) | HKLM:\Software\HELIOS\Foundation\ | 0 | <1 MB | Hive |
| Registry (HELIOS Status) | HKLM:\Software\HELIOS\Status\ | 0-3 | <1 MB | Hive |
| Registry (Services) | HKLM:\SYSTEM\CurrentControlSet\Services\ | 2 | <1 MB | Hive |
| Report Generator Module | C:\Program Files\HELIOS\Dashboard\Modules\ReportGenerator\ReportGenerator.dll | 3 | ~8 MB | Dll |
| Report Template | C:\ProgramData\HELIOS\Capability\Reports\Report-Templates\daily-report.template.xml | 3 | ~50 KB | Xml |
| Risk Assessment | C:\ProgramData\HELIOS\Security\Analysis\Risk-Assessment-YYYY-MM-DD.json | 1 | ~5-10 MB | Json |
| Rollback Script (Phase 0) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase0-Rollback.ps1 | 0 | ~50 KB | Ps1 |
| Rollback Script (Phase 1) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase1-Rollback.ps1 | 1 | ~50 KB | Ps1 |
| Rollback Script (Phase 2) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase2-Rollback.ps1 | 2 | ~50 KB | Ps1 |
| Rollback Script (Phase 3) | C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase3-Rollback.ps1 | 3 | ~50 KB | Ps1 |
| Security Center Module | C:\Program Files\HELIOS\Dashboard\Modules\SecurityCenter\SecurityCenter.dll | 3 | ~12 MB | Dll |
| Security Log Database | C:\Windows\System32\winevt\Logs\HELIOS\Security-Audit.evtx | 1 | 50-200 MB | Evtx |
| Security Policies | C:\ProgramData\HELIOS\Security\Policies\ | 1 | ~50-200 KB | Directory |
| Service Configuration (HELIOS) | HKLM:\SYSTEM\CurrentControlSet\Services\HELIOSMonitor\ | 2 | <1 MB | Registry |
| Shortcut (Dashboard) | C:\Users\[USERNAME]\Desktop\HELIOS Dashboard.lnk | 3 | ~2 KB | Lnk |
| Shortcut (Vault) | C:\Users\[USERNAME]\Desktop\Vault Quick Access.lnk | 1 | ~2 KB | Lnk |
| Signature Database (Threats) | C:\ProgramData\HELIOS\Capability\AI-Models\Data-Files\signature-database.db | 3 | 100 MB | Database |
| Startup Item (Monitor) | C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\HELIOS-Monitor.lnk | 2 | ~2 KB | Lnk |
| Startup Item (Vault Monitor) | C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\HELIOS-Vault-Monitor.lnk | 2 | ~2 KB | Lnk |
| System Overview Module | C:\Program Files\HELIOS\Dashboard\Modules\SystemOverview\SystemOverview.dll | 3 | ~8 MB | Dll |
| Threat Analysis Database | C:\ProgramData\HELIOS\Security\Analysis\Threat-Database.db | 1 | 50-200 MB | Database |
| Threat Definitions | C:\ProgramData\HELIOS\Capability\AI-Models\Data-Files\threat-definitions.db | 3 | 50 MB | Database |
| Threat Detection Scan | C:\ProgramData\HELIOS\Security\Analysis\Threat-Scan-YYYY-MM-DD.report | 1 | ~5-10 MB | Report |
| Trends Report (Threats) | C:\ProgramData\HELIOS\Capability\Reports\Trend-Analysis\Threat-Trends-YYYY.pdf | 3 | 5-10 MB | Pdf |
| Vault Database | C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\Vault.db | 1 | 20-50 MB | Database |
| Vault Manager Module | C:\Program Files\HELIOS\Dashboard\Modules\VaultManager\VaultManager.dll | 3 | ~8 MB | Dll |
| Vault Monitor Executable | C:\Program Files\HELIOS\Vault\VaultMonitor.exe | 1 | ~3 MB | Exe |
| Weekly Report | C:\ProgramData\HELIOS\Capability\Reports\Weekly-Reports\Weekly-Report-YYYY-WXX.pdf | 3 | 5-20 MB | Pdf |
| Workflow (Daily Security Scan) | C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Daily-Security-Scan.workflow | 3 | ~50 KB | File |
| Workflow (Deep Analysis) | C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Weekly-Deep-Analysis.workflow | 3 | ~50 KB | File |
| Workflow (Incident Response) | C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Incident-Response.workflow | 3 | ~50 KB | File |
| Workflow (Monthly Report) | C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Monthly-Report.workflow | 3 | ~50 KB | File |
| Workflow (Performance Optimization) | C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Performance-Optimization.workflow | 3 | ~50 KB | File |
| Workflow (Real-Time Monitoring) | C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Real-Time-Monitoring.workflow | 3 | ~50 KB | File |
| Workflow (Vault Backup) | C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Vault-Backup.workflow | 3 | ~50 KB | File |

---

## Index by File Type

### Executables (*.exe)

| Component | Location | Phase |
|-----------|----------|-------|
| Dashboard Application | C:\Program Files\HELIOS\Dashboard\Dashboard.exe | 3 |
| System Monitor Service | C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe | 2 |
| System Optimizer Service | C:\Program Files\HELIOS\Optimizer\HELIOSOptimizer.exe | 2 |
| Vault Monitor | C:\Program Files\HELIOS\Vault\VaultMonitor.exe | 1 |
| Analysis Engine | C:\Program Files\HELIOS\Analyzer\HELIOSAnalyzer.exe | 3 |
| USB Creator | C:\ProgramData\HELIOS\Foundation\USBCreator\Creator.exe | 0 |

### Database Files (*.db,*.sqlite)

| Component | Location | Phase | Grows |
|-----------|----------|-------|-------|
| Main Analysis Database | C:\ProgramData\HELIOS\Database\master.db | 3 | Yes |
| Audit Log Database | C:\ProgramData\HELIOS\Database\audit.db | 3 | Yes |
| Analytics Database | C:\ProgramData\HELIOS\Database\analytics.db | 3 | Yes |
| Quarantine Database | C:\ProgramData\HELIOS\Security\Quarantine\Quarantine.db | 1 | Yes |
| Cache Inventory | C:\ProgramData\HELIOS\Optimization\Cache\Cache-Inventory.db | 2 | Yes |
| Threat Database | C:\ProgramData\HELIOS\Security\Analysis\Threat-Database.db | 1 | Yes |
| Threat Definitions | C:\ProgramData\HELIOS\Capability\AI-Models\Data-Files\threat-definitions.db | 3 | No |
| Vault Database | C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\Vault.db | 1 | Yes |

### Configuration Files (*.config,*.cfg, *.json,*.xml)

| Component | Location | Phase |
|-----------|----------|-------|
| Dashboard Configuration | C:\Program Files\HELIOS\Dashboard\Dashboard.config | 3 |
| Cleanup Rules | C:\ProgramData\HELIOS\Optimization\Cleanup\Cleanup-Rules.cfg | 2 |
| Firewall Rules (Export) | C:\ProgramData\HELIOS\Security\Policies\Firewall-Rules.xml | 1 |
| Installation Config | C:\ProgramData\HELIOS\Foundation\InstallScripts\Config\InstallConfig.xml | 0 |
| Partition Configuration | C:\ProgramData\HELIOS\Foundation\Baselines\Partitions\Standard-GPT.cfg | 0 |

### Log Files (*.log)

| Component | Location | Phase | Size |
|-----------|----------|-------|------|
| Phase 0 Installation | C:\ProgramData\HELIOS\Logs\Phase0.log | 0 | 10-50 MB |
| Phase 1 Security | C:\ProgramData\HELIOS\Logs\Phase1.log | 1 | 50-100 MB |
| Phase 2 Optimization | C:\ProgramData\HELIOS\Logs\Phase2.log | 2 | 50-200 MB |
| Phase 3 Capability | C:\ProgramData\HELIOS\Logs\Phase3.log | 3 | 100-200 MB |
| Vault Operations | C:\ProgramData\HELIOS\Logs\Vault-Operations.log | 1 | 5-20 MB |
| Cleanup Operations | C:\ProgramData\HELIOS\Logs\Cleanup-Operations.log | 2 | 10-50 MB |

### Registry Keys (HKLM:)

| Component | Location | Phase | Typical Size |
|-----------|----------|-------|--------------|
| AppLocker Rules | HKLM:\Software\Policies\Microsoft\Windows\SrpV2\ | 1 | <1 MB |
| Firewall Configuration | HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\ | 1 | <1 MB |
| HELIOS Foundation Config | HKLM:\Software\HELIOS\Foundation\ | 0 | <1 MB |
| HELIOS Paths | HKLM:\Software\HELIOS\Paths\ | 0-3 | <1 MB |
| HELIOS Status | HKLM:\Software\HELIOS\Status\ | 0-3 | <1 MB |
| HELIOS Services | HKLM:\SYSTEM\CurrentControlSet\Services\HELIOS* | 2 | <1 MB |
| Services Configuration | HKLM:\SYSTEM\CurrentControlSet\Services\ | 2 | ~10 MB |

---

## Index by Phase

### Phase 0 Files

See **PHASE_0_FILE_LOCATIONS.md** for complete list

Main directories:

- `C:\ProgramData\HELIOS\Foundation\` (~2.5-5.5 GB)
- `C:\ProgramData\HELIOS\Logs\Phase0.log`

### Phase 1 Files

See **PHASE_1_FILE_LOCATIONS.md** for complete list

Main directories:

- `C:\ProgramData\HELIOS\Security\` (~200-1 GB)
- `C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\` (~50-200 MB)
- `HKLM:\Software\Policies\Microsoft\Windows\SrpV2\`

### Phase 2 Files

See **PHASE_2_FILE_LOCATIONS.md** for complete list

Main directories:

- `C:\ProgramData\HELIOS\Optimization\` (~200-500 MB)
- `C:\Windows\System32\Tasks\HELIOS\`
- `HKLM:\SYSTEM\CurrentControlSet\Services\HELIOS*`

### Phase 3 Files

See **PHASE_3_FILE_LOCATIONS.md** for complete list

Main directories:

- `C:\Program Files\HELIOS\Dashboard\` (~200-300 MB)
- `C:\ProgramData\HELIOS\Capability\` (~2-4 GB)
- `C:\ProgramData\HELIOS\Database\` (~100-500 MB)

---

## Search Help

**Find components by:**

1. **Name**: Use Alphabetical Component Index (top of this document)
2. **Type**: Use Index by File Type section
3. **Phase**: Use Index by Phase section
4. **Exact Path**: Use DIRECTORY_TREE.md for full structure
5. **Registry Keys**: Use REGISTRY_CHANGES.md for all registry modifications

**Examples:**

- "Where is the vault?" → Search "Vault Database" in table above
- "What files does Phase 2 use?" → See Index by Phase (Phase 2) or PHASE_2_FILE_LOCATIONS.md
- "Find all log files" → See Index by File Type (Log Files)
- "Where are AI models?" → Search "Model ()" in table or see PHASE_3_FILE_LOCATIONS.md
