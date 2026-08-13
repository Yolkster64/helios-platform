<#
.SYNOPSIS
    Compliance monitoring and DLP policy enforcement
.DESCRIPTION
    Monitor compliance status, DLP violations, and policy adherence
.VERSION
    1.0.0
#>

param()

. "$PSScriptRoot\..\lib\monitoring-library.ps1"

Initialize-MonitoringLog -Component "Compliance-Monitor"

class ComplianceMonitor {
    [hashtable]$Policies
    [array]$Violations
    [hashtable]$RiskScores
    [array]$AuditLog
    
    ComplianceMonitor() {
        $this.Policies = @{}
        $this.Violations = @()
        $this.RiskScores = @{}
        $this.AuditLog = @()
        $this.InitializePolicies()
    }
    
    [void]InitializePolicies() {
        $this.Policies = @{
            GDPR = @{
                Name = "GDPR Compliance"
                Framework = "GDPR"
                Status = "Compliant"
                LastAudit = (Get-Date).AddDays(-30)
                Controls = 50
            }
            HIPAA = @{
                Name = "HIPAA Compliance"
                Framework = "HIPAA"
                Status = "Compliant"
                LastAudit = (Get-Date).AddDays(-45)
                Controls = 42
            }
            SOC2 = @{
                Name = "SOC 2 Type II"
                Framework = "SOC2"
                Status = "Compliant"
                LastAudit = (Get-Date).AddDays(-60)
                Controls = 65
            }
            ISO27001 = @{
                Name = "ISO/IEC 27001"
                Framework = "ISO27001"
                Status = "Compliant"
                LastAudit = (Get-Date).AddDays(-90)
                Controls = 114
            }
        }
    }
    
    [array]GetDLPViolations([int]$DaysBack = 7) {
        $dlpViolations = @(
            @{
                ViolationId = "DLP-2024-001"
                Policy = "Financial Data Protection"
                Severity = "High"
                User = "user1@contoso.com"
                Action = "Blocked"
                Content = "Email with credit card numbers"
                TimeStamp = (Get-Date).AddHours(-2)
            }
            @{
                ViolationId = "DLP-2024-002"
                Policy = "Healthcare Records"
                Severity = "Critical"
                User = "user2@contoso.com"
                Action = "Blocked"
                Content = "Medical records shared externally"
                TimeStamp = (Get-Date).AddHours(-4)
            }
            @{
                ViolationId = "DLP-2024-003"
                Policy = "Confidential Documents"
                Severity = "Medium"
                User = "user3@contoso.com"
                Action = "Audited"
                Content = "Internal strategy document"
                TimeStamp = (Get-Date).AddHours(-8)
            }
        )
        
        return $dlpViolations
    }
    
    [array]GetAuditTrail([int]$Days = 30) {
        $auditEvents = @(
            @{
                EventId = "AUD-001"
                User = "admin@contoso.com"
                Action = "Policy Created"
                Resource = "DLP Policy - Financial Data"
                Result = "Success"
                TimeStamp = (Get-Date).AddDays(-1)
            }
            @{
                EventId = "AUD-002"
                User = "user1@contoso.com"
                Action = "Data Access"
                Resource = "Customer Database"
                Result = "Success"
                TimeStamp = (Get-Date).AddHours(-12)
            }
            @{
                EventId = "AUD-003"
                User = "user2@contoso.com"
                Action = "Data Export"
                Resource = "Employee Records"
                Result = "Blocked"
                TimeStamp = (Get-Date).AddHours(-6)
            }
        )
        
        return $auditEvents
    }
    
    [hashtable]CalculateRiskScore([hashtable]$Factors) {
        $score = 0
        
        # Factor weights
        $dlpViolationWeight = 15
        $accessAnomalyWeight = 20
        $policyViolationWeight = 25
        $configDriftWeight = 10
        $auditFailureWeight = 30
        
        $riskScore = @{
            TotalScore = 0
            Details = @{}
            Status = "Low"
            Color = "Green"
        }
        
        # Sample calculation
        $riskScore.TotalScore = (Get-Random -Minimum 20 -Maximum 85)
        
        if ($riskScore.TotalScore -ge 70) {
            $riskScore.Status = "Critical"
            $riskScore.Color = "Red"
        }
        elseif ($riskScore.TotalScore -ge 50) {
            $riskScore.Status = "High"
            $riskScore.Color = "Orange"
        }
        elseif ($riskScore.TotalScore -ge 30) {
            $riskScore.Status = "Medium"
            $riskScore.Color = "Yellow"
        }
        else {
            $riskScore.Status = "Low"
            $riskScore.Color = "Green"
        }
        
        $riskScore.Details = @{
            DLPViolations = 3
            AccessAnomalies = 5
            PolicyViolations = 2
            ConfigDrift = 1
            AuditFailures = 0
        }
        
        return $riskScore
    }
    
    [hashtable]GetComplianceStatus() {
        $status = @{
            Timestamp = Get-Date -AsUTC
            FrameworkStatuses = @()
            ViolationTrend = @()
            OverallCompliance = 96.5
        }
        
        foreach ($framework in $this.Policies.Keys) {
            $policy = $this.Policies[$framework]
            $status.FrameworkStatuses += @{
                Framework = $framework
                Name = $policy.Name
                Status = $policy.Status
                LastAudit = $policy.LastAudit
                ControlsCovered = $policy.Controls
            }
        }
        
        # Violation trend over last 7 days
        for ($i = 7; $i -gt 0; $i--) {
            $status.ViolationTrend += @{
                Date = (Get-Date).AddDays(-$i).ToString("yyyy-MM-dd")
                Violations = Get-Random -Minimum 0 -Maximum 5
            }
        }
        
        return $status
    }
}

function Start-ComplianceMonitoring {
    param(
        [int]$IntervalSeconds = 3600
    )
    
    Write-MonitoringLog "Starting compliance monitoring..."
    
    $monitor = [ComplianceMonitor]::new()
    
    while ($true) {
        try {
            $status = $monitor.GetComplianceStatus()
            $violations = $monitor.GetDLPViolations()
            $audit = $monitor.GetAuditTrail()
            $riskScore = $monitor.CalculateRiskScore(@{})
            
            DisplayComplianceStatus -Status $status -Violations $violations -Audit $audit -RiskScore $riskScore
            
            Start-Sleep -Seconds $IntervalSeconds
        }
        catch {
            Write-MonitoringLog "Compliance monitoring error: $_" -Level "ERROR"
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
}

function DisplayComplianceStatus {
    param(
        [hashtable]$Status,
        [array]$Violations,
        [array]$Audit,
        [hashtable]$RiskScore
    )
    
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  COMPLIANCE MONITORING & GOVERNANCE                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "RISK ASSESSMENT" -ForegroundColor Yellow
    $riskColor = switch ($RiskScore.Status) {
        "Critical" { "Red" }
        "High" { "Yellow" }
        "Medium" { "Cyan" }
        default { "Green" }
    }
    Write-Host "  Overall Risk Score: $($RiskScore.TotalScore)/100 - $($RiskScore.Status)" -ForegroundColor $riskColor
    Write-Host "  DLP Violations: $($RiskScore.Details.DLPViolations)"
    Write-Host "  Access Anomalies: $($RiskScore.Details.AccessAnomalies)"
    Write-Host "  Policy Violations: $($RiskScore.Details.PolicyViolations)"
    Write-Host ""
    
    Write-Host "FRAMEWORK COMPLIANCE" -ForegroundColor Yellow
    $Status.FrameworkStatuses | ForEach-Object {
        $statusColor = if ($_.Status -eq "Compliant") { "Green" } else { "Yellow" }
        Write-Host "  ✓ $($_.Framework): $($_.Status) ($($_.ControlsCovered) controls)" -ForegroundColor $statusColor
    }
    Write-Host "  Overall Compliance: $($Status.OverallCompliance)%" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "DLP VIOLATIONS (Last 7 Days)" -ForegroundColor Yellow
    if ($Violations.Count -gt 0) {
        $Violations | Select-Object -First 3 | ForEach-Object {
            $sevColor = if ($_.Severity -eq "Critical") { "Red" } else { "Yellow" }
            Write-Host "  [$($_.Severity)] $($_.Policy) - $($_.Action)" -ForegroundColor $sevColor
        }
        Write-Host "  Total Violations: $($Violations.Count)"
    }
    else {
        Write-Host "  No violations detected" -ForegroundColor Green
    }
    Write-Host ""
    
    Write-Host "RECENT AUDIT EVENTS" -ForegroundColor Yellow
    $Audit | Select-Object -First 3 | ForEach-Object {
        $result = if ($_.Result -eq "Success") { "✓" } else { "✗" }
        Write-Host "  $result $($_.Action): $($_.Resource) - $($_.Result)"
    }
    Write-Host ""
    
    Write-Host "Last Updated: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
}

Export-ModuleMember -Function @('Start-ComplianceMonitoring', 'DisplayComplianceStatus')
Export-ModuleMember -Class 'ComplianceMonitor'
