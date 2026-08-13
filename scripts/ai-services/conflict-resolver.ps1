<#
.SYNOPSIS
Conflict Resolver - Detect and resolve conflicting AI suggestions

.DESCRIPTION
Identifies conflicting suggestions from different AI services, analyzes alternatives,
applies user preferences, and learns from resolutions to improve future decisions.

.EXAMPLE
$resolver = New-ConflictResolver -ConfigPath $configPath
$resolution = $resolver.ResolveConflict($suggestions)
#>

param(
    [string]$ConfigPath = "C:\Users\ADMIN\helios-platform\config\ai-services\ai-services-config.json",
    [string]$LogPath = "C:\Users\ADMIN\helios-platform\logs\ai-services"
)

class ConflictResolver {
    [hashtable]$Config
    [System.IO.StreamWriter]$Logger
    [hashtable]$ResolutionHistory
    [hashtable]$UserPreferences
    [hashtable]$ConflictPatterns
    
    ConflictResolver([hashtable]$Config, [string]$LogPath) {
        $this.Config = $Config
        $this.ResolutionHistory = @{}
        $this.UserPreferences = @{}
        $this.ConflictPatterns = @{}
        $this.InitializeLogger($LogPath)
        $this.LogInfo("Conflict Resolver initialized successfully")
    }
    
    [void]InitializeLogger([string]$LogPath) {
        if (-not (Test-Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        $logFile = Join-Path $LogPath "resolver_$(Get-Date -Format 'yyyy-MM-dd').log"
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
    
    [void]LogWarning([string]$Message) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $this.Logger.WriteLine("[$timestamp] [WARNING] $Message")
    }
    
    [void]LogDebug([string]$Message) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $this.Logger.WriteLine("[$timestamp] [DEBUG] $Message")
    }
    
    [array]DetectConflicts([array]$Suggestions) {
        try {
            $this.LogInfo("Detecting conflicts in $($Suggestions.Count) suggestions")
            $conflicts = @()
            
            for ($i = 0; $i -lt $Suggestions.Count; $i++) {
                for ($j = $i + 1; $j -lt $Suggestions.Count; $j++) {
                    $conflict = $this.CompareAndAnalyzeSuggestions($Suggestions[$i], $Suggestions[$j])
                    
                    if ($conflict.IsConflict) {
                        $conflicts += $conflict
                        $this.LogWarning("Conflict detected between $($Suggestions[$i].Service) and $($Suggestions[$j].Service)")
                    }
                }
            }
            
            return $conflicts
        }
        catch {
            $this.LogError("Error detecting conflicts: $_")
            return @()
        }
    }
    
    [PSCustomObject]CompareAndAnalyzeSuggestions([PSCustomObject]$Suggestion1, [PSCustomObject]$Suggestion2) {
        $similarity = $this.CalculateSimilarity($Suggestion1.Content, $Suggestion2.Content)
        $conflictThreshold = $this.Config.coordination.conflictThreshold
        
        $conflict = @{
            IsConflict = $similarity -lt $conflictThreshold
            Service1 = $Suggestion1.Service
            Service2 = $Suggestion2.Service
            Content1 = $Suggestion1.Content
            Content2 = $Suggestion2.Content
            Similarity = $similarity
            Confidence1 = $Suggestion1.Confidence ?? 0.5
            Confidence2 = $Suggestion2.Confidence ?? 0.5
            Timestamp = Get-Date
        }
        
        if ($conflict.IsConflict) {
            $conflict['ConflictType'] = $this.ClassifyConflict($Suggestion1, $Suggestion2)
            $conflict['Severity'] = $this.AssessConflictSeverity($Suggestion1, $Suggestion2, $similarity)
        }
        
        return [PSCustomObject]$conflict
    }
    
    [double]CalculateSimilarity([string]$Text1, [string]$Text2) {
        # Normalize texts
        $norm1 = $Text1.ToLower() -replace "[^a-z0-9\s]", ""
        $norm2 = $Text2.ToLower() -replace "[^a-z0-9\s]", ""
        
        if ($norm1 -eq $norm2) { return 1.0 }
        if ($norm1.Length -eq 0 -or $norm2.Length -eq 0) { return 0.0 }
        
        # Calculate Levenshtein distance as approximation
        $maxLen = [Math]::Max($norm1.Length, $norm2.Length)
        $matches = 0
        $minLen = [Math]::Min($norm1.Length, $norm2.Length)
        
        for ($i = 0; $i -lt $minLen; $i++) {
            if ($norm1[$i] -eq $norm2[$i]) { $matches++ }
        }
        
        return [double]$matches / $maxLen
    }
    
    [string]ClassifyConflict([PSCustomObject]$Suggestion1, [PSCustomObject]$Suggestion2) {
        $content1 = $Suggestion1.Content.ToLower()
        $content2 = $Suggestion2.Content.ToLower()
        
        # Analyze keywords for conflict classification
        if (($content1 -match "use|implement") -and ($content2 -match "don't|avoid|not")) {
            return "Contradictory"
        }
        elseif (($content1 -match "performance|speed|fast") -or ($content2 -match "readability|clarity")) {
            return "TradeOff"
        }
        elseif (($content1 -match "different|alternative") -or ($content2 -match "different|alternative")) {
            return "Alternative"
        }
        else {
            return "Unclassified"
        }
    }
    
    [string]AssessConflictSeverity([PSCustomObject]$Suggestion1, [PSCustomObject]$Suggestion2, [double]$Similarity) {
        $severityScore = (1 - $Similarity) * 100
        $confidenceDiff = [Math]::Abs(($Suggestion1.Confidence ?? 0.5) - ($Suggestion2.Confidence ?? 0.5))
        
        $totalSeverity = ($severityScore * 0.6) + ($confidenceDiff * 100 * 0.4)
        
        if ($totalSeverity -lt 20) { return "Low" }
        elseif ($totalSeverity -lt 50) { return "Medium" }
        elseif ($totalSeverity -lt 80) { return "High" }
        else { return "Critical" }
    }
    
    [PSCustomObject]ResolveConflict([array]$Suggestions, [hashtable]$UserContext = @{}) {
        try {
            $this.LogInfo("Resolving conflict with $($Suggestions.Count) suggestions")
            
            # Detect conflicts
            $conflicts = $this.DetectConflicts($Suggestions)
            
            if ($conflicts.Count -eq 0) {
                $this.LogInfo("No conflicts detected. Returning consensus.")
                return @{
                    HasConflicts = $false
                    Resolution = "No conflicts detected"
                    Recommendation = $this.CreateConsensusRecommendation($Suggestions)
                }
            }
            
            # Apply resolution strategies
            $resolution = $this.ApplyResolutionStrategy($Suggestions, $conflicts, $UserContext)
            
            # Record resolution for learning
            $this.RecordResolution($Suggestions, $conflicts, $resolution)
            
            return $resolution
        }
        catch {
            $this.LogError("Error resolving conflict: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    [PSCustomObject]ApplyResolutionStrategy([array]$Suggestions, [array]$Conflicts, [hashtable]$UserContext) {
        $this.LogDebug("Applying resolution strategy for $($Conflicts.Count) conflicts")
        
        # Strategy 1: Apply user preferences
        if ($UserContext.ContainsKey('preferences')) {
            $preferred = $this.ApplyUserPreferences($Suggestions, $UserContext.preferences)
            if ($preferred) {
                return @{
                    HasConflicts = $true
                    ConflictCount = $Conflicts.Count
                    ResolutionMethod = "UserPreference"
                    Recommendation = $preferred
                    Details = "Resolved using user preferences"
                }
            }
        }
        
        # Strategy 2: Confidence-based resolution
        $confidenceResolution = $this.ResolveByConfidence($Suggestions)
        if ($confidenceResolution) {
            return @{
                HasConflicts = $true
                ConflictCount = $Conflicts.Count
                ResolutionMethod = "ConfidenceWeighting"
                Recommendation = $confidenceResolution.Recommendation
                Details = "Resolved using confidence scores"
                Winner = $confidenceResolution.Winner
                Confidence = $confidenceResolution.ConfidenceScore
            }
        }
        
        # Strategy 3: Comparative analysis
        $comparison = $this.CompareAlternatives($Suggestions, $Conflicts)
        return @{
            HasConflicts = $true
            ConflictCount = $Conflicts.Count
            ResolutionMethod = "ComparativeAnalysis"
            Recommendation = $comparison.Recommendation
            Alternatives = $comparison.Alternatives
            Details = "Multiple valid approaches identified"
        }
    }
    
    [PSCustomObject]ApplyUserPreferences([array]$Suggestions, [hashtable]$Preferences) {
        foreach ($suggestion in $Suggestions) {
            $match = $false
            
            foreach ($pref in $Preferences.GetEnumerator()) {
                if ($suggestion.Content -match $pref.Value) {
                    $match = $true
                    break
                }
            }
            
            if ($match) {
                return $suggestion
            }
        }
        
        return $null
    }
    
    [PSCustomObject]ResolveByConfidence([array]$Suggestions) {
        $suggestionsWithConfidence = $Suggestions | Where-Object { $_.Confidence } | Sort-Object -Property Confidence -Descending
        
        if ($suggestionsWithConfidence.Count -gt 0) {
            $winner = $suggestionsWithConfidence[0]
            $averageConfidence = ($suggestionsWithConfidence | Measure-Object -Property Confidence -Average).Average
            
            return @{
                Recommendation = $winner.Content
                Winner = $winner.Service
                ConfidenceScore = [Math]::Round($averageConfidence, 2)
            }
        }
        
        return $null
    }
    
    [PSCustomObject]CompareAlternatives([array]$Suggestions, [array]$Conflicts) {
        $alternatives = @()
        
        foreach ($suggestion in $Suggestions) {
            $analysis = @{
                Service = $suggestion.Service
                Suggestion = $suggestion.Content
                Confidence = $suggestion.Confidence ?? 0.5
                Pros = $this.ExtractPros($suggestion.Content)
                Cons = $this.ExtractCons($suggestion.Content)
                ComplexityScore = $this.CalculateComplexity($suggestion.Content)
            }
            
            $alternatives += [PSCustomObject]$analysis
        }
        
        return @{
            Recommendation = "Multiple valid approaches. Choose based on requirements:"
            Alternatives = $alternatives
            ComparisonMetrics = @{
                Complexity = ($alternatives | Measure-Object -Property ComplexityScore -Average).Average
                Coverage = $alternatives.Count
            }
        }
    }
    
    [array]ExtractPros([string]$Content) {
        $pros = @()
        
        $keywords = "advantage|benefit|improved|faster|simpler|efficient|scalable|robust|secure"
        $lines = $Content -split "`n"
        
        foreach ($line in $lines) {
            if ($line -match $keywords) {
                $pros += $line.Trim()
            }
        }
        
        return $pros[0..([Math]::Min(3, $pros.Count - 1))]
    }
    
    [array]ExtractCons([string]$Content) {
        $cons = @()
        
        $keywords = "disadvantage|drawback|slower|complex|difficult|risk|issue|problem"
        $lines = $Content -split "`n"
        
        foreach ($line in $lines) {
            if ($line -match $keywords) {
                $cons += $line.Trim()
            }
        }
        
        return $cons[0..([Math]::Min(3, $cons.Count - 1))]
    }
    
    [int]CalculateComplexity([string]$Content) {
        $complexity = 0
        
        # Count technical terms
        if ($Content -match "algorithm|architecture|pattern|framework") { $complexity += 20 }
        if ($Content -match "database|cache|queue|distributed") { $complexity += 15 }
        if ($Content -match "async|concurrent|parallel|threading") { $complexity += 15 }
        if ($Content -match "security|encryption|authentication") { $complexity += 10 }
        
        # Count code complexity indicators
        $complexity += ([regex]::Matches($Content, 'if|for|while|case')).Count * 5
        
        return [Math]::Min($complexity, 100)
    }
    
    [PSCustomObject]CreateConsensusRecommendation([array]$Suggestions) {
        if ($Suggestions.Count -eq 1) {
            return @{
                Type = "SingleSuggestion"
                Content = $Suggestions[0].Content
                Service = $Suggestions[0].Service
            }
        }
        
        # Merge complementary suggestions
        $merged = ""
        $avgConfidence = 0
        
        foreach ($suggestion in $Suggestions) {
            $merged += "`n=== $($suggestion.Service) ===`n$($suggestion.Content)"
            $avgConfidence += ($suggestion.Confidence ?? 0.5)
        }
        
        $avgConfidence = $avgConfidence / $Suggestions.Count
        
        return @{
            Type = "Consensus"
            Content = $merged
            Services = ($Suggestions | ForEach-Object { $_.Service }) -join ", "
            AverageConfidence = [Math]::Round($avgConfidence, 2)
        }
    }
    
    [void]RecordResolution([array]$Suggestions, [array]$Conflicts, [PSCustomObject]$Resolution) {
        $key = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        
        $this.ResolutionHistory[$key] = @{
            SuggestionCount = $Suggestions.Count
            ConflictCount = $Conflicts.Count
            ResolutionMethod = $Resolution.ResolutionMethod ?? "Unknown"
            Services = ($Suggestions | ForEach-Object { $_.Service }) -join ","
            Timestamp = Get-Date
        }
        
        # Update patterns
        $this.UpdateConflictPatterns($Conflicts)
        
        $this.LogInfo("Resolution recorded. Method: $($Resolution.ResolutionMethod)")
    }
    
    [void]UpdateConflictPatterns([array]$Conflicts) {
        foreach ($conflict in $Conflicts) {
            $key = "$($conflict.Service1)_vs_$($conflict.Service2)"
            
            if (-not $this.ConflictPatterns.ContainsKey($key)) {
                $this.ConflictPatterns[$key] = @{
                    Count = 0
                    Types = @{}
                }
            }
            
            $this.ConflictPatterns[$key].Count++
            
            $conflictType = $conflict.ConflictType ?? "Unclassified"
            if (-not $this.ConflictPatterns[$key].Types.ContainsKey($conflictType)) {
                $this.ConflictPatterns[$key].Types[$conflictType] = 0
            }
            
            $this.ConflictPatterns[$key].Types[$conflictType]++
        }
    }
    
    [void]SetUserPreference([string]$Key, [string]$Pattern) {
        $this.UserPreferences[$Key] = $Pattern
        $this.LogInfo("User preference set: $Key => $Pattern")
    }
    
    [PSCustomObject]GetConflictStatistics() {
        $stats = @{
            TotalResolutions = $this.ResolutionHistory.Count
            TotalConflicts = ($this.ResolutionHistory.Values | Measure-Object -Property ConflictCount -Sum).Sum
            CommonPatterns = @()
        }
        
        foreach ($pattern in $this.ConflictPatterns.GetEnumerator()) {
            $stats.CommonPatterns += [PSCustomObject]@{
                ServicePair = $pattern.Name
                ConflictCount = $pattern.Value.Count
                Types = $pattern.Value.Types
            }
        }
        
        return [PSCustomObject]$stats
    }
    
    [void]Close() {
        $this.Logger.Close()
    }
}

# ============================================================================
# MAIN
# ============================================================================

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $resolver = [ConflictResolver]::new($config, $LogPath)
    $script:ConflictResolver = $resolver
    
    if ($PSBoundParameters.Count -eq 0 -and $MyInvocation.ScriptName -eq $PSCommandPath) {
        Write-Host "Conflict Resolver initialized successfully"
        Write-Host "Usage: `$result = `$ConflictResolver.ResolveConflict(`$suggestions)"
        Write-Host "        `$ConflictResolver.GetConflictStatistics()"
    }
}
catch {
    Write-Error "Failed to initialize Conflict Resolver: $_"
    exit 1
}
