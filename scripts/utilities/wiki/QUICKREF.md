# Wiki Utilities - Quick Reference

## File Locations

```
C:\Users\ADMIN\helios-platform\
├── docs/
│   ├── wiki.db.sql           (Schema definition)
│   ├── wiki.db               (Generated - SQLite database)
│   ├── wiki/                 (Generated - Markdown files)
│   │   ├── INDEX.md          (Root index)
│   │   ├── level2/           (Category level)
│   │   ├── level4/           (File level)
│   │   ├── DEPENDENCY_GRAPH.md
│   │   ├── dependencies.dot
│   │   ├── dependencies.json
│   │   └── cross-reference-report.md
│   └── [other docs]
└── scripts/utilities/wiki/
    ├── setup-wiki.ps1        (Initialize database)
    ├── generate-wiki.ps1     (Generate documentation)
    ├── wiki-search.ps1       (Query database)
    ├── check-cross-references.ps1
    ├── map-dependencies.ps1
    ├── wiki-orchestrate.ps1  (Master coordinator)
    └── README.md             (Full documentation)
```

## Common Commands

### Initialize

```powershell
cd C:\Users\ADMIN\helios-platform\scripts\utilities\wiki
.\wiki-orchestrate.ps1 -Action init
```

### Full Regeneration

```powershell
.\wiki-orchestrate.ps1 -Action full
```

### Quick Search

```powershell
.\wiki-search.ps1 -Query "keyword"
.\wiki-search.ps1 -SearchType orphaned
.\wiki-search.ps1 -SearchType conflicts
```

### Validate

```powershell
.\check-cross-references.ps1 -GenerateReport
```

### Map Dependencies

```powershell
.\map-dependencies.ps1 -OutputFormat all
```

## Database Tables

| Table | Records What |
|-------|--------------|
| `files` | Every documented file |
| `categories` | Documentation hierarchy |
| `cross_references` | File-to-file links |
| `dependencies` | Component relationships |
| `notes` | Team annotations |
| `metadata` | Key-value file info |
| `builds` | Build configurations |
| `snippets` | Reusable code |

## Complexity Levels

- simple (0-50 lines)
- moderate (50-200 lines)
- complex (200-500 lines)
- advanced (500+ lines)

## Build Inclusion Types

- standard (always included)
- optional (include if specified)
- enterprise (enterprise-only)
- internal (internal-only)

## Dependency Types

- hard (must have)
- soft (normally used)
- optional (may use)
- conditional (context-specific)

## Search Types

| Type | Usage |
|------|-------|
| keyword | .\wiki-search.ps1 -Query "term" |
| category | .\wiki-search.ps1 -SearchType category -Query "Scripts" |
| complexity | .\wiki-search.ps1 -Query "advanced" |
| orphaned | .\wiki-search.ps1 -SearchType orphaned |
| conflicts | .\wiki-search.ps1 -SearchType conflicts |
| dependencies | .\wiki-search.ps1 -SearchType dependencies -Query "path" |
| sql | .\wiki-search.ps1 -SearchType sql -Query "SELECT ..." |

## Output Formats

- **table** - Terminal display (default)
- **json** - JSON export
- **csv** - Spreadsheet format
- **markdown** - Documentation
- **dot** - Graph visualization
- **html** - Web browsable

## Documentation Levels

```
Level 1: Project Overview (INDEX.md)
  ├─ Level 2: Categories (docs/wiki/level2/*/INDEX.md)
  │   ├─ Level 3: Subcategories
  │   │   ├─ Level 4: Individual Files (docs/wiki/level4/*.md)
  │   │   │   └─ Level 5: Inline Details
```

## Tips & Tricks

### Search for high-complexity files

```powershell
.\wiki-search.ps1 -SearchType complexity -Query "advanced"
```

### Find files with no documentation

```powershell
.\wiki-search.ps1 -SearchType sql -Query `
  "SELECT * FROM files WHERE documented=0"
```

### Export to CSV

```powershell
.\wiki-search.ps1 -SearchType orphaned -Format csv
```

### View dependency graph in browser

```powershell
# Generate DOT file, then use online viewer:
# http://www.webgraphviz.com/
.\map-dependencies.ps1 -OutputFormat dot
```

### Circular dependency details

```powershell
.\check-cross-references.ps1 -CheckCircular -GenerateReport
# Check: docs/cross-reference-report.md
```

### Update after code changes (incremental)

```powershell
.\wiki-orchestrate.ps1 -Action generate -Incremental
.\check-cross-references.ps1 -ValidateFiles
```

## Metadata Example

Create `script.ps1.meta.json`:

```json
{
  "category": "Scripts/Build",
  "tags": ["build", "automation"],
  "dependencies": ["other-script.ps1"],
  "complexity": "advanced",
  "status": "active",
  "maintainer": "team@example.com"
}
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Database locked | Run: `.\setup-wiki.ps1 -ForceReset` |
| SQLite not found | Install: `choco install sqlite` |
| No results | Check query syntax: `.\wiki-search.ps1 -SearchType sql -Query "SELECT COUNT(*) FROM files"` |
| Broken references | Run: `.\check-cross-references.ps1 -GenerateReport` |
| Circular deps | Check: `docs/cross-reference-report.md` |

## Integration Points

### Build System

- Get components: `.\wiki-search.ps1 -SearchType sql -Query "SELECT * FROM files WHERE build_inclusion='standard'"`

### CI/CD Pipeline

- Regenerate: `.\wiki-orchestrate.ps1 -Action full`

### Documentation Sites

- Output: `docs/wiki/` (Markdown files)

### Analysis Tools

- Export: `.\wiki-search.ps1 -Format json` or `-Format csv`

---

**For full documentation:** See `README.md`
