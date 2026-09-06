# Helios Platform Wiki Generation Utilities

Comprehensive wiki management system for the Helios Platform, providing automated documentation generation, database-backed search, dependency mapping, and cross-reference validation.

## 📋 Overview

The wiki system consists of 6 integrated PowerShell utilities that work together to maintain living documentation at 5 levels:

1. **Level 1**: Project overview
2. **Level 2**: Category/component groups
3. **Level 3**: Subcategory/system details
4. **Level 4**: Individual file documentation
5. **Level 5**: Inline code details

## 📁 Files

### Core Utilities

| Script | Purpose | Key Functions |
|--------|---------|----------------|
| **setup-wiki.ps1** | Database initialization | Creates SQLite schema, indexes, root categories |
| **generate-wiki.ps1** | Content generation | Scans files, extracts metadata, generates markdown/HTML |
| **wiki-search.ps1** | Database queries | Keyword, category, complexity, orphaned file search |
| **check-cross-references.ps1** | Link validation | Validates references, finds conflicts, detects cycles |
| **map-dependencies.ps1** | Graph generation | Creates DOT/markdown/JSON dependency graphs |
| **wiki-orchestrate.ps1** | Master coordinator | Runs full pipelines or individual tasks |

### Database

| File | Purpose |
|------|---------|
| **wiki.db.sql** | SQLite schema (9 tables, 15+ indexes, 5 views) |
| **wiki.db** | Generated database (created by setup-wiki.ps1) |

## 🚀 Quick Start

### 1. Initialize Database

```powershell
# Create fresh database with schema and root categories
cd C:\Users\ADMIN\helios-platform\scripts\utilities\wiki
.\setup-wiki.ps1

# Or with force reset if database already exists
.\setup-wiki.ps1 -ForceReset
```

### 2. Generate Documentation

```powershell
# Full generation with HTML and database updates
.\generate-wiki.ps1

# Custom source directories
.\generate-wiki.ps1 -SourceDirs @('scripts', 'configs')

# Generate HTML only
.\generate-wiki.ps1 -GenerateHtml
```

### 3. Validate References

```powershell
# Full validation with report
.\check-cross-references.ps1 -ValidateFiles -CheckCircular -GenerateReport

# Auto-fix broken references
.\check-cross-references.ps1 -AutoFix
```

### 4. Map Dependencies

```powershell
# Generate all formats (markdown, DOT, JSON)
.\map-dependencies.ps1 -OutputFormat all

# Just markdown graph
.\map-dependencies.ps1 -OutputFormat markdown

# Include optional dependencies
.\map-dependencies.ps1 -IncludeOptional -MaxDepth 10
```

### 5. Search Wiki

```powershell
# Keyword search
.\wiki-search.ps1 -Query "authentication" -SearchType keyword

# Find orphaned files
.\wiki-search.ps1 -SearchType orphaned

# Category filter
.\wiki-search.ps1 -SearchType category -Category "Scripts"

# Find conflicts
.\wiki-search.ps1 -SearchType conflicts

# Custom SQL
.\wiki-search.ps1 -SearchType sql -Query "SELECT * FROM files WHERE complexity='advanced'"
```

### 6. Full Orchestration

```powershell
# Complete system regeneration
.\wiki-orchestrate.ps1 -Action full

# Individual actions
.\wiki-orchestrate.ps1 -Action init
.\wiki-orchestrate.ps1 -Action generate
.\wiki-orchestrate.ps1 -Action validate
.\wiki-orchestrate.ps1 -Action map

# Search
.\wiki-orchestrate.ps1 -Action search -SearchQuery "build"
```

## 📊 Database Schema

### Tables

#### `files` (Master Registry)

- Tracks all documented files
- Fields: path, name, category, type, purpose, complexity, status, version, build_inclusion
- Primary index: path (UNIQUE)

#### `categories` (Hierarchical)

- 5-level documentation structure
- Fields: name, parent_id, level, description, icon, order_index
- Enables breadcrumb navigation

#### `cross_references` (Link Graph)

- File-to-file and file-to-concept references
- Fields: source_file_id, target_file_id, reference_type, conflict_potential
- Types: depends_on, used_by, related, extends, implements, conflicts

#### `dependencies` (Dependency Graph)

- Component relationships
- Fields: source_id, target_id, dependency_type, is_circular, depth
- Types: hard, soft, optional, conditional

#### `notes` (Annotations)

- Team change history and observations
- Fields: file_id, note_type, content, author, priority, resolved
- Types: observation, warning, todo, deprecated, optimization, security, performance

#### `metadata` (Key-Value Store)

- Additional file information
- Flexible key-value pairs with typing

#### `builds` (Build Registry)

- Build configuration tracking
- Includes build components junction table
- Fields: name, environment, framework, include_optional/enterprise

#### `snippets` (Code Registry)

- Reusable code with compression
- Fields: name, category, language, code, description, tags, usage_count

### Indexes (15 total)

Optimized for common queries:

- `idx_files_*` - Category, type, status, complexity, build, modified
- `idx_categories_*` - Parent, level
- `idx_xref_*` - Source, target, type, conflict
- `idx_notes_*` - File, type, priority
- `idx_metadata_*` - File, key
- `idx_deps_*` - Source, target, circular
- `idx_snippets_*` - Category, language, tags

### Views (5 total)

Pre-built queries for common operations:

- `active_files` - All active, documented files
- `documented_files` - Sorted by complexity
- `undocumented_files` - Missing documentation
- `orphaned_files` - No references
- `circular_dependencies` - Circular refs by depth

## 📝 Metadata Extraction

### PowerShell Script Headers

Extracts from comment blocks:

```powershell
<#
.SYNOPSIS
    One-line description

.DESCRIPTION
    Detailed description

.PARAMETER ParamName
    Parameter description

.EXAMPLE
    Usage example

.NOTES
    Additional notes
#>
```

### Meta JSON Files

Companion `.meta.json` files for additional metadata:

```json
{
  "category": "Scripts/Utilities",
  "tags": ["automation", "admin"],
  "dependencies": ["other-script.ps1"],
  "complexity": "advanced",
  "status": "active"
}
```

## 🔍 Search Capabilities

### Search Types

| Type | Description | Example |
|------|-------------|---------|
| **keyword** | Full-text search in name/purpose | `wiki-search.ps1 -Query "auth"` |
| **category** | Filter by category | `wiki-search.ps1 -SearchType category -Category "Scripts"` |
| **complexity** | Filter by complexity level | `wiki-search.ps1 -Query "complex"` |
| **build** | Find in build configurations | `wiki-search.ps1 -SearchType build -Query "standard"` |
| **orphaned** | Find files with no references | `wiki-search.ps1 -SearchType orphaned` |
| **conflicts** | Find conflicting dependencies | `wiki-search.ps1 -SearchType conflicts` |
| **dependencies** | Trace dependency chains | `wiki-search.ps1 -Query "path/to/file.ps1"` |
| **sql** | Execute custom SQL | `wiki-search.ps1 -SearchType sql` |

### Output Formats

- **table** - Pretty-printed table (default)
- **json** - JSON format
- **csv** - Comma-separated values

## 📈 Dependency Mapping

### Output Formats

#### Markdown (`DEPENDENCY_GRAPH.md`)

- ASCII diagrams
- Statistics and summaries
- High-degree components
- Circular dependency warnings

#### DOT Format (`dependencies.dot`)

- Graph visualization format
- Can be converted to PNG/PDF with Graphviz
- Color-coded nodes (root, leaf, middle)
- Circular dependencies marked

#### JSON (`dependencies.json`)

- Machine-readable graph data
- Full metadata preserved
- Import into tools/analyzers

### Generation

```powershell
# Generate all formats
.\map-dependencies.ps1 -OutputFormat all

# With optional dependencies, max depth 10
.\map-dependencies.ps1 -IncludeOptional -MaxDepth 10

# Just markdown for quick view
.\map-dependencies.ps1 -OutputFormat markdown
```

## ✅ Cross-Reference Validation

### Checks Performed

1. **File Existence** - Verify all referenced files exist
2. **Circular Dependencies** - Detect cycles (with depth)
3. **Conflict Detection** - Flag conflicting dependencies
4. **Path Validation** - Check relative paths
5. **Link Status** - Mark validated/unvalidated

### Report Generation

```powershell
# Generate detailed HTML report
.\check-cross-references.ps1 -GenerateReport

# Includes:
# - Broken reference list
# - Conflict matrix
# - Circular dependency chains
# - Recommendations
```

## 🔧 Integration

### With Build System

Connect to build configuration:

```powershell
# Register build components in database
# Then use in build targeting:
.\map-dependencies.ps1 | ForEach-Object {
    # Use for build selection logic
}
```

### With Documentation Generation

```powershell
# Full pipeline
.\wiki-orchestrate.ps1 -Action full

# Incremental update after code changes
.\wiki-orchestrate.ps1 -Action generate -Incremental
.\wiki-orchestrate.ps1 -Action validate
```

### Scheduled Regeneration

Add to Windows Task Scheduler or build pipeline:

```powershell
# Daily regeneration at 2 AM
Invoke-Expression "C:\...\wiki-orchestrate.ps1 -Action full"
```

## 📊 Statistics & Reporting

### Database Statistics

```powershell
.\wiki-search.ps1  # Shows stats at end
```

### Validation Report

```powershell
.\check-cross-references.ps1 -GenerateReport
# Creates: cross-reference-report.md
```

### Dependency Report

```powershell
.\map-dependencies.ps1 -OutputFormat all
# Creates:
#   - DEPENDENCY_GRAPH.md
#   - dependencies.dot
#   - dependencies.json
```

## 🎯 Best Practices

1. **Regular Updates**
   - Run `wiki-orchestrate.ps1 -Action full` weekly
   - Use incremental updates for frequent changes

2. **Metadata Maintenance**
   - Add `.meta.json` files with additional context
   - Keep complexity ratings accurate
   - Update status flags (active/deprecated/archived)

3. **Cross-References**
   - Link related files explicitly
   - Mark conflicts to prevent integration issues
   - Review circular dependency warnings

4. **Documentation Levels**
   - Use consistent naming conventions
   - Maintain category hierarchy
   - Update INDEX.md at each level

5. **Build Integration**
   - Register build configurations
   - Track component inclusion (standard/optional/enterprise)
   - Update on major architectural changes

## 🔐 Build Configurations

Track build variations:

```powershell
# Database records:
# - standard build (core components)
# - enterprise build (+ optional modules)
# - minimal build (essential only)
# - development build (+ internal tools)
```

Database queries for build selection:

```powershell
# Find all files in standard build
.\wiki-search.ps1 -SearchType sql -Query `
  "SELECT * FROM files WHERE build_inclusion='standard'"
```

## 📚 Complexity Levels

- **simple** - <50 lines, basic functionality
- **moderate** - 50-200 lines, some logic
- **complex** - 200-500 lines, multiple features
- **advanced** - >500 lines, complex algorithms

## 🐛 Troubleshooting

### Database Locked

```powershell
# Reset database
.\setup-wiki.ps1 -ForceReset

# Verify SQLite installed
sqlite3 --version
```

### Broken References Not Found

```powershell
# Update validation cache
.\check-cross-references.ps1 -ValidateFiles

# Check file paths are relative to project root
```

### Circular Dependencies False Positives

```powershell
# Review conflict reports
.\check-cross-references.ps1 -GenerateReport

# Analyze manually
.\map-dependencies.ps1 -OutputFormat dot
```

## 📞 Support

For issues or enhancements:

1. Check database with: `.\wiki-search.ps1 -SearchType sql`
2. Review reports: `docs/cross-reference-report.md`
3. Check generated graphs: `docs/DEPENDENCY_GRAPH.md`

## 📄 License & Attribution

Part of the Helios Platform project.

---

**Last Updated**: 2024  
**Version**: 1.0  
**Maintenance**: scripts/utilities/wiki/
