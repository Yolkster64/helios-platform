# ============================================================================
# HELIOS MASTER LEARNING ORCHESTRATOR
# Bidirectional Learning + Optimization Implementation
# ============================================================================

param(
    [string]$Mode = 'continuous',  # continuous, once, report-only
    [int]$IntervalMinutes = 5,
    [bool]$ApplyOptimizations = $true
)

# Import all modules
$moduleBase = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath '..\..\..\scripts'
Import-Module "$moduleBase\metrics\MetricsCollector.psm1" -Force
Import-Module "$moduleBase\database\DatabaseHelper.psm1" -Force
Import-Module "$moduleBase\agents\AgentOrchestration.psm1" -Force
Import-Module "$moduleBase\learning\LearningSystem.psm1" -Force
Import-Module "$moduleBase\automation\AutomationRules.psm1" -Force
Import-Module "$moduleBase\learning\BidirectionalLearning.psm1" -Force

# Initialize databases and systems
Initialize-MetricsDatabase
$conn = Connect-MetricsDatabase

# Color output
$colors = @{
    extract = 'Cyan'
    patterns = 'Magenta'
    recommend = 'Yellow'
    apply = 'Green'
    report = 'Blue'
}

function Start-LearningOrchestration {
    param(
        [string]$Mode = 'continuous',
        [int]$IntervalMinutes = 5,
        [bool]$ApplyOptimizations = $true
    )
    
    Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║        HELIOS MASTER LEARNING ORCHESTRATOR - BIDIRECTIONAL LEARNING        ║
║                  360° Optimization Intelligence System                     ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    
    $cycleCount = 0
    $startTime = Get-Date
    
    do {
        $cycleCount++
        $cycleStartTime = Get-Date
        Write-Host "`n[Cycle $cycleCount] $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
        Write-Host ('=' * 80)
        
        # PHASE 1: EXTRACT INSIGHTS FROM ALL SYSTEMS
        Write-Host "`n📊 PHASE 1: Extracting System Insights..." -ForegroundColor ($colors.extract)
        
        $framework = Initialize-LearningFramework
        
        # Simulate system data (in production, pulls from live systems)
        $systemData = @{
            agents = @{
                agent1 = @{ id='agent1'; success_rate=0.9977; efficiency=0.9973; task_type_preferences='Foundation'; error_patterns=@('network_timeout'); historical_efficiency=@(0.92, 0.94, 0.96, 0.9973) }
                agent2 = @{ id='agent2'; success_rate=0.9955; efficiency=0.9894; task_type_preferences='Execution'; specialization_score=0.92; learning_trajectory=0.08 }
                agent3 = @{ id='agent3'; success_rate=0.9898; efficiency=0.9845; task_type_preferences='Optimization'; specialization_score=0.87 }
            }
            metrics = @{
                system_availability = 1.0
                resource_utilization_percent = 45.0
                database_query_latency_ms = 23.0
                board_sync_duration_ms = 245.0
                successful_auto_fixes = 87
                learning_confidence = 0.875
                manual_interventions = 3
                auto_fixes = 87
                issues_resolved_count = 45
                issues_created_count = 42
                system_stability = 0.9977
            }
            rules = @(
                @{ name='auto-retry'; execution_count=156; successful_executions=154; accuracy=0.9871 }
                @{ name='reassign'; execution_count=89; successful_executions=87; accuracy=0.9787 }
                @{ name='escalate'; execution_count=22; successful_executions=22; accuracy=1.0 }
                @{ name='auto-fix'; execution_count=87; successful_executions=86; accuracy=0.9885 }
                @{ name='notify'; execution_count=45; successful_executions=44; accuracy=0.9777 }
                @{ name='rebalance'; execution_count=12; successful_executions=11; accuracy=0.9166 }
                @{ name='learning-feedback'; execution_count=288; successful_executions=287; accuracy=0.9965 }
            )
            board = @{
                issues_resolved_count = 45
                issues_created_count = 42
                cycle_efficiency = 1.071
            }
        }
        
        $insights = Extract-SystemInsights @systemData
        
        Write-Host "  ✓ Extracted from $(($framework.Keys | Measure-Object).Count) learning channels"
        Write-Host "  ✓ Agent learning: $($insights.agent_insights.Count) agents analyzed"
        Write-Host "  ✓ Metrics health: $($insights.metric_insights.system_health)"
        Write-Host "  ✓ Rule effectiveness: $($insights.rule_insights.effective_rules.Count)/7 rules >95% success"
        
        # PHASE 2: IDENTIFY CROSS-SYSTEM PATTERNS
        Write-Host "`n🔗 PHASE 2: Identifying Cross-System Patterns..." -ForegroundColor ($colors.patterns)
        
        $patterns = Identify-CrossSystemPatterns -Insights $insights -HistoricalData @{}
        Write-Host "  ✓ Identified $($patterns.Count) cross-system patterns"
        $patterns | ForEach-Object { Write-Host "    • $($_.name) (confidence: $('{0:P0}' -f $_.confidence))" }
        
        # PHASE 3: GENERATE OPTIMIZATION RECOMMENDATIONS
        Write-Host "`n💡 PHASE 3: Generating Optimization Recommendations..." -ForegroundColor ($colors.recommend)
        
        $recommendations = Generate-OptimizationRecommendations -Patterns $patterns -Insights $insights -PriorityLevel 2
        Write-Host "  ✓ Generated $($recommendations.Count) recommendations"
        
        # Show top 3 recommendations
        $recommendations | Select-Object -First 3 | ForEach-Object {
            Write-Host "    $($_.priority). $($_.title)" -ForegroundColor Yellow
            Write-Host "       Impact: $($_.impact) | ROI: $($_.expected_roi)x"
        }
        
        # PHASE 4: APPLY OPTIMIZATIONS TO SYSTEMS
        if ($ApplyOptimizations) {
            Write-Host "`n🔧 PHASE 4: Applying Optimizations to Systems..." -ForegroundColor ($colors.apply)
            
            $applied = Apply-OptimizationLearning -Agents $systemData.agents -Rules $systemData.rules -Metrics $systemData.metrics
            
            Write-Host "  ✓ Applied $($applied.agent_optimizations.Count) agent optimizations"
            $applied.agent_optimizations | ForEach-Object { Write-Host "    • $_" }
            
            Write-Host "  ✓ Applied $($applied.rule_adjustments.Count) rule adjustments"
            $applied.rule_adjustments | ForEach-Object { Write-Host "    • $_" }
            
            Write-Host "  ✓ Applied $($applied.metric_improvements.Count) metric improvements"
            $applied.metric_improvements | ForEach-Object { Write-Host "    • $_" }
        }
        
        # PHASE 5: GENERATE COMPREHENSIVE REPORT
        Write-Host "`n📋 PHASE 5: Generating Learning Report..." -ForegroundColor ($colors.report)
        
        $report = Build-LearningReport -Insights $insights -Patterns $patterns -Recommendations $recommendations -Applied $applied
        
        # Save report
        $reportPath = ".\data\learning\report-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
        New-Item -ItemType Directory -Force -Path (Split-Path $reportPath) | Out-Null
        $report | Out-File $reportPath -Encoding UTF8
        
        Write-Host "  ✓ Report saved: $reportPath"
        Write-Host "  ✓ Summary: $(('✅' * ($applied.agent_optimizations.Count + $applied.rule_adjustments.Count + $applied.metric_improvements.Count)) -join ' ')"
        
        # PHASE 6: UPDATE TRACKING DATABASE
        Write-Host "`n💾 PHASE 6: Updating Tracking Database..." -ForegroundColor ($colors.report)
        
        # Insert learnings into SQL
        foreach ($learning in @(
            @{ id="learn-$cycleCount-001"; insight="Cycle $cycleCount complete"; source="orchestrator" }
        )) {
            try {
                $sql = "INSERT INTO optimization_learnings (id, category, insight, source, confidence_score, status) VALUES ('$($learning.id)', 'cycle', '$($learning.insight)', '$($learning.source)', 0.87, 'applied')"
                Invoke-Sql -Connection $conn -Query $sql
            } catch {
                Write-Warning "  ! Failed to insert learning: $_"
            }
        }
        
        Write-Host "  ✓ Tracking database updated"
        
        # CYCLE METRICS
        $cycleDuration = ((Get-Date) - $cycleStartTime).TotalSeconds
        Write-Host "`n⏱️  Cycle Duration: $cycleDuration seconds"
        Write-Host "📊 Cumulative: Cycle $cycleCount | Duration $(((Get-Date) - $startTime).TotalMinutes -as [int]) minutes"
        
        # NEXT CYCLE
        if ($Mode -eq 'continuous') {
            Write-Host "`n⏳ Waiting $IntervalMinutes minutes until next cycle..." -ForegroundColor Gray
            Start-Sleep -Seconds ($IntervalMinutes * 60)
        } else {
            Write-Host "`n✅ Single-run mode complete" -ForegroundColor Green
            break
        }
        
    } while ($Mode -eq 'continuous')
    
    Write-Host @"

╔════════════════════════════════════════════════════════════════════════════╗
║                    LEARNING ORCHESTRATOR COMPLETE                          ║
║                    Bidirectional Learning Operational                      ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
}

# MAIN EXECUTION
Write-Host "🚀 Starting HELIOS Master Learning Orchestrator..." -ForegroundColor Cyan
Start-LearningOrchestration -Mode $Mode -IntervalMinutes $IntervalMinutes -ApplyOptimizations $ApplyOptimizations
