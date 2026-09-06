# {{BUILD_NAME}} - Manifest & Contents

**Template Version:** 1.0  
**Build Version:** {{BUILD_VERSION}}  
**Generated:** {{GENERATION_DATE}}

---

## 📋 Complete File Manifest

### Directory Structure

```
{{BUILD_NAME}}/
├── bin/
│   ├── {{SCRIPT_1}}.ps1
│   ├── {{SCRIPT_2}}.ps1
│   └── {{SCRIPT_3}}.ps1
├── lib/
│   ├── {{MODULE_1}}/
│   ├── {{MODULE_2}}/
│   └── {{MODULE_3}}/
├── config/
│   ├── config.default.json
│   ├── config.prod.json
│   └── config.dev.json
├── docs/
│   ├── README.md
│   ├── USAGE.md
│   └── EXAMPLES.md
├── tests/
│   ├── unit/
│   └── integration/
├── examples/
│   ├── example1.ps1
│   └── example2.ps1
└── {{OTHER_DIRS}}/
```

---

## 📦 Included Files

### Scripts & Executables

| File | Size | Purpose |
|------|------|---------|
| {{SCRIPT_1}}.ps1 | {{SIZE_1}} | {{PURPOSE_1}} |
| {{SCRIPT_2}}.ps1 | {{SIZE_2}} | {{PURPOSE_2}} |
| {{SCRIPT_3}}.ps1 | {{SIZE_3}} | {{PURPOSE_3}} |

**Total Scripts:** {{TOTAL_SCRIPTS}}  
**Total Size:** {{SCRIPTS_SIZE}}

### Modules & Libraries

| Module | Size | Functions |
|--------|------|-----------|
| {{MODULE_1}} | {{MOD_SIZE_1}} | {{FUNC_COUNT_1}} |
| {{MODULE_2}} | {{MOD_SIZE_2}} | {{FUNC_COUNT_2}} |
| {{MODULE_3}} | {{MOD_SIZE_3}} | {{FUNC_COUNT_3}} |

**Total Modules:** {{TOTAL_MODULES}}  
**Total Size:** {{MODULES_SIZE}}

### Configuration Files

| File | Purpose | Editable |
|------|---------|----------|
| {{CONFIG_1}} | {{CONFIG_PURPOSE_1}} | {{EDITABLE_1}} |
| {{CONFIG_2}} | {{CONFIG_PURPOSE_2}} | {{EDITABLE_2}} |

### Documentation

| File | Lines | Subject |
|------|-------|---------|
| README.md | {{README_LINES}} | Build overview |
| USAGE.md | {{USAGE_LINES}} | Usage guide |
| EXAMPLES.md | {{EXAMPLES_LINES}} | Code examples |

**Total Docs:** {{TOTAL_DOCS}} files  
**Total Lines:** {{DOC_LINES}}

### Tests

| Test Suite | Count | Type |
|-----------|-------|------|
| Unit Tests | {{UNIT_COUNT}} | {{UNIT_TYPE}} |
| Integration | {{INT_COUNT}} | {{INT_TYPE}} |
| E2E | {{E2E_COUNT}} | {{E2E_TYPE}} |

---

## 📊 Build Statistics

### Size Analysis

| Category | Files | Size | % of Total |
|----------|-------|------|-----------|
| Scripts | {{SCRIPT_FILE_COUNT}} | {{SCRIPT_TOTAL}} | {{SCRIPT_PERCENT}}% |
| Modules | {{MODULE_FILE_COUNT}} | {{MODULE_TOTAL}} | {{MODULE_PERCENT}}% |
| Docs | {{DOC_FILE_COUNT}} | {{DOC_TOTAL}} | {{DOC_PERCENT}}% |
| Tests | {{TEST_FILE_COUNT}} | {{TEST_TOTAL}} | {{TEST_PERCENT}}% |
| Config | {{CONFIG_FILE_COUNT}} | {{CONFIG_TOTAL}} | {{CONFIG_PERCENT}}% |

**Total Build:** {{TOTAL_FILES}} files, {{TOTAL_SIZE}}

### Compression

- **Uncompressed:** {{UNCOMPRESSED_SIZE}}
- **Compressed ({{COMPRESSION_ALGO}}):** {{COMPRESSED_SIZE}}
- **Compression Ratio:** {{COMPRESSION_RATIO}}%

---

## ✅ Manifest Validation

### Checksum Verification

| File | SHA256 |
|------|--------|
| {{CHECKSUM_FILE_1}} | {{CHECKSUM_1}} |
| {{CHECKSUM_FILE_2}} | {{CHECKSUM_2}} |

### File Integrity

- Total Files: {{TOTAL_FILES}}
- Verified: {{VERIFIED_FILES}}
- Status: ✓ All files intact

---

## 🔗 File Dependencies

### Critical Files

Files required for operation:

- {{CRITICAL_FILE_1}}: {{CRITICAL_DESC_1}}
- {{CRITICAL_FILE_2}}: {{CRITICAL_DESC_2}}
- {{CRITICAL_FILE_3}}: {{CRITICAL_DESC_3}}

### Optional Files

Can be removed:

- {{OPTIONAL_FILE_1}}: {{OPTIONAL_DESC_1}}
- {{OPTIONAL_FILE_2}}: {{OPTIONAL_DESC_2}}

---

**For Components:** [COMPONENTS_INCLUDED.md](./COMPONENTS_INCLUDED.md)  
**For Validation:** [BUILD_INTEGRITY_REPORT.md](./BUILD_INTEGRITY_REPORT.md)  
**For Changes:** [MODIFICATION_HISTORY.md](./MODIFICATION_HISTORY.md)

---

Generated from template version 1.0
