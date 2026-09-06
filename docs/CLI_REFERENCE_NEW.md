# HELIOS CLI Reference Documentation

## Overview

The HELIOS Command-Line Interface (CLI) is a comprehensive tool for managing the HELIOS Platform from the command line. It supports automation, batch processing, scheduling, and interactive usage.

## Installation

### Windows

1. Download the CLI executable
2. Add to PATH or use directly: `helios-cli.exe`
3. Or use PowerShell module:

   ```powershell
   Import-Module .\HELIOS.CLI.psm1
   ```

### Linux/macOS

1. Copy `helios-cli.sh` to `/usr/local/bin/helios-cli`
2. Make executable: `chmod +x /usr/local/bin/helios-cli`
3. Use: `helios-cli [command]`

## Quick Start

### Check Status

```bash
helios-cli status
helios-cli status --json
helios-cli status --verbose
```

### Check Health

```bash
helios-cli health
helios-cli health --verbose
helios-cli health --json
```

### Deploy

```bash
helios-cli deploy --config deployment.json
helios-cli deploy --config deployment.json --verbose
```

## Commands

### 1. Deploy

Deploy components or applications to the platform.

**Usage:**

```bash
helios-cli deploy [OPTIONS]
```

**Options:**

- `--config FILE`: Path to deployment configuration file (required)
- `--environment ENV`: Target environment (dev, staging, prod)
- `--version VERSION`: Specific version to deploy
- `--force`: Force deployment without confirmation

**Examples:**

```bash
helios-cli deploy --config app.json
helios-cli deploy --config app.json --environment production --force
```

### 2. Config

Manage platform configuration.

**Usage:**

```bash
helios-cli config <ACTION> [KEY] [VALUE]
```

**Actions:**

- `get [KEY]`: Get configuration value
- `set KEY VALUE`: Set configuration value
- `list`: List all configuration
- `reset`: Reset to defaults

**Examples:**

```bash
helios-cli config get api.endpoint
helios-cli config set api.timeout 30
helios-cli config list
helios-cli config list --json
```

### 3. Status

Display platform status.

**Usage:**

```bash
helios-cli status [OPTIONS]
```

**Examples:**

```bash
helios-cli status
helios-cli status --json
helios-cli status --verbose
```

### 4. Health

Check platform health and system metrics.

**Usage:**

```bash
helios-cli health [OPTIONS]
```

**Options:**

- `--checks`: Run specific health checks
- `--deep`: Perform deep health checks
- `--json`: Output as JSON

**Examples:**

```bash
helios-cli health
helios-cli health --deep
helios-cli health --json
```

### 5. Restart

Restart platform services or components.

**Usage:**

```bash
helios-cli restart [SERVICE]
```

**Services:**

- `all`: Restart all services
- `api`: Restart API service
- `worker`: Restart worker service
- `database`: Restart database

**Examples:**

```bash
helios-cli restart all
helios-cli restart api
```

### 6. Scale

Scale components up or down.

**Usage:**

```bash
helios-cli scale <COMPONENT> --instances COUNT
```

**Components:**

- `web`: Web servers
- `api`: API servers
- `worker`: Worker processes
- `cache`: Cache nodes

**Examples:**

```bash
helios-cli scale web --instances 5
helios-cli scale worker --instances 10
```

### 7. Backup

Create backups of platform data.

**Usage:**

```bash
helios-cli backup [OPTIONS]
```

**Options:**

- `--path DIR`: Backup destination directory
- `--incremental`: Create incremental backup
- `--compress`: Compress backup
- `--include RESOURCES`: Specific resources to backup

**Examples:**

```bash
helios-cli backup --path /backups
helios-cli backup --path /backups --compress --incremental
helios-cli backup --include "database,files" --path /backups
```

### 8. Restore

Restore from backup.

**Usage:**

```bash
helios-cli restore <BACKUP_FILE> [OPTIONS]
```

**Options:**

- `--verify`: Verify backup before restore
- `--point-in-time TIME`: Restore to specific point in time
- `--test`: Test restore without applying

**Examples:**

```bash
helios-cli restore backup-20240101.tar.gz
helios-cli restore backup-20240101.tar.gz --verify
helios-cli restore backup-20240101.tar.gz --test
```

### 9. List

List platform resources.

**Usage:**

```bash
helios-cli list <RESOURCE_TYPE> [OPTIONS]
```

**Resource Types:**

- `services`: Deployed services
- `components`: Platform components
- `nodes`: Cluster nodes
- `deployments`: Active deployments
- `backups`: Available backups

**Options:**

- `--filter CONDITION`: Filter results
- `--sort FIELD`: Sort by field
- `--json`: Output as JSON

**Examples:**

```bash
helios-cli list services
helios-cli list services --json
helios-cli list deployments --filter "status=running"
```

### 10. Watch

Watch resources for changes in real-time.

**Usage:**

```bash
helios-cli watch <RESOURCE> [OPTIONS]
```

**Options:**

- `--interval SEC`: Update interval
- `--filter CONDITION`: Filter watched resources

**Examples:**

```bash
helios-cli watch services
helios-cli watch nodes --interval 5
```

### 11. Execute

Execute scripts or commands.

**Usage:**

```bash
helios-cli execute <SCRIPT_FILE> [OPTIONS]
```

**Options:**

- `--args ARGS`: Pass arguments to script
- `--timeout SEC`: Script timeout
- `--wait`: Wait for completion

**Examples:**

```bash
helios-cli execute deploy.sh
helios-cli execute script.ps1 --args "--verbose"
```

### 12. Schedule

Schedule tasks for execution.

**Usage:**

```bash
helios-cli schedule <TASK_NAME> --command COMMAND --schedule SCHEDULE
```

**Schedule Options:**

- `hourly`: Every hour
- `daily`: Every day
- `weekly`: Every week
- `monthly`: Every month
- Cron expressions: `0 2 * * *` (2 AM daily)

**Examples:**

```bash
helios-cli schedule backup --command backup --schedule daily
helios-cli schedule health-check --command health --schedule hourly
helios-cli schedule cleanup --command cleanup --schedule "0 3 * * *"
```

## Global Options

All commands support these global options:

### Output Options

- `-h, --help`: Show help for command
- `-v, --version`: Show CLI version
- `-q, --quiet`: Suppress output
- `--verbose`: Verbose output
- `-j, --json`: Output in JSON format
- `-o, --output FILE`: Write output to file

### Execution Options

- `--timeout SEC`: Set command timeout (default: 30 seconds)
- `--async`: Run asynchronously
- `--retry COUNT`: Retry on failure

### Example Usage

```bash
helios-cli status --json > status.json
helios-cli deploy --config app.json --verbose --output deploy.log
helios-cli health --timeout 60
```

## Batch Processing

Execute multiple commands from a JSON batch file.

**Usage:**

```bash
helios-cli --batch batch.json [--continue]
```

**Batch File Format:**

```json
{
  "name": "Deployment Batch",
  "description": "Deploy and verify services",
  "commands": [
    {
      "name": "Pre-deployment checks",
      "command": "health",
      "options": {
        "checks": "critical"
      }
    },
    {
      "name": "Deploy application",
      "command": "deploy",
      "options": {
        "config": "app.json"
      }
    },
    {
      "name": "Post-deployment verification",
      "command": "health",
      "options": {
        "checks": "all"
      }
    }
  ]
}
```

**Options:**

- `--continue`: Continue on error (default: stop on first error)

## Interactive Mode

Launch interactive CLI session.

**Usage:**

```bash
helios-cli -i
# or
helios-cli --interactive
```

**Example:**

```
$ helios-cli -i
HELIOS CLI Interactive Mode. Type 'exit' to quit, 'help' for commands.
helios> status
helios> deploy --config app.json
helios> exit
```

## Command History

Commands are automatically tracked in `%APPDATA%/HELIOS/history.json`.

**View History:**

```bash
helios-cli history
helios-cli history --count 100
helios-cli history --search "deploy"
```

## PowerShell Integration

### Available Cmdlets

```powershell
Get-HeliosStatus              # Get platform status
Get-HeliosHealth              # Get health information
Invoke-HeliosDeploy           # Deploy application
Invoke-HeliosConfig           # Manage configuration
Restart-HeliosService         # Restart services
Scale-HeliosComponent         # Scale components
New-HeliosBackup              # Create backup
Restore-HeliosBackup          # Restore from backup
Get-HeliosResource            # List resources
Invoke-HeliosScript           # Execute script
New-HeliosScheduledTask       # Schedule task
Get-HeliosHistory             # Get command history
```

### Examples

```powershell
# Import module
Import-Module .\HELIOS.CLI.psm1

# Get status
Get-HeliosStatus

# Deploy application
Invoke-HeliosDeploy -Config "deployment.json"

# Scale component
Scale-HeliosComponent -Component "web" -Instances 5

# Create backup
New-HeliosBackup -Path "C:\backups"

# Schedule task
New-HeliosScheduledTask -TaskName "daily-backup" -Command "backup" -Schedule "daily"
```

## Exit Codes

- `0`: Success
- `1`: General error
- `2`: Command not found
- `3`: Invalid arguments
- `4`: Timeout
- `5`: Configuration error

## Error Handling

### Common Errors

**"No command specified"**

- Solution: Provide a command, e.g., `helios-cli status`

**"Unknown command"**

- Solution: Check command spelling, use `helios-cli help`

**"Configuration error"**

- Solution: Verify configuration files and paths

**"Timeout"**

- Solution: Increase timeout with `--timeout` option

## Configuration

CLI configuration is stored in `%APPDATA%/HELIOS/config.json` on Windows or `~/.config/HELIOS/config.json` on Linux/macOS.

**Example Configuration:**

```json
{
  "apiEndpoint": "https://api.helios.local",
  "timeout": 30,
  "retryCount": 3,
  "outputFormat": "default",
  "logLevel": "info"
}
```

## Performance Tips

1. **Use JSON output for parsing**: `--json`
2. **Use batch mode for multiple operations**: `--batch`
3. **Run long operations asynchronously**: `--async`
4. **Increase timeout for slow operations**: `--timeout 120`
5. **Use quiet mode in scripts**: `--quiet`

## Troubleshooting

### Debug Output

```bash
helios-cli status --verbose
```

### Show Full Error

```bash
helios-cli deploy --config app.json --verbose
```

### Check Logs

```bash
helios-cli history --search "error"
```

## Advanced Usage

### Piping Output

```bash
helios-cli list services --json | jq '.items[] | .name'
```

### Conditional Execution

```bash
helios-cli health --json && helios-cli deploy --config app.json
```

### Parallel Execution

```bash
helios-cli status --async &
helios-cli health --async &
wait
```

## Support and Documentation

- Documentation: https://helios.local/docs
- Issue Tracker: https://github.com/HELIOS/helios-platform/issues
- Community: https://helios.local/community
