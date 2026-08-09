<#
.SYNOPSIS
Monitor and check execution status of build agents

.DESCRIPTION
Displays real-time status of running or recently completed agent executions,
including detailed information about each agent, failures, and logs.

.PARAMETER Status
Show current status (default)

.PARAMETER Details
Show detailed information about specific agent

.PARAMETER AgentId
Agent number to show details for (1-11)

.PARAMETER FollowLogs
Follow live logs for an agent

.PARAMETER ShowFailed
Show only failed agents

.PARAMETER ShowRunning
Show only running agents

.EXAMPLE
.\check-agent-status.ps1
.\check-agent-status.ps1 -ShowFailed
.\check-agent-status.ps1 -Details -AgentId 3
.\check-agent-status.ps1 -FollowLogs -AgentId 5

.NOTES
Status information is read from orchestrator_status.json
#>

param(
    [switch]$Status,
    [switch]$Details,
    [int]$AgentId = 0,
    [switch]$FollowLogs,
    [switch]$ShowFailed,
    [switch]$ShowRunning
)

$ErrorActionPreference = "Continue"

# Define paths
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommandPath
$BaseDir = Split-Path -Parent $ScriptRoot
$ConfigPath = Join-Path $BaseDir "config"
$LogsPath = Join-Path $BaseDir "logs"
$TempPath = Join-Path $BaseDir "temp"
$StatusFile = Join-Path $TempPath "orchestrator_status.json"

# Load status
function Get-OrchestratorStatus {
    if (-not (Test-Path $StatusFile)) {
        Write-Host "No status file found. No orchestration running." -ForegroundColor Yellow
        return $null
    }
    
    return Get-Content $StatusFile | ConvertFrom-Json
}

# Display status overview
function Show-StatusOverview {
    $status = Get-OrchestratorStatus
    
    if ($null -eq $status) {
        return
    }
    
    Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ BUILD AGENT ORCHESTRATION STATUS                     ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $startTime = [datetime]::Parse($status.StartTime)
    $duration = if ($status.EndTime) {
        $endTime = [datetime]::Parse($status.EndTime)
        $endTime - $startTime
    }
    else {
        (Get-Date) - $startTime
    }
    
    Write-Host "`nOverall Status: " -NoNewline -ForegroundColor White
    $color = @{"Success" = "Green"; "Failed" = "Red"; "In Progress" = "Yellow"; "Partial Failure" = "Yellow"}
    Write-Host $status.Status -ForegroundColor $color[$status.Status]
    
    Write-Host "Start Time:    $startTime" -ForegroundColor Gray
    if ($status.EndTime) {
        Write-Host "End Time:      $([datetime]::Parse($status.EndTime))" -ForegroundColor Gray
    }
    Write-Host "Duration:      $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Gray
    
    # Summary
    $completed = @($status.Agents.PSObject.Properties | Where-Object { $_.Value.Status -eq "Completed" }).Count
    $running = @($status.Agents.PSObject.Properties | Where-Object { $_.Value.Status -eq "Running" }).Count
    $failed = @($status.Agents.PSObject.Properties | Where-Object { $_.Value.Status -eq "Failed" }).Count
    $skipped = $status.SkippedAgents.Count
    
    Write-Host "`n╔════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ EXECUTION SUMMARY              ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ Completed:  $($completed.ToString().PadLeft(3)) agents       ║" -ForegroundColor Green
    Write-Host "║ Running:    $($running.ToString().PadLeft(3)) agents       ║" -ForegroundColor Yellow
    Write-Host "║ Failed:     $($failed.ToString().PadLeft(3)) agents       ║" -ForegroundColor Red
    Write-Host "║ Skipped:    $($skipped.ToString().PadLeft(3)) agents       ║" -ForegroundColor Gray
    Write-Host "╚════════════════════════════════╝" -ForegroundColor Cyan
    
    # Agent details
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ AGENT EXECUTION DETAILS                                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    foreach ($prop in $status.Agents.PSObject.Properties | Sort-Object Name) {
        $agent = $prop.Value
        $agentName = $prop.Name
        
        $statusIcon = switch ($agent.Status) {
            "Completed" { "✓" }
            "Running" { "►" }
            "Failed" { "✗" }
            default { "○" }
        }
        
        $color = switch ($agent.Status) {
            "Completed" { "Green" }
            "Running" { "Yellow" }
            "Failed" { "Red" }
            default { "Gray" }
        }
        
        Write-Host "$statusIcon ${agentName}: " -NoNewline -ForegroundColor $color
        Write-Host $agent.Status -ForegroundColor $color
        
        if ($agent.Status -eq "Failed" -and $agent.Error) {
            Write-Host "  └─ Error: $($agent.Error)" -ForegroundColor Red
        }
    }
    
    if ($status.FailedAgents.Count -gt 0) {
        Write-Host "`nFailed Agents: " -ForegroundColor Red
        $status.FailedAgents | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor Red
        }
    }
    
    if ($status.RolledBackAgents.Count -gt 0) {
        Write-Host "`nRolled Back Agents: " -ForegroundColor Yellow
        $status.RolledBackAgents | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor Yellow
        }
    }
}

# Show failed agents
function Show-FailedAgents {
    $status = Get-OrchestratorStatus
    
    if ($null -eq $status -or $status.FailedAgents.Count -eq 0) {
        Write-Host "No failed agents." -ForegroundColor Green
        return
    }
    
    Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║ FAILED AGENTS                                        ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Red
    
    foreach ($agent in $status.FailedAgents) {
        $agentStatus = $status.Agents.$agent
        Write-Host "`n$agent" -ForegroundColor Red
        Write-Host "  Error: $($agentStatus.Error)" -ForegroundColor Red
        Write-Host "  Log: $($agentStatus.LogFile)" -ForegroundColor Gray
    }
}

# Show running agents
function Show-RunningAgents {
    $status = Get-OrchestratorStatus
    
    if ($null -eq $status) {
        return
    }
    
    $running = $status.Agents.PSObject.Properties | Where-Object { $_.Value.Status -eq "Running" }
    
    if ($running.Count -eq 0) {
        Write-Host "No agents currently running." -ForegroundColor Green
        return
    }
    
    Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║ RUNNING AGENTS                                       ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    foreach ($prop in $running) {
        $agent = $prop.Value
        $agentName = $prop.Name
        $startTime = [datetime]::Parse($agent.StartTime)
        $elapsed = (Get-Date) - $startTime
        
        Write-Host "`n$agentName" -ForegroundColor Yellow
        Write-Host "  Running for: $($elapsed.Hours)h $($elapsed.Minutes)m $($elapsed.Seconds)s" -ForegroundColor Gray
        Write-Host "  Log: $($agent.LogFile)" -ForegroundColor Gray
    }
}

# Show agent details
function Show-AgentDetails {
    param([int]$AgentId)
    
    if ($AgentId -lt 1 -or $AgentId -gt 11) {
        Write-Host "Invalid agent ID. Must be between 1 and 11." -ForegroundColor Red
        return
    }
    
    $status = Get-OrchestratorStatus
    if ($null -eq $status) {
        return
    }
    
    $agentName = "agent-$AgentId"
    $agent = $status.Agents.$agentName
    
    if ($null -eq $agent) {
        Write-Host "Agent $agentName not found in status." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ AGENT $agentName DETAILS" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nStatus: " -NoNewline -ForegroundColor White
    $color = switch ($agent.Status) {
        "Completed" { "Green" }
        "Running" { "Yellow" }
        "Failed" { "Red" }
        default { "Gray" }
    }
    Write-Host $agent.Status -ForegroundColor $color
    
    if ($agent.StartTime) {
        Write-Host "Start Time:  $([datetime]::Parse($agent.StartTime))" -ForegroundColor Gray
    }
    if ($agent.EndTime) {
        $start = [datetime]::Parse($agent.StartTime)
        $end = [datetime]::Parse($agent.EndTime)
        $duration = $end - $start
        Write-Host "End Time:    $end" -ForegroundColor Gray
        Write-Host "Duration:    $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Gray
    }
    
    if ($agent.Error) {
        Write-Host "Error:       $($agent.Error)" -ForegroundColor Red
    }
    
    if ($agent.LogFile) {
        Write-Host "Log File:    $($agent.LogFile)" -ForegroundColor Gray
        if (Test-Path $agent.LogFile) {
            Write-Host "`nLast 20 lines of log:" -ForegroundColor Cyan
            Write-Host "────────────────────────────────────────────────────" -ForegroundColor Gray
            Get-Content $agent.LogFile | Select-Object -Last 20 | ForEach-Object {
                Write-Host $_
            }
        }
    }
}

# Follow logs
function Follow-AgentLogs {
    param([int]$AgentId)
    
    if ($AgentId -lt 1 -or $AgentId -gt 11) {
        Write-Host "Invalid agent ID. Must be between 1 and 11." -ForegroundColor Red
        return
    }
    
    $agentName = "agent-$AgentId"
    $logPath = Get-ChildItem $LogsPath -Filter "*${agentName}*.log" | Select-Object -Last 1 -ExpandProperty FullName
    
    if (-not $logPath) {
        Write-Host "No log file found for $agentName" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Following logs: $logPath" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
    
    Get-Content -Path $logPath -Wait -Tail 50
}

# Main execution
Write-Host ""

if ($FollowLogs) {
    Follow-AgentLogs -AgentId $AgentId
}
elseif ($Details) {
    Show-AgentDetails -AgentId $AgentId
}
elseif ($ShowFailed) {
    Show-FailedAgents
}
elseif ($ShowRunning) {
    Show-RunningAgents
}
else {
    Show-StatusOverview
}

Write-Host ""
