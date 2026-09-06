# HELIOS Platform Wiki Database Schema

All files, metadata, cross-references, and notes tracked in SQLite database.

## Database Structure

### `files` Table

- `id` - Unique identifier
- `path` - Full file path
- `category` - Module category (security, gui, tools, etc)
- `type` - script, config, doc, template
- `purpose` - What this file does
- `complexity` - basic, intermediate, advanced, expert
- `status` - draft, testing, production
- `version` - File version
- `created_date`, `modified_date` - Timestamps

### `categories` Table

- Hierarchical organization
- Parent-child relationships
- Category descriptions

### `cross_references` Table

- `reference_type` - depends_on, used_by, related_to, coordinates_with
- `conflict_potential` - 0.0-1.0 AI-assessed conflict risk
- `ai_coordination_needed` - boolean flag
- Links source and target files

### `notes` Table

- Team notes and adaptations at file level
- `change_type` - adaptation, bug_fix, improvement, note
- `impact_level` - low, medium, high
- `related_files` - Other files affected
- Date-stamped with author

### `metadata` Table

- Flexible key-value store
- Extra data per file
- Tags, dependencies, etc

### `dependencies` Table

- Module dependencies
- External dependencies
- Version constraints
- System requirements

## Usage

```sql
-- Find all files in security category
SELECT * FROM files WHERE category = 'security';

-- Find cross-references
SELECT * FROM cross_references 
WHERE source_file_id = ? AND reference_type = 'depends_on';

-- Find recent changes
SELECT * FROM notes 
WHERE file_id = ? ORDER BY created_date DESC;

-- AI conflict detection
SELECT * FROM cross_references 
WHERE conflict_potential > 0.5;
```

## Initialization

Database automatically initialized by `setup-wiki.ps1`
