# HELIOS Phase 1: Security Hardening & Protection

## Overview

HELIOS Phase 1 is the **foundational security layer** that locks down your Windows system against threats, unauthorized access, and malicious software. This phase transforms an open Windows installation into a hardened fortress by implementing multiple layers of protection.

## What Gets Locked Down

| Component | What Happens | Result |
|-----------|-------------|--------|
| **Program Execution** | AppLocker blocks all programs except whitelisted ones | Only trusted software runs |
| **Network Traffic** | Firewall rules block unauthorized connections | Malware can't phone home |
| **Sensitive Data** | Vault encryption protects passwords and keys | Data stays private even if disk is stolen |
| **Threat Isolation** | Quarantine system isolates suspicious files | Threats can't spread |
| **User Accounts** | Account privileges strictly managed | Limited damage from compromised accounts |
| **Threat Detection** | Windows Defender + Malwarebytes actively scan | Real-time protection against known threats |

## Prerequisites

Before starting Phase 1, ensure you have:

- **Windows 10 or Windows 11** (64-bit recommended)
- **Administrator Access** - You need full admin rights
- **Backup of Important Data** - In case something needs to be rolled back
- **List of Trusted Applications** - Know what programs you actually use
- **Internet Connection** - For downloading updates and threat definitions
- **2-4 Hours of Time** - Phase 1 is thorough and can't be rushed
- **System Restart Permission** - Several components require restart

## Time Estimate

| Activity | Time | Notes |
|----------|------|-------|
| Review & Planning | 30 min | Understand what will be changed |
| AppLocker Configuration | 45 min | Define whitelisted applications |
| Firewall Hardening | 30 min | Apply inbound/outbound rules |
| Vault Encryption Setup | 20 min | Secure data storage |
| Quarantine System Init | 15 min | Prepare isolated threat storage |
| User Account Setup | 30 min | Create restricted account tiers |
| Threat Detection Config | 20 min | Enable and update scanners |
| Testing & Verification | 45 min | Confirm everything works |
| **Total (First Run)** | **3.5 hours** | Includes all setup and testing |
| **Total (Maintenance)** | **30 min/week** | Updates, threat scanning |

## What Changes

### Visible Changes

- New **Admin**, **Standard**, **Restricted** user account tiers
- Programs won't launch unless explicitly allowed (AppLocker approval)
- Some network tools blocked (by firewall)
- Quarantine folder appears at `C:\Vault\Quarantine`

### Invisible Changes

- Windows Registry hardening (HKLM:\System\CurrentControlSet\Services)
- Firewall rules (Windows Defender Firewall with Advanced Security)
- Vault encryption settings (BitLocker-compatible)
- Event logs tracking all blocked activities
- Defender + Malwarebytes scheduled scans

### Performance Impact

- **Startup**: +30-60 seconds (additional security checks)
- **Program Launch**: +2-5 seconds first run (AppLocker validation)
- **Disk Access**: Minimal (< 5% overhead)
- **Network**: None (firewall is kernel-level)

## The Security Layers (Defense in Depth)

```
┌─────────────────────────────────────────────────┐
│         Layer 1: Program Execution              │
│    (AppLocker - only whitelisted apps run)      │
├─────────────────────────────────────────────────┤
│          Layer 2: Network Security              │
│   (Firewall - blocks unauthorized traffic)      │
├─────────────────────────────────────────────────┤
│      Layer 3: Data Protection                   │
│   (Vault Encryption - secures sensitive data)   │
├─────────────────────────────────────────────────┤
│       Layer 4: Threat Isolation                 │
│  (Quarantine - stops malware from spreading)    │
├─────────────────────────────────────────────────┤
│      Layer 5: Account Security                  │
│   (User tiers - limits damage from breakins)    │
├─────────────────────────────────────────────────┤
│      Layer 6: Active Detection                  │
│  (Defender + Malwarebytes - finds threats)      │
└─────────────────────────────────────────────────┘
```

## Quick Start

1. **Read** `PLAIN_ENGLISH_GUIDE.md` - Understand each component
2. **Review** `BEFORE_AND_AFTER.md` - See what will change
3. **Check** `SCRIPTS_INDEX.md` - See all scripts available
4. **Run** scripts from Phase 1 in recommended order
5. **Verify** using `TESTING_GUIDE.md` - Confirm everything works

## Key Files

| File | Purpose |
|------|---------|
| `README.md` | This file - overview and getting started |
| `PLAIN_ENGLISH_GUIDE.md` | How-to guide for each security component |
| `FILE_ARCHITECTURE.md` | Where all security files go |
| `BEFORE_AND_AFTER.md` | What the system looks like before/after |
| `SCRIPTS_INDEX.md` | Complete list of Phase 1 scripts |
| `TESTING_GUIDE.md` | How to verify everything works |

## Warning Signs That Phase 1 Was Needed

If your system has ANY of these, Phase 1 is urgent:

- Programs launching without your permission
- Network connections to unknown IP addresses
- Slowdowns or resource hogging
- New toolbars or browser extensions you didn't install
- Files appearing in unexpected folders
- Antivirus warnings or frequent crashes
- Ransom messages or file encryption

## Support & Rollback

If something breaks:

1. **Check** `TESTING_GUIDE.md` for known issues
2. **Review** individual script "How To Undo" sections
3. **Contact** HELIOS Support if you need manual recovery
4. **Restore** from backup if needed

## Next Steps

After Phase 1 completes successfully, you're ready for:

- **Phase 2 (Compliance)** - Meet regulatory standards
- **Phase 3 (Monitoring)** - Real-time threat surveillance
- **Phase 4 (Incident Response)** - Automated threat response

## Status

| Phase | Status | Details |
|-------|--------|---------|
| Phase 1 | **CURRENT** | You are here |
| Phase 2 | Planned | After security baseline |
| Phase 3 | Planned | After compliance |
| Phase 4 | Planned | After monitoring |

---

**Last Updated**: April 12, 2026  
**Version**: 1.0  
**Maintained By**: HELIOS Platform Team
