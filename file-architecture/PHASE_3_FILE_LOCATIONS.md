# Phase 3: Capability - File Locations

Phase 3 deploys the full HELIOS capability platform including the dashboard application, AI models, profile definitions, workflow systems, and analysis database.

## Overview

| Component | Location | Purpose |
|-----------|----------|---------|
| Dashboard App | C:\Program Files\HELIOS\Dashboard\ | Main user interface application |
| AI Models | C:\ProgramData\HELIOS\Capability\AI-Models\ | Machine learning models |
| Profile Definitions | C:\ProgramData\HELIOS\Capability\Profiles\ | System profile configurations |
| Workflow Definitions | C:\ProgramData\HELIOS\Capability\Workflows\ | Automated workflow tasks |
| Analysis Database | C:\ProgramData\HELIOS\Database\ | Central analysis and metadata database |
| Reports | C:\ProgramData\HELIOS\Capability\Reports\ | Analysis reports and insights |
| Capability Logs | C:\ProgramData\HELIOS\Logs\Phase3.log | Phase 3 diagnostic logs |
| AI Configuration | HKLM:\Software\HELIOS\Capability\ | AI system registry settings |

---

## Dashboard Application

**Location**: `C:\Program Files\HELIOS\Dashboard\`

**Purpose**: Main HELIOS user interface and control center

**Files Created**:

```
C:\Program Files\HELIOS\Dashboard\
├── Dashboard.exe                       # Main application executable
├── Dashboard.config                    # Application configuration
├── app.manifest                        # Application manifest (UAC)
├── settings.json                       # Default application settings
├── license.txt                         # License information
│
├── Dependencies\
│   ├── System.Core.dll
│   ├── System.Windows.Forms.dll
│   ├── System.Net.Http.dll
│   ├── Newtonsoft.Json.dll
│   ├── log4net.dll
│   └── (other required DLLs)
│
├── Resources\
│   ├── Icons\
│   │   ├── app-icon.ico
│   │   ├── logo.png
│   │   └── (UI icons)
│   ├── Images\
│   │   ├── dashboard-background.png
│   │   └── (UI graphics)
│   ├── Themes\
│   │   ├── Light-Theme.xaml
│   │   ├── Dark-Theme.xaml
│   │   └── High-Contrast-Theme.xaml
│   └── Localization\
│       ├── en-US.json
│       ├── es-ES.json
│       ├── fr-FR.json
│       └── (other languages)
│
├── Modules\
│   ├── SystemOverview\
│   │   ├── SystemOverview.dll
│   │   └── config.xml
│   ├── SecurityCenter\
│   │   ├── SecurityCenter.dll
│   │   └── policies.xml
│   ├── VaultManager\
│   │   ├── VaultManager.dll
│   │   └── config.xml
│   ├── PerformanceAnalyzer\
│   │   ├── PerformanceAnalyzer.dll
│   │   ├── metrics.xml
│   │   └── graphs.xml
│   ├── ReportGenerator\
│   │   ├── ReportGenerator.dll
│   │   └── templates\
│   ├── WorkflowEngine\
│   │   ├── WorkflowEngine.dll
│   │   └── core-workflows.xml
│   ├── AIConsole\
│   │   ├── AIConsole.dll
│   │   └── prompts.xml
│   └── Settings\
│       ├── Settings.dll
│       └── settings-schema.xml
│
├── Plugins\
│   ├── PluginBase.dll
│   ├── ThirdPartyPlugins\
│   └── CorePlugins\
│       ├── CloudSync.dll
│       ├── DataExport.dll
│       └── EmailNotifier.dll
│
├── Logs\
│   ├── Dashboard.log
│   ├── Dashboard-Errors.log
│   └── Dashboard-Performance.log
│
└── Data\
    ├── App-Cache.db
    └── recent-files.json
```

**Access**: Users can run; admin for installation

**Size**: 200-300 MB with all modules

**Examples**:

```
C:\Program Files\HELIOS\Dashboard\Dashboard.exe
C:\Program Files\HELIOS\Dashboard\Modules\AIConsole\AIConsole.dll
```

---

## AI Models Directory

**Location**: `C:\ProgramData\HELIOS\Capability\AI-Models\`

**Purpose**: Machine learning models for analysis and decision-making

**Files Created**:

```
C:\ProgramData\HELIOS\Capability\AI-Models\
├── Core-Models\
│   ├── threat-detection-v4.1.model     # 150 MB
│   ├── performance-anomaly-v3.2.model  # 120 MB
│   ├── system-health-v2.1.model        # 80 MB
│   ├── behavior-analysis-v5.0.model    # 200 MB
│   └── pattern-recognition-v3.5.model  # 100 MB
│
├── Specialized-Models\
│   ├── Network-Anomaly-Detector\
│   │   ├── model.bin                   # 75 MB
│   │   ├── config.json
│   │   └── metadata.txt
│   ├── File-Behavior-Analyzer\
│   │   ├── model.bin                   # 90 MB
│   │   ├── config.json
│   │   └── metadata.txt
│   ├── Process-Analyzer\
│   │   ├── model.bin                   # 110 MB
│   │   ├── config.json
│   │   └── metadata.txt
│   └── Malware-Classifier\
│   │   ├── model.bin                   # 140 MB
│   │   ├── config.json
│   │   └── metadata.txt
│
├── Data-Files\
│   ├── training-data-summary.json      # Training dataset info
│   ├── model-accuracy-metrics.csv      # Performance metrics
│   ├── threat-definitions.db           # 50 MB threat database
│   └── signature-database.db           # 100 MB signature database
│
├── Model-Versions\
│   ├── v4.0\
│   │   ├── threat-detection-v4.0.model
│   │   └── (v4.0 models - for rollback)
│   ├── v3.9\
│   │   └── (v3.9 models - archive)
│   └── v3.8\
│       └── (v3.8 models - archive)
│
└── Model-Metadata\
    ├── models.json                     # Model registry and versions
    ├── last-update.txt                 # Last model update timestamp
    └── model-performance.csv           # Accuracy and latency metrics
```

**Model File Format**:

- Binary ML models (TensorFlow, PyTorch, or custom format)
- Size: 75-200 MB each (total ~800 MB - 1.5 GB)
- Loaded into memory on startup
- Cannot be directly modified (read-only)

**Access**: Admin to update; services read models

**Size**: 1-1.5 GB total

**Examples**:

```
C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\threat-detection-v4.1.model
C:\ProgramData\HELIOS\Capability\AI-Models\Specialized-Models\Malware-Classifier\model.bin
C:\ProgramData\HELIOS\Capability\AI-Models\Data-Files\threat-definitions.db
```

---

## Profile Definitions

**Location**: `C:\ProgramData\HELIOS\Capability\Profiles\`

**Purpose**: System and analysis profile configurations

**Files Created**:

```
C:\ProgramData\HELIOS\Capability\Profiles\
├── System-Profiles\
│   ├── Enterprise-High-Security.profile
│   │   # For enterprise high-security environments
│   ├── Home-User.profile
│   │   # For home/consumer systems
│   ├── Developer-Machine.profile
│   │   # For developer workstations
│   ├── Server-Production.profile
│   │   # For production servers
│   └── Laptop-Battery-Saving.profile
│       # For battery-powered laptops
│
├── Analysis-Profiles\
│   ├── Quick-Scan.profile              # Fast analysis profile
│   ├── Deep-Analysis.profile           # Comprehensive analysis
│   ├── Real-Time-Monitor.profile       # Continuous monitoring
│   ├── Threat-Hunting.profile          # Advanced threat detection
│   └── Performance-Tuning.profile      # Performance optimization
│
├── Threat-Response-Profiles\
│   ├── Containment.profile             # Isolate and contain
│   ├── Investigation.profile           # Detailed forensics
│   ├── Remediation.profile             # Cleanup and restore
│   └── Recovery.profile                # System recovery
│
├── Custom-Profiles\
│   ├── User-Profile-1.profile
│   ├── User-Profile-2.profile
│   └── (user-created profiles)
│
├── AI-Profiles\
│   ├── AI-Aggressive-Detection.profile # Max sensitivity AI
│   ├── AI-Balanced.profile             # Normal AI sensitivity
│   ├── AI-Minimal.profile              # Low sensitivity AI
│   └── AI-Custom.profile               # Custom AI settings
│
└── Profile-Metadata\
    ├── profiles.json                   # Profile registry
    ├── last-used.txt                   # Last active profile
    └── profile-compatibility.txt       # Compatibility matrix
```

**Profile JSON Structure**:

```json
{
  "profile_name": "Enterprise-High-Security",
  "version": "4.1.0",
  "description": "High-security enterprise profile",
  "threat_level": "critical",
  "ai_settings": {
    "model": "threat-detection-v4.1",
    "sensitivity": 0.95,
    "detection_threshold": 0.8,
    "auto_quarantine": true,
    "threat_response": "isolate"
  },
  "analysis_settings": {
    "scan_frequency": "hourly",
    "deep_inspection": true,
    "behavioral_analysis": true,
    "log_retention_days": 90
  },
  "vault_settings": {
    "encryption": "AES-256",
    "auto_lock_minutes": 15,
    "backup_frequency": "daily"
  }
}
```

**Access**: Admin to create/modify; services read profiles

**Size**: ~10-50 KB per profile; total ~500 KB

**Examples**:

```
C:\ProgramData\HELIOS\Capability\Profiles\System-Profiles\Enterprise-High-Security.profile
C:\ProgramData\HELIOS\Capability\Profiles\Analysis-Profiles\Deep-Analysis.profile
C:\ProgramData\HELIOS\Capability\Profiles\AI-Profiles\AI-Aggressive-Detection.profile
```

---

## Workflow Definitions

**Location**: `C:\ProgramData\HELIOS\Capability\Workflows\`

**Purpose**: Automated workflow task definitions

**Files Created**:

```
C:\ProgramData\HELIOS\Capability\Workflows\
├── Built-In-Workflows\
│   ├── Daily-Security-Scan.workflow
│   │   # Runs: Daily 2:00 AM
│   │   # Steps: Scan threats, analyze anomalies, generate report
│   │
│   ├── Weekly-Deep-Analysis.workflow
│   │   # Runs: Weekly Saturday 3:00 AM
│   │   # Steps: Full system scan, historical analysis, trends
│   │
│   ├── Monthly-Report.workflow
│   │   # Runs: 1st of month 1:00 AM
│   │   # Steps: Aggregate data, generate insights, email report
│   │
│   ├── Real-Time-Monitoring.workflow
│   │   # Runs: Continuous
│   │   # Steps: Monitor threats, alert on anomalies
│   │
│   ├── Incident-Response.workflow
│   │   # Triggered: On threat detection
│   │   # Steps: Isolate, analyze, notify, remediate
│   │
│   ├── Vault-Backup.workflow
│   │   # Runs: Daily 1:00 AM
│   │   # Steps: Backup vault, verify backup, cleanup old backups
│   │
│   └── Performance-Optimization.workflow
│       # Runs: Daily 2:30 AM
│       # Steps: Cleanup temp files, optimize cache, defrag
│
├── Custom-Workflows\
│   ├── User-Workflow-1.workflow
│   ├── User-Workflow-2.workflow
│   └── (user-created workflows)
│
├── Workflow-Templates\
│   ├── template-security-scan.xml
│   ├── template-data-analysis.xml
│   ├── template-reporting.xml
│   └── template-automation.xml
│
└── Workflow-Metadata\
    ├── workflows.json                  # Workflow registry
    ├── execution-history.log           # Workflow execution log
    └── workflow-performance.csv        # Success rates, timing
```

**Workflow XML Structure Example**:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Workflow>
  <Name>Daily-Security-Scan</Name>
  <Version>4.1.0</Version>
  <Description>Daily security scan and threat analysis</Description>
  <Schedule>
    <Type>Daily</Type>
    <Time>02:00:00</Time>
    <Timezone>UTC</Timezone>
  </Schedule>
  <Steps>
    <Step id="1">
      <Action>ScanForThreats</Action>
      <Profile>Quick-Scan</Profile>
      <OnComplete>Continue</OnComplete>
      <OnError>Notify-Admin</OnError>
    </Step>
    <Step id="2">
      <Action>AnalyzeAnomalies</Action>
      <Model>behavior-analysis-v5.0</Model>
      <Threshold>0.8</Threshold>
      <OnComplete>Continue</OnComplete>
    </Step>
    <Step id="3">
      <Action>GenerateReport</Action>
      <ReportType>Daily-Summary</ReportType>
      <EmailTo>admin@company.com</EmailTo>
      <OnComplete>Archive</OnComplete>
    </Step>
  </Steps>
  <Actions>
    <OnSuccess>LogCompletion</OnSuccess>
    <OnFailure>AlertAdmin,LogError</OnFailure>
    <Timeout>3600</Timeout>
  </Actions>
</Workflow>
```

**Access**: Admin to create/modify; services execute workflows

**Size**: ~10-100 KB per workflow; total ~2-5 MB

**Examples**:

```
C:\ProgramData\HELIOS\Capability\Workflows\Built-In-Workflows\Daily-Security-Scan.workflow
C:\ProgramData\HELIOS\Capability\Workflows\Custom-Workflows\User-Workflow-1.workflow
C:\ProgramData\HELIOS\Capability\Workflows\Workflow-Metadata\workflows.json
```

---

## Analysis Database

**Location**: `C:\ProgramData\HELIOS\Database\master.db`

**Purpose**: Central analysis database storing all findings, history, and metadata

**Files Created**:

```
C:\ProgramData\HELIOS\Database\
├── master.db                           # Main database file
│   # SQLite database
│   # Size: 100-500 MB depending on history
│   # Tables: See structure below
│
├── audit.db                            # Audit log database
│   # Track all administrative actions
│   # Size: 50-200 MB
│
├── analytics.db                        # Analytics database
│   # Performance metrics and trends
│   # Size: 50-100 MB
│
├── Backups\
│   ├── master-2024-01-15.db.backup    # Daily backup
│   ├── master-2024-01-14.db.backup
│   ├── master-2024-01-13.db.backup
│   └── master-2024-01-12.db.backup    # 3+ day rotation
│
├── Archives\
│   ├── 2024-01\
│   │   └── master-2024-01-31.db       # Monthly archive
│   ├── 2023-12\
│   └── 2023-11\
│
└── Metadata\
    ├── database-schema.sql             # Schema definition
    ├── last-backup.txt                 # Last backup timestamp
    └── integrity-check.log             # Database integrity reports
```

**Database Schema** (master.db):

```
Tables:
├── threats_detected
│   ├── id INTEGER PRIMARY KEY
│   ├── detection_timestamp DATETIME
│   ├── threat_type TEXT (malware, anomaly, suspicious)
│   ├── severity TEXT (critical, high, medium, low)
│   ├── file_path TEXT
│   ├── file_hash TEXT (SHA-256)
│   ├── threat_name TEXT
│   ├── action_taken TEXT (quarantine, alert, log)
│   ├── ai_confidence FLOAT (0.0-1.0)
│   └── resolution_status TEXT (unresolved, investigating, resolved)
│
├── system_analysis
│   ├── id INTEGER PRIMARY KEY
│   ├── analysis_timestamp DATETIME
│   ├── profile_used TEXT
│   ├── duration_seconds INTEGER
│   ├── items_scanned INTEGER
│   ├── threats_found INTEGER
│   ├── anomalies_detected INTEGER
│   ├── status TEXT (completed, running, failed)
│   └── report_id INTEGER (foreign key)
│
├── performance_metrics
│   ├── id INTEGER PRIMARY KEY
│   ├── timestamp DATETIME
│   ├── cpu_usage_percent FLOAT
│   ├── memory_usage_mb INTEGER
│   ├── disk_io_mbps FLOAT
│   ├── active_processes INTEGER
│   ├── services_running INTEGER
│   └── boot_time_seconds FLOAT
│
├── vault_access_log
│   ├── id INTEGER PRIMARY KEY
│   ├── access_timestamp DATETIME
│   ├── username TEXT
│   ├── action TEXT (open, modify, delete, backup)
│   ├── item_type TEXT (credential, certificate, key)
│   ├── item_name TEXT
│   ├── result TEXT (success, failed)
│   └── details TEXT
│
├── workflow_execution
│   ├── id INTEGER PRIMARY KEY
│   ├── workflow_name TEXT
│   ├── execution_timestamp DATETIME
│   ├── completion_timestamp DATETIME
│   ├── status TEXT (completed, failed, cancelled)
│   ├── items_processed INTEGER
│   ├── errors_count INTEGER
│   └── execution_log TEXT
│
├── ai_predictions
│   ├── id INTEGER PRIMARY KEY
│   ├── prediction_timestamp DATETIME
│   ├── model_used TEXT
│   ├── input_data TEXT (JSON)
│   ├── prediction_result TEXT (JSON)
│   ├── confidence FLOAT (0.0-1.0)
│   └── actual_outcome TEXT (for validation)
│
├── reports
│   ├── id INTEGER PRIMARY KEY
│   ├── report_type TEXT (daily, weekly, monthly, incident)
│   ├── generation_timestamp DATETIME
│   ├── report_data BLOB (binary PDF or JSON)
│   ├── threat_count INTEGER
│   ├── anomaly_count INTEGER
│   └── archived_date DATETIME
│
└── system_changes
    ├── id INTEGER PRIMARY KEY
    ├── change_timestamp DATETIME
    ├── change_type TEXT (service, registry, file, policy)
    ├── component TEXT
    ├── previous_value TEXT
    ├── new_value TEXT
    ├── initiated_by TEXT (user, system, workflow)
    └── rollback_available BOOLEAN
```

**Access**: Admin to query/backup; services read/write

**Size**: 100-500 MB (grows over time; archive old data)

**Examples**:

```
C:\ProgramData\HELIOS\Database\master.db
C:\ProgramData\HELIOS\Database\Backups\master-2024-01-15.db.backup
C:\ProgramData\HELIOS\Database\Archives\2024-01\master-2024-01-31.db
```

---

## Reports Directory

**Location**: `C:\ProgramData\HELIOS\Capability\Reports\`

**Purpose**: Generated analysis reports and insights

**Files Created**:

```
C:\ProgramData\HELIOS\Capability\Reports\
├── Daily-Reports\
│   ├── Daily-Report-2024-01-15.pdf    # Today's report
│   ├── Daily-Report-2024-01-14.pdf
│   ├── Daily-Report-2024-01-13.pdf
│   └── Daily-Report-2024-01-12.pdf    # Last 3 days
│
├── Weekly-Reports\
│   ├── Weekly-Report-2024-W03.pdf     # Week 3 summary
│   ├── Weekly-Report-2024-W02.pdf
│   └── Weekly-Report-2024-W01.pdf
│
├── Monthly-Reports\
│   ├── Monthly-Report-2024-01.pdf     # January summary
│   ├── Monthly-Report-2023-12.pdf     # December
│   └── Monthly-Report-2023-11.pdf     # November
│
├── Incident-Reports\
│   ├── Incident-2024-01-15-001.pdf    # Incident investigation
│   ├── Incident-2024-01-14-001.pdf
│   └── (incident details)
│
├── Trend-Analysis\
│   ├── Threat-Trends-2024.pdf         # Threat trend analysis
│   ├── Performance-Trends-2024.pdf    # Performance trends
│   └── AI-Insights-2024.pdf           # AI model insights
│
├── Executive-Summaries\
│   ├── Executive-Summary-2024-Q1.pdf  # Quarterly summary
│   ├── Executive-Summary-2023-Q4.pdf
│   └── Executive-Summary-2023-Q3.pdf
│
├── Report-Templates\
│   ├── daily-report.template.xml
│   ├── weekly-report.template.xml
│   ├── monthly-report.template.xml
│   ├── incident-report.template.xml
│   └── executive-summary.template.xml
│
├── Report-Data\
│   ├── threat-statistics-2024.json    # Statistical data
│   ├── performance-metrics-2024.csv   # Metric timeseries
│   ├── anomaly-list-2024.json         # Anomalies detected
│   └── incident-summary-2024.json     # Incident summaries
│
└── Report-Metadata\
    ├── reports.json                    # Report registry
    ├── generation-history.log          # Report generation log
    └── distribution-list.txt           # Email distribution
```

**Report Contents**:

- Executive summary
- Threat statistics
- Performance metrics
- Anomalies detected
- Incidents investigated
- Recommendations
- Compliance status
- AI insights

**Access**: Admin to manage; users can view own reports

**Size**: 5-20 MB per report; directory ~500 MB - 2 GB

**Examples**:

```
C:\ProgramData\HELIOS\Capability\Reports\Daily-Reports\Daily-Report-2024-01-15.pdf
C:\ProgramData\HELIOS\Capability\Reports\Weekly-Reports\Weekly-Report-2024-W03.pdf
C:\ProgramData\HELIOS\Capability\Reports\Incident-Reports\Incident-2024-01-15-001.pdf
```

---

## AI Configuration Registry

**Location**: `HKLM:\Software\HELIOS\Capability\`

**Purpose**: AI system configuration and settings

**Registry Keys**:

```
HKLM:\Software\HELIOS\Capability\
├── AI-Settings\
│   ├── ModelPath                       # "C:\ProgramData\HELIOS\Capability\AI-Models"
│   ├── ActiveModel                     # "threat-detection-v4.1.model"
│   ├── InferenceThreads                # 4 (CPU threads for inference)
│   ├── GPUAcceleration                 # 1 (enabled if GPU available)
│   ├── ModelUpdateFrequency            # 604800 (weekly in seconds)
│   ├── ConfidenceThreshold             # 0.75 (minimum confidence for alerts)
│   └── AutoRetraining                  # 1 (enable model retraining)
│
├── Analysis-Settings\
│   ├── DefaultProfile                  # "Enterprise-High-Security"
│   ├── ScanFrequency                   # "hourly"
│   ├── DeepInspection                  # 1 (enabled)
│   ├── BehavioralAnalysis              # 1 (enabled)
│   ├── AnomalyDetection                # 1 (enabled)
│   └── MaxConcurrentAnalysis           # 4
│
├── Dashboard-Settings\
│   ├── UITheme                         # "Light" or "Dark"
│   ├── Language                        # "en-US"
│   ├── RefreshInterval                 # 5000 (milliseconds)
│   ├── EnableNotifications             # 1 (enabled)
│   └── TrayIconEnabled                 # 1 (show in system tray)
│
├── Reporting-Settings\
│   ├── EnableAutoReporting             # 1 (enabled)
│   ├── ReportFrequency                 # "daily"
│   ├── ReportFormat                    # "pdf"
│   ├── EmailDistribution               # "admin@company.com"
│   └── ArchiveReports                  # 1 (enabled)
│
├── Integration-Settings\
│   ├── CloudSyncEnabled                # 1 (sync to cloud)
│   ├── CloudProvider                   # "AWS" or "Azure"
│   ├── DataExportEnabled               # 1 (allow exports)
│   └── WebDashboardEnabled             # 1 (enable web UI)
│
└── Feature-Flags\
    ├── BetaFeatures                    # 0 (disabled by default)
    ├── AdvancedAI                      # 1 (enabled)
    ├── MachineLearning                 # 1 (enabled)
    └── ExperimentalModels              # 0 (disabled)
```

**Examples**:

```
HKLM:\Software\HELIOS\Capability\AI-Settings\ActiveModel = "threat-detection-v4.1.model"
HKLM:\Software\HELIOS\Capability\Analysis-Settings\DefaultProfile = "Enterprise-High-Security"
HKLM:\Software\HELIOS\Capability\Dashboard-Settings\UITheme = "Dark"
```

**Access**: Admin/SYSTEM required

---

## Phase 3 Logs

**Location**: `C:\ProgramData\HELIOS\Logs\Phase3.log`

**Purpose**: Phase 3 deployment and capability diagnostic logs

**Files Created**:

```
C:\ProgramData\HELIOS\Logs\
├── Phase3.log                          # Main Phase 3 log
├── Phase3-Details.log                  # Verbose Phase 3 log
├── Phase3-Errors.log                   # Phase 3 errors only
├── Phase3-Warnings.log                 # Phase 3 warnings
├── Dashboard-Startup.log               # Dashboard startup logs
├── AI-Model-Loading.log                # AI model initialization
├── Workflow-Execution.log              # Workflow run logs
├── Report-Generation.log               # Report generation logs
├── Analysis-Operations.log             # Analysis operation logs
└── Database-Operations.log             # Database transaction logs
```

**Access**: Admin to write; everyone can read

**Size**: 100-200 MB with verbose logging

---

## Complete Directory Tree

```
C:\Program Files\HELIOS\
├── Dashboard\                          # Phase 3 root (user-facing)
│   ├── Dashboard.exe
│   ├── Dependencies\
│   ├── Resources\
│   ├── Modules\
│   ├── Plugins\
│   ├── Logs\
│   └── Data\
│
└── (Other HELIOS components for earlier phases)

C:\ProgramData\HELIOS\
├── Capability\                         # Phase 3 root (system data)
│   ├── AI-Models\
│   │   ├── Core-Models\
│   │   ├── Specialized-Models\
│   │   ├── Data-Files\
│   │   ├── Model-Versions\
│   │   └── Model-Metadata\
│   ├── Profiles\
│   │   ├── System-Profiles\
│   │   ├── Analysis-Profiles\
│   │   ├── Threat-Response-Profiles\
│   │   ├── Custom-Profiles\
│   │   ├── AI-Profiles\
│   │   └── Profile-Metadata\
│   ├── Workflows\
│   │   ├── Built-In-Workflows\
│   │   ├── Custom-Workflows\
│   │   ├── Workflow-Templates\
│   │   └── Workflow-Metadata\
│   └── Reports\
│       ├── Daily-Reports\
│       ├── Weekly-Reports\
│       ├── Monthly-Reports\
│       ├── Incident-Reports\
│       ├── Trend-Analysis\
│       ├── Executive-Summaries\
│       ├── Report-Templates\
│       ├── Report-Data\
│       └── Report-Metadata\
│
├── Database\
│   ├── master.db                       # Main analysis database
│   ├── audit.db
│   ├── analytics.db
│   ├── Backups\
│   ├── Archives\
│   └── Metadata\
│
└── Logs\
    ├── Phase3.log
    ├── Dashboard-Startup.log
    ├── AI-Model-Loading.log
    └── (other Phase 3 logs)
```

---

## File Size Summary

| Component | Size |
|-----------|------|
| Dashboard application (exe + libs) | 200-300 MB |
| AI models (all) | 1-1.5 GB |
| Profiles | ~500 KB |
| Workflows | ~2-5 MB |
| Analysis database (master.db) | 100-500 MB |
| Report backups (3 months) | 500 MB - 2 GB |
| **Total Phase 3** | **2-4.5 GB** |

---

## Next Steps

After Phase 3 completes:

- Dashboard operational
- AI capabilities active
- Automated workflows running
- Analysis and reporting active

HELIOS platform fully deployed!

See **QUICK_LOOKUP_TABLE.md** for complete component reference.
