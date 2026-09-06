# HELIOS 5-Level Wiki Documentation Structure

Complete documentation system spanning root, category, module, script, and build levels.

---

## Documentation Architecture

```
HELIOS Platform
│
├─ Level 1: ROOT DOCUMENTATION (entry point)
│  ├─ README.md ........................... Main overview
│  ├─ ARCHITECTURE.md ..................... System design
│  ├─ QUICK_START.md ...................... 5-minute setup
│  ├─ BUILD_DETAILS.md .................... Build breakdown
│  ├─ BUILD_VARIANTS.md ................... 7 preset variants
│  ├─ COMPONENT_MATRIX.md ................. Component x build matrix
│  ├─ COMPRESSED_CODE_REGISTRY.md ......... Snippet index
│  ├─ CONTRIBUTING.md ..................... Extension guide
│  ├─ INDEX.md ............................ Complete file index
│  ├─ MODULES.md .......................... All modules
│  ├─ API.md .............................. All functions
│  └─ ROADMAP.md .......................... Future plans
│
├─ Level 2: CATEGORY DOCUMENTATION (13 major categories)
│  ├─ scripts/security/
│  │  ├─ README.md ........................ Category overview
│  │  ├─ USAGE.md ......................... How to use
│  │  ├─ INDEX.md ......................... Submodules list
│  │  ├─ API.md ........................... Available functions
│  │  ├─ DEPENDENCIES.md .................. Requirements
│  │  ├─ EXAMPLES.md ...................... Usage examples
│  │  ├─ TROUBLESHOOTING.md ............... Issues & fixes
│  │  ├─ NOTES.md ......................... Team notes/changes
│  │  ├─ BUILD_USAGE.md ................... Which builds include
│  │  ├─ COMPRESSED_SNIPPETS.md ........... Code snippets
│  │  └─ COMPONENT_DETAILS.md ............. Detailed breakdown
│  │
│  ├─ scripts/optimization/
│  ├─ scripts/gui/
│  ├─ scripts/ai-hub/
│  ├─ scripts/cloud/
│  ├─ scripts/tools/
│  ├─ scripts/build-agents/
│  ├─ scripts/utilities/
│  ├─ scripts/installer/
│  ├─ configs/
│  ├─ templates/
│  ├─ builds/
│  └─ docs/
│
├─ Level 3: MODULE DOCUMENTATION (sub-categories)
│  ├─ scripts/security/baseline/
│  │  ├─ README.md ........................ Module overview
│  │  ├─ USAGE.md ......................... How to run
│  │  ├─ API.md ........................... Functions
│  │  ├─ EXAMPLES.md ...................... Commands
│  │  ├─ DEPENDENCIES.md .................. Requirements
│  │  ├─ NOTES.md ......................... Team notes
│  │  ├─ CHANGELOG.md ..................... Version history
│  │  ├─ BUILD_INCLUSION.md ............... Which builds use
│  │  └─ CODE_SNIPPETS.md ................. Code references
│  │
│  ├─ scripts/security/hardening/
│  ├─ scripts/security/advanced/
│  ├─ scripts/security/deep-cleaning/
│  └─ (similar structure for all 90+ modules)
│
├─ Level 4: SCRIPT DOCUMENTATION (every .ps1 file)
│  ├─ scripts/security/baseline/applock/setup.ps1
│  │  ├─ File header ...................... Purpose, author, date
│  │  ├─ Function docs .................... Every function
│  │  ├─ Parameter docs ................... Every parameter
│  │  ├─ setup.ps1.wiki.md ................ Detailed explanation
│  │  ├─ setup.ps1.meta.json .............. Metadata
│  │  ├─ setup.ps1.examples.md ............ Usage examples
│  │  ├─ setup.ps1.build-usage.md ......... Used in which builds
│  │  └─ setup.ps1.snippet-ref.md ......... Compressed snippet ref
│  │
│  └─ (similar for all 200+ scripts)
│
└─ Level 5: BUILD DOCUMENTATION (variant details) ⭐ NEW
   ├─ builds/saved-builds/build-20260413-phase1/
   │  ├─ README.md ........................ Build overview
   │  ├─ MANIFEST.md ...................... Exactly what's included
   │  ├─ COMPONENTS_INCLUDED.md ........... All components + versions
   │  ├─ COMPRESSED_SNIPPETS_USED.md ...... Code snippets in build
   │  ├─ CONFIGURATION.md ................. Build settings
   │  ├─ DEPENDENCIES_GRAPH.md ............ Component deps
   │  ├─ BUILD_INTEGRITY_REPORT.md ........ Validation results
   │  └─ MODIFICATION_HISTORY.md .......... All changes
   │
   ├─ builds/saved-builds/build-20260413-phase2/
   ├─ builds/saved-builds/build-gaming-latest/
   └─ (one per saved build)
```

---

## What's In Each Level

### Level 1: Root Documentation

**Purpose:** Entry point for entire system

**Files:**

- `README.md` - Main overview (what HELIOS is)
- `ARCHITECTURE.md` - System design and philosophy
- `QUICK_START.md` - Get running in 5 minutes
- `BUILD_DETAILS.md` - Detailed breakdown of build system
- `BUILD_VARIANTS.md` - All 7 variants explained
- `COMPONENT_MATRIX.md` - What's in each variant
- `COMPRESSED_CODE_REGISTRY.md` - Snippet registry index
- `INDEX.md` - Complete file index
- `MODULES.md` - All modules documented
- `API.md` - All public functions
- `CONTRIBUTING.md` - How to extend/contribute
- `ROADMAP.md` - Future plans

**Audience:** Everyone (entry point)

**Size:** ~50 KB markdown

---

### Level 2: Category Documentation

**Purpose:** Overview for each major category (13 total)

**Files:**

```
- README.md ........................ What does this category do?
- USAGE.md ........................ How to use this category
- INDEX.md ........................ All modules in category
- API.md .......................... All functions available
- DEPENDENCIES.md ................. What this needs
- EXAMPLES.md ..................... Real-world examples
- TROUBLESHOOTING.md .............. Problems & solutions
- NOTES.md ........................ Team notes/changes
- BUILD_USAGE.md .................. Which builds use this
- COMPRESSED_SNIPPETS.md ......... Code snippets
- COMPONENT_DETAILS.md ........... Detailed info
```

**Categories:** 13 major (security, optimization, gui, ai-hub, tools, build-agents, storage, installer, utilities, cloud, configs, templates, builds)

**Size:** ~20 KB per category

---

### Level 3: Module Documentation

**Purpose:** Details for each module/sub-folder

**Files:** Same as Level 2 (11 files)

**Modules:** 90+ sub-folders

**Size:** ~5-10 KB per module

---

### Level 4: Script Documentation

**Purpose:** Self-documenting code with metadata

**Files Per Script:**

- `{script}.ps1` - Script with embedded docs
- `{script}.wiki.md` - Extended explanation
- `{script}.meta.json` - Structured metadata
- `{script}.examples.md` - Usage examples
- `{script}.build-usage.md` - Where script is used
- `{script}.snippet-ref.md` - Compressed code reference

**Scripts:** 200+ PowerShell scripts

**Size:** ~1-2 KB per script + metadata

---

### Level 5: Build Documentation ⭐ NEW

**Purpose:** Detailed breakdown of each saved build

**Files Per Build:**

```
- README.md ........................ Build overview
- MANIFEST.md ...................... Exact contents
- COMPONENTS_INCLUDED.md .......... All components
- COMPRESSED_SNIPPETS_USED.md ..... Snippets in build
- CONFIGURATION.md ................. Build config
- DEPENDENCIES_GRAPH.md ........... Dependencies
- BUILD_INTEGRITY_REPORT.md ....... Validation
- MODIFICATION_HISTORY.md ......... Change log
```

**Builds:** Variable (one per saved build state)

**Size:** ~10-20 KB per build

---

## Database-Driven Wiki (SQLite)

All files tracked in `docs/wiki.db`:

### Tables

- `files` - Every file catalogued
- `categories` - Category hierarchy
- `cross_references` - File relationships
- `notes` - Team notes/changes
- `metadata` - Key-value data
- `dependencies` - Module dependencies
- `builds` - Build configurations
- `snippets` - Compressed code registry

### Query Examples

```sql
-- Find all files in security category
SELECT * FROM files WHERE category = 'security';

-- Find cross-references
SELECT * FROM cross_references 
WHERE source_file_id = ? AND reference_type = 'depends_on';

-- Find which builds use this file
SELECT * FROM builds_files 
WHERE file_id = ?;

-- Search for all notes mentioning "toggle"
SELECT * FROM notes 
WHERE content LIKE '%toggle%';

-- Find conflicting configurations
SELECT * FROM cross_references 
WHERE conflict_potential > 0.5;
```

---

## Navigation System

### Breadcrumb Navigation

Every page shows path:

```
HELIOS > Scripts > Security > Baseline > AppLocker > setup.ps1
```

### Search Across All Levels

```powershell
# Find files by keyword
.\scripts\utilities\wiki-search.ps1 -Query "applock"

# Find by category
.\scripts\utilities\wiki-search.ps1 -Category "security"

# Find by build usage
.\scripts\utilities\wiki-search.ps1 -InBuild "phase-2"

# Find by complexity
.\scripts\utilities\wiki-search.ps1 -Complexity "intermediate"
```

### Index Files Auto-Generated

- `docs/INDEX.md` - Root index
- `docs/MODULES.md` - All modules
- `scripts/security/INDEX.md` - Security submodules
- `scripts/security/baseline/INDEX.md` - Baseline files
- etc. for all 90+ modules

---

## File Metadata System

### Meta JSON Structure

```json
{
  "name": "setup.ps1",
  "path": "scripts/security/baseline/applock/",
  "version": "1.0.0",
  "author": "GitHub Copilot",
  "created": "2026-04-13",
  "modified": "2026-04-13",
  "status": "production",
  "category": ["security", "baseline", "applock"],
  "depends_on": ["powershell-7", "windows-11-pro"],
  "tags": ["applock", "security", "whitelist"],
  "complexity": "intermediate",
  "estimated_time": "15 minutes",
  "cross_references": [
    "scripts/security/hardening/...",
    "scripts/build-agents/agent-2-security/..."
  ],
  "build_inclusion": {
    "phase-1": true,
    "phase-2": true,
    "phase-3": true,
    "variant-gaming": false,
    "variant-dev": true,
    "variant-security": true
  },
  "compressed_snippet_id": "security-snippets:applock-basic",
  "compressed_snippet_size": "2.3 KB",
  "toggleable": true,
  "ai_generated": false,
  "ai_coordination": ["agent-2-security", "hardening/services-disable"]
}
```

---

## Teams Notes & Adaptation Tracking

### NOTES.md at Each Level

Track adaptations and changes with:

- Date stamp
- What changed
- Why it changed
- Who made the change
- Impact level
- Related files
- AI suggestions (if applicable)

---

## HTML Wiki Generation

Auto-generated from markdown:

- ✅ Full-text search
- ✅ Advanced filters
- ✅ Build inspector view
- ✅ Component reference
- ✅ Snippet viewer
- ✅ Dependency graph visualization
- ✅ Cross-reference explorer

---

## Commands for Wiki Management

```powershell
# Generate entire wiki
.\scripts\utilities\wiki\generate-wiki.ps1

# Update specific category
.\scripts\utilities\wiki\generate-wiki.ps1 -Category "security"

# Create index files
.\scripts\utilities\wiki\update-indexes.ps1

# Search wiki
.\scripts\utilities\wiki\wiki-search.ps1 -Query "applock"

# Validate cross-references
.\scripts\utilities\wiki\check-cross-references.ps1

# Find orphaned files
.\scripts\utilities\wiki\find-orphaned-files.ps1

# Generate dependency graph
.\scripts\utilities\wiki\map-dependencies.ps1
```

---

## Statistics

- **Documentation Levels:** 5
- **Root docs:** 12 files (~50 KB)
- **Categories:** 13 with 11 files each (~143 files, ~260 KB)
- **Modules:** 90+ with 11 files each (~990 files, ~450 KB)
- **Scripts:** 200+ with 6 metadata files (~1,400 files)
- **Builds:** Variable (1+ per saved state)
- **Total Markdown:** ~1,500+ files (~850 KB)
- **Database:** SQLite with full-text search (~5 MB)
- **HTML Wiki:** Auto-generated (~50 MB uncompressed)

---

## Quick Navigation

**I want to:**

- 📖 Learn what HELIOS is → Start at `README.md`
- 🚀 Get running quickly → Go to `QUICK_START.md`
- 🏗️ Understand architecture → Read `ARCHITECTURE.md`
- 🔍 Browse all modules → See `MODULES.md`
- 🔧 Use security features → Go to `scripts/security/README.md`
- 💾 Manage builds → Go to `scripts/build-manager/README.md`
- 🤖 Use AI integration → Go to `scripts/ai-integration/README.md`
- 🎮 Find a specific command → Use `wiki-search.ps1`
- 📊 Compare builds → Run `compare-builds.ps1`
- 🔄 Switch builds → Run `select-build.ps1`
