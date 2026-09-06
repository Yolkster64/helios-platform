# HELIOS Phase 0 - Quick Reference Card

**Print this page for quick access while working**

---

## Phase 0 At A Glance

| Item | Value |
|------|-------|
| **Purpose** | USB installer & fresh Windows 11 install |
| **Time** | 45-75 minutes total |
| **Scripts** | 5 PowerShell scripts |
| **Files Created** | ~30 main folders + registry changes |
| **Drive Changes** | C: (system) + D: (data) partitions |
| **Prerequisites** | 16GB USB + Windows 11 ISO |

---

## 5 Scripts In Order

```
1. usb-creator.ps1           → Create bootable USB
2. windows-installer.ps1     → Install Windows on computer
3. partition-manager.ps1     → Setup C: and D: drives
4. storage-setup.ps1         → Create folder structure
5. system-baseline.ps1       → Configure system baseline
```

---

## Running Scripts

```powershell
# All scripts run from:
cd C:\HELIOS\phases\0-foundation\scripts

# Run each script:
.\usb-creator.ps1
.\partition-manager.ps1
.\storage-setup.ps1
.\system-baseline.ps1

# Always run as Administrator!
```

---

## Key Locations

| Path | Purpose |
|------|---------|
| `C:\HELIOS\` | HELIOS installation root |
| `C:\Program Files\` | Applications |
| `C:\Windows\` | Operating system |
| `D:\Users\` | Personal files |
| `D:\Backups\` | System backups |
| `D:\Projects\` | Work projects |

---

## Quick Troubleshooting

| Problem | Fix |
|---------|-----|
| "Access Denied" | Run PowerShell as Administrator |
| USB won't boot | Try different USB port, check boot order |
| Windows install fails | Try different USB drive |
| Scripts won't run | Check path, run as admin |
| D: drive missing | Run partition-manager.ps1 |
| Folders missing | Run storage-setup.ps1 |

---

## Testing After Phase 0

```powershell
# Quick 2-minute check:

# 1. Check Windows version
wmic os get caption | findstr "11"

# 2. Check drives exist
Get-Volume | Select-Object DriveLetter

# 3. Check HELIOS folder
Test-Path "C:\HELIOS\"

# 4. Check Users folder
Test-Path "D:\Users\"

# All should return TRUE/Yes
```

---

## Important Warnings

⚠️ **These actions DELETE data permanently:**

- USB Creator erases entire USB drive
- Partition Manager reshuffles drives
- Windows Installation erases system drive

✓ **Back up all data first!**

---

## Reading Guide

**5 minutes?** → README.md  
**20 minutes?** → PLAIN_ENGLISH_GUIDE.md  
**30 minutes?** → README + PLAIN_ENGLISH_GUIDE + DOCS_INDEX  
**1 hour?** → Read all documentation  

---

## Phase 0 Checklist

```
Preparation:
☐ Back up data
☐ Read README.md
☐ Download Windows 11 ISO
☐ Have 16GB USB ready

Execution:
☐ Run usb-creator.ps1
☐ Boot from USB
☐ Run Windows installer
☐ Run partition-manager.ps1
☐ Run storage-setup.ps1
☐ Run system-baseline.ps1

Verification:
☐ Windows 11 installed
☐ C: and D: drives exist
☐ Folders in HELIOS structure
☐ No critical errors in logs

Ready:
☐ Phase 0 complete ✓
☐ Ready for Phase 1 ✓
```

---

## File Locations Quick Map

```
System Drive (C:)
├── C:\HELIOS\
│   ├── phases\
│   ├── tools\
│   ├── config\
│   └── logs\
├── C:\Program Files\
└── C:\Windows\

Data Drive (D:)
├── D:\Users\ADMIN\
│   ├── Documents\
│   ├── Downloads\
│   └── Pictures\
├── D:\Backups\
├── D:\Projects\
└── D:\Archive\
```

---

## Undo Quick Reference

| Script | How To Undo |
|--------|------------|
| USB Creator | Don't boot from USB, format normally |
| Windows Install | Reinstall Windows from scratch |
| Partition Manager | Run again with different sizes |
| Storage Setup | Delete folders or reformat |
| System Baseline | Use System Restore point |

---

## Emergency Contacts

**Phase 0 Won't Start?**
→ Check README.md Prerequisites section

**Scripts Failing?**
→ Check C:\HELIOS\logs\phase0\ for error messages

**Verification Failed?**
→ Use TESTING_GUIDE.md troubleshooting section

**Need Details?**
→ PLAIN_ENGLISH_GUIDE.md explains each step

---

## Performance Notes

**SSD (Fastest)**

- USB creation: 10-15 min
- Windows install: 20-25 min
- Total: ~45-55 min

**HDD (Slower)**

- USB creation: 15-20 min
- Windows install: 30-35 min
- Total: ~65-85 min

**Tips to Speed Up:**

- Use USB 3.0 port (not 2.0)
- Install on SSD (not HDD)
- Use newer USB drive
- Close other programs

---

## Documentation Files

```
README.md                    5 min read
├─ DOCS_INDEX.md             2 min read
├─ PLAIN_ENGLISH_GUIDE.md   20 min read
├─ FILE_ARCHITECTURE.md     10 min read
├─ SCRIPTS_INDEX.md         15 min read
└─ TESTING_GUIDE.md         10 min read
   + 15 min to run tests
```

---

## Key Phone Numbers to Remember

Nothing! All documentation is local. No internet required.

✓ All files: C:\HELIOS\phases\0-foundation\  
✓ All scripts: C:\HELIOS\phases\0-foundation\scripts\  
✓ All logs: C:\HELIOS\logs\phase0\  

---

## After Phase 0 Complete

Phase 0 ✓  
↓  
Ready for Phase 1: Customization  
↓  
Then Phase 2: Hardening  
↓  
Then Phase 3: Security  
↓  
Then Phase 4: Optimization  

---

**Print & Keep This Page Handy!**

Last section before you start Phase 0.
