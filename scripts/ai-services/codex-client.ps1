<#
.SYNOPSIS
Codex Client - Code generation and refactoring

.DESCRIPTION
Handles communication with OpenAI's Codex API for code generation,
code refactoring, and other code-related tasks with temperature control.

.EXAMPLE
$client = New-CodexClient -ApiKey $apiKey -ConfigPath $configPath
$response = $client.GenerateCode("Create a function that reverses a string", "python")
#>

param(
    [string]$ApiKey = $env:OPENAI_API_KEY_CODEX,
    [string]$ConfigPath = "C:\Users\ADMIN\helios-platform\config\ai-services\ai-services-config.json"
)

class CodexClient {
    [string]$ApiKey
    [hashtable]$Config
    [string]$BaseUrl = "https://api.openai.com/v1"
    [System.Net.Http.HttpClient]$HttpClient
    [System.IO.StreamWriter]$Logger
    [hashtable]$RequestStats
    [hashtable]$RetryPolicy
    
    CodexClient([string]$ApiKey, [hashtable]$Config) {
        if ([string]::IsNullOrEmpty($ApiKey)) {
            throw "API key is required for Codex client"
        }
        
        $this.ApiKey = $ApiKey
        $this.Config = $Config
        $this.InitializeHttpClient()
        $this.InitializeLogger()
        $this.InitializeRetryPolicy()
        $this.InitializeStats()
    }
    
    [void]InitializeHttpClient() {
        $this.HttpClient = New-Object System.Net.Http.HttpClient
        $this.HttpClient.DefaultRequestHeaders.Add("Authorization", "Bearer $($this.ApiKey)")
        $this.HttpClient.DefaultRequestHeaders.Add("Content-Type", "application/json")
        $timeout = $this.Config.services.codex.timeout
        $this.HttpClient.Timeout = [TimeSpan]::FromSeconds($timeout)
    }
    
    [void]InitializeLogger() {
        $logPath = $this.Config.logging.logPath
        if (-not (Test-Path $logPath)) {
            New-Item -ItemType Directory -Path $logPath -Force | Out-Null
        }
        $logFile = Join-Path $logPath "codex_$(Get-Date -Format 'yyyy-MM-dd').log"
        $this.Logger = [System.IO.StreamWriter]::new($logFile, $true)
        $this.Logger.AutoFlush = $true
    }
    
    [void]InitializeRetryPolicy() {
        $this.RetryPolicy = @{
            MaxRetries = $this.Config.services.codex.retries
            RetryDelay = $this.Config.services.codex.retryDelay
            BackoffMultiplier = 2
            MaxBackoffDelay = 60
        }
    }
    
    [void]InitializeStats() {
        $this.RequestStats = @{
            TotalRequests = 0
            GenerationRequests = 0
            RefactoringRequests = 0
            SuccessfulRequests = 0
            FailedRequests = 0
            TotalTokensUsed = 0
            TotalCost = 0
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
    
    [PSCustomObject]GenerateCode([string]$Description, [string]$Language = "python", [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Generating code for: $Description (Language: $Language)")
            $this.RequestStats.GenerationRequests++
            
            # Build prompt
            $prompt = $this.BuildGenerationPrompt($Description, $Language)
            
            # Prepare request with lower temperature for code generation
            $temperature = $Options['temperature'] ?? 0.5
            $requestBody = $this.PrepareRequestBody($prompt, $temperature, $Options)
            
            # Invoke with retries
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Code generated successfully. Tokens: $($response.usage.total_tokens)")
            
            $generatedCode = $response.choices[0].text.Trim()
            
            return @{
                Success = $true
                Code = $generatedCode
                Language = $Language
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Model = $response.model
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Code generation failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]RefactorCode([string]$Code, [string]$Language = "python", [string]$Objective = "improve readability", [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Refactoring $Language code. Objective: $Objective")
            $this.RequestStats.RefactoringRequests++
            
            # Build refactoring prompt
            $prompt = $this.BuildRefactoringPrompt($Code, $Language, $Objective)
            
            # Prepare request
            $temperature = $Options['temperature'] ?? 0.3
            $requestBody = $this.PrepareRequestBody($prompt, $temperature, $Options)
            
            # Invoke with retries
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Code refactored successfully. Tokens: $($response.usage.total_tokens)")
            
            $refactoredCode = $response.choices[0].text.Trim()
            
            return @{
                Success = $true
                OriginalCode = $Code
                RefactoredCode = $refactoredCode
                Language = $Language
                Objective = $Objective
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Changes = $this.AnalyzeChanges($Code, $refactoredCode)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Code refactoring failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]AnalyzeCode([string]$Code, [string]$Language = "python", [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Analyzing $Language code")
            
            # Build analysis prompt
            $prompt = $this.BuildAnalysisPrompt($Code, $Language)
            
            $temperature = $Options['temperature'] ?? 0.7
            $requestBody = $this.PrepareRequestBody($prompt, $temperature, $Options)
            
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Code analysis completed. Tokens: $($response.usage.total_tokens)")
            
            return @{
                Success = $true
                Code = $Code
                Analysis = $response.choices[0].text.Trim()
                Language = $Language
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Code analysis failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]TestGeneration([string]$Code, [string]$Language = "python", [string]$Framework = "pytest", [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Generating tests for $Language code using $Framework")
            
            # Build test generation prompt
            $prompt = $this.BuildTestGenerationPrompt($Code, $Language, $Framework)
            
            $temperature = $Options['temperature'] ?? 0.4
            $requestBody = $this.PrepareRequestBody($prompt, $temperature, $Options)
            
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Tests generated successfully. Tokens: $($response.usage.total_tokens)")
            
            return @{
                Success = $true
                SourceCode = $Code
                TestCode = $response.choices[0].text.Trim()
                Language = $Language
                Framework = $Framework
                TokensUsed = $response.usage.total_tokens
                Cost = $this.CalculateCost($response.usage)
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Test generation failed: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [string]BuildGenerationPrompt([string]$Description, [string]$Language) {
        return @"
Write a $Language function/method based on this description:
$Description

Requirements:
- Include proper error handling
- Add comments explaining the logic
- Use best practices for $Language
- Optimize for readability and performance

Code:
"@
    }
    
    [string]BuildRefactoringPrompt([string]$Code, [string]$Language, [string]$Objective) {
        return @"
Refactor this $Language code to ${Objective}:

Original code:
```$Language
$Code
```

Instructions:
- Maintain the same functionality
- Apply $Language best practices
- Improve code quality
- Add helpful comments if needed

Refactored code:
```$Language
"@
    }
    
    [string]BuildAnalysisPrompt([string]$Code, [string]$Language) {
        return @"
Analyze this $Language code and provide:
1. Code quality assessment
2. Performance considerations
3. Potential bugs or issues
4. Improvement suggestions

Code:
```$Language
$Code
```

Analysis:
"@
    }
    
    [string]BuildTestGenerationPrompt([string]$Code, [string]$Language, [string]$Framework) {
        return @"
Generate comprehensive unit tests for this $Language code using $Framework.

Source code:
```$Language
$Code
```

Test requirements:
- Cover normal cases
- Include edge cases
- Test error scenarios
- Ensure good code coverage

Test code:
```$Language
"@
    }
    
    [hashtable]PrepareRequestBody([string]$Prompt, [double]$Temperature, [hashtable]$Options) {
        $requestBody = @{
            model = $this.Config.services.codex.model
            prompt = $Prompt
            temperature = $Temperature
            max_tokens = $Options['maxTokens'] ?? $this.Config.services.codex.maxTokens
            top_p = $Options['topP'] ?? 1.0
            frequency_penalty = $Options['frequencyPenalty'] ?? 0.0
            presence_penalty = $Options['presencePenalty'] ?? 0.0
            stop = @("`n`n")
        }
        
        return $requestBody
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
                
                $this.LogWarning("Request failed (attempt $attempt). Retrying in ${delay}s: $_")
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
        $response = $this.HttpClient.PostAsync("$($this.BaseUrl)/completions", $content).Result
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
        
        $responseObject | Add-Member -NotePropertyName ResponseTime -NotePropertyValue $stopwatch.ElapsedMilliseconds
        
        return $responseObject
    }
    
    [double]CalculateCost([PSCustomObject]$Usage) {
        $svcConfig = $this.Config.services.codex
        $inputCost = ($Usage.prompt_tokens / 1000) * $svcConfig.costPerThousandTokens.input
        $outputCost = ($Usage.completion_tokens / 1000) * $svcConfig.costPerThousandTokens.output
        return $inputCost + $outputCost
    }
    
    [string]AnalyzeChanges([string]$Original, [string]$Refactored) {
        $originalLines = $Original -split "`n"
        $refactoredLines = $Refactored -split "`n"
        
        $analysis = "Changes made:`n"
        $analysis += "- Original lines: $($originalLines.Count)`n"
        $analysis += "- Refactored lines: $($refactoredLines.Count)`n"
        
        if ($refactoredLines.Count -lt $originalLines.Count) {
            $analysis += "- Lines reduced by: $($originalLines.Count - $refactoredLines.Count)`n"
        }
        
        return $analysis
    }
    
    [PSCustomObject]GetStatistics() {
        return [PSCustomObject]@{
            TotalRequests = $this.RequestStats.TotalRequests
            GenerationRequests = $this.RequestStats.GenerationRequests
            RefactoringRequests = $this.RequestStats.RefactoringRequests
            SuccessfulRequests = $this.RequestStats.SuccessfulRequests
            FailedRequests = $this.RequestStats.FailedRequests
            SuccessRate = if ($this.RequestStats.TotalRequests -gt 0) {
                [Math]::Round(($this.RequestStats.SuccessfulRequests / $this.RequestStats.TotalRequests * 100), 2)
            } else { 0 }
            TotalTokensUsed = $this.RequestStats.TotalTokensUsed
            TotalCost = [Math]::Round($this.RequestStats.TotalCost, 4)
        }
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
    $client = [CodexClient]::new($ApiKey, $config)
    
    $script:CodexClient = $client
    
    if ($PSBoundParameters.Count -eq 0 -and $MyInvocation.ScriptName -eq $PSCommandPath) {
        Write-Host "Codex Client initialized successfully"
        Write-Host "Usage: `$response = `$CodexClient.GenerateCode(`"Your code description`", `"python`")"
    }
}
catch {
    Write-Error "Failed to initialize Codex Client: $_"
    exit 1
}
