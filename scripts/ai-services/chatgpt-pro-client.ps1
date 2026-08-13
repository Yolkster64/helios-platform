<#
.SYNOPSIS
ChatGPT Pro (GPT-4) Client - OpenAI API integration

.DESCRIPTION
Handles communication with OpenAI's ChatGPT Pro API (GPT-4 model).
Provides streaming support, error handling, retry logic, and rate limiting.

.EXAMPLE
$client = New-ChatGPTProClient -ApiKey $apiKey -ConfigPath $configPath
$response = $client.SendPrompt("Analyze this code", $codeContent)
#>

param(
    [string]$ApiKey = $env:OPENAI_API_KEY_CHATGPT_PRO,
    [string]$ConfigPath = "C:\Users\ADMIN\helios-platform\config\ai-services\ai-services-config.json"
)

class ChatGPTProClient {
    [string]$ApiKey
    [hashtable]$Config
    [string]$BaseUrl = "https://api.openai.com/v1"
    [System.Net.Http.HttpClient]$HttpClient
    [System.IO.StreamWriter]$Logger
    [hashtable]$RequestStats
    [hashtable]$RetryPolicy
    
    ChatGPTProClient([string]$ApiKey, [hashtable]$Config) {
        if ([string]::IsNullOrEmpty($ApiKey)) {
            throw "API key is required for ChatGPT Pro client"
        }
        
        $this.ApiKey = $ApiKey
        $this.Config = $Config
        $this.InitializeHttpClient()
        $this.InitializeLogger()
        $this.InitializeRetryPolicy()
        $this.RequestStats = @{
            TotalRequests = 0
            SuccessfulRequests = 0
            FailedRequests = 0
            TotalTokensUsed = 0
            TotalCost = 0
        }
    }
    
    [void]InitializeHttpClient() {
        $this.HttpClient = New-Object System.Net.Http.HttpClient
        $this.HttpClient.DefaultRequestHeaders.Add("Authorization", "Bearer $($this.ApiKey)")
        $this.HttpClient.DefaultRequestHeaders.Add("Content-Type", "application/json")
        $timeout = $this.Config.services.'chatgpt-pro'.timeout
        $this.HttpClient.Timeout = [TimeSpan]::FromSeconds($timeout)
    }
    
    [void]InitializeLogger() {
        $logPath = $this.Config.logging.logPath
        if (-not (Test-Path $logPath)) {
            New-Item -ItemType Directory -Path $logPath -Force | Out-Null
        }
        $logFile = Join-Path $logPath "chatgpt-pro_$(Get-Date -Format 'yyyy-MM-dd').log"
        $this.Logger = [System.IO.StreamWriter]::new($logFile, $true)
        $this.Logger.AutoFlush = $true
    }
    
    [void]InitializeRetryPolicy() {
        $this.RetryPolicy = @{
            MaxRetries = $this.Config.services.'chatgpt-pro'.retries
            RetryDelay = $this.Config.services.'chatgpt-pro'.retryDelay
            BackoffMultiplier = 2
            MaxBackoffDelay = 60
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
    
    [PSCustomObject]SendPrompt([string]$Prompt, [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Sending prompt to ChatGPT Pro (GPT-4)")
            
            # Prepare request
            $requestBody = $this.PrepareRequestBody($Prompt, $Options)
            
            # Attempt with retries
            $response = $this.InvokeWithRetry($requestBody)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Prompt processed successfully. Tokens used: $($response.usage.total_tokens)")
            
            return @{
                Success = $true
                Content = $response.choices[0].message.content
                TokensUsed = $response.usage.total_tokens
                InputTokens = $response.usage.prompt_tokens
                OutputTokens = $response.usage.completion_tokens
                Model = $response.model
                Cost = $this.CalculateCost($response.usage)
                FinishReason = $response.choices[0].finish_reason
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Failed to send prompt: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [PSCustomObject]SendPromptStreaming([string]$Prompt, [scriptblock]$OnChunk = $null, [hashtable]$Options = @{}) {
        try {
            $this.LogInfo("Sending streaming prompt to ChatGPT Pro (GPT-4)")
            
            # Prepare request with streaming
            $requestBody = $this.PrepareRequestBody($Prompt, $Options + @{stream = $true})
            
            # Invoke streaming request
            $response = $this.InvokeStreamingRequest($requestBody, $OnChunk)
            
            $this.RequestStats.SuccessfulRequests++
            $this.LogInfo("Streaming prompt processed successfully")
            
            return @{
                Success = $true
                Content = $response.FullContent
                TokensUsed = $response.EstimatedTokens
                Cost = $response.EstimatedCost
                ChunksReceived = $response.ChunkCount
                Timestamp = Get-Date
            }
        }
        catch {
            $this.RequestStats.FailedRequests++
            $this.LogError("Failed to send streaming prompt: $_")
            return @{
                Success = $false
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
    
    [hashtable]PrepareRequestBody([string]$Prompt, [hashtable]$Options) {
        $systemPrompt = $Options['system'] ?? "You are a helpful AI assistant specialized in code analysis and technical strategy."
        
        $requestBody = @{
            model = $this.Config.services.'chatgpt-pro'.model
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
            temperature = $Options['temperature'] ?? $this.Config.services.'chatgpt-pro'.temperature
            max_tokens = $Options['maxTokens'] ?? $this.Config.services.'chatgpt-pro'.maxTokens
            top_p = $Options['topP'] ?? 1.0
            frequency_penalty = $Options['frequencyPenalty'] ?? 0.0
            presence_penalty = $Options['presencePenalty'] ?? 0.0
        }
        
        if ($Options.ContainsKey('stream') -and $Options['stream']) {
            $requestBody['stream'] = $true
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
                
                $this.LogWarning("Request failed (attempt $attempt/$($this.RetryPolicy.MaxRetries + 1)). Retrying in ${delay}s: $_")
                Start-Sleep -Seconds $delay
                
                # Exponential backoff
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
        
        $responseObject | Add-Member -NotePropertyName ResponseTime -NotePropertyValue $stopwatch.ElapsedMilliseconds
        
        return $responseObject
    }
    
    [PSCustomObject]InvokeStreamingRequest([hashtable]$RequestBody, [scriptblock]$OnChunk) {
        $jsonBody = $RequestBody | ConvertTo-Json -Depth 10
        $content = New-Object System.Net.Http.StringContent($jsonBody, [System.Text.Encoding]::UTF8, "application/json")
        
        $fullContent = ""
        $chunkCount = 0
        $estimatedTokens = 0
        
        try {
            $request = New-Object System.Net.Http.HttpRequestMessage -ArgumentList ([System.Net.Http.HttpMethod]::Post), "$($this.BaseUrl)/chat/completions"
            $request.Content = $content
            
            $stream = $this.HttpClient.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result.Content.ReadAsStreamAsync().Result
            $reader = New-Object System.IO.StreamReader($stream)
            
            while ($reader.Peek() -ge 0) {
                $line = $reader.ReadLine()
                
                if ($line.StartsWith("data: ")) {
                    $json = $line.Substring(6)
                    
                    if ($json -eq "[DONE]") {
                        break
                    }
                    
                    try {
                        $chunk = $json | ConvertFrom-Json
                        if ($chunk.choices[0].delta.content) {
                            $content = $chunk.choices[0].delta.content
                            $fullContent += $content
                            $chunkCount++
                            
                            if ($OnChunk) {
                                & $OnChunk -Content $content
                            }
                        }
                    }
                    catch {
                        $this.LogWarning("Failed to parse streaming chunk: $_")
                    }
                }
            }
            
            $reader.Close()
            $estimatedTokens = [Math]::Ceiling($fullContent.Length / 4)
            
            return @{
                FullContent = $fullContent
                EstimatedTokens = $estimatedTokens
                EstimatedCost = $this.CalculateCostFromTokens($estimatedTokens)
                ChunkCount = $chunkCount
            }
        }
        catch {
            throw $_
        }
    }
    
    [double]CalculateCost([PSCustomObject]$Usage) {
        $svcConfig = $this.Config.services.'chatgpt-pro'
        $inputCost = ($Usage.prompt_tokens / 1000) * $svcConfig.costPerThousandTokens.input
        $outputCost = ($Usage.completion_tokens / 1000) * $svcConfig.costPerThousandTokens.output
        return $inputCost + $outputCost
    }
    
    [double]CalculateCostFromTokens([int]$TokenCount) {
        $svcConfig = $this.Config.services.'chatgpt-pro'
        return ($TokenCount / 1000) * $svcConfig.costPerThousandTokens.input
    }
    
    [PSCustomObject]GetStatistics() {
        return [PSCustomObject]@{
            TotalRequests = $this.RequestStats.TotalRequests
            SuccessfulRequests = $this.RequestStats.SuccessfulRequests
            FailedRequests = $this.RequestStats.FailedRequests
            SuccessRate = if ($this.RequestStats.TotalRequests -gt 0) {
                [Math]::Round(($this.RequestStats.SuccessfulRequests / $this.RequestStats.TotalRequests * 100), 2)
            } else { 0 }
            TotalTokensUsed = $this.RequestStats.TotalTokensUsed
            TotalCost = [Math]::Round($this.RequestStats.TotalCost, 4)
            AverageCostPerRequest = if ($this.RequestStats.SuccessfulRequests -gt 0) {
                [Math]::Round(($this.RequestStats.TotalCost / $this.RequestStats.SuccessfulRequests), 4)
            } else { 0 }
        }
    }
    
    [void]ResetStatistics() {
        $this.RequestStats.TotalRequests = 0
        $this.RequestStats.SuccessfulRequests = 0
        $this.RequestStats.FailedRequests = 0
        $this.RequestStats.TotalTokensUsed = 0
        $this.RequestStats.TotalCost = 0
        $this.LogInfo("Statistics reset")
    }
    
    [void]Close() {
        $this.HttpClient.Dispose()
        $this.Logger.Close()
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Load-Configuration {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }
    
    return Get-Content $Path -Raw | ConvertFrom-Json
}

# ============================================================================
# MAIN
# ============================================================================

try {
    $config = Load-Configuration -Path $ConfigPath
    $client = [ChatGPTProClient]::new($ApiKey, $config)
    
    $script:ChatGPTProClient = $client
    
    if ($PSBoundParameters.Count -eq 0 -and $MyInvocation.ScriptName -eq $PSCommandPath) {
        Write-Host "ChatGPT Pro Client initialized successfully"
        Write-Host "Usage: `$response = `$ChatGPTProClient.SendPrompt(`"Your prompt here`")"
        Write-Host "        `$ChatGPTProClient.GetStatistics()"
    }
}
catch {
    Write-Error "Failed to initialize ChatGPT Pro Client: $_"
    exit 1
}
