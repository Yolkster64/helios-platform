<#
.SYNOPSIS
GPT-4.5 Client - Advanced reasoning and analysis

.DESCRIPTION
Handles communication with OpenAI's GPT-4.5 API for complex analysis,
architectural decisions, and advanced reasoning with long context support.

.EXAMPLE
$client = New-GPT45Client -ApiKey $apiKey -ConfigPath $configPath
$response = $client.AnalyzeArchitecture($systemDescription)
#>

param(
    [string]$ApiKey = $env:OPENAI_API_KEY_GPT45,
    [string]$ConfigPath = "C:\Users\ADMIN\helios-platform\config\ai-services\ai-services-config.json"
)

class GPT45Client {
    [string]$ApiKey
    [hashtable]$Config
    [string]$BaseUrl = "https://api.openai.com/v1"
    [System.Net.Http.HttpClient]$HttpClient
    [System.IO.StreamWriter]$Logger
    [hashtable]$RequestStats
    [hashtable]$RetryPolicy
    [array]$ConversationHistory
    
    GPT45Client([string]$ApiKey, [hashtable]$Config) {
        if ([string]::IsNullOrEmpty($ApiKey)) {
            throw "API key is required for GPT-4.5 client"
        }
        
        $this.ApiKey = $ApiKey
        $this.Config = $Config
        $this.InitializeHttpClient()
        $this.InitializeLogger()
        $this.InitializeRetryPolicy()
        $this.InitializeStats()
        $this.ConversationHistory = @()
    }
    
    [void]InitializeHttpClient() {
        $this.HttpClient = New-Object System.Net.Http.HttpClient
        $this.HttpClient.DefaultRequestHeaders.Add("Authorization", "Bearer $($this.ApiKey)")
        $this.HttpClient.DefaultRequestHeaders.Add("Content-Type", "application/json")
        $timeout = $this.Config.services.'gpt-4-5'.timeout
        $this.HttpClient.Timeout = [TimeSpan]::FromSeconds($timeout)
    }
    
    [void]InitializeLogger() {
        $logPath = $this.Config.logging.logPath
        if (-not (Test-Path $logPath)) {
            New-Item -ItemType Directory -Path $logPath -Force | Out-Null
        }
        $logFile = Join-Path $logPath "gpt-4-5_$(Get-Date -Format 'yyyy-MM-dd').log"
        $this.Logger = [System.IO.StreamWriter]::new($logFile, $true)
        $this.Logger.AutoFlush = $true
    }
    
    [void]InitializeRetryPolicy() {
        $this.RetryPolicy = @{
            MaxRetries = $this.Config.services.'gpt-4-5'.retries
            RetryDelay = $this.Config.services.'gpt-4-5'.retryDelay
            BackoffMultiplier = 2
            MaxBackoffDelay = 60
        }
    }
    
    [void]InitializeStats() {
        $this.RequestStats = @{
            TotalRequests = 0
            AnalysisRequests = 0
            ArchitectureRequests = 0
            SuccessfulRequests = 0
            FailedRequests = 0
            TotalTokensUsed = 0
            TotalCost = 0
            AveageResponseTime = 0
        }
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
    
    [PSCustomObject]AnalyzeComplexProblem([string]$ProblemStatement, [hashtable]$Context = @{}, [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Analyzing complex problem")
            $this.RequestStats.AnalysisRequests++
            
            # Build prompt with context
            $prompt = $this.BuildAnalysisPrompt($ProblemStatement, $Context)
            
            # Prepare request
            $requestBody = $this.PrepareRequestBody($prompt, $Options)
            
            # Invoke with retries
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Complex analysis completed. Tokens: $($response.usage.total_tokens)")
            
            # Add to conversation history
            $this.AddToHistory("user", $ProblemStatement)
            $this.AddToHistory("assistant", $response.choices[0].message.content)
            
            return @{
                Success = $true
                Analysis = $response.choices[0].message.content
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                FinishReason = $response.choices[0].finish_reason
                Confidence = $this.EstimateConfidence($response.choices[0].message.content)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Complex analysis failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]AnalyzeArchitecture([string]$SystemDescription, [array]$Components, [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Analyzing system architecture")
            $this.RequestStats.ArchitectureRequests++
            
            # Build architecture analysis prompt
            $prompt = $this.BuildArchitecturePrompt($SystemDescription, $Components)
            
            $requestBody = $this.PrepareRequestBody($prompt, $Options)
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Architecture analysis completed")
            
            $analysis = $response.choices[0].message.content
            $this.AddToHistory("user", $prompt)
            $this.AddToHistory("assistant", $analysis)
            
            return @{
                Success = $true
                ArchitectureAnalysis = $analysis
                Recommendations = $this.ExtractRecommendations($analysis)
                RiskAssessment = $this.ExtractRisks($analysis)
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Architecture analysis failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]BugAnalysis([string]$ErrorMessage, [string]$Code, [string]$Context = "", [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Analyzing bug report")
            
            # Build bug analysis prompt
            $prompt = $this.BuildBugAnalysisPrompt($ErrorMessage, $Code, $Context)
            
            $requestBody = $this.PrepareRequestBody($prompt, $Options)
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Bug analysis completed")
            
            $analysis = $response.choices[0].message.content
            
            return @{
                Success = $true
                ErrorMessage = $ErrorMessage
                Analysis = $analysis
                RootCauseAnalysis = $this.ExtractRootCause($analysis)
                SuggestedFixes = $this.ExtractFixes($analysis)
                Severity = $this.EstimateSeverity($ErrorMessage)
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Bug analysis failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]SecurityReview([string]$Code, [string]$Language = "python", [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Performing security review on $Language code")
            
            # Build security review prompt
            $prompt = $this.BuildSecurityReviewPrompt($Code, $Language)
            
            $requestBody = $this.PrepareRequestBody($prompt, $Options)
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Security review completed")
            
            $review = $response.choices[0].message.content
            
            return @{
                Success = $true
                Code = $Code
                SecurityReview = $review
                Vulnerabilities = $this.ExtractVulnerabilities($review)
                Recommendations = $this.ExtractSecurityRecommendations($review)
                RiskLevel = $this.AssessRiskLevel($review)
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Security review failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]ContinueConversation([string]$UserMessage, [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Continuing conversation")
            
            # Add user message to history
            $this.AddToHistory("user", $UserMessage)
            
            # Prepare request with full conversation history
            $requestBody = $this.PrepareRequestBodyWithHistory($UserMessage, $Options)
            
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Conversation continued")
            
            $assistantMessage = $response.choices[0].message.content
            $this.AddToHistory("assistant", $assistantMessage)
            
            return @{
                Success = $true
                UserMessage = $UserMessage
                AssistantResponse = $assistantMessage
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Conversation continuation failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [string]BuildAnalysisPrompt([string]$ProblemStatement, [hashtable]$Context) {
        $contextStr = ""
        foreach ($key in $Context.Keys) {
            $contextStr += "`n$key : $($Context[$key])"
        }
        
        return @"
Perform a detailed analysis of the following problem:

Problem Statement:
$ProblemStatement

Context:
$contextStr

Please provide:
1. Problem decomposition
2. Root cause analysis
3. Potential solutions with pros/cons
4. Recommended approach
5. Implementation considerations
6. Risk assessment

Analysis:
"@
    }
    
    [string]BuildArchitecturePrompt([string]$SystemDescription, [array]$Components) {
        $componentList = ($Components | ForEach-Object { "- $_" }) -join "`n"
        
        return @"
Analyze the following system architecture:

System Description:
$SystemDescription

Components:
$componentList

Provide a comprehensive architecture review including:
1. Architecture strengths
2. Potential issues
3. Scalability concerns
4. Security considerations
5. Recommendations for improvement
6. Alternative approaches

Analysis:
"@
    }
    
    [string]BuildBugAnalysisPrompt([string]$ErrorMessage, [string]$Code, [string]$Context) {
        return @"
Analyze this bug report and help find the root cause:

Error Message:
$ErrorMessage

Code:
```
$Code
```

Additional Context:
$Context

Please provide:
1. Root cause identification
2. Why this error occurs
3. Suggested fixes with code examples
4. Prevention strategies
5. Related potential bugs to check

Analysis:
"@
    }
    
    [string]BuildSecurityReviewPrompt([string]$Code, [string]$Language) {
        return @"
Perform a security review of this $Language code:

```$Language
$Code
```

Identify and analyze:
1. Security vulnerabilities
2. Potential attack vectors
3. Input validation issues
4. Authentication/authorization problems
5. Data protection concerns
6. Recommended security improvements

Review:
"@
    }
    
    [hashtable]PrepareRequestBody([string]$Prompt, [hashtable]$Options) {
        $systemPrompt = $Options['system'] ?? "You are an expert AI architect and security analyst with deep knowledge of software systems."
        
        $requestBody = @{
            model = $this.Config.services.'gpt-4-5'.model
            messages = @(
                @{
                    role = "system"
                    content = $systemPrompt
                },
                @{
                    role = "user"
                    content = $Prompt
                }
            )
            temperature = $Options['temperature'] ?? $this.Config.services.'gpt-4-5'.temperature
            max_tokens = $Options['maxTokens'] ?? $this.Config.services.'gpt-4-5'.maxTokens
            top_p = $Options['topP'] ?? 1.0
        }
        
        return $requestBody
    }
    
    [hashtable]PrepareRequestBodyWithHistory([string]$UserMessage, [hashtable]$Options) {
        $systemPrompt = $Options['system'] ?? "You are an expert AI architect and security analyst with deep knowledge of software systems."
        
        # Build messages array with history
        $messages = @(@{
            role = "system"
            content = $systemPrompt
        })
        
        foreach ($historyItem in $this.ConversationHistory) {
            $messages += $historyItem
        }
        
        $requestBody = @{
            model = $this.Config.services.'gpt-4-5'.model
            messages = $messages
            temperature = $Options['temperature'] ?? $this.Config.services.'gpt-4-5'.temperature
            max_tokens = $Options['maxTokens'] ?? $this.Config.services.'gpt-4-5'.maxTokens
            top_p = $Options['topP'] ?? 1.0
        }
        
        return $requestBody
    }
    
    [void]AddToHistory([string]$Role, [string]$Content) {
        $this.ConversationHistory += @{
            role = $Role
            content = $Content
        }
    }
    
    [PSCustomObject]InvokeWithRetry([hashtable]$RequestBody) {
        $attempt = 0
        $delay = $this.RetryPolicy.RetryDelay
        
        while ($attempt -le $this.RetryPolicy.MaxRetries) {
            try {
                $response = $this.MakeHttpRequest($RequestBody)
                return $response
            }
            catch {
                $attempt++
                if ($attempt -gt $this.RetryPolicy.MaxRetries) {
                    throw
                }
                
                $this.LogWarning("Request failed. Retrying in ${delay}s: $_")
                Start-Sleep -Seconds $delay
                $delay = [Math]::Min($delay * $this.RetryPolicy.BackoffMultiplier, $this.RetryPolicy.MaxBackoffDelay)
            }
        }
        throw "Max retries exceeded"
    }
    
    [PSCustomObject]MakeHttpRequest([hashtable]$RequestBody) {
        $jsonBody = $RequestBody | ConvertTo-Json -Depth 10
        $content = New-Object System.Net.Http.StringContent($jsonBody, [System.Text.Encoding]::UTF8, "application/json")
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = $this.HttpClient.PostAsync("$($this.BaseUrl)/chat/completions", $content).Result
        $stopwatch.Stop()
        
        if (-not $response.IsSuccessStatusCode) {
            $errorContent = $response.Content.ReadAsStringAsync().Result
            throw "API request failed with status $($response.StatusCode): $errorContent"
        }
        
        $responseContent = $response.Content.ReadAsStringAsync().Result
        $responseObject = $responseContent | ConvertFrom-Json
        
        $this.RequestStats.TotalRequests++
        $this.RequestStats.TotalTokensUsed += $responseObject.usage.total_tokens
        $this.RequestStats.TotalCost += $this.CalculateCost($responseObject.usage)
        
        return $responseObject
    }
    
    [double]CalculateCost([PSCustomObject]$Usage) {
        $svcConfig = $this.Config.services.'gpt-4-5'
        $inputCost = ($Usage.prompt_tokens / 1000) * $svcConfig.costPerThousandTokens.input
        $outputCost = ($Usage.completion_tokens / 1000) * $svcConfig.costPerThousandTokens.output
        return $inputCost + $outputCost
    }
    
    [double]EstimateConfidence([string]$Response) {
        return [Math]::Min(0.95, 0.7 + ($Response.Length / 10000))
    }
    
    [string]ExtractRecommendations([string]$Text) {
        $lines = $Text -split "`n"
        $recommendations = $lines | Where-Object { $_ -match "recommendation|improve|should" } -join "`n"
        return if ($recommendations) { $recommendations } else { "See full analysis" }
    }
    
    [string]ExtractRisks([string]$Text) {
        $lines = $Text -split "`n"
        $risks = $lines | Where-Object { $_ -match "risk|concern|issue|problem" } -join "`n"
        return if ($risks) { $risks } else { "No critical risks identified" }
    }
    
    [string]ExtractRootCause([string]$Text) {
        $match = [regex]::Match($Text, "root cause[:\s]+([^`n]+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        return if ($match.Success) { $match.Groups[1].Value } else { $Text.Substring(0, [Math]::Min(200, $Text.Length)) }
    }
    
    [string]ExtractFixes([string]$Text) {
        return ($Text -split "`n" | Where-Object { $_ -match "fix|solution|patch|change" }) -join "`n"
    }
    
    [string]ExtractVulnerabilities([string]$Text) {
        return ($Text -split "`n" | Where-Object { $_ -match "vulnerability|exploit|attack" }) -join "`n"
    }
    
    [string]ExtractSecurityRecommendations([string]$Text) {
        return ($Text -split "`n" | Where-Object { $_ -match "recommendation|should|must|improve" }) -join "`n"
    }
    
    [string]AssessRiskLevel([string]$Text) {
        if ($Text -match "critical|severe|high risk") { return "Critical" }
        elseif ($Text -match "high|serious") { return "High" }
        elseif ($Text -match "medium|moderate") { return "Medium" }
        else { return "Low" }
    }
    
    [string]EstimateSeverity([string]$ErrorMessage) {
        if ($ErrorMessage -match "fatal|crash|seg fault|out of memory") { return "Critical" }
        elseif ($ErrorMessage -match "error|failed|exception") { return "High" }
        else { return "Medium" }
    }
    
    [PSCustomObject]GetStatistics() {
        return [PSCustomObject]@{
            TotalRequests = $this.RequestStats.TotalRequests
            AnalysisRequests = $this.RequestStats.AnalysisRequests
            ArchitectureRequests = $this.RequestStats.ArchitectureRequests
            SuccessfulRequests = $this.RequestStats.SuccessfulRequests
            FailedRequests = $this.RequestStats.FailedRequests
            SuccessRate = if ($this.RequestStats.TotalRequests -gt 0) {
                [Math]::Round(($this.RequestStats.SuccessfulRequests / $this.RequestStats.TotalRequests * 100), 2)
            } else { 0 }
            TotalTokensUsed = $this.RequestStats.TotalTokensUsed
            TotalCost = [Math]::Round($this.RequestStats.TotalCost, 4)
        }
    }
    
    [void]ClearHistory() {
        $this.ConversationHistory = @()
        $this.LogInfo("Conversation history cleared")
    }
    
    [void]Close() {
        $this.HttpClient.Dispose()
        $this.Logger.Close()
    }
}

# ============================================================================
# MAIN
# ============================================================================

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $client = [GPT45Client]::new($ApiKey, $config)
    
    $script:GPT45Client = $client
    
    if ($PSBoundParameters.Count -eq 0 -and $MyInvocation.ScriptName -eq $PSCommandPath) {
        Write-Host "GPT-4.5 Client initialized successfully"
        Write-Host "Usage: `$response = `$GPT45Client.AnalyzeComplexProblem(`"Your problem statement`")"
    }
}
catch {
    Write-Error "Failed to initialize GPT-4.5 Client: $_"
    exit 1
}
