# Helios Wiki Utilities - Complete Index

## 📦 Package Contents

### Core Utilities (6 scripts)

1. **setup-wiki.ps1** (6.3 KB)
   - Initialize SQLite database
   - Create schema and indexes
   - Seed root categories
   - Can force reset existing databases

2. **generate-wiki.ps1** (11.1 KB)
   - Scan source directories
   - Extract PowerShell metadata
   - Parse .meta.json companion files
   - Generate markdown documentation (5 levels)
   - Create HTML wiki
   - Update database with file registry

3. **wiki-search.ps1** (8.4 KB)
   - Query database by keyword
   - Filter by category, complexity, build, tags
   - Find orphaned files
   - Detect conflicting references
   - Support custom SQL queries
   - Export as table/JSON/CSV

4. **check-cross-references.ps1** (9.7 KB)
   - Validate all links exist
   - Detect circular dependencies
   - Identify conflicts
   - Generate detailed reports
   - Optional auto-fix for broken references

5. **map-dependencies.ps1** (12.0 KB)
   - Create dependency graphs
   - Generate markdown visualization
   - Export DOT format for Graphviz
   - Output JSON for analysis
   - Detect circular dependencies by depth

6. **wiki-orchestrate.ps1** (4.3 KB)
   - Master coordinator script
   - Run individual actions or full pipeline
   - Support incremental updates
   - Integrated search functionality

### Integration Utilities (1 script)

7. **build-wiki-integration.ps1** (10.2 KB)
   - List build configurations
   - Get components for specific builds
   - Register new builds
   - Update build components
   - Generate build documentation

### Documentation (3 files)

- **README.md** (11.8 KB) - Full documentation
- **QUICKREF.md** (5.4 KB) - Quick reference guide
- **DATABASE_GUIDE.md** (This file) - Complete API reference

### Database (1 file)

- **wiki.db.sql** (7.7 KB) - SQLite schema with 9 tables, 24 indexes, 5 views

## 🗄️ Complete Database Schema

### Tables

#### 1. `files` - Master File Registry

```sql
CREATE TABLE files (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,        -- Relative path from project root
    name TEXT NOT NULL,               -- File name without extension
    category_id INTEGER,              -- Foreign key to categories
    file_type TEXT,                   -- .ps1, .json, .yaml, etc
    purpose TEXT,                     -- Description
    complexity TEXT,                  -- simple|moderate|complex|advanced
    status TEXT,                      -- active|deprecated|experimental|archived
    version TEXT,                     -- Version number
    build_inclusion TEXT,             -- standard|optional|enterprise|internal
    last_modified DATETIME,
    created_at DATETIME,
    documented BOOLEAN                -- 0 or 1
);

-- Key Indexes:
idx_files_category       -- Category lookups
idx_files_type          -- Type filtering
idx_files_status        -- Status filtering
idx_files_complexity    -- Complexity sorting
idx_files_build         -- Build inclusion
idx_files_modified      -- Last modification tracking
```

#### 2. `categories` - Hierarchical Documentation Structure

```sql
CREATE TABLE categories (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,        -- Category name
    parent_id INTEGER,                -- Parent category (null for root)
    level INTEGER,                    -- 1-5 documentation level
    description TEXT,
    icon TEXT,                        -- Unicode emoji
    order_index INTEGER
);

-- Key Indexes:
idx_categories_parent   -- Parent lookups
idx_categories_level    -- Level filtering
```

**Root Categories (Auto-Seeded):**

- Scripts (Level 1)
- Configurations (Level 1)
- Documentation (Level 1)
- Templates (Level 1)
- Build (Level 1)

#### 3. `cross_references` - Link Graph

```sql
CREATE TABLE cross_references (
    id INTEGER PRIMARY KEY,
    source_file_id INTEGER NOT NULL,  -- Origin file
    target_file_id INTEGER,           -- Destination file (null if concept)
    target_concept TEXT,              -- Concept name if no file
    reference_type TEXT,              -- depends_on|used_by|related|extends|implements|conflicts
    conflict_potential BOOLEAN,       -- Flag if conflicting
    conflict_notes TEXT,              -- Why it conflicts
    validated BOOLEAN,                -- 0 or 1
    validation_date DATETIME,
    created_at DATETIME
);

-- Key Indexes:
idx_xref_source         -- Source lookups
idx_xref_target         -- Target lookups
idx_xref_type           -- Type filtering
idx_xref_conflict       -- Conflict detection
```

#### 4. `dependencies` - Component Relationships

```sql
CREATE TABLE dependencies (
    id INTEGER PRIMARY KEY,
    source_id INTEGER NOT NULL,       -- Source file
    target_id INTEGER NOT NULL,       -- Target file
    dependency_type TEXT,             -- hard|soft|optional|conditional
    is_circular BOOLEAN,              -- 0 or 1
    depth INTEGER,                    -- Recursion depth
    description TEXT,                 -- Why dependency exists
    created_at DATETIME
);

-- Key Indexes:
idx_deps_source         -- Source lookups
idx_deps_target         -- Target lookups
idx_deps_circular       -- Circular detection
```

#### 5. `notes` - Team Annotations

```sql
CREATE TABLE notes (
    id INTEGER PRIMARY KEY,
    file_id INTEGER,                  -- Associated file
    note_type TEXT,                   -- observation|warning|todo|deprecated|optimization|security|performance
    content TEXT NOT NULL,            -- Note content
    author TEXT,                      -- Who made note
    priority TEXT,                    -- low|medium|high|critical
    resolved BOOLEAN,                 -- 0 or 1
    created_at DATETIME,
    updated_at DATETIME
);

-- Key Indexes:
idx_notes_file          -- File lookups
idx_notes_type          -- Type filtering
idx_notes_priority      -- Priority sorting
```

#### 6. `metadata` - Key-Value Store

```sql
CREATE TABLE metadata (
    id INTEGER PRIMARY KEY,
    file_id INTEGER,                  -- Associated file
    key TEXT NOT NULL,                -- Key name
    value TEXT,                       -- Value
    data_type TEXT,                   -- string|integer|datetime|boolean|json
    created_at DATETIME
);

-- Unique on (file_id, key)

-- Key Indexes:
idx_metadata_file       -- File lookups
idx_metadata_key        -- Key lookups
```

#### 7. `builds` - Build Configurations

```sql
CREATE TABLE builds (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,        -- Build name (standard, enterprise, etc)
    description TEXT,
    environment TEXT,                 -- Production, development, etc
    target_framework TEXT,
    include_optional BOOLEAN,         -- Include optional components
    include_enterprise BOOLEAN,       -- Include enterprise components
    components TEXT,                  -- JSON component list
    created_at DATETIME,
    modified_at DATETIME
);
```

#### 8. `build_components` - Build-File Junction

```sql
CREATE TABLE build_components (
    id INTEGER PRIMARY KEY,
    build_id INTEGER NOT NULL,        -- Associated build
    file_id INTEGER NOT NULL,         -- Included file
    inclusion_type TEXT,              -- required|optional
    order_index INTEGER               -- Load order
);

-- Key Index:
idx_build_components    -- Build lookups
```

#### 9. `snippets` - Code Registry

```sql
CREATE TABLE snippets (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,               -- Snippet name
    category TEXT,                    -- Category/tag
    language TEXT,                    -- ps1|json|sql|etc
    code TEXT NOT NULL,               -- Code content
    compressed_code TEXT,             -- Compressed version
    description TEXT,
    file_id INTEGER,                  -- Source file
    complexity TEXT,                  -- simple|moderate|complex
    tags TEXT,                        -- Comma-separated tags
    usage_count INTEGER,              -- Times used
    created_at DATETIME,
    updated_at DATETIME
);

-- Key Indexes:
idx_snippets_category   -- Category lookups
idx_snippets_language   -- Language filtering
idx_snippets_tags       -- Tag searching
```

## 🔍 Pre-Built Views

### 1. `active_files`

All active, documented files ordered by category and name.

```sql
SELECT * FROM active_files;
```

### 2. `documented_files`

All documented files sorted by complexity.

```sql
SELECT * FROM documented_files;
```

### 3. `undocumented_files`

Files missing documentation, sorted by complexity (descending).

```sql
SELECT * FROM undocumented_files;
```

### 4. `orphaned_files`

Files with no incoming or outgoing references.

```sql
SELECT * FROM orphaned_files;
```

### 5. `circular_dependencies`

All circular dependencies sorted by depth.

```sql
SELECT * FROM circular_dependencies;
```

## 🔧 Utility Scripts - Complete Reference

### setup-wiki.ps1

**Purpose:** Initialize and configure wiki database

**Parameters:**

```powershell
-DatabasePath <string>      # Path to wiki.db (default: docs/wiki.db)
-ForceReset <switch>        # Delete and recreate if exists
-SeedCategories <switch>    # Populate root categories (default: $true)
```

**Usage:**

```powershell
# Fresh setup
.\setup-wiki.ps1

# Reset existing database
.\setup-wiki.ps1 -ForceReset

# Custom location
.\setup-wiki.ps1 -DatabasePath C:\path\to\wiki.db
```

**Output:**

- Creates/updates wiki.db
- Initializes schema
- Creates 15+ indexes
- Populates root categories
- Displays statistics

---

### generate-wiki.ps1

**Purpose:** Generate wiki from codebase

**Parameters:**

```powershell
-SourceDirs <string[]>      # Dirs to scan (default: scripts, docs, configs, templates)
-OutputDir <string>        # Wiki output (default: docs/wiki)
-DatabasePath <string>     # DB path (default: docs/wiki.db)
-GenerateHtml <switch>     # Create HTML wiki (default: $true)
-UpdateDb <switch>         # Update database (default: $true)
```

**Usage:**

```powershell
# Full generation
.\generate-wiki.ps1

# Specific directories
.\generate-wiki.ps1 -SourceDirs @('scripts', 'configs')

# Database only
.\generate-wiki.ps1 -GenerateHtml:$false

# Custom output
.\generate-wiki.ps1 -OutputDir C:\docs\wiki
```

**Output:**

- docs/wiki/INDEX.md (Level 1)
- docs/wiki/level2/*/INDEX.md (Level 2)
- docs/wiki/level4/*.md (Level 4)
- Updated wiki.db

**Metadata Extraction:**

- PowerShell: SYNOPSIS, DESCRIPTION, PARAMETERS
- JSON: Custom metadata from .meta.json
- Complexity auto-estimated by line count

---

### wiki-search.ps1

**Purpose:** Query wiki database

**Parameters:**

```powershell
-Query <string>             # Search term or SQL query
-SearchType <string>        # keyword|category|complexity|build|orphaned|conflicts|dependencies|sql
-Category <string>          # Filter by category
-Complexity <string>        # simple|moderate|complex|advanced
-Format <string>            # table|json|csv
-DatabasePath <string>      # DB path
```

**Search Types:**

| Type | Usage | Example |
|------|-------|---------|
| keyword | Full-text search | `.\wiki-search.ps1 -Query "auth"` |
| category | Files in category | `.\wiki-search.ps1 -SearchType category -Query "Scripts"` |
| complexity | By complexity | `.\wiki-search.ps1 -Query "advanced"` |
| build | In build config | `.\wiki-search.ps1 -SearchType build -Query "standard"` |
| orphaned | No references | `.\wiki-search.ps1 -SearchType orphaned` |
| conflicts | Conflicting refs | `.\wiki-search.ps1 -SearchType conflicts` |
| dependencies | Dependency chains | `.\wiki-search.ps1 -SearchType dependencies -Query "path"` |
| sql | Custom query | `.\wiki-search.ps1 -SearchType sql -Query "SELECT ..."` |

**Output Formats:**

```powershell
-Format table   # Terminal table (default)
-Format json    # JSON array
-Format csv     # CSV with headers
```

**Examples:**

```powershell
# Find high-complexity files
.\wiki-search.ps1 -Query "advanced"

# Export to JSON
.\wiki-search.ps1 -SearchType orphaned -Format json

# Custom query
.\wiki-search.ps1 -SearchType sql -Query `
  "SELECT name, complexity FROM files WHERE status='active'"

# Find conflicts
.\wiki-search.ps1 -SearchType conflicts
```

---

### check-cross-references.ps1

**Purpose:** Validate cross-references and detect issues

**Parameters:**

```powershell
-ValidateFiles <switch>     # Check if referenced files exist (default: $true)
-CheckCircular <switch>     # Detect circular dependencies
-GenerateReport <switch>    # Create markdown report
-AutoFix <switch>           # Attempt to fix broken refs
-DatabasePath <string>      # DB path
-ReportPath <string>        # Report location
```

**Usage:**

```powershell
# Full validation
.\check-cross-references.ps1 -ValidateFiles -CheckCircular -GenerateReport

# Just find conflicts
.\check-cross-references.ps1

# Auto-fix broken references
.\check-cross-references.ps1 -AutoFix
```

**Checks:**

- File existence
- Circular dependencies (with depth analysis)
- Conflicting references
- Path validity
- Reference validation status

**Output:**

- Console summary
- cross-reference-report.md (with -GenerateReport)
- Statistics: total, valid, broken, conflicts, circular

---

### map-dependencies.ps1

**Purpose:** Create dependency graphs and visualizations

**Parameters:**

```powershell
-OutputFormat <string>      # markdown|dot|json|all (default: all)
-IncludeOptional <switch>   # Include optional deps
-MaxDepth <int>             # Recursion depth (default: 5)
-OutputDir <string>         # Output location
-DatabasePath <string>      # DB path
```

**Output Formats:**

**Markdown** (DEPENDENCY_GRAPH.md):

- Statistics
- Component hierarchy
- Root/leaf components
- Circular dependency warnings
- Dependency matrix

**DOT** (dependencies.dot):

- Graphviz format
- Color-coded nodes (root=yellow, leaf=green, middle=blue)
- Circular edges marked red
- Can generate PNG/PDF with: `dot -Tpng dependencies.dot -o dependencies.png`

**JSON** (dependencies.json):

- Machine-readable
- Full metadata
- Import to external tools

**Usage:**

```powershell
# Generate all formats
.\map-dependencies.ps1

# Just markdown graph
.\map-dependencies.ps1 -OutputFormat markdown

# With optional dependencies
.\map-dependencies.ps1 -IncludeOptional -MaxDepth 10

# Deeper analysis
.\map-dependencies.ps1 -MaxDepth 15
```

---

### wiki-orchestrate.ps1

**Purpose:** Master coordinator for wiki operations

**Parameters:**

```powershell
-Action <string>           # init|generate|validate|map|full|search
-SearchQuery <string>      # For search action
-Incremental <switch>      # Only update changes
-Verbose <switch>          # Detailed output
```

**Actions:**

| Action | Purpose |
|--------|---------|
| init | Initialize database |
| generate | Generate documentation |
| validate | Validate cross-references |
| map | Create dependency graphs |
| full | Complete regeneration |
| search | Query database |

**Usage:**

```powershell
# Complete setup
.\wiki-orchestrate.ps1 -Action full

# Individual actions
.\wiki-orchestrate.ps1 -Action init
.\wiki-orchestrate.ps1 -Action generate
.\wiki-orchestrate.ps1 -Action validate
.\wiki-orchestrate.ps1 -Action map

# Incremental update
.\wiki-orchestrate.ps1 -Action generate -Incremental

# Search
.\wiki-orchestrate.ps1 -Action search -SearchQuery "authentication"
```

---

### build-wiki-integration.ps1

**Purpose:** Build system integration

**Parameters:**

```powershell
-Action <string>           # list-builds|get-components|register-build|update-components|build-doc
-BuildName <string>        # Build name
-Components <string[]>     # Component paths
-DatabasePath <string>     # DB path
```

**Actions:**

```powershell
# List all builds
.\build-wiki-integration.ps1 -Action list-builds

# Get build components
.\build-wiki-integration.ps1 -Action get-components -BuildName "enterprise"

# Register new build
.\build-wiki-integration.ps1 -Action register-build `
  -BuildName "minimal" `
  -Components @('core.ps1', 'utils.ps1')

# Update components
.\build-wiki-integration.ps1 -Action update-components `
  -BuildName "standard" `
  -Components @('a.ps1', 'b.ps1', 'c.ps1')

# Generate documentation
.\build-wiki-integration.ps1 -Action build-doc -BuildName "enterprise"
```

**Output:**

- Build list with statistics
- Component manifests
- Build documentation (BUILD_BUILDNAME.md)

## 📊 Common SQL Queries

### Find All Active Files

```sql
SELECT * FROM files WHERE status = 'active' ORDER BY complexity;
```

### Get Files by Category

```sql
SELECT f.* FROM files f
JOIN categories c ON f.category_id = c.id
WHERE c.name = 'Scripts'
ORDER BY f.name;
```

### Find Undocumented Files

```sql
SELECT * FROM undocumented_files;
```

### Get Orphaned Files (No References)

```sql
SELECT * FROM orphaned_files;
```

### Find Circular Dependencies

```sql
SELECT * FROM circular_dependencies ORDER BY depth DESC;
```

### Build Component Query

```sql
SELECT f.name, f.complexity FROM files f
JOIN build_components bc ON f.id = bc.file_id
JOIN builds b ON bc.build_id = b.id
WHERE b.name = 'standard'
ORDER BY bc.order_index;
```

### Get High-Complexity Files

```sql
SELECT name, path, complexity FROM files
WHERE complexity IN ('complex', 'advanced')
ORDER BY complexity DESC;
```

### Find Conflicts

```sql
SELECT src.name as source, tgt.name as target, xr.conflict_notes
FROM cross_references xr
JOIN files src ON xr.source_file_id = src.id
LEFT JOIN files tgt ON xr.target_file_id = tgt.id
WHERE xr.conflict_potential = 1;
```

### Dependencies Analysis

```sql
SELECT COUNT(*) as total_deps,
       AVG(depth) as avg_depth,
       MAX(depth) as max_depth,
       SUM(CASE WHEN is_circular=1 THEN 1 ELSE 0 END) as circular
FROM dependencies;
```

## 🎯 Integration Patterns

### With CI/CD Pipeline

```powershell
# In build script
& "path/to/wiki-orchestrate.ps1" -Action full
if ($LASTEXITCODE -ne 0) { throw "Wiki generation failed" }
```

### With Version Control

```powershell
# Pre-commit hook
.\wiki-orchestrate.ps1 -Action generate -Incremental
git add docs/wiki/
```

### Scheduled Tasks

```powershell
# Windows Task Scheduler
# Trigger: Daily at 2 AM
# Action: PowerShell
# Script: wiki-orchestrate.ps1 -Action full
```

### Build System Integration

```powershell
# Get components for specific build
$components = & "wiki-search.ps1" -SearchType sql `
  -Query "SELECT path FROM files WHERE build_inclusion='standard'"
```

## 📈 Performance Considerations

### Indexing

- 24 indexes optimize common queries
- Largest index: cross_references (multi-column)
- Typical DB size: 10-50 MB

### Query Performance

- File lookups: O(log n) via path index
- Category searches: O(log n) via category index
- Full-text search: O(n) worst case, typically O(log n) via indexes

### Database Maintenance

```sql
-- Optimize database
VACUUM;

-- Reindex if slow
REINDEX;

-- Check integrity
PRAGMA integrity_check;
```

## 🔐 Security

- Database file should be restricted to team access
- Sensitive paths can be sanitized in exports
- No plaintext credentials in metadata
- Cross-reference validation prevents external injection

## 📝 Example Workflow

1. **Initial Setup**

   ```powershell
   .\setup-wiki.ps1
   ```

2. **First Generation**

   ```powershell
   .\generate-wiki.ps1 -GenerateHtml
   ```

3. **Validate**

   ```powershell
   .\check-cross-references.ps1 -GenerateReport
   ```

4. **Map Dependencies**

   ```powershell
   .\map-dependencies.ps1
   ```

5. **Search**

   ```powershell
   .\wiki-search.ps1 -Query "important"
   ```

6. **Integrate with Build**

   ```powershell
   .\build-wiki-integration.ps1 -Action register-build `
     -BuildName "standard" -Components $standardComponents
   ```

7. **Regular Updates**

   ```powershell
   # Weekly full regeneration
   .\wiki-orchestrate.ps1 -Action full
   ```

---

**Version:** 1.0  
**Last Updated:** 2024  
**Location:** scripts/utilities/wiki/
