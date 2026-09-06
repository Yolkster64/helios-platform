# {{PROJECT_NAME}} - Complete File Index

**Template Version:** 1.0  
**Last Updated:** {{LAST_UPDATED}}  
**Total Files:** {{TOTAL_FILE_COUNT}}

---

## 📑 Table of Contents

- [Root Level Documentation](#-root-level-documentation)
- [Category-Level Documentation](#-category-level-documentation)
- [Module-Level Documentation](#-module-level-documentation)
- [Script-Level Documentation](#-script-level-documentation)
- [Build-Level Documentation](#-build-level-documentation)

---

## 🏠 Root Level Documentation

### Overview & Getting Started

| File | Purpose | Audience | Lines | Last Updated |
|------|---------|----------|-------|--------------|
| [README.md](./README.md) | Main project overview | Everyone | {{README_LINES}} | {{README_DATE}} |
| [QUICK_START.md](./QUICK_START.md) | 5-minute setup guide | New Users | {{QUICKSTART_LINES}} | {{QUICKSTART_DATE}} |
| [INDEX.md](./INDEX.md) | This file - complete index | Everyone | {{INDEX_LINES}} | {{INDEX_DATE}} |

### Technical Documentation

| File | Purpose | Audience | Lines | Last Updated |
|------|---------|----------|-------|--------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design & components | Architects, Developers | {{ARCH_LINES}} | {{ARCH_DATE}} |
| [MODULES.md](./MODULES.md) | All modules reference | Developers | {{MODULES_LINES}} | {{MODULES_DATE}} |
| [API.md](./API.md) | Complete API reference | Developers, Integrators | {{API_LINES}} | {{API_DATE}} |

### Project Management

| File | Purpose | Audience | Lines | Last Updated |
|------|---------|----------|-------|--------------|
| [CONTRIBUTING.md](./CONTRIBUTING.md) | How to contribute | Contributors | {{CONTRIB_LINES}} | {{CONTRIB_DATE}} |
| [ROADMAP.md](./ROADMAP.md) | Future plans & vision | Product Team, Users | {{ROADMAP_LINES}} | {{ROADMAP_DATE}} |
| [RELEASE_NOTES.md](./RELEASE_NOTES.md) | Version history | Everyone | {{RELEASENOTES_LINES}} | {{RELEASENOTES_DATE}} |

### Help & Reference

| File | Purpose | Audience | Lines | Last Updated |
|------|---------|----------|-------|--------------|
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues & solutions | All Users | {{TROUBLESHOOT_LINES}} | {{TROUBLESHOOT_DATE}} |
| [FAQ.md](./FAQ.md) | Frequently asked questions | All Users | {{FAQ_LINES}} | {{FAQ_DATE}} |
| [GLOSSARY.md](./GLOSSARY.md) | Technical terminology | All Users | {{GLOSSARY_LINES}} | {{GLOSSARY_DATE}} |

---

## 📁 Category-Level Documentation

### Security

**Location:** `./security/`  
**Maintainer:** {{SECURITY_MAINTAINER}}  
**Status:** {{SECURITY_STATUS}}

| File | Purpose | Dependencies |
|------|---------|--------------|
| security/README.md | Security overview | ARCHITECTURE.md |
| security/USAGE.md | Security implementation | README.md |
| security/API.md | Security functions | API.md |
| security/EXAMPLES.md | Security examples | USAGE.md |
| security/TROUBLESHOOTING.md | Security issues | TROUBLESHOOTING.md |
| security/NOTES.md | Security notes | README.md |
| security/BUILD_USAGE.md | Build references | ARCHITECTURE.md |
| security/DEPENDENCIES.md | Security dependencies | {{DEPS}} |
| security/INDEX.md | Security index | README.md |
| security/COMPONENT_DETAILS.md | Component details | ARCHITECTURE.md |
| security/COMPRESSED_SNIPPETS.md | Code snippets | API.md |

### {{CATEGORY_2}} ({{CATEGORY_2_DESC}})

**Location:** `./{{CATEGORY_2_SLUG}}/`  
**Maintainer:** {{CATEGORY_2_MAINTAINER}}  
**Status:** {{CATEGORY_2_STATUS}}

| File | Purpose |
|------|---------|
| {{CATEGORY_2_SLUG}}/README.md | Category overview |
| {{CATEGORY_2_SLUG}}/USAGE.md | Usage guide |
| {{CATEGORY_2_SLUG}}/API.md | API reference |
| {{CATEGORY_2_SLUG}}/EXAMPLES.md | Code examples |
| {{CATEGORY_2_SLUG}}/TROUBLESHOOTING.md | Known issues |

### {{CATEGORY_3}} ({{CATEGORY_3_DESC}})

**Location:** `./{{CATEGORY_3_SLUG}}/`

| File | Purpose |
|------|---------|
| {{CATEGORY_3_SLUG}}/README.md | Category overview |
| {{CATEGORY_3_SLUG}}/USAGE.md | Usage guide |
| {{CATEGORY_3_SLUG}}/API.md | API reference |
| {{CATEGORY_3_SLUG}}/EXAMPLES.md | Code examples |
| {{CATEGORY_3_SLUG}}/TROUBLESHOOTING.md | Known issues |

---

## 🧩 Module-Level Documentation

### {{MODULE_1}} Module

**Location:** `./{{CATEGORY_1}}/{{MODULE_1}}/`  
**Type:** {{MODULE_1_TYPE}}  
**Status:** {{MODULE_1_STATUS}}  
**Lines of Code:** {{MODULE_1_LOC}}

| File | Purpose |
|------|---------|
| README.md | Module overview |
| USAGE.md | How to use |
| API.md | Function reference |
| EXAMPLES.md | Usage examples |
| DEPENDENCIES.md | Module dependencies |
| TROUBLESHOOTING.md | Known issues |
| NOTES.md | Implementation notes |

**Key Functions:**

- {{FUNCTION_1}}: {{FUNCTION_1_DESC}}
- {{FUNCTION_2}}: {{FUNCTION_2_DESC}}
- {{FUNCTION_3}}: {{FUNCTION_3_DESC}}

### {{MODULE_2}} Module

**Location:** `./{{CATEGORY_2}}/{{MODULE_2}}/`  
**Type:** {{MODULE_2_TYPE}}  
**Dependencies:** {{MODULE_2_DEPS}}

---

## 🔧 Script-Level Documentation

### {{CATEGORY_1}}/{{MODULE_1}}/{{SCRIPT_1}}.ps1

**Location:** `./{{CATEGORY_1}}/{{MODULE_1}}/{{SCRIPT_1}}.ps1`  
**Purpose:** {{SCRIPT_1_PURPOSE}}  
**Lines:** {{SCRIPT_1_LINES}}

**Associated Documentation:**

- `{{SCRIPT_1}}.meta.json` - Metadata
- `{{SCRIPT_1}}.wiki.md` - Extended explanation
- `{{SCRIPT_1}}.examples.md` - Usage examples
- `{{SCRIPT_1}}.build-usage.md` - Build references
- `{{SCRIPT_1}}.snippet-ref.md` - Code snippets

**Parameters:**

- `-Parameter1`: {{PARAM_1_DESC}}
- `-Parameter2`: {{PARAM_2_DESC}}
- `-Parameter3`: {{PARAM_3_DESC}}

**Examples:**

```powershell
# {{EXAMPLE_1_DESC}}
{{EXAMPLE_1_CODE}}

# {{EXAMPLE_2_DESC}}
{{EXAMPLE_2_CODE}}
```

---

## 📦 Build-Level Documentation

### {{BUILD_1}} Build

**Location:** `./builds/{{BUILD_1}}/`  
**Purpose:** {{BUILD_1_PURPOSE}}  
**Size:** {{BUILD_1_SIZE}}  
**Version:** {{BUILD_1_VERSION}}

**Documentation Files:**

- README.md - Build overview
- MANIFEST.md - Exact contents
- COMPONENTS_INCLUDED.md - Component list
- CONFIGURATION.md - Build configuration
- DEPENDENCIES_GRAPH.md - Dependency graph
- BUILD_INTEGRITY_REPORT.md - Validation report
- MODIFICATION_HISTORY.md - Change history
- COMPRESSED_SNIPPETS_USED.md - Code snippets

**Includes:**

- {{MODULE_INCLUDED_1}}
- {{MODULE_INCLUDED_2}}
- {{MODULE_INCLUDED_3}}

---

## 📊 Documentation Statistics

### File Counts by Level

| Level | File Count | Total Lines | Avg Lines |
|-------|-----------|------------|-----------|
| Level 1 (Root) | {{L1_COUNT}} | {{L1_LINES}} | {{L1_AVG}} |
| Level 2 (Category) | {{L2_COUNT}} | {{L2_LINES}} | {{L2_AVG}} |
| Level 3 (Module) | {{L3_COUNT}} | {{L3_LINES}} | {{L3_AVG}} |
| Level 4 (Script) | {{L4_COUNT}} | {{L4_LINES}} | {{L4_AVG}} |
| Level 5 (Build) | {{L5_COUNT}} | {{L5_LINES}} | {{L5_AVG}} |
| **TOTAL** | **{{TOTAL_COUNT}}** | **{{TOTAL_LINES}}** | - |

### Documentation by Category

| Category | Files | Purpose | Status |
|----------|-------|---------|--------|
| {{CAT_1}} | {{CAT_1_FILES}} | {{CAT_1_PURPOSE}} | {{CAT_1_STATUS}} |
| {{CAT_2}} | {{CAT_2_FILES}} | {{CAT_2_PURPOSE}} | {{CAT_2_STATUS}} |
| {{CAT_3}} | {{CAT_3_FILES}} | {{CAT_3_PURPOSE}} | {{CAT_3_STATUS}} |
| {{CAT_4}} | {{CAT_4_FILES}} | {{CAT_4_PURPOSE}} | {{CAT_4_STATUS}} |

---

## 🔍 Quick Reference by Purpose

### Getting Started

- [README.md](./README.md) - Start here!
- [QUICK_START.md](./QUICK_START.md) - 5-minute setup
- [CONTRIBUTING.md](./CONTRIBUTING.md) - Contributing guide

### Learning the System

- [ARCHITECTURE.md](./ARCHITECTURE.md) - System design
- [MODULES.md](./MODULES.md) - Module overview
- [API.md](./API.md) - API reference

### Using the System

- Category READMEs (./{{category}}/README.md)
- Module USAGE.md files
- Script examples in .examples.md files

### Troubleshooting

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues
- [FAQ.md](./FAQ.md) - Frequently asked questions
- [GLOSSARY.md](./GLOSSARY.md) - Terminology

### Development

- [CONTRIBUTING.md](./CONTRIBUTING.md) - How to contribute
- [ROADMAP.md](./ROADMAP.md) - Future plans
- Category COMPONENT_DETAILS.md files

### Deployment & Operations

- Build README.md files
- Build MANIFEST.md files
- Build CONFIGURATION.md files

---

## 🔗 Cross-References

### Popular Paths

**For Developers:**

```
1. README.md (overview)
   ↓
2. QUICK_START.md (setup)
   ↓
3. ARCHITECTURE.md (design)
   ↓
4. MODULES.md (components)
   ↓
5. API.md (reference)
```

**For Operations:**

```
1. README.md (overview)
   ↓
2. builds/*/README.md (build info)
   ↓
3. builds/*/MANIFEST.md (contents)
   ↓
4. TROUBLESHOOTING.md (issues)
```

**For Contributors:**

```
1. CONTRIBUTING.md (guidelines)
   ↓
2. ARCHITECTURE.md (design)
   ↓
3. Category COMPONENT_DETAILS.md
   ↓
4. Module API.md
```

---

## 📝 File Format Guide

### Markdown Files (.md)

- UTF-8 encoding
- Heading hierarchy 1-3 levels
- Code blocks with language specification
- Tables for structured data
- Links use relative paths

### JSON Files (.json)

- Pretty-printed (2 space indent)
- Required fields documented
- Examples provided
- Schema validation recommended

### Metadata Files (.meta.json)

```json
{
  "name": "{{SCRIPT_NAME}}",
  "version": "{{VERSION}}",
  "purpose": "{{PURPOSE}}",
  "category": "{{CATEGORY}}",
  "dependencies": ["{{DEP1}}", "{{DEP2}}"],
  "parameters": {
    "{{PARAM1}}": "{{TYPE}}"
  }
}
```

---

## 🔄 Documentation Maintenance

### Update Schedule

| File | Update Frequency | Owner |
|------|-----------------|-------|
| {{FILE_1}} | {{FREQUENCY_1}} | {{OWNER_1}} |
| {{FILE_2}} | {{FREQUENCY_2}} | {{OWNER_2}} |
| {{FILE_3}} | {{FREQUENCY_3}} | {{OWNER_3}} |

### Review Checklist

- [ ] Links valid
- [ ] Examples tested
- [ ] Formatting consistent
- [ ] TOC updated
- [ ] Outdated info removed
- [ ] New features documented

---

## 🔍 Finding What You Need

### By Audience

**I'm a new user** → [README.md](./README.md) → [QUICK_START.md](./QUICK_START.md)

**I'm a developer** → [ARCHITECTURE.md](./ARCHITECTURE.md) → [API.md](./API.md)

**I'm an operator** → [builds/*/README.md](./builds/) → [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

**I want to contribute** → [CONTRIBUTING.md](./CONTRIBUTING.md)

### By Task

**Setup** → [QUICK_START.md](./QUICK_START.md)  
**Learn design** → [ARCHITECTURE.md](./ARCHITECTURE.md)  
**Use feature** → Category USAGE.md  
**Fix problem** → [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)  
**Deploy** → builds/*/README.md  
**Develop** → [CONTRIBUTING.md](./CONTRIBUTING.md)  

---

**Generated from template version 1.0 on {{GENERATION_DATE}}**  
**Last verified: {{LAST_VERIFIED}}**
