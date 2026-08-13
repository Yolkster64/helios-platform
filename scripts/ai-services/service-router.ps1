<#
.SYNOPSIS
Service Router - Intelligent task routing to optimal AI services

.DESCRIPTION
Routes tasks to the best AI service based on task type, performance metrics,
cost considerations, and service availability. Combines results from multiple
services with intelligent weighting and consensus mechanisms.

.EXAMPLE
$router = New-ServiceRouter -ConfigPath $configPath
$result = $router.RouteTask("code-review", $codeContent)
#>

param(
    [string]$ConfigPath = "C:\Users\ADMIN\helios-platform\config\ai-services\service-weights.json",
    [string]$LogPath = "C:\Users\ADMIN\helios-platform\logs\ai-services"
)

class ServiceRouter {
    [hashtable]$ServiceWeights
    [hashtable]$PerformanceMetrics
    [hashtable]$ServiceClients
    [System.IO.StreamWriter]$Logger
    [hashtable]$RoutingHistory
    [hashtable]$CombinationStrategies
    
    ServiceRouter([string]$ConfigPath, [string]$LogPath) {
        $this.ServiceWeights = $this.LoadServiceWeights($ConfigPath)
        $this.PerformanceMetrics = $this.ServiceWeights.servicePerformance
        $this.RoutingHistory = @{}
        $this.CombinationStrategies = $this.ServiceWeights.combinationStrategies
        $this.InitializeLogger($LogPath)
        $this.LogInfo("Service Router initialized successfully")
    }
    
    [hashtable]LoadServiceWeights([string]$Path) {
        try {
            if (-not (Test-Path $Path)) {
                throw "Service weights configuration not found: $Path"
            }
            $weights = Get-Content $Path -Raw | ConvertFrom-Json | ConvertTo-Hashtable
            return $weights
        }
        catch {
            Write-Error "Failed to load service weights: $_"
            throw
        }
    }
    
    [void]InitializeLogger([string]$LogPath) {
        if (-not (Test-Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        $logFile = Join-Path $LogPath "router_$(Get-Date -Format 'yyyy-MM-dd').log"
        $this.Logger = [System.IO.StreamWriter]::new($logFile, $true)
        $this.Logger.AutoFlush = $true
    }
    
    [void]LogInfo([string]$Message) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $this.Logger.WriteLine("[$timestamp] [INFO] $Message")
    }
    
    [void]LogError([string]$Message) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $this.Logger.WriteLine("[$timestamp] [ERROR] $Message")
    }
    
    [void]LogDebug([string]$Message) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $this.Logger.WriteLine("[$timestamp] [DEBUG] $Message")
    }
    
    [array]DetermineOptimalServices([string]$TaskType) {
        try {
            $this.LogInfo("Determining optimal services for task type: $TaskType")
            
            $taskConfig = $this.ServiceWeights.taskTypeToServices[$TaskType]
            
            if (-not $taskConfig) {
                $this.LogWarning("Unknown task type: $TaskType. Using all available services.")
                return @("chatgpt-pro", "codex", "gpt-4-5")
            }
            
            $services = @()
            
            # Add primary service
            if ($taskConfig.primary) {
                $services += $taskConfig.primary
            }
            
            # Add secondary services if available
            if ($taskConfig.secondary) {
                $services += $taskConfig.secondary
            }
            
            $this.LogDebug("Services for $TaskType : $($services -join ', ')")
            return $services
        }
        catch {
            $this.LogError("Error determining optimal services: $_")
            return @()
        }
    }
    
    [PSCustomObject]RouteTask([string]$TaskType, [string]$Content, [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Routing task: $TaskType (Content length: $($Content.Length) chars)")
            
            $services = $this.DetermineOptimalServices($TaskType)
            
            if ($services.Count -eq 0) {
                throw "No suitable services found for task type: $TaskType"
            }
            
            # Prioritize services by weight and performance
            $prioritizedServices = $this.PrioritizeServices($services, $TaskType)
            
            # Route to primary service first
            $primaryService = $prioritizedServices[0]
            $this.LogInfo("Primary service selected: $primaryService")
            
            $result = @{
                TaskType = $TaskType
                PrimaryService = $primaryService
                Services = $prioritizedServices
                Results = @()
                Status = "Pending"
                Timestamp = Get-Date
            }
            
            # If multiple services needed, collect results
            if ($prioritizedServices.Count -gt 1 -and $Options.ContainsKey('multiService')) {
                $this.LogInfo("Multi-service analysis requested. Total services: $($prioritizedServices.Count)")
                $result.Results = $this.CollectMultiServiceResults($prioritizedServices, $TaskType, $Content, $Options)
                $result.CombinedResult = $this.CombineResults($result.Results, $TaskType, $Options)
                $result.Status = "Completed"
            }
            else {
                # Single service routing
                $result.Status = "Routed"
            }
            
            # Track routing decision
            $this.TrackRoutingDecision($TaskType, $primaryService, $prioritizedServices)
            
            return $result
        }
        catch {
            $this.LogError("Task routing failed: $_")
            return @{
                Success = $false
                Error = $_
                Timestamp = Get-Date
            }
        }
    }
    
    [array]PrioritizeServices([array]$Services, [string]$TaskType) {
        $taskConfig = $this.ServiceWeights.taskTypeToServices[$TaskType]
        
        $prioritized = $Services | ForEach-Object {
            $service = $_
            $performance = $this.PerformanceMetrics[$service]
            
            # Calculate priority score
            $weight = if ($service -eq $taskConfig.primary) { 1.0 } else { 0.7 }
            $successScore = $performance.successRate * 0.4
            $efficiencyScore = $performance.costEfficiency * 0.3
            $speedScore = (1 / $performance.averageResponseTime) * 0.3
            
            $score = ($weight * 100) + $successScore + $efficiencyScore + $speedScore
            
            [PSCustomObject]@{
                Service = $service
                Score = $score
                Weight = $weight
                Performance = $performance
            }
        } | Sort-Object -Property Score -Descending
        
        return $prioritized | ForEach-Object { $_.Service }
    }
    
    [array]CollectMultiServiceResults([array]$Services, [string]$TaskType, [string]$Content, [hashtable]$Options) {
        $results = @()
        
        foreach ($service in $Services) {
            try {
                $this.LogInfo("Calling service: $service")
                
                # Simulate service call (in production, would call actual service)
                $result = $this.CallServiceForRouting($service, $TaskType, $Content, $Options)
                
                $results += [PSCustomObject]@{
                    Service = $service
                    Response = $result.Response
                    Score = $result.Score
                    Cost = $result.Cost
                    ResponseTime = $result.ResponseTime
                    Status = "Success"
                }
            }
            catch {
                $this.LogError("Service $service failed: $_")
                $results += [PSCustomObject]@{
                    Service = $service
                    Status = "Failed"
                    Error = $_.Exception.Message
                }
            }
        }
        
        return $results
    }
    
    [PSCustomObject]CallServiceForRouting([string]$ServiceName, [string]$TaskType, [string]$Content, [hashtable]$Options) {
        # In production, would call actual service clients
        $responseTime = Get-Random -Minimum 1 -Maximum 10
        
        return @{
            Response = "Response from $ServiceName for $TaskType (Content: $($Content.Length) chars)"
            Score = [Math]::Round((Get-Random -Minimum 0.7 -Maximum 1.0), 2)
            Cost = [Math]::Round((Get-Random -Minimum 0.01 -Maximum 0.50), 4)
            ResponseTime = [Math]::Round(($responseTime), 2)
            Tokens = Get-Random -Minimum 100 -Maximum 2000
        }
    }
    
    [PSCustomObject]CombineResults([array]$Results, [string]$TaskType, [hashtable]$Options) {
        $this.LogInfo("Combining results from $($Results.Count) services")
        
        # Filter successful results
        $successfulResults = $Results | Where-Object { $_.Status -eq "Success" }
        
        if ($successfulResults.Count -eq 0) {
            return @{
                Success = $false
                Message = "No successful results from any service"
            }
        }
        
        # Determine combination strategy
        $strategy = $Options['combinationStrategy'] ?? "consensus"
        
        switch ($strategy) {
            "consensus" {
                return $this.CreateConsensus($successfulResults, $TaskType)
            }
            "hierarchical" {
                return $this.HierarchicalCombination($successfulResults, $TaskType)
            }
            "complementary" {
                return $this.ComplementaryCombination($successfulResults, $TaskType)
            }
            "weighted-voting" {
                return $this.WeightedVoting($successfulResults)
            }
            default {
                return $this.CreateConsensus($successfulResults, $TaskType)
            }
        }
        return $null
    }

    [PSCustomObject]CreateConsensus([array]$Results, [string]$TaskType) {
        $this.LogDebug("Creating consensus from $($Results.Count) results")
        
        $totalScore = 0
        $combinedResponse = ""
        
        foreach ($result in $Results) {
            $totalScore += $result.Score
            $combinedResponse += "`n=== $($result.Service) (Score: $($result.Score)) ===`n$($result.Response)"
        }
        
        $averageScore = $totalScore / $Results.Count
        
        return @{
            Type = "Consensus"
            CombinedResponse = $combinedResponse
            AverageScore = [Math]::Round($averageScore, 2)
            ServiceCount = $Results.Count
            Services = ($Results | ForEach-Object { $_.Service }) -join ", "
            Confidence = [Math]::Min(0.99, $averageScore + 0.1)
        }
    }
    
    [PSCustomObject]HierarchicalCombination([array]$Results, [string]$TaskType) {
        $this.LogDebug("Using hierarchical combination")
        
        # Sort by score descending
        $sorted = $Results | Sort-Object -Property Score -Descending
        
        # Primary response from highest scoring service
        $primaryResult = $sorted[0]
        $secondaryInsights = ""
        
        if ($sorted.Count -gt 1) {
            foreach ($result in $sorted[1..($sorted.Count - 1)]) {
                $secondaryInsights += "`n--- Additional insight from $($result.Service) ---`n$($result.Response)"
            }
        }
        
        return @{
            Type = "Hierarchical"
            PrimaryService = $primaryResult.Service
            PrimaryResponse = $primaryResult.Response
            SecondaryInsights = $secondaryInsights
            PrimaryScore = $primaryResult.Score
        }
    }
    
    [PSCustomObject]ComplementaryCombination([array]$Results, [string]$TaskType) {
        $this.LogDebug("Using complementary combination")
        
        $combinedResponse = ""
        $perspectives = @()
        
        foreach ($result in $Results) {
            $perspectives += [PSCustomObject]@{
                Service = $result.Service
                Score = $result.Score
                Insight = $result.Response
            }
            
            $combinedResponse += "`n=== $($result.Service) Perspective ===`n$($result.Response)"
        }
        
        return @{
            Type = "Complementary"
            Perspectives = $perspectives
            CombinedAnalysis = $combinedResponse
            PerspectiveCount = $Results.Count
            Recommendation = $this.GenerateComplementaryRecommendation($perspectives)
        }
    }
    
    [PSCustomObject]WeightedVoting([array]$Results) {
        $this.LogDebug("Performing weighted voting")
        
        $totalWeight = 0
        $weightedScore = 0
        $votes = @()
        
        foreach ($result in $Results) {
            $weight = $result.Score
            $totalWeight += $weight
            $weightedScore += $weight
            
            $votes += @{
                Service = $result.Service
                Vote = $result.Score
                Weight = $weight
            }
        }
        
        $averageWeightedScore = $weightedScore / $Results.Count
        
        return @{
            Type = "WeightedVoting"
            Votes = $votes
            AverageWeightedScore = [Math]::Round($averageWeightedScore, 2)
            Winner = ($Results | Sort-Object -Property Score -Descending | Select-Object -First 1).Service
            Confidence = [Math]::Round($averageWeightedScore, 2)
        }
    }
    
    [string]GenerateComplementaryRecommendation([array]$Perspectives) {
        $recommendation = "Synthesized recommendation based on multiple perspectives:`n`n"
        
        # Find high-confidence perspectives
        $highConfidence = $Perspectives | Where-Object { $_.Score -gt 0.8 }
        
        if ($highConfidence) {
            $recommendation += "High-confidence insights:`n"
            foreach ($p in $highConfidence) {
                $recommendation += "- $($p.Service): $(($p.Insight -split "`n")[0])`n"
            }
        }
        
        return $recommendation
    }
    
    [void]TrackRoutingDecision([string]$TaskType, [string]$PrimaryService, [array]$AllServices) {
        $key = "$TaskType`_$(Get-Date -Format 'yyyy-MM-dd')"
        
        if (-not $this.RoutingHistory.ContainsKey($key)) {
            $this.RoutingHistory[$key] = @{
                TaskType = $TaskType
                Decisions = @()
            }
        }
        
        $this.RoutingHistory[$key].Decisions += @{
            PrimaryService = $PrimaryService
            AllServices = $AllServices -join ","
            Timestamp = Get-Date
        }
    }
    
    [PSCustomObject]GetRoutingStats([string]$TaskType = "") {
        $stats = @()
        
        foreach ($key in $this.RoutingHistory.Keys) {
            if ($TaskType -eq "" -or $key.StartsWith($TaskType)) {
                $entry = $this.RoutingHistory[$key]
                $stats += [PSCustomObject]@{
                    TaskType = $entry.TaskType
                    Date = ($key -split "_")[1]
                    TotalDecisions = $entry.Decisions.Count
                    PrimaryServices = (($entry.Decisions | ForEach-Object { $_.PrimaryService } | Sort-Object -Unique) -join ",")
                }
            }
        }
        
        return $stats
    }
    
    [PSCustomObject]GetServiceEffectiveness() {
        $effectiveness = @()
        
        foreach ($service in $this.PerformanceMetrics.PSObject.Properties.Name) {
            $perf = $this.PerformanceMetrics[$service]
            $effectiveness += [PSCustomObject]@{
                Service = $service
                SuccessRate = "$($perf.successRate * 100)%"
                AverageResponseTime = "$($perf.averageResponseTime)s"
                CostEfficiency = $perf.costEfficiency
            }
        }
        
        return $effectiveness | Sort-Object -Property CostEfficiency -Descending
    }
    
    [void]Close() {
        $this.Logger.Close()
        $this.LogInfo("Service Router closed")
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function ConvertTo-Hashtable {
    param(
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]$InputObject
    )
    
    $hash = @{}
    $InputObject.PSObject.Properties | ForEach-Object {
        if ($_.Value -is [PSCustomObject]) {
            $hash[$_.Name] = ConvertTo-Hashtable $_.Value
        }
        elseif ($_.Value -is [array]) {
            $hash[$_.Name] = @($_.Value)
        }
        else {
            $hash[$_.Name] = $_.Value
        }
    }
    return $hash
}

# ============================================================================
# MAIN
# ============================================================================

try {
    $router = [ServiceRouter]::new($ConfigPath, $LogPath)
    $script:ServiceRouter = $router
    
    if ($PSBoundParameters.Count -eq 0 -and $MyInvocation.ScriptName -eq $PSCommandPath) {
        Write-Host "Service Router initialized successfully"
        Write-Host "Usage: `$result = `$ServiceRouter.RouteTask(`"code-review`", `$codeContent)"
        Write-Host "        `$ServiceRouter.GetServiceEffectiveness()"
    }
}
catch {
    Write-Error "Failed to initialize Service Router: $_"
    exit 1
}
