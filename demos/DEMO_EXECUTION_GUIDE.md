# HELIOS Platform Demo Execution Guide

Complete guide for running and understanding the HELIOS Platform Demo Application Suite.

## ⚡ Quick Start (5 minutes)

### 1. Build the Demo Application

```powershell
cd C:\Users\ADMIN\helios-platform\demos

# Restore dependencies
dotnet restore

# Build for Release
dotnet build -c Release
```

### 2. Run Interactive Demo Launcher

```powershell
# Option A: Using dotnet run
dotnet run

# Option B: Direct executable (after build)
.\bin\Release\net8.0\HeliosDemos.exe

# Option C: Using command line argument
dotnet run -- 1
```

### 3. Select Demo

The interactive menu shows all 7 demos with descriptions and estimated durations.

---

## 🎯 Running Individual Demos

### Method 1: Interactive Menu

1. Run `HeliosDemos.exe` or `dotnet run`
2. Follow numbered menu (1-7)
3. Demo executes automatically
4. Press any key to return to menu

### Method 2: Command Line Arguments

```bash
# Run by name
dotnet run -- quickstart          # Demo 1
dotnet run -- gaming              # Demo 2
dotnet run -- developer           # Demo 3
dotnet run -- security            # Demo 4
dotnet run -- multiphase          # Demo 5
dotnet run -- enterprise          # Demo 6
dotnet run -- custom              # Demo 7

# Run by number
dotnet run -- 1                   # Demo 1
dotnet run -- 3                   # Demo 3
dotnet run -- 6                   # Demo 6

# Run all demos
dotnet run -- all                 # All 7 demos sequentially
```

---

## 📊 Understanding Demo Output

### Real-time Console Output

Each demo displays:

- ✓ Progress bars with percentage completion
- ✓ Color-coded status messages
- ✓ Component deployment status
- ✓ Performance metrics
- ✓ Real-time counters

### Color Scheme

- 🟢 **Green** - Success, completed operations
- 🔴 **Red** - Errors, failures
- 🟡 **Yellow** - Warnings, attention needed
- 🔵 **Cyan** - Information, progress
- 🟣 **Magenta** - Phase markers, major sections
- ⚫ **Gray** - Metadata, additional info

### Console Output Example

```
┌─────────────────────────────────────────────────────┐
│ HELIOS PLATFORM DEMO: Quick Start Demo               │
└─────────────────────────────────────────────────────┘

═══ PHASE 0: System Validation ═══
✓ Windows 11 Pro detected
✓ System requirements met
✓ Admin privileges confirmed

═══ PHASE 1: Professional Tier Deployment ═══
[1/7] 14%: Installing Monado Engine...
  ⟳ Deploying Monado Engine...
  ✓ Monado Engine deployed successfully
```

---

## 📁 Output Files Location

All output files are saved to:

```
C:\Users\<YourUsername>\helios-demos\<YYYY-MM-DD>\
```

### File Types Generated

**1. Execution Log (.log)**

- Raw execution log with timestamps
- Detailed step-by-step progress
- Useful for debugging and detailed review

**2. Text Report (.report.txt)**

- Formatted summary report
- Key metrics and statistics
- Component deployment list
- Final status summary

**3. JSON Report (.json)**

- Machine-readable format
- Structured data for parsing
- Easy integration with other tools
- Contains all metrics and status information

### Example Output Structure

```
C:\Users\ADMIN\helios-demos\
├── 2024-04-13\
│   ├── QuickStartDemo_14-30-45.log
│   ├── QuickStartDemo_14-30-45.report.txt
│   ├── QuickStartDemo_14-30-45.json
│   ├── GamingOptimizationDemo_15-42-22.log
│   ├── GamingOptimizationDemo_15-42-22.report.txt
│   └── GamingOptimizationDemo_15-42-22.json
```

---

## 🔍 Demo-Specific Execution Details

### Demo 1: Quick Start Demo (8 minutes)

**What to expect:**

- Real-time progress of component deployment
- Before/after system metrics table
- 7 components deployed sequentially
- Dashboard configuration display

**Key metrics shown:**

- CPU usage before/after
- Memory usage before/after
- Disk usage percentage
- Process count

**Command:**

```bash
dotnet run -- quickstart
```

---

### Demo 2: Gaming Optimization Demo (10 minutes)

**What to expect:**

- Gaming environment validation (GPU, RAM, Monitor)
- 6 gaming tools installation
- System optimization steps
- GPU configuration details
- Benchmark execution with progress
- FPS improvements comparison (45 → 145 FPS)

**Key metrics shown:**

- Average FPS (baseline vs. optimized)
- GPU temperature (78°C → 62°C)
- Frame time (22.2ms → 6.9ms)
- Power consumption
- Min/Max FPS

**Command:**

```bash
dotnet run -- gaming
```

---

### Demo 3: Developer Setup Demo (12 minutes)

**What to expect:**

- Environment validation (OS, permissions, disk space)
- 4 core development tools installation
- 4 container tools setup
- 4 runtime environments installation
- 4 development utilities
- 10 VS Code extensions configuration
- Workspace setup (directories, Git, SSH)
- Developer dashboard display

**Key metrics shown:**

- Tools installed count
- IDE status
- Runtime versions
- Container tools
- Extensions count (10)

**Command:**

```bash
dotnet run -- developer
```

---

### Demo 4: Security Hardening Demo (10 minutes)

**What to expect:**

- Initial security audit (5 vulnerabilities found)
- Firewall hardening setup
- AppLocker policy configuration
- UAC enhancement
- BitLocker encryption setup
- Security policy application
- Windows Defender activation
- Security score improvement (35 → 92)
- Compliance report generation

**Key metrics shown:**

- Initial security score: 35/100
- Final security score: 92/100
- Vulnerabilities found: 5
- All issues resolved
- Compliance certifications verified

**Command:**

```bash
dotnet run -- security
```

---

### Demo 5: Multi-Phase Deployment Demo (15 minutes)

**What to expect:**

- Real-time progress bars for each phase
- Phase-by-phase component deployment (8 phases)
- Timing analysis for each phase
- Rollback demonstration (Phase 7 → 4)
- Resource utilization metrics
- Complete timeline summary

**Key metrics shown:**

- Phase execution timeline
- Total components deployed
- Average phase duration
- Resource utilization
- Success rate (100%)

**Command:**

```bash
dotnet run -- multiphase
```

---

### Demo 6: Enterprise Deployment Demo (14 minutes)

**What to expect:**

- Enterprise infrastructure validation
- 9 components deployment (7 core + 2 auxiliary)
- Active Directory integration
- Role-Based Access Control (RBAC) setup
- Backup and disaster recovery configuration
- Monitoring setup (47 alert rules, 4 dashboards)
- High availability configuration (3 regions, 99.99% SLA)
- Comprehensive enterprise report generation
- 6 output reports (HTML, PDF, JSON, CSV, XLSX)

**Key metrics shown:**

- Deployment tier: Ultimate
- Components: 9 total
- Regions: 3
- Alert rules: 47
- SLA: 99.99%
- Security score: 98/100

**Command:**

```bash
dotnet run -- enterprise
```

---

### Demo 7: Custom Configuration Demo (9 minutes)

**What to expect:**

- Interactive tier selection (Professional/Enterprise/Ultimate)
- Component selection from 7 available
- Deployment options configuration (8 options)
- Configuration review summary
- Estimated deployment time calculation
- Custom deployment execution
- Configuration profile export (multiple formats)

**Key metrics shown:**

- Selected tier
- Component count (3-7)
- Options enabled
- Estimated time
- Actual deployment time

**Command:**

```bash
dotnet run -- custom
```

---

## 🏃 Running All Demos

### Sequential Execution

```bash
# Run all 7 demos in sequence
dotnet run -- all

# Or select option 8 from interactive menu
```

**Total Duration:** ~90 minutes

### Summary Output After Completion

Displays table with:

- All demo names
- Success/failure status
- Individual execution times
- Total execution time
- Overall success rate
- Total components deployed

---

## 🛠️ Build Instructions

### Prerequisites

- Windows 10/11 Pro or Enterprise
- .NET 8 SDK (or Runtime for pre-built exe)
- Administrator terminal
- 500MB free disk space

### Build Commands

```powershell
# Navigate to demos folder
cd C:\Users\ADMIN\helios-platform\demos

# Restore NuGet packages
dotnet restore

# Build Debug version
dotnet build -c Debug

# Build Release version (optimized executable)
dotnet build -c Release

# Clean build artifacts
dotnet clean

# Publish as self-contained executable
dotnet publish -c Release -o .\publish
```

### Output Executables

After successful build:

```
.\bin\Debug\net8.0\HeliosDemos.exe          # Debug version
.\bin\Release\net8.0\HeliosDemos.exe        # Release version (optimized)
```

---

## 📋 System Requirements Checklist

Before running demos, verify:

- [ ] Windows 10/11 Pro or Enterprise edition
- [ ] Administrator or elevated privileges
- [ ] .NET 8 Runtime or SDK installed
- [ ] 8GB RAM minimum (16GB recommended)
- [ ] 50GB+ free disk space total
- [ ] Internet connection (for optional components)
- [ ] Display capable of 1920x1080 minimum

### Verify .NET Installation

```powershell
dotnet --version
# Should output: 8.0.x or higher
```

---

## 🐛 Troubleshooting

### Issue: "dotnet: command not found"

**Solution:**

1. Install .NET 8 SDK from https://dotnet.microsoft.com/download
2. Restart PowerShell/Terminal after installation
3. Verify with `dotnet --version`

### Issue: "Access denied" or "Permission denied"

**Solution:**

1. Run PowerShell as Administrator
2. Navigate to demos folder
3. Execute: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
4. Try again

### Issue: Demo hangs or freezes

**Solution:**

1. Press Ctrl+C to interrupt
2. Check available disk space: `Get-PSDrive C`
3. Ensure no other heavy processes running
4. Try running demo again

### Issue: Log files not created

**Solution:**

1. Check path: `C:\Users\<username>\helios-demos`
2. Ensure folder exists: `mkdir C:\Users\$env:USERNAME\helios-demos`
3. Verify write permissions on folder
4. Try running demo again

### Issue: Wrong output tier or components

**Solution (Custom Demo):**

- This is correct behavior for interactive selection
- For consistent results, use specific demo (not custom)
- Custom demo simulates selecting Enterprise tier with 6 components

---

## 📊 Reading JSON Reports

Each demo generates a .json file with structured data:

```json
{
  "demoName": "QuickStartDemo",
  "executionTime": "00:08:30",
  "success": true,
  "components": [
    "Monado Engine",
    "Security System",
    "AI Orchestrator",
    "GUI Dashboard",
    "Build Agents",
    "DevAI Hub",
    "Software Stack"
  ],
  "metrics": {
    "TotalDeploymentTime": 510.5,
    "DeploymentTier": "Professional",
    "ComponentCount": 7,
    "SystemReady": true
  }
}
```

### Using JSON Reports

```powershell
# Read and parse JSON in PowerShell
$report = Get-Content "QuickStartDemo_14-30-45.json" | ConvertFrom-Json
$report.metrics
$report.success
```

---

## 🎓 Learning Outcomes

After running demos, you'll understand:

- ✓ HELIOS Platform architecture
- ✓ Component deployment process
- ✓ System optimization capabilities
- ✓ Security hardening procedures
- ✓ Enterprise deployment best practices
- ✓ Gaming optimization techniques
- ✓ Development environment setup
- ✓ Multi-phase deployment orchestration
- ✓ High availability configuration
- ✓ Monitoring and alerting setup

---

## 📞 Support & Resources

### Documentation

- **DEMO_SCENARIOS.md** - Detailed scenario descriptions
- **DEMO_EXECUTION_GUIDE.md** - This file
- **README.md** - Quick reference

### Logs and Reports

- Check `.log` files for detailed execution trace
- Review `.report.txt` for formatted summary
- Parse `.json` for programmatic access

### Common Paths

```
Source code:     C:\Users\ADMIN\helios-platform\demos\
Executables:     C:\Users\ADMIN\helios-platform\demos\bin\Release\net8.0\
Output files:    C:\Users\<username>\helios-demos\<date>\
```

---

## ✅ Verification Checklist

After each demo run:

- [ ] Console output shows completion
- [ ] No errors displayed
- [ ] Log files created in helios-demos folder
- [ ] Report file contains expected metrics
- [ ] JSON file is valid and parseable
- [ ] Execution time is reasonable
- [ ] Success status is correct

---

**Version:** 1.0.0  
**Last Updated:** 2024-04-13  
**Status:** Production Ready ✓

For latest updates, visit the HELIOS Platform repository at:
https://github.com/M0nado/helios-platform
