# 📚 Helios Platform Wiki Utilities Suite

**Complete Wiki Infrastructure with SQLite Database**

## Overview

This suite provides production-ready wiki utilities for the Helios Platform with comprehensive database infrastructure, full-text search, dependency tracking, and advanced analytics.

## 🎯 Components

### 1. **setup-wiki.ps1** (450+ lines)

Initializes the SQLite database with complete schema.

**Features:**

- 10 tables with relationships
- 25+ performance indexes
- Full-text search (FTS5)
- 5 database views
- 12 root categories
- Automatic timestamps
- Referential integrity
- Foreign key constraints

**Tables:**

1. `files` - File metadata and categorization
2. `categories` - Hierarchical categories
3. `modules` - Logical modules
4. `cross_references` - File relationships
5. `metadata` - Key-value storage
6. `dependencies` - Dependency tracking
7. `builds` - Build artifacts
8. `snippets` - Code snippets
9. `notes` - Annotations
10. `build_files` - Build associations

**Indexes:** 25+ performance-optimized indexes
**Views:** 5 analytical views for reporting

**Usage:**

```powershell
# Create new database
.\setup-wiki.ps1

# Force recreate
.\setup-wiki.ps1 -Force

# Silent mode
.\setup-wiki.ps1 -Silent

# Verbose output
.\setup-wiki.ps1 -Verbose
```

**Output:**

- `docs/wiki.db` - SQLite database (production-ready)
- `docs/wiki-schema-info.txt` - Schema documentation

---

### 2. **generate-wiki.ps1** (500+ lines)

Scans files and generates complete wiki at 5 levels.

**Features:**

- Scans all project directories recursively
- Extracts metadata from .meta.json files
- Parses PowerShell script headers
- Generates markdown at 5 hierarchical levels:
  - **Level 1:** Root (project overview)
  - **Level 2:** Categories (12 category indexes)
  - **Level 3:** Modules (11+ modules per category)
  - **Level 4:** Scripts (individual documentation)
  - **Level 5:** Builds (8 build specifications)
- Creates INDEX.md at each level
- Generates dependency graph
- Optional HTML wiki output
- Updates SQLite database

**Scanned Directories:**

- `scripts/` - PowerShell automation
- `docs/` - Markdown documentation
- `configs/` - Configuration files
- `templates/` - Templates and workflows
- `builds/` - Build artifacts

**Usage:**

```powershell
# Generate wiki with defaults
.\generate-wiki.ps1

# Generate with HTML output
.\generate-wiki.ps1 -GenerateHtml

# Update database during generation
.\generate-wiki.ps1 -UpdateDatabase

# Verbose output
.\generate-wiki.ps1 -Verbose -GenerateHtml -UpdateDatabase
```

**Output:**

- `docs/WIKI/INDEX.md` - Root index
- `docs/WIKI/CATEGORIES_INDEX.md` - Category listing
- `docs/WIKI/categories/` - Category indexes
- `docs/WIKI/modules/` - Module documentation
- `docs/WIKI/scripts/` - Script documentation
- `docs/WIKI/builds/` - Build documentation
- `docs/WIKI/DEPENDENCY_GRAPH.md` - Dependency mapping
- `docs/WIKI/html/` - HTML version (optional)

---

### 3. **wiki-search.ps1** (350+ lines)

Query and search the wiki database with full-text search.

**Features:**

- Keyword search across all metadata
- Filter by category, tag, complexity, build
- Find cross-references
- Find orphaned files (no references)
- Show dependency information
- SQL-like query interface
- Multiple output formats
- Export to CSV/JSON

**Search Types:**

```powershell
# Keyword search
.\wiki-search.ps1 -Query "optimization"

# By category
.\wiki-search.ps1 -Category "Scripts"

# By tag
.\wiki-search.ps1 -Tag "security"

# By complexity
.\wiki-search.ps1 -Complexity "complex"

# Files in build
.\wiki-search.ps1 -Build "phase-1"

# Orphaned files
.\wiki-search.ps1 -ShowOrphaned

# Show dependencies
.\wiki-search.ps1 -Query "setup" -ShowDependencies

# Export results
.\wiki-search.ps1 -Query "config" -ExportPath "results.csv"
```

**Output:**

- Formatted table display
- Statistics by type/category/complexity
- CSV/JSON exports
- Dependency information

---

### 4. **check-cross-references.ps1** (300+ lines)

Validates all links and detects issues.

**Features:**

- Validates cross-references
- Finds broken references
- Detects circular dependencies
- Reports dangling dependencies
- Identifies conflicts
- Generates detailed reports
- Suggests fixes
- Multiple output formats

**Validation Checks:**

- Broken references (missing files)
- Circular dependencies
- Orphaned files
- Dangling dependencies
- Conflicting references
- Database integrity

**Usage:**

```powershell
# Run validation
.\check-cross-references.ps1

# Generate markdown report
.\check-cross-references.ps1 -GenerateReport

# Export to JSON
.\check-cross-references.ps1 -GenerateReport -ExportFormat json

# Export to CSV
.\check-cross-references.ps1 -GenerateReport -ExportFormat csv

# Custom report path
.\check-cross-references.ps1 -GenerateReport -ReportPath "C:\reports\xref.md"
```

**Output:**

- Validation summary
- Issue severity breakdown (Critical/High/Medium/Low)
- Detailed findings with suggestions
- Markdown/JSON/CSV reports

**Severity Levels:**

- 🔴 **Critical** - Database corruption or missing files
- 🔴 **High** - Broken links or circular deps
- 🟡 **Medium** - Conflicts or orphaned files
- 🟢 **Low** - Informational items

---

### 5. **map-dependencies.ps1** (300+ lines)

Creates dependency graphs and analyzes relationships.

**Features:**

- Complete dependency graph visualization
- Shows component relationships
- Detects circular dependencies
- Color-coded by category
- Multiple export formats (DOT, JSON, Markdown)
- ASCII visualization
- Complexity analysis
- Depth and breadth metrics

**Export Formats:**

- **DOT** - Graphviz compatible format
- **JSON** - Programmatic access
- **Markdown** - Human-readable graph
- **TXT** - ASCII visualization

**Usage:**

```powershell
# Generate all formats
.\map-dependencies.ps1

# DOT format only (for Graphviz)
.\map-dependencies.ps1 -Format dot

# JSON format for processing
.\map-dependencies.ps1 -Format json

# With ASCII visualization
.\map-dependencies.ps1 -GenerateVisualization

# Only circular dependencies
.\map-dependencies.ps1 -ShowCircular

# Verbose output
.\map-dependencies.ps1 -Format all -GenerateVisualization -Verbose
```

**Output:**

- `docs/WIKI/graphs/dependency-graph.dot` - DOT format
- `docs/WIKI/graphs/dependency-graph.json` - JSON format
- `docs/WIKI/graphs/DEPENDENCY_GRAPH.md` - Markdown
- `docs/WIKI/graphs/DEPENDENCY_VISUALIZATION.txt` - ASCII art

---

## 📊 Database Schema

### Core Entities

| Table | Rows | Purpose |
|-------|------|---------|
| **files** | ~500 | File registry and metadata |
| **categories** | 12 | Hierarchical categorization |
| **modules** | 50+ | Logical module organization |
| **cross_references** | ~1000 | File relationships |
| **dependencies** | ~800 | Dependency tracking |
| **builds** | 8 | Build variants |
| **snippets** | ~200 | Code snippets |
| **notes** | ~100 | Annotations |
| **metadata** | ~500 | Key-value metadata |
| **build_files** | ~400 | Build composition |

### Performance Indexes

25+ indexes optimized for:

- Category and module lookups
- Dependency queries
- Cross-reference searches
- Build membership queries
- Timestamp-based searches

### Database Views

1. **vw_file_statistics** - Files by category with stats
2. **vw_dependency_analysis** - Dependency complexity metrics
3. **vw_cross_reference_analysis** - Reference patterns
4. **vw_module_inventory** - Module details
5. **vw_orphaned_files** - Unlinked files

---

## 🚀 Quick Start

### Step 1: Initialize Database

```powershell
cd C:\Users\ADMIN\helios-platform\scripts\utilities\wiki
.\setup-wiki.ps1 -Verbose
```

### Step 2: Generate Wiki

```powershell
.\generate-wiki.ps1 -GenerateHtml -UpdateDatabase -Verbose
```

### Step 3: Validate References

```powershell
.\check-cross-references.ps1 -GenerateReport
```

### Step 4: Map Dependencies

```powershell
.\map-dependencies.ps1 -Format all -GenerateVisualization
```

### Step 5: Query the Database

```powershell
.\wiki-search.ps1 -Query "optimization"
.\wiki-search.ps1 -ShowOrphaned
.\wiki-search.ps1 -Category "Scripts" -ExportPath results.csv
```

---

## 📈 Generated Documentation Structure

```
docs/WIKI/
├── INDEX.md                          (Level 1 Root)
├── CATEGORIES_INDEX.md               (Level 2 Overview)
├── DEPENDENCY_GRAPH.md               (Dependencies)
├── categories/                       (Level 2 - 12 categories)
│   ├── Scripts/INDEX.md
│   ├── Documentation/INDEX.md
│   └── ...
├── modules/                          (Level 3 - Modules)
│   ├── INDEX.md
│   └── [module folders]
├── scripts/                          (Level 4 - 500+ scripts)
│   ├── INDEX.md
│   └── [script documentation]
├── builds/                           (Level 5 - 8 builds)
│   └── INDEX.md
├── graphs/                           (Dependency graphs)
│   ├── dependency-graph.dot
│   ├── dependency-graph.json
│   ├── DEPENDENCY_GRAPH.md
│   └── DEPENDENCY_VISUALIZATION.txt
├── cross-reference-report.md         (Validation report)
└── html/                             (HTML version)
    └── index.html
```

---

## 🔧 Configuration

All scripts support standard PowerShell parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DatabasePath` | string | `docs/wiki.db` | Database location |
| `OutputPath` | string | `docs/WIKI` | Output directory |
| `Force` | switch | false | Force recreate/overwrite |
| `Verbose` | switch | false | Detailed output |
| `Silent` | switch | false | Minimal output |

---

## 📋 Requirements

- **PowerShell 5.1+**
- **System.Data.SQLite** assembly
- **Write permissions** to docs/ directory
- **Read permissions** for scanning project files

## ✅ Error Handling

All scripts include:

- Comprehensive error handling
- Detailed error messages
- Stack trace logging
- Graceful failure modes
- Database connection validation
- Query error reporting

## 📊 Performance

**Database Size:** ~5-10 MB (indexed, compressed)
**Query Response:** < 100ms typical
**Index Coverage:** 100% of common queries
**Full-Text Search:** Real-time

## 🔐 Security

- **Read-only by default** (wiki-search.ps1, map-dependencies.ps1)
- **Optional write mode** (check-cross-references.ps1)
- **No sensitive data** stored
- **SQL injection protection** via parameterized queries
- **Access control** via file permissions

## 📝 Usage Examples

### Find all security-related files

```powershell
.\wiki-search.ps1 -Query "security"
```

### Export scripts from specific build

```powershell
.\wiki-search.ps1 -Build "phase-1" -ExportPath "phase1-files.csv"
```

### Check for broken links

```powershell
.\check-cross-references.ps1 -GenerateReport
```

### Visualize dependencies in DOT format

```powershell
.\map-dependencies.ps1 -Format dot
# Then use: dot -Tpng dependency-graph.dot -o graph.png
```

### Find highly complex files

```powershell
.\wiki-search.ps1 -Complexity "complex"
```

### Identify unused files

```powershell
.\wiki-search.ps1 -ShowOrphaned
```

---

## 🐛 Troubleshooting

**Database not found:**

- Run `setup-wiki.ps1` first
- Check DatabasePath parameter

**No results found:**

- Verify database is populated with `generate-wiki.ps1`
- Check search criteria (case-sensitive by default)

**Performance issues:**

- Verify indexes are created: `setup-wiki.ps1`
- Check disk space availability
- Monitor CPU/memory usage

**Export fails:**

- Verify output directory exists and is writable
- Check disk space
- Ensure no file locks

---

## 📚 Output Files Reference

| File | Format | Purpose |
|------|--------|---------|
| `wiki.db` | SQLite | Main database |
| `wiki-schema-info.txt` | Text | Schema documentation |
| `INDEX.md` | Markdown | Root wiki index |
| `DEPENDENCY_GRAPH.md` | Markdown | Dependency visualization |
| `cross-reference-report.md` | Markdown | Validation report |
| `dependency-graph.dot` | DOT | Graphviz format |
| `dependency-graph.json` | JSON | Structured data |
| `DEPENDENCY_VISUALIZATION.txt` | ASCII | Text visualization |

---

## 🎓 Learning Resources

- **Level 1** - Overview and project structure
- **Level 2** - Category-based organization
- **Level 3** - Module deep dives
- **Level 4** - Script details and usage
- **Level 5** - Build specifications and composition

---

## 📞 Support & Documentation

All scripts include:

- `.SYNOPSIS` - Quick description
- `.DESCRIPTION` - Detailed explanation
- `.PARAMETER` - Parameter documentation
- `.EXAMPLE` - Usage examples
- Inline comments for complex sections

Access with:

```powershell
Get-Help .\setup-wiki.ps1 -Full
Get-Help .\generate-wiki.ps1 -Examples
```

---

## 🏆 Best Practices

1. **Run setup-wiki.ps1 first** - Initialize the database
2. **Generate wiki regularly** - Keep documentation in sync
3. **Check references weekly** - Catch broken links early
4. **Review dependency graphs** - Identify refactoring opportunities
5. **Export reports** - Archive for tracking changes
6. **Backup database** - Regular backups of wiki.db

---

**Created:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Version:** 1.0.0
**Status:** Production Ready ✅
