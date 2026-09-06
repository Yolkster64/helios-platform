# PHASE-1-AppLocker

## Quick Summary

Windows AppLocker implementation for application whitelisting. Provides policy management, rule creation, and enforcement monitoring. Core security control for Phase 1.

## Key Facts

- **Owner**: TBD
- **Status**: Planned
- **Version**: 0.1.0-dev
- **Phase**: 1 (Security)
- **Team Size**: 2 developers
- **Timeline**: Weeks 5-7
- **Dependencies**: PHASE-0-System-Setup v1.0+
- **Depends On Us**: PHASE-1-Quarantine (uses our policies)

## What It Does

Implements application whitelisting through AppLocker:

1. **Policy Management**
   - Create AppLocker policies
   - Define allowed/blocked applications
   - Support hash, path, and publisher rules
   - Manage policy inheritance

2. **Rule Creation & Management**
   - Add/remove AppLocker rules
   - Bulk rule import/export
   - Rule validation and testing
   - Rule performance tuning

3. **Enforcement & Monitoring**
   - Enable AppLocker in audit/enforce mode
   - Monitor policy violations
   - Log blocked applications
   - Generate compliance reports

4. **Integration with HELIOS**
   - Store policies in Vault (encrypted)
   - Report violations to Quarantine
   - Push status to Dashboard

## API Reference

### Public Functions

#### Enable-AppLocker

```
Enable-AppLocker -RuleSet <string> -Mode <string> [-Backup]
```

Enables AppLocker on the system.

**Parameters**:

- RuleSet: "Developer" | "Standard" | "Strict"
- Mode: "Audit" | "Enforce"
- Backup: Save current policy before enabling

**Returns**: Object with Status, RulesLoaded, Mode

**Example**:

```powershell
Enable-AppLocker -RuleSet "Standard" -Mode "Audit" -Backup
```

#### New-AppLockerRule

```
New-AppLockerRule -Name <string> -Path <string> -RuleType <string> [-Action <string>]
```

Creates a new AppLocker rule.

**Parameters**:

- Name: Descriptive rule name
- Path: File path pattern (e.g., "C:\Program Files\*")
- RuleType: "Executable" | "DLL" | "Script" | "Installer"
- Action: "Allow" | "Deny" (default: "Allow")

**Returns**: Rule object with Id, Name, Path, RuleType

**Example**:

```powershell
New-AppLockerRule -Name "Allow Office" -Path "C:\Program Files\Microsoft Office\*" -RuleType "Executable"
```

#### Get-AppLockerStatus

```
Get-AppLockerStatus [-Detailed]
```

Gets current AppLocker status.

**Returns**: Object with Enabled, Mode, RulesLoaded, ViolationCount

**Example**:

```powershell
Get-AppLockerStatus -Detailed | Format-Table
```

#### Invoke-AppLockerValidation

```
Invoke-AppLockerValidation -RuleSet <string>
```

Validates AppLocker ruleset for conflicts/issues.

**Returns**: Object with Valid, Issues, Warnings

**Example**:

```powershell
Invoke-AppLockerValidation -RuleSet "Standard"
```

### Integration Points

- **Depends On**: PHASE-0-System-Setup (hardened baseline)
- **Shares Data With**: PHASE-1-Credential-Vault (stores policies)
- **Sends Events To**: PHASE-1-Quarantine (policy violations)
- **Reports To**: PHASE-3-Control-Dashboard (status/metrics)

## Status & Metrics

| Metric | Value |
|---|---|
| Overall Progress | 0% (Planned) |
| Code Complete | 0% |
| Tests Written | 0% |
| Tests Passing | 0/0 |
| Code Quality | — |
| Test Coverage | — |
| Blockers | None |

## Known Issues

None yet (planning phase).

## Getting Help

### Common Questions

**Q: What's the difference between Audit and Enforce mode?**
A: Audit logs violations but doesn't block. Enforce blocks apps not in whitelist. Start in Audit.

**Q: Can I use AppLocker on Home editions?**
A: No, AppLocker requires Windows Pro or Enterprise.

**Q: How do I exclude built-in Windows apps?**
A: Standard rulesets include built-in app rules. Create custom rules as needed.

### Documentation

- **PLAIN_ENGLISH_GUIDE.md** - Simple usage guide
- **FILE_ARCHITECTURE.md** - Code organization
- **SCRIPTS_INDEX.md** - Complete function reference
- **TESTING_GUIDE.md** - How to test
- **docs/** - Extended documentation

## Development Roadmap

### Week 5: Design & Framework

- [ ] Design AppLocker policy format
- [ ] Design API contracts
- [ ] Define integration points
- [ ] Create test framework

### Week 6: Core Implementation

- [ ] Implement Enable-AppLocker
- [ ] Implement New-AppLockerRule
- [ ] Implement Get-AppLockerStatus
- [ ] Write unit tests

### Week 7: Testing & Integration

- [ ] Complete Invoke-AppLockerValidation
- [ ] Write integration tests
- [ ] Test with Vault integration
- [ ] Prepare for Phase 1 integration

## Integration Checklist

Before declaring this module done:

- [ ] All unit tests passing (80%+ coverage)
- [ ] Integration with PHASE-0-System-Setup verified
- [ ] Policies stored in PHASE-1-Vault
- [ ] Events sent to PHASE-1-Quarantine
- [ ] Status reported to PHASE-3-Dashboard
- [ ] Documentation complete
- [ ] v1.0.0-rc.1 released

## Contact & Support

- **Owner**: [Owner Name] (owner@example.com)
- **Team Lead**: [Lead Name] (lead@example.com)
- **Slack**: #helios-phase-1-security
- **Issues**: GitHub Issues / #helios-blockers

## Links

- [SUBMODULE_TEMPLATE.md](../../SUBMODULE_TEMPLATE.md) - How to structure code
- [CONTRIBUTION_GUIDE.md](../../CONTRIBUTION_GUIDE.md) - How to contribute
- [DEVELOPMENT_ROADMAP.md](../../DEVELOPMENT_ROADMAP.md) - Phase timeline
- [INTEGRATION_CHECKPOINTS.md](../../INTEGRATION_CHECKPOINTS.md) - Phase 1 integration tests

---

**Submodule Version**: 0.1.0-dev  
**Last Updated**: 2024-01-08  
**Maintained By**: Security Team
