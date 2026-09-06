# HELIOS Platform v2 - Testing Infrastructure

## Overview

This directory contains the comprehensive testing and code checking infrastructure for HELIOS Platform v2. The testing strategy covers multiple layers: unit tests, integration tests, system tests, performance validation, and automated code quality checks.

## Testing Strategy

### Pyramid Architecture

```
      ┌─────────────────┐
      │  System Tests   │  Full end-to-end validation
      │   (Slow, Few)   │
      ├─────────────────┤
      │Integration Tests│  Phase interactions & data flow
      │  (Medium, Some) │
      ├─────────────────┤
      │  Unit Tests     │  Individual components
      │ (Fast, Many)    │
      └─────────────────┘
```

### Testing Layers

| Layer | Purpose | Speed | Coverage | Examples |
|-------|---------|-------|----------|----------|
| **Unit Tests** | Validate individual functions/scripts | <1s each | Syntax, logic, edge cases | PowerShell function tests |
| **Integration Tests** | Validate phase interactions | 1-10s each | Phase transitions, data flow | Phase 0→1 registry changes |
| **System Tests** | Full platform validation | 10-60s each | End-to-end functionality | Boot time, app launch, security |
| **Code Checks** | Automated quality gates | <5s each | Security, syntax, standards | No hardcoded passwords, lint |

## Directory Structure

```
tests/
├── README.md                          # This file
├── CODE_CHECKING_POLICY.md            # Automated checks that run on every commit
├── UNIT_TESTS_GUIDE.md                # How to write and run unit tests
├── INTEGRATION_TESTS_GUIDE.md         # Phase interaction validation
├── SYSTEM_TESTS_GUIDE.md              # Full system validation
├── PERFORMANCE_METRICS.md             # Performance testing framework
├── ROLLBACK_TESTING.md                # Rollback procedure validation
├── BEFORE_AFTER_CAPTURE.md            # System state capture procedures
├── TEST_TEMPLATES.md                  # Ready-to-use test templates
├── TROUBLESHOOTING_TESTS.md           # Diagnostic tests
└── .github/
    └── workflows/
        └── code-checks.yml            # GitHub Actions CI/CD workflow
```

## Quick Start

### Running All Tests

```powershell
# Run all test suites
.\Run-AllTests.ps1

# Run specific test type
.\Run-UnitTests.ps1
.\Run-IntegrationTests.ps1
.\Run-SystemTests.ps1
```

### Before Deployment Checklist

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] System tests pass on clean VM
- [ ] Code checks pass (no security issues)
- [ ] Performance baseline established
- [ ] Before-state snapshot captured
- [ ] Rollback procedure tested

## Testing Workflow

### During Development

1. **Write code** → Phase script (e.g., `Phase-0-Optimize.ps1`)
2. **Write unit tests** → `test-phase-0-unit.ps1`
3. **Run unit tests locally** → Verify logic is correct
4. **Commit to feature branch** → GitHub Actions runs code checks
5. **Fix any check failures** → Retry tests

### Before Phase Release

1. **Run integration tests** → Verify interaction with previous phases
2. **Capture before-state** → Save baseline for rollback
3. **Run system tests** → Full validation on clean environment
4. **Measure performance** → Establish metrics
5. **Test rollback** → Ensure recovery procedures work

### On Production Deployment

1. **Pre-flight checks** → Verify system readiness
2. **Execute phase** → Run phase script
3. **Post-execution validation** → Verify success
4. **Monitor performance** → Track metrics vs. baseline
5. **Document outcome** → Record results for audit

## Code Quality Gates

Every commit triggers automated checks:

✓ **Syntax Validation** - PowerShell syntax is correct
✓ **Security Scanning** - No hardcoded passwords, suspicious code
✓ **Registry Validation** - Registry modifications are documented
✓ **File Path Validation** - All paths are valid
✓ **Documentation** - Required documentation is present
✓ **Test Coverage** - Sufficient test coverage exists

## Key Principles

1. **Automation First** - All checks run automatically, fail fast
2. **Independent Testing** - Any phase can be tested alone
3. **State Capture** - Always capture before/after state
4. **Rollback Ready** - Every change has a documented rollback
5. **Measurable** - All tests produce quantifiable results
6. **Repeatable** - Tests produce same results each run
7. **Fast Feedback** - Unit tests run in seconds, system tests in minutes

## Test Execution Order

```
Fast Checks (Every Commit)
  ↓
Unit Tests (Per Phase)
  ↓
Integration Tests (Phase Chains)
  ↓
System Tests (Full Platform)
  ↓
Performance Tests (Baseline Established)
  ↓
Rollback Tests (Recovery Verified)
```

## Common Tasks

### Add a new unit test

See `UNIT_TESTS_GUIDE.md` for template and examples

### Test a phase integration

See `INTEGRATION_TESTS_GUIDE.md` for phase interaction validation

### Establish performance baseline

See `PERFORMANCE_METRICS.md` for measurement procedures

### Create rollback snapshot

See `BEFORE_AFTER_CAPTURE.md` and `ROLLBACK_TESTING.md`

### Debug test failures

See `TROUBLESHOOTING_TESTS.md` for diagnostic procedures

## Success Criteria

A phase is ready for deployment when:

- ✅ All unit tests pass with 80%+ coverage
- ✅ All integration tests pass
- ✅ System tests pass (boot, app launch, security)
- ✅ No code check violations
- ✅ Performance metrics documented
- ✅ Rollback procedure tested and working
- ✅ Before/after state captured and validated

## Continuous Improvement

Test coverage and procedures are continuously refined based on:

- Phase execution results
- Performance measurements
- User feedback
- Security findings
- Rollback requests

## Support & Documentation

| Document | Purpose |
|----------|---------|
| `CODE_CHECKING_POLICY.md` | What automated checks run and why |
| `UNIT_TESTS_GUIDE.md` | Writing testable code and unit tests |
| `INTEGRATION_TESTS_GUIDE.md` | Testing phase interactions |
| `SYSTEM_TESTS_GUIDE.md` | Full platform validation |
| `PERFORMANCE_METRICS.md` | Measuring system performance |
| `ROLLBACK_TESTING.md` | Testing recovery procedures |
| `BEFORE_AFTER_CAPTURE.md` | Capturing system state snapshots |
| `TEST_TEMPLATES.md` | Copy-paste test templates |
| `TROUBLESHOOTING_TESTS.md` | Diagnosing test failures |

---

**Version:** 2.0  
**Last Updated:** 2024  
**Maintained By:** HELIOS Development Team
