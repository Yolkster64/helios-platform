# {{PROJECT_NAME}} - Modules Reference

**Template Version:** 1.0  
**Total Modules:** {{MODULE_COUNT}}  
**Last Updated:** {{LAST_UPDATED}}

---

## 📚 Module Overview

{{PROJECT_NAME}} is organized into {{MODULE_COUNT}} core modules, each serving a specific purpose in the system architecture.

---

## 🏗️ Module Structure

### Module Levels

```
{{PROJECT_NAME}}
├── Level 1: Core Modules ({{CORE_MODULE_COUNT}})
├── Level 2: Feature Modules ({{FEATURE_MODULE_COUNT}})
├── Level 3: Utility Modules ({{UTIL_MODULE_COUNT}})
└── Level 4: Support Modules ({{SUPPORT_MODULE_COUNT}})
```

---

## 📦 Core Modules ({{CORE_MODULE_COUNT}} modules)

### {{CORE_MODULE_1}}

**Path:** `./{{CATEGORY_1}}/{{CORE_MODULE_1}}/`  
**Purpose:** {{CORE_MODULE_1_PURPOSE}}  
**Status:** {{CORE_MODULE_1_STATUS}}  
**Version:** {{CORE_MODULE_1_VERSION}}

**Key Features:**

- {{FEATURE_1}}: {{FEATURE_1_DESC}}
- {{FEATURE_2}}: {{FEATURE_2_DESC}}
- {{FEATURE_3}}: {{FEATURE_3_DESC}}

**Main Functions:**

- `{{FUNCTION_1}}`: {{FUNCTION_1_DESC}}
- `{{FUNCTION_2}}`: {{FUNCTION_2_DESC}}
- `{{FUNCTION_3}}`: {{FUNCTION_3_DESC}}

**Dependencies:**

- {{DEP_1}} ({{DEP_1_VERSION}})
- {{DEP_2}} ({{DEP_2_VERSION}})

**Usage Example:**

```powershell
# {{USAGE_EXAMPLE_1}}
{{CODE_EXAMPLE_1}}

# {{USAGE_EXAMPLE_2}}
{{CODE_EXAMPLE_2}}
```

**Documentation:**

- [README](./{{CATEGORY_1}}/{{CORE_MODULE_1}}/README.md)
- [API Reference](./{{CATEGORY_1}}/{{CORE_MODULE_1}}/API.md)
- [Examples](./{{CATEGORY_1}}/{{CORE_MODULE_1}}/EXAMPLES.md)
- [Troubleshooting](./{{CATEGORY_1}}/{{CORE_MODULE_1}}/TROUBLESHOOTING.md)

---

### {{CORE_MODULE_2}}

**Path:** `./{{CATEGORY_2}}/{{CORE_MODULE_2}}/`  
**Purpose:** {{CORE_MODULE_2_PURPOSE}}  
**Status:** {{CORE_MODULE_2_STATUS}}

**Key Functions:**

- `{{CORE_M2_FUNCTION_1}}`
- `{{CORE_M2_FUNCTION_2}}`
- `{{CORE_M2_FUNCTION_3}}`

**Example:**

```powershell
{{CORE_M2_CODE_EXAMPLE}}
```

**Learn More:** [Module Documentation](./{{CATEGORY_2}}/{{CORE_MODULE_2}}/README.md)

---

### {{CORE_MODULE_3}}

**Path:** `./{{CATEGORY_3}}/{{CORE_MODULE_3}}/`  
**Purpose:** {{CORE_MODULE_3_PURPOSE}}  
**Status:** {{CORE_MODULE_3_STATUS}}

**Learn More:** [Module Documentation](./{{CATEGORY_3}}/{{CORE_MODULE_3}}/README.md)

---

## 🎯 Feature Modules ({{FEATURE_MODULE_COUNT}} modules)

### {{FEATURE_MODULE_1}}

**Path:** `./{{FEATURE_CAT_1}}/{{FEATURE_MODULE_1}}/`  
**Purpose:** {{FEATURE_MODULE_1_PURPOSE}}  
**Related To:** {{FEATURE_MODULE_1_RELATED}}

**Main Functions:**

- `{{FM1_FUNC_1}}()`
- `{{FM1_FUNC_2}}()`

**Learn More:** [Module Documentation](./{{FEATURE_CAT_1}}/{{FEATURE_MODULE_1}}/README.md)

---

### {{FEATURE_MODULE_2}}

**Path:** `./{{FEATURE_CAT_2}}/{{FEATURE_MODULE_2}}/`  
**Purpose:** {{FEATURE_MODULE_2_PURPOSE}}

**Learn More:** [Module Documentation](./{{FEATURE_CAT_2}}/{{FEATURE_MODULE_2}}/README.md)

---

## 🛠️ Utility Modules ({{UTIL_MODULE_COUNT}} modules)

### {{UTIL_MODULE_1}}

**Path:** `./{{UTIL_CAT_1}}/{{UTIL_MODULE_1}}/`  
**Purpose:** {{UTIL_MODULE_1_PURPOSE}}  
**Category:** Utility/Helper

**Functions:**

- `{{UM1_FUNC_1}}`
- `{{UM1_FUNC_2}}`

---

### {{UTIL_MODULE_2}}

**Path:** `./{{UTIL_CAT_2}}/{{UTIL_MODULE_2}}/`  
**Purpose:** {{UTIL_MODULE_2_PURPOSE}}

---

## 🔧 Support Modules ({{SUPPORT_MODULE_COUNT}} modules)

### {{SUPPORT_MODULE_1}}

**Path:** `./{{SUPPORT_CAT_1}}/{{SUPPORT_MODULE_1}}/`  
**Purpose:** {{SUPPORT_MODULE_1_PURPOSE}}  
**Status:** {{SUPPORT_MODULE_1_STATUS}}

---

## 📊 Module Dependency Graph

### Core Dependencies

```
{{CORE_MODULE_1}}
    ├── {{DEP_M1_1}}
    └── {{DEP_M1_2}}

{{CORE_MODULE_2}}
    ├── {{CORE_MODULE_1}} ← dependency
    ├── {{DEP_M2_1}}
    └── {{DEP_M2_2}}

{{CORE_MODULE_3}}
    ├── {{CORE_MODULE_2}}
    └── {{DEP_M3_1}}
```

### Module Interaction Matrix

| From | To | Type | Purpose |
|------|----|----|---------|
| {{MODULE_A}} | {{MODULE_B}} | Function Call | {{PURPOSE_AB}} |
| {{MODULE_B}} | {{MODULE_C}} | Event | {{PURPOSE_BC}} |
| {{MODULE_C}} | {{MODULE_A}} | Callback | {{PURPOSE_CA}} |

---

## 🔌 Module Interfaces

### {{CORE_MODULE_1}} Interface

**Exports:**

```powershell
# Functions
{{EXPORT_FUNC_1}}
{{EXPORT_FUNC_2}}

# Events
{{EXPORT_EVENT_1}}
{{EXPORT_EVENT_2}}

# Constants
${{CONSTANT_1}} = {{VALUE_1}}
${{CONSTANT_2}} = {{VALUE_2}}
```

**Imports:**

```powershell
# Required from {{DEP_1}}
[{{DEP_1_TYPE}}]${{DEP_1_VAR}}

# Required from {{DEP_2}}
[{{DEP_2_TYPE}}]${{DEP_2_VAR}}
```

---

## 🚀 Module Initialization

### Initialization Order

1. **Phase 1: Core Setup**
   - {{CORE_MODULE_1}}: Initialize base functionality
   - {{UTIL_MODULE_1}}: Setup utilities
   - {{UTIL_MODULE_2}}: Setup helpers

2. **Phase 2: Feature Setup**
   - {{FEATURE_MODULE_1}}: Initialize features
   - {{FEATURE_MODULE_2}}: Configure options
   - {{FEATURE_MODULE_3}}: Setup handlers

3. **Phase 3: Runtime Setup**
   - {{SUPPORT_MODULE_1}}: Start monitoring
   - {{SUPPORT_MODULE_2}}: Start cleanup

### Initialization Code Example

```powershell
# Load modules in order
{{INIT_STEP_1}}
{{INIT_STEP_2}}
{{INIT_STEP_3}}

# Verify initialization
{{INIT_VERIFY}}
```

---

## 🔄 Module Lifecycle

### Loading

```powershell
# Import module
Import-Module {{MODULE_NAME}}

# Verify loaded
Get-Module {{MODULE_NAME}}
```

### Configuration

```powershell
# Configure module
Set-{{MODULE_NAME}}Config @{
    {{CONFIG_KEY_1}} = {{CONFIG_VALUE_1}}
    {{CONFIG_KEY_2}} = {{CONFIG_VALUE_2}}
}
```

### Unloading

```powershell
# Cleanup
Remove-{{MODULE_NAME}}
# or
Remove-Module {{MODULE_NAME}}
```

---

## 📈 Module Capabilities Matrix

| Module | Read | Write | Delete | Query | Transform | Validate |
|--------|------|-------|--------|-------|-----------|----------|
| {{MOD_1}} | ✓ | ✓ | - | ✓ | ✓ | ✓ |
| {{MOD_2}} | ✓ | ✓ | ✓ | ✓ | - | ✓ |
| {{MOD_3}} | ✓ | - | - | ✓ | ✓ | - |
| {{MOD_4}} | - | ✓ | ✓ | - | - | ✓ |

---

## 🧪 Module Testing

### Test Coverage

| Module | Unit | Integration | E2E | Coverage |
|--------|------|-------------|-----|----------|
| {{MODULE_1}} | ✓ | ✓ | ✓ | {{COV_1}}% |
| {{MODULE_2}} | ✓ | ✓ | - | {{COV_2}}% |
| {{MODULE_3}} | ✓ | - | - | {{COV_3}}% |

### Running Module Tests

```powershell
# Test specific module
Invoke-Pester ./{{CATEGORY}}/{{MODULE}}/Tests/

# Test all modules
Invoke-Pester ./Tests/ -Recurse

# Test with coverage
Invoke-Pester ./Tests/ -CodeCoverage ./{{MODULE}}/*.ps1
```

---

## 📦 Module Versioning

### Version Strategy

- **Format:** MAJOR.MINOR.PATCH
- **Breaking Changes:** New MAJOR version
- **New Features:** New MINOR version
- **Bug Fixes:** New PATCH version

### Version Compatibility

| Module | Current | Min Supported | Status |
|--------|---------|--------------|--------|
| {{MODULE_1}} | {{VERSION_1}} | {{MIN_VERSION_1}} | {{STATUS_1}} |
| {{MODULE_2}} | {{VERSION_2}} | {{MIN_VERSION_2}} | {{STATUS_2}} |
| {{MODULE_3}} | {{VERSION_3}} | {{MIN_VERSION_3}} | {{STATUS_3}} |

---

## 🔍 Module Discovery

### Finding Modules

```powershell
# List all loaded modules
Get-Module

# Search for specific module
Get-Module -Name "{{MODULE_PATTERN}}"

# Get module details
Get-Module {{MODULE_NAME}} | Select-Object *

# Get module commands
Get-Command -Module {{MODULE_NAME}}
```

### Module Information

```powershell
# Get module path
(Get-Module {{MODULE_NAME}}).Path

# Get exported functions
Get-Command -Module {{MODULE_NAME}} -Type Function

# Get module version
(Get-Module {{MODULE_NAME}}).Version
```

---

## 🚨 Module Troubleshooting

### Common Module Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| {{ISSUE_1}} | {{CAUSE_1}} | {{SOLUTION_1}} |
| {{ISSUE_2}} | {{CAUSE_2}} | {{SOLUTION_2}} |
| {{ISSUE_3}} | {{CAUSE_3}} | {{SOLUTION_3}} |

### Module Loading Errors

```powershell
# Error: Module not found
# Solution: Ensure module path is in PSModulePath
$env:PSModulePath

# Error: Version mismatch
# Solution: Check module version requirements
Get-Module {{MODULE_NAME}} | Select-Object Version
```

---

## 📚 Module Documentation Index

### Core Module Documentation

| Module | README | API | Examples | Tests |
|--------|--------|-----|----------|-------|
| {{MODULE_1}} | [Link](./{{CATEGORY_1}}/{{MODULE_1}}/README.md) | [Link](./{{CATEGORY_1}}/{{MODULE_1}}/API.md) | [Link](./{{CATEGORY_1}}/{{MODULE_1}}/EXAMPLES.md) | {{TEST_COUNT}} |
| {{MODULE_2}} | [Link](./{{CATEGORY_2}}/{{MODULE_2}}/README.md) | [Link](./{{CATEGORY_2}}/{{MODULE_2}}/API.md) | [Link](./{{CATEGORY_2}}/{{MODULE_2}}/EXAMPLES.md) | {{TEST_COUNT}} |

---

## 🔗 Related Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - System architecture
- [API.md](./API.md) - API reference
- [README.md](./README.md) - Project overview

---

**Generated from template version 1.0 on {{GENERATION_DATE}}**
