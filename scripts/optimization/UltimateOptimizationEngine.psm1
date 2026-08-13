#===================================================================================================
# ULTIMATE OPTIMIZATION ENGINE - Meta-Learner & Hybrid Strategy Coordinator
#===================================================================================================
# Combines ALL learned tricks into unified meta-system that automatically selects optimal approach
# Handles: Single vs Parallel vs Multi-Parallel, Model Mixing, Cost-Power Tradeoffs, etc.

$InformationPreference = "Continue"

class OptimizationStrategy {
    [string]$Name
    [string]$Category          # single-task, parallel, multi-parallel, distributed, hierarchical
    [double]$CostMultiplier    # 1.0 = baseline, 0.5 = 50% cost savings
    [double]$SpeedMultiplier   # 1.0 = baseline, 2.0 = 2x faster
    [double]$QualityScore      # 0-100, target is 95+
    [double]$ReliabilityScore  # 0-100, target is 99.9+
    [double]$ScalabilityLimit  # max tasks/agents this strategy handles well
    [hashtable]$OptimalFor     # conditions where this strategy excels
    [string[]]$Dependencies    # other strategies that complement this one
    [double]$OverheadPercent   # coordination/learning overhead
}

class HybridPlan {
    [string]$PlanId
    [OptimizationStrategy[]]$Strategies
    [double]$WeightedCost      # blended cost across all strategies
    [double]$WeightedSpeed     # blended speed
    [double]$WeightedQuality   # blended quality
    [hashtable]$TaskRouting    # which tasks go to which strategy
    [hashtable]$ModelMixing    # which models back up which
    [string[]]$BackupChains    # cost/quality backup chains
    [double]$SynergyBonus      # combined effect of multiple strategies
}

#===================================================================================================
# CORE OPTIMIZATION STRATEGIES
#===================================================================================================

function Get-AllOptimizationStrategies {
    <#
    .SYNOPSIS
    Returns catalog of all proven optimization strategies from learned data
    #>
    
    return @(
        # STRATEGY 1: Ultra-Fast Single Model (for simple, latency-critical tasks)
        [PSCustomObject]@{
            Name = "ultra-fast-single"
            Category = "single-task"
            Description = "Single fastest model for <100ms latency requirements"
            CostMultiplier = 1.0
            SpeedMultiplier = 3.0
            QualityScore = 88.0
            ReliabilityScore = 99.2
            ScalabilityLimit = 1000
            OptimalFor = @{
                TaskComplexity = "simple"
                LatencyBudget = "<100ms"
                Accuracy = ">=85%"
                Scale = "<1000/sec"
            }
            Dependencies = @()
            OverheadPercent = 0
            Models = @("qwen-turbo-max", "gemini-3-flash", "mistral-small")
            Parallelism = 1
        }
        
        # STRATEGY 2: Ultra-Cheap Hybrid (mix cheap models based on complexity)
        [PSCustomObject]@{
            Name = "ultra-cheap-hybrid"
            Category = "parallel"
            Description = "Mix fast + cheap for 30-40% cost savings"
            CostMultiplier = 0.65
            SpeedMultiplier = 1.2
            QualityScore = 92.0
            ReliabilityScore = 99.1
            ScalabilityLimit = 5000
            OptimalFor = @{
                TaskComplexity = "mixed"
                CostBudget = "optimize"
                Accuracy = ">=90%"
                Scale = "<5000/sec"
            }
            Dependencies = @("routing-by-complexity")
            OverheadPercent = 5
            Models = @("haiku", "qwen-turbo-max", "sonnet-cheap", "gemini-flash")
            Parallelism = 4
            Mixing = @{
                simple = @("qwen-turbo-max", "gemini-3-flash")
                moderate = @("claude-haiku", "mistral-small")
                complex = @("claude-sonnet", "gpt-4o")
            }
        }
        
        # STRATEGY 3: Premium Quality (use best models regardless of cost)
        [PSCustomObject]@{
            Name = "premium-quality"
            Category = "single-task"
            Description = "Opus-only for maximum accuracy and reasoning"
            CostMultiplier = 5.0
            SpeedMultiplier = 0.8
            QualityScore = 98.2
            ReliabilityScore = 99.9
            ScalabilityLimit = 500
            OptimalFor = @{
                TaskComplexity = "complex"
                CostBudget = "unlimited"
                Accuracy = ">=98%"
                Scale = "<500/min"
            }
            Dependencies = @()
            OverheadPercent = 0
            Models = @("claude-opus", "gpt-4-turbo", "gemini-ultra")
            Parallelism = 1
        }
        
        # STRATEGY 4: Multi-Agent Parallel (spread across 12 agents, route by specialization)
        [PSCustomObject]@{
            Name = "multi-agent-parallel"
            Category = "parallel"
            Description = "Spread work across 12 agents with specialization routing"
            CostMultiplier = 0.85
            SpeedMultiplier = 8.0
            QualityScore = 95.2
            ReliabilityScore = 99.77
            ScalabilityLimit = 100000
            OptimalFor = @{
                TaskComplexity = "varied"
                CostBudget = "balance"
                Accuracy = ">=95%"
                Scale = ">5000/sec"
            }
            Dependencies = @("dynamic-specialization", "agent-synergy")
            OverheadPercent = 8
            AgentCount = 12
            Parallelism = 12
            SpecializationBonus = 0.10  # 10% bonus per specialization match
        }
        
        # STRATEGY 5: Hierarchical Distributed (teams of agents for massive scale)
        [PSCustomObject]@{
            Name = "hierarchical-distributed"
            Category = "distributed"
            Description = "4-6 agent teams with load balancing for 100k+ tasks"
            CostMultiplier = 0.75
            SpeedMultiplier = 10.0
            QualityScore = 94.5
            ReliabilityScore = 99.9
            ScalabilityLimit = 1000000
            OptimalFor = @{
                TaskComplexity = "diverse"
                CostBudget = "optimize"
                Accuracy = ">=94%"
                Scale = ">100k/sec"
            }
            Dependencies = @("hierarchical-routing", "distributed-learning")
            OverheadPercent = 12
            TeamsCount = 3
            AgentsPerTeam = 4
            Parallelism = 100
        }
        
        # STRATEGY 6: Model Backup Chains (primary + N backups for reliability)
        [PSCustomObject]@{
            Name = "model-backup-chains"
            Category = "parallel"
            Description = "Primary model + 2-3 backups for 99.9%+ uptime"
            CostMultiplier = 1.15
            SpeedMultiplier = 0.95
            QualityScore = 96.0
            ReliabilityScore = 99.95
            ScalabilityLimit = 10000
            OptimalFor = @{
                TaskComplexity = "critical"
                CostBudget = "allow-reliability"
                Accuracy = ">=95%"
                Scale = "<10k/sec"
                Uptime = ">=99.9%"
            }
            Dependencies = @()
            OverheadPercent = 15
            BackupChain = @(
                @("claude-opus", "claude-sonnet", "gpt-4-turbo"),
                @("claude-sonnet", "gpt-4o", "gemini-pro"),
                @("gpt-4o", "mistral-large", "qwen-max")
            )
        }
        
        # STRATEGY 7: Cost-Power Synergy (agents back each other up, reduce cost + increase power)
        [PSCustomObject]@{
            Name = "cost-power-synergy"
            Category = "multi-parallel"
            Description = "Agents collaborate: cheap agents prep, powerful agents execute, cheap verify"
            CostMultiplier = 0.70
            SpeedMultiplier = 1.5
            QualityScore = 96.5
            ReliabilityScore = 99.8
            ScalabilityLimit = 50000
            OptimalFor = @{
                TaskComplexity = "structured"
                CostBudget = "optimize"
                Accuracy = ">=96%"
                Scale = "<50k/sec"
            }
            Dependencies = @("agent-synergy", "knowledge-compression")
            OverheadPercent = 10
            Pipeline = @(
                @{Stage = "prep"; Agent = "foundation-1"; Model = "haiku"; Cost = 0.05}
                @{Stage = "execute"; Agent = "exec-1"; Model = "sonnet"; Cost = 0.5}
                @{Stage = "verify"; Agent = "quality-1"; Model = "haiku"; Cost = 0.05}
            )
            CostSavings = 0.30
            PowerGain = 1.5
        }
        
        # STRATEGY 8: Knowledge Compression (distill complex reasoning to simple models)
        [PSCustomObject]@{
            Name = "knowledge-compression"
            Category = "multi-parallel"
            Description = "Expensive model reasons once, cheap models apply reasoning 1000x"
            CostMultiplier = 0.20
            SpeedMultiplier = 100.0
            QualityScore = 93.0
            ReliabilityScore = 98.5
            ScalabilityLimit = 1000000
            OptimalFor = @{
                TaskComplexity = "reasoning-heavy"
                Scale = ">100k/sec"
                CostBudget = "minimize"
                Accuracy = ">=93%"
            }
            Dependencies = @("pattern-extraction", "model-specialization")
            OverheadPercent = 20
            Technique = "extract-reasoning-once-apply-many"
        }
        
        # STRATEGY 9: Temporal Load Balancing (route based on time, cost, congestion)
        [PSCustomObject]@{
            Name = "temporal-load-balancing"
            Category = "parallel"
            Description = "Route to cheapest model during off-peak, fastest during peak"
            CostMultiplier = 0.80
            SpeedMultiplier = 1.1
            QualityScore = 94.0
            ReliabilityScore = 99.5
            ScalabilityLimit = 50000
            OptimalFor = @{
                TaskComplexity = "any"
                LoadPattern = "variable"
                CostBudget = "balance"
                Accuracy = ">=94%"
            }
            Dependencies = @("load-prediction", "dynamic-pricing")
            OverheadPercent = 5
        }
        
        # STRATEGY 10: Cross-Model Compression (share knowledge across model families)
        [PSCustomObject]@{
            Name = "cross-model-compression"
            Category = "multi-parallel"
            Description = "Extract patterns from Anthropic → apply via OpenAI → refine with Mistral"
            CostMultiplier = 0.50
            SpeedMultiplier = 5.0
            QualityScore = 94.5
            ReliabilityScore = 99.0
            ScalabilityLimit = 500000
            OptimalFor = @{
                TaskComplexity = "structured"
                ProviderDiversity = "required"
                Scale = ">100k/sec"
                CostBudget = "minimize"
            }
            Dependencies = @("multi-provider", "cross-model-learning")
            OverheadPercent = 15
            ModelFamilies = @("anthropic", "openai", "mistral", "google")
        }
        
        # STRATEGY 11: Task Decomposition (break complex into simple subtasks)
        [PSCustomObject]@{
            Name = "task-decomposition"
            Category = "hierarchical"
            Description = "Complex tasks broken into simple subtasks for cheap models"
            CostMultiplier = 0.45
            SpeedMultiplier = 2.0
            QualityScore = 95.0
            ReliabilityScore = 99.2
            ScalabilityLimit = 100000
            OptimalFor = @{
                TaskComplexity = "complex"
                CostBudget = "minimize"
                Scale = "<100k/sec"
                Accuracy = ">=95%"
            }
            Dependencies = @("decomposition-engine", "subtask-routing")
            OverheadPercent = 10
            Levels = 3
        }
        
        # STRATEGY 12: Speculative Execution (cheap model predicts, expensive validates)
        [PSCustomObject]@{
            Name = "speculative-execution"
            Category = "parallel"
            Description = "Fast model predicts, slow model validates, reuse if correct"
            CostMultiplier = 0.55
            SpeedMultiplier = 3.5
            QualityScore = 96.0
            ReliabilityScore = 99.3
            ScalabilityLimit = 50000
            OptimalFor = @{
                TaskComplexity = "moderate"
                Scale = "<50k/sec"
                CostBudget = "minimize"
                Accuracy = ">=95%"
            }
            Dependencies = @("prediction-accuracy")
            OverheadPercent = 8
            ValidationThreshold = 0.85  # If confidence > 85%, skip expensive validation
        }
    )
}

#===================================================================================================
# HYBRID PLAN GENERATION
#===================================================================================================

function New-HybridOptimizationPlan {
    <#
    .SYNOPSIS
    Creates optimal hybrid plan combining multiple strategies
    
    .PARAMETER TaskProfile
    Characteristics of tasks to optimize: complexity, scale, cost_budget, accuracy_target, latency
    
    .PARAMETER DataProfile
    Characteristics of data: size, diversity, sources, compression_potential
    #>
    param(
        [hashtable]$TaskProfile = @{
            complexity = "mixed"
            scale = 10000
            costBudget = "optimize"
            accuracyTarget = 95
            latencyMax = 500
        },
        [hashtable]$DataProfile = @{
            totalTasks = 100000
            diversity = "high"
            sources = 5
            compressionPotential = 0.4
        },
        [int]$AgentCount = 12,
        [int]$LearningCycles = 3
    )
    
    $allStrategies = Get-AllOptimizationStrategies
    
    # HYBRID PLAN LOGIC: Combine multiple strategies based on profiles
    
    # If scale is very high and cost is priority: Use knowledge compression + hierarchical
    if ($DataProfile.totalTasks -gt 50000 -and $TaskProfile.costBudget -eq "minimize") {
        $selectedStrategies = @(
            $allStrategies | where {$_.Name -eq "knowledge-compression"},
            $allStrategies | where {$_.Name -eq "hierarchical-distributed"},
            $allStrategies | where {$_.Name -eq "task-decomposition"}
        )
    }
    # If mixed complexity: Use multi-agent parallel + cost-power synergy
    elseif ($TaskProfile.complexity -eq "mixed") {
        $selectedStrategies = @(
            $allStrategies | where {$_.Name -eq "multi-agent-parallel"},
            $allStrategies | where {$_.Name -eq "cost-power-synergy"},
            $allStrategies | where {$_.Name -eq "speculative-execution"}
        )
    }
    # If accuracy is critical: Use premium + backup chains
    elseif ($TaskProfile.accuracyTarget -ge 98) {
        $selectedStrategies = @(
            $allStrategies | where {$_.Name -eq "premium-quality"},
            $allStrategies | where {$_.Name -eq "model-backup-chains"}
        )
    }
    # If speed is critical: Use ultra-fast single + parallel
    elseif ($TaskProfile.latencyMax -lt 200) {
        $selectedStrategies = @(
            $allStrategies | where {$_.Name -eq "ultra-fast-single"},
            $allStrategies | where {$_.Name -eq "temporal-load-balancing"}
        )
    }
    # Default: Balanced hybrid
    else {
        $selectedStrategies = @(
            $allStrategies | where {$_.Name -eq "ultra-cheap-hybrid"},
            $allStrategies | where {$_.Name -eq "multi-agent-parallel"},
            $allStrategies | where {$_.Name -eq "model-backup-chains"}
        )
    }
    
    # Calculate blended metrics
    $weightedCost = ($selectedStrategies | measure -Property CostMultiplier -Average).Average
    $weightedSpeed = ($selectedStrategies | measure -Property SpeedMultiplier -Average).Average
    $weightedQuality = ($selectedStrategies | measure -Property QualityScore -Average).Average
    
    # Calculate synergy bonus (strategies that complement each other)
    $synergyBonus = Invoke-StrategySynergyAnalysis $selectedStrategies
    
    # Build model mixing strategy
    $modelMixing = Build-ModelMixingStrategy $selectedStrategies $TaskProfile
    
    # Build backup chains
    $backupChains = Build-BackupChains $selectedStrategies $TaskProfile
    
    # Build task routing
    $taskRouting = Build-TaskRouting $selectedStrategies $TaskProfile $DataProfile
    
    return [PSCustomObject]@{
        PlanId = "hybrid-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Strategies = $selectedStrategies
        WeightedCost = $weightedCost
        WeightedSpeed = $weightedSpeed
        WeightedQuality = $weightedQuality
        SynergyBonus = $synergyBonus
        ModelMixing = $modelMixing
        BackupChains = $backupChains
        TaskRouting = $taskRouting
        TaskProfile = $TaskProfile
        DataProfile = $DataProfile
        Summary = "Strategies: $(($selectedStrategies | % {$_.Name}) -join ' + ') | Cost: $([math]::Round($weightedCost, 2))x | Speed: $([math]::Round($weightedSpeed, 1))x | Quality: $([math]::Round($weightedQuality, 1))%"
    }
}

#===================================================================================================
# STRATEGY SYNERGY ANALYSIS
#===================================================================================================

function Invoke-StrategySynergyAnalysis {
    param([PSCustomObject[]]$Strategies)
    
    $synergyMatrix = @{
        "ultra-fast-single" = @{
            "model-backup-chains" = 0.15  # Good: fast primary + reliable backups
            "temporal-load-balancing" = 0.10
        }
        "ultra-cheap-hybrid" = @{
            "task-decomposition" = 0.20   # Excellent: cheap models + decomposed tasks
            "knowledge-compression" = 0.25  # Excellent: multiple cheap steps
            "cost-power-synergy" = 0.20
        }
        "multi-agent-parallel" = @{
            "cost-power-synergy" = 0.25    # Excellent: agent collaboration
            "dynamic-specialization" = 0.20
            "model-backup-chains" = 0.15
        }
        "knowledge-compression" = @{
            "task-decomposition" = 0.25    # Excellent: compress then decompose
            "cross-model-compression" = 0.30  # Excellent: compress across providers
        }
    }
    
    $totalSynergy = 0
    for ($i = 0; $i -lt $Strategies.Count; $i++) {
        for ($j = $i + 1; $j -lt $Strategies.Count; $j++) {
            $s1 = $Strategies[$i].Name
            $s2 = $Strategies[$j].Name
            
            if ($synergyMatrix[$s1][$s2]) {
                $totalSynergy += $synergyMatrix[$s1][$s2]
            }
        }
    }
    
    # Apply synergy bonus: 1.0 + total synergy, capped at 1.5x
    return [math]::Min(1.0 + $totalSynergy, 1.5)
}

#===================================================================================================
# MODEL MIXING STRATEGY
#===================================================================================================

function Build-ModelMixingStrategy {
    param(
        [PSCustomObject[]]$Strategies,
        [hashtable]$TaskProfile
    )
    
    $mixingStrategy = @{}
    
    foreach ($strategy in $Strategies) {
        if ($strategy.Mixing) {
            $mixingStrategy[$strategy.Name] = $strategy.Mixing
        }
    }
    
    # Tier-based mixing
    $mixingStrategy["by-task-complexity"] = @{
        "ultra-simple" = @{
            models = @("qwen-turbo-max", "gemini-3-flash")
            distribution = @{haiku=0.3; qwen=0.4; gemini=0.3}
            cost = 0.008
        }
        "simple" = @{
            models = @("claude-haiku", "mistral-small", "qwen-turbo")
            distribution = @{haiku=0.4; mistral=0.3; qwen=0.3}
            cost = 0.015
        }
        "moderate" = @{
            models = @("claude-sonnet", "gpt-4o", "mistral-large")
            distribution = @{sonnet=0.4; gpt=0.3; mistral=0.3}
            cost = 0.25
        }
        "complex" = @{
            models = @("claude-opus", "gpt-4-turbo", "gemini-ultra")
            distribution = @{opus=0.4; gpt=0.35; gemini=0.25}
            cost = 2.5
        }
    }
    
    # Cost-optimized mixing
    $mixingStrategy["cost-optimized"] = @{
        cheap = 0.60      # 60% to cheap models (haiku, qwen)
        moderate = 0.30   # 30% to moderate (sonnet, gpt-4o)
        expensive = 0.10  # 10% to expensive (opus)
        validation = @{"cheap" = @("moderate", "expensive")}
    }
    
    # Quality-optimized mixing
    $mixingStrategy["quality-optimized"] = @{
        expensive = 0.60  # 60% to expensive (opus, gpt-4)
        moderate = 0.30   # 30% to moderate (sonnet, gpt-4o)
        cheap = 0.10      # 10% to cheap (fallback)
    }
    
    # Dynamic mixing based on task profile
    if ($TaskProfile.costBudget -eq "minimize") {
        $mixingStrategy["active"] = $mixingStrategy["cost-optimized"]
    } elseif ($TaskProfile.accuracyTarget -ge 98) {
        $mixingStrategy["active"] = $mixingStrategy["quality-optimized"]
    } else {
        $mixingStrategy["active"] = @{
            cheap = 0.40
            moderate = 0.45
            expensive = 0.15
        }
    }
    
    return $mixingStrategy
}

#===================================================================================================
# BACKUP CHAIN STRATEGY
#===================================================================================================

function Build-BackupChains {
    param(
        [PSCustomObject[]]$Strategies,
        [hashtable]$TaskProfile
    )
    
    # Primary → Secondary → Tertiary backup chains
    $backupChains = @{
        "ultra-reliable" = @(
            @("claude-opus", "gpt-4-turbo", "gemini-ultra"),      # For complex critical
            @("claude-sonnet", "gpt-4o", "mistral-large"),        # For moderate critical
            @("claude-haiku", "qwen-turbo", "gemini-flash")       # For simple fallback
        )
        
        "cost-optimized" = @(
            @("qwen-turbo-max", "mistral-small", "gemini-flash"), # Primary: cheap
            @("claude-haiku", "gpt-mini", "llama-8b"),            # Secondary: acceptable cost
            @("claude-sonnet", "gpt-4o", "mistral-large")         # Tertiary: if all else fails
        )
        
        "balanced" = @(
            @("claude-sonnet", "gpt-4o", "mistral-large"),        # Primary: balanced
            @("claude-haiku", "qwen-turbo", "gemini-pro"),        # Secondary: cheaper
            @("claude-opus", "gpt-4-turbo", "gemini-ultra")       # Tertiary: premium
        )
        
        "provider-diverse" = @(
            @("claude-sonnet", "gpt-4o", "gemini-pro"),           # Primary: diverse
            @("qwen-max", "mistral-large", "llama-70b"),          # Secondary: alternative providers
            @("claude-opus", "gpt-4-turbo", "gemini-ultra")       # Tertiary: premium
        )
    }
    
    # Cost reduction from backup chains
    $backupChains["cost-analysis"] = @{
        "primary-only" = 1.0
        "primary+secondary" = 1.05
        "primary+secondary+tertiary" = 1.15
        "notes" = "Backup chains add 5-15% cost but increase reliability from 99% to 99.9%+"
    }
    
    return $backupChains
}

#===================================================================================================
# TASK ROUTING STRATEGY
#===================================================================================================

function Build-TaskRouting {
    param(
        [PSCustomObject[]]$Strategies,
        [hashtable]$TaskProfile,
        [hashtable]$DataProfile
    )
    
    $routing = @{
        "complexity-based" = @{
            "ultra-simple" = @{
                strategies = @("ultra-fast-single", "ultra-cheap-hybrid")
                models = @("qwen-turbo-max", "gemini-3-flash")
                parallelism = 8
            }
            "simple" = @{
                strategies = @("ultra-cheap-hybrid", "multi-agent-parallel")
                models = @("claude-haiku", "mistral-small", "qwen-turbo")
                parallelism = 4
            }
            "moderate" = @{
                strategies = @("multi-agent-parallel", "cost-power-synergy")
                models = @("claude-sonnet", "gpt-4o", "mistral-large")
                parallelism = 6
            }
            "complex" = @{
                strategies = @("premium-quality", "knowledge-compression")
                models = @("claude-opus", "gpt-4-turbo", "gemini-ultra")
                parallelism = 2
            }
        }
        
        "source-based" = @{
            # Route tasks based on data source
            "api" = @{strategy = "ultra-fast-single"; priority = "speed"}
            "database" = @{strategy = "multi-agent-parallel"; priority = "throughput"}
            "batch" = @{strategy = "knowledge-compression"; priority = "cost"}
            "realtime" = @{strategy = "ultra-fast-single"; priority = "latency"}
            "archive" = @{strategy = "cost-power-synergy"; priority = "cost-quality"}
        }
        
        "specialization-based" = @{
            "routing" = @{agent = "foundation-1"; models = @("haiku", "qwen")}
            "aggregation" = @{agent = "foundation-2"; models = @("haiku", "gemini")}
            "execution" = @{agent = "exec-1"; models = @("sonnet", "gpt-4o")}
            "optimization" = @{agent = "optim-1"; models = @("opus", "gpt-4")}
            "quality" = @{agent = "quality-1"; models = @("sonnet", "gpt-4o")}
        }
        
        "agent-capacity" = @{
            "foundation-agents" = @{capacity = 1000; distribution = "equal"}
            "execution-agents" = @{capacity = 200; distribution = "by-capability"}
            "optimization-agents" = @{capacity = 50; distribution = "priority"}
            "quality-agents" = @{capacity = 100; distribution = "by-task-type"}
        }
    }
    
    return $routing
}

#===================================================================================================
# LEARNING & ADAPTATION
#===================================================================================================

function Invoke-ContinuousLearning {
    param(
        [PSCustomObject]$HybridPlan,
        [hashtable]$ExecutionMetrics,
        [int]$LearningCycleNumber
    )
    
    # Extract what worked well
    $performanceByStrategy = @{}
    foreach ($strategy in $HybridPlan.Strategies) {
        $perf = $ExecutionMetrics.ByStrategy[$strategy.Name]
        
        $performanceByStrategy[$strategy.Name] = @{
            actualCost = $perf.cost
            expectedCost = $strategy.CostMultiplier
            costError = $perf.cost - $strategy.CostMultiplier
            
            actualSpeed = $perf.speed
            expectedSpeed = $strategy.SpeedMultiplier
            speedGain = $perf.speed / $strategy.SpeedMultiplier
            
            actualQuality = $perf.quality
            expectedQuality = $strategy.QualityScore
            qualityDelta = $perf.quality - $strategy.QualityScore
            
            adjustmentNeeded = ($perf.cost / $strategy.CostMultiplier) -gt 1.2 -or
                              ($perf.quality / $strategy.QualityScore) -lt 0.95
        }
    }
    
    # Identify which strategies underperformed
    $underperformers = $performanceByStrategy.Keys | 
        where {$performanceByStrategy[$_].adjustmentNeeded} |
        foreach {
            @{
                strategy = $_
                costError = $performanceByStrategy[$_].costError
                qualityError = $performanceByStrategy[$_].qualityDelta
            }
        }
    
    # Identify winners to emphasize more
    $winners = $performanceByStrategy.Keys |
        where {
            $performanceByStrategy[$_].costError -lt -0.1 -and
            $performanceByStrategy[$_].qualityDelta -gt 2
        }
    
    return @{
        CycleNumber = $LearningCycleNumber
        Winners = $winners
        Underperformers = $underperformers
        Adjustments = @{
            increaseWeight = $winners
            decreaseWeight = ($underperformers | % {$_.strategy})
            replaceStrategy = ($underperformers | where {$_.costError -gt 0.5} | % {$_.strategy})
        }
        LearningConfidence = 1.0 - (($underperformers.Count) / $HybridPlan.Strategies.Count)
    }
}

#===================================================================================================
# META-OPTIMIZATION: AUTO-SELECT BEST HYBRID PLAN
#===================================================================================================

function Get-OptimalHybridPlan {
    <#
    .SYNOPSIS
    Automatically selects the best hybrid plan based on task and data profiles
    
    Uses learned data to weight different strategies and combine them optimally
    #>
    param(
        [hashtable]$TaskProfile,
        [hashtable]$DataProfile,
        [ValidateSet("cost", "speed", "quality", "reliability", "balanced")]
        [string]$Priority = "balanced"
    )
    
    Write-Host "🧠 Analyzing optimization landscape..." -ForegroundColor Cyan
    
    $allStrategies = Get-AllOptimizationStrategies
    
    # Score each strategy based on priority and profiles
    $scores = @{}
    foreach ($strategy in $allStrategies) {
        $score = 0
        $reasons = @()
        
        # Task complexity matching
        if ($TaskProfile.complexity -eq "simple" -and $strategy.QualityScore -lt 92) {
            $score += 20
            $reasons += "Good for simple tasks"
        }
        if ($TaskProfile.complexity -eq "complex" -and $strategy.QualityScore -gt 94) {
            $score += 20
            $reasons += "Strong on complex reasoning"
        }
        
        # Scale handling
        if ($DataProfile.totalTasks -gt $strategy.ScalabilityLimit) {
            $score -= 30
            $reasons += "Scalability limit exceeded"
        } else {
            $score += 10
        }
        
        # Cost/Speed/Quality priorities
        switch ($Priority) {
            "cost" {
                $score += (1 / $strategy.CostMultiplier) * 100
                $reasons += "Cost-optimized selection"
            }
            "speed" {
                $score += $strategy.SpeedMultiplier * 50
                $reasons += "Speed-optimized selection"
            }
            "quality" {
                $score += $strategy.QualityScore
                $reasons += "Quality-optimized selection"
            }
            "reliability" {
                $score += $strategy.ReliabilityScore
                $reasons += "Reliability-optimized selection"
            }
            "balanced" {
                $score += ($strategy.QualityScore + $strategy.ReliabilityScore) / 2
                $reasons += "Balanced optimization"
            }
        }
        
        $scores[$strategy.Name] = @{
            Score = $score
            Reasons = $reasons
            Strategy = $strategy
        }
    }
    
    # Sort by score and return top 5 for hybrid combination
    $topStrategies = $scores.Keys | sort {$scores[$_].Score} -Descending | select -First 5
    
    Write-Host "✅ Top 5 strategies ranked:`n"
    $topStrategies | foreach -Index 0 {
        Write-Host "  $($_ + 1). $($scores[$_].Strategy.Name) (Score: $([math]::Round($scores[$_].Score, 1)))" -ForegroundColor Yellow
        $scores[$_].Reasons | foreach {Write-Host "     - $_" -ForegroundColor Gray}
    }
    
    # Build hybrid plan from top strategies
    $selectedStrategies = $topStrategies | foreach {$scores[$_].Strategy}
    
    $hybridPlan = New-HybridOptimizationPlan -TaskProfile $TaskProfile -DataProfile $DataProfile
    
    return @{
        TopRankedStrategies = $selectedStrategies
        HybridPlan = $hybridPlan
        ScoresDetail = $scores
    }
}

#===================================================================================================
# EXPORT FUNCTIONS
#===================================================================================================

Export-ModuleMember -Function @(
    "Get-AllOptimizationStrategies"
    "New-HybridOptimizationPlan"
    "Invoke-StrategySynergyAnalysis"
    "Build-ModelMixingStrategy"
    "Build-BackupChains"
    "Build-TaskRouting"
    "Invoke-ContinuousLearning"
    "Get-OptimalHybridPlan"
)
