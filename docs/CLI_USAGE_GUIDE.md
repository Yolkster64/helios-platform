# HELIOS CLI Usage Guide

## Getting Started

### Installation

#### Windows

```powershell
# Add to PATH or use with full path
helios-cli.exe status

# Using PowerShell module
Import-Module .\HELIOS.CLI.psm1
Get-HeliosStatus
```

#### Linux/macOS

```bash
# Make executable and add to PATH
chmod +x /usr/local/bin/helios-cli
helios-cli status
```

## Common Workflows

### 1. Daily Operational Checks

```bash
# Check system health
helios-cli health --verbose

# Get detailed status
helios-cli status --json

# List running services
helios-cli list services
```

### 2. Deploying an Application

```bash
# Simple deployment
helios-cli deploy --config deployment.json

# With verbose output
helios-cli deploy --config deployment.json --verbose

# Batch deployment
helios-cli --batch deployment-batch.json
```

### 3. Backup and Recovery

```bash
# Create backup
helios-cli backup --path /backups --compress

# List available backups
helios-cli list backups

# Restore from backup
helios-cli restore /backups/backup-20240101.tar.gz --verify
```

### 4. Scaling Services

```bash
# Scale web servers to 5 instances
helios-cli scale web --instances 5

# Scale API servers to 10 instances
helios-cli scale api --instances 10

# List current services
helios-cli list services --json
```

### 5. Managing Configuration

```bash
# Get specific configuration
helios-cli config get api.endpoint

# Set configuration value
helios-cli config set api.timeout 30

# List all configuration
helios-cli config list --json
```

### 6. Monitoring and Watching

```bash
# Watch services for changes
helios-cli watch services --interval 5

# Watch nodes for changes
helios-cli watch nodes

# Get real-time health status
helios-cli health --deep
```

### 7. Scheduling Tasks

```bash
# Schedule daily backup
helios-cli schedule daily-backup --command backup --schedule daily

# Schedule hourly health check
helios-cli schedule hourly-check --command health --schedule hourly

# View scheduled tasks
helios-cli list scheduled-tasks
```

### 8. Executing Scripts

```bash
# Execute deployment script
helios-cli execute ./deploy.sh

# Execute with arguments
helios-cli execute ./script.ps1 --args "--environment production"

# Execute with timeout
helios-cli execute ./long-task.sh --timeout 300
```

## Output Formatting

### JSON Output

```bash
# Get status in JSON format
helios-cli status --json

# Parse JSON with jq
helios-cli status --json | jq '.Status'

# Save to file
helios-cli status --json > status.json
```

### Verbose Output

```bash
# Get detailed output including timing and metadata
helios-cli status --verbose
helios-cli deploy --config app.json --verbose
helios-cli health --verbose
```

### Quiet Mode

```bash
# Suppress all output (useful in scripts)
helios-cli status --quiet
helios-cli deploy --config app.json --quiet && echo "Deployment succeeded"
```

## Advanced Features

### Batch Processing

Create a batch file (`deployment-batch.json`):

```json
{
  "name": "Full Deployment",
  "commands": [
    { "name": "health-check", "command": "health" },
    { "name": "backup", "command": "backup", "options": { "path": "/backups" } },
    { "name": "deploy", "command": "deploy", "options": { "config": "app.json" } }
  ]
}
```

Execute:

```bash
helios-cli --batch deployment-batch.json
helios-cli --batch deployment-batch.json --continue  # Continue on error
```

### Interactive Mode

```bash
# Start interactive CLI
helios-cli -i

# Commands in interactive mode
helios> status
helios> health --verbose
helios> deploy --config app.json
helios> exit
```

### Command History

```bash
# View recent commands
helios-cli history

# View more history
helios-cli history --count 100

# Search history
helios-cli history --search "deploy"
```

## PowerShell Examples

```powershell
# Import the module
Import-Module .\HELIOS.CLI.psm1

# Get status and convert to PowerShell object
$status = Get-HeliosStatus
$status.Status

# Deploy and check results
$result = Invoke-HeliosDeploy -Config "app.json"
if ($result.ExitCode -eq 0) {
    Write-Host "Deployment successful"
} else {
    Write-Host "Deployment failed"
}

# Create backup with PowerShell
$backup = New-HeliosBackup -Path "C:\backups"

# Scale component with PowerShell
Scale-HeliosComponent -Component "web" -Instances 5

# Schedule task
New-HeliosScheduledTask -TaskName "daily-backup" -Command "backup" -Schedule "daily"
```

## Bash/Shell Examples

```bash
#!/bin/bash

# Set error handling
set -e

# Check health before deploying
helios-cli health --timeout 30 || exit 1

# Create backup
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
helios-cli backup --path "/backups/$BACKUP_DATE" --compress

# Deploy
helios-cli deploy --config deployment.json --verbose

# Verify deployment
helios-cli status --json | grep -q "running" && echo "Deployment successful"
```

## Configuration Management

### Create Configuration File

```json
{
  "apiEndpoint": "https://api.helios.local",
  "timeout": 30,
  "retryCount": 3,
  "environment": "production",
  "logging": {
    "level": "info",
    "format": "json"
  }
}
```

### Load Configuration

```bash
# Using environment variable
export HELIOS_CONFIG=/etc/helios/config.json
helios-cli status

# Or inline
helios-cli --config /etc/helios/config.json status
```

## Error Handling

### Handling Errors in Scripts

```bash
#!/bin/bash

# Method 1: Check exit code
helios-cli deploy --config app.json
if [ $? -ne 0 ]; then
    echo "Deployment failed"
    exit 1
fi

# Method 2: Use set -e (exit on error)
set -e
helios-cli health
helios-cli deploy --config app.json
helios-cli status

# Method 3: Trap errors
trap 'echo "Command failed on line $LINENO"' ERR
helios-cli deploy --config app.json
```

### Debugging

```bash
# Get verbose output
helios-cli status --verbose

# Enable debug logging
HELIOS_DEBUG=1 helios-cli deploy --config app.json

# Check command history for errors
helios-cli history --search "error"
```

## Performance Optimization

### Parallel Execution

```bash
# Run multiple commands in parallel
helios-cli status --json &
helios-cli health --json &
helios-cli list services &
wait

# Continue after all complete
helios-cli deploy --config app.json
```

### Timeout Management

```bash
# Set timeout for long-running operation
helios-cli deploy --config app.json --timeout 300

# Use reasonable timeouts for batch operations
helios-cli --batch large-deployment.json --timeout 600
```

### Output to File

```bash
# Write output to file
helios-cli status --json -o status.json
helios-cli deploy --config app.json -o deploy.log --verbose

# Append to log
helios-cli status >> deployment.log 2>&1
```

## Integration Examples

### With Cron

```bash
# /etc/cron.d/helios-maintenance
# Daily backup at 2 AM
0 2 * * * root /usr/local/bin/helios-cli backup --path /backups --compress --quiet

# Hourly health check
0 * * * * root /usr/local/bin/helios-cli health --quiet || /usr/local/bin/notify-admin
```

### With CI/CD

```yaml
# GitHub Actions
- name: Deploy with HELIOS CLI
  run: |
    helios-cli deploy --config deployment.json --environment production --verbose
    helios-cli health --timeout 60
```

### With Kubernetes

```bash
# Deploy Kubernetes manifests through HELIOS
kubectl create configmap helios-deploy --from-file=deployment.json
helios-cli execute helm-deploy.sh --args "--config /mnt/config/deployment.json"
```

## Troubleshooting

### Common Issues

**"Command not found"**

```bash
# Add to PATH
export PATH=$PATH:/usr/local/bin
which helios-cli

# Or use full path
/usr/local/bin/helios-cli status
```

**"Timeout occurred"**

```bash
# Increase timeout
helios-cli deploy --config app.json --timeout 300

# Or check if service is responsive
helios-cli health --verbose
```

**"Connection refused"**

```bash
# Verify endpoint
helios-cli config get api.endpoint

# Test connectivity
curl -v https://api.helios.local/health
```

**"Permission denied"**

```bash
# Make script executable
chmod +x helios-cli.sh

# Check file permissions
ls -la /usr/local/bin/helios-cli
```

## Best Practices

1. **Use JSON output for automation**: `helios-cli status --json`
2. **Set appropriate timeouts**: `--timeout 120` for complex operations
3. **Use quiet mode in production scripts**: `helios-cli deploy --quiet`
4. **Always create backups before deployment**: `helios-cli backup --compress`
5. **Verify health after operations**: `helios-cli health --deep`
6. **Log all operations**: Redirect output to files for audit trail
7. **Use batch files for complex workflows**: `helios-cli --batch workflow.json`
8. **Schedule regular health checks**: `helios-cli schedule`
9. **Keep command history**: Useful for debugging and auditing
10. **Test in development first**: Use `--environment dev` before production

## Resources

- Full Documentation: `/docs/CLI_REFERENCE_NEW.md`
- Issue Tracker: https://github.com/HELIOS/helios-platform/issues
- Community Forum: https://helios.local/community
