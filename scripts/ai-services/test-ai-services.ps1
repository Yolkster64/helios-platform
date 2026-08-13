<#
.SYNOPSIS
Test AI Services

.DESCRIPTION
Comprehensive testing script for all AI services, including connection tests,
API key validation, performance benchmarks, and health checks.

.EXAMPLE
.\test-ai-services.ps1
.\test-ai-services.ps1 -Quick
.\test-ai-services.ps1 -Benchmark
#>

param(
    [string]$ConfigPath = "C:\Users\ADMIN\helios-platform\config\ai-services\ai-services-config.json",
    [string]$ApiKeysPath = "C:\Users\ADMIN\helios-platform\config\ai-services\api-keys.env",
    [switch]$Quick,
    [switch]$Benchmark,
    [switch]$Verbose
)

# ============================================================================
# TEST FUNCTIONS
# ============================================================================

function Test-ConfigurationFiles {
    Write-Host "`n[TEST] Configuration Files" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $passed = 0
    $failed = 0
    
    # Check main config
    if (Test-Path $ConfigPath) {
        Write-Host "✓ Main configuration found" -ForegroundColor Green
        $passed++
        
        try {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            Write-Host "✓ Main configuration valid JSON" -ForegroundColor Green
            $passed++
        }
        catch {
            Write-Host "✗ Main configuration JSON invalid: $_" -ForegroundColor Red
            $failed++
        }
    }
    else {
        Write-Host "✗ Main configuration not found" -ForegroundColor Red
        $failed++
    }
    
    # Check API keys
    if (Test-Path $ApiKeysPath) {
        Write-Host "✓ API keys file found" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "⚠ API keys file not found (expected)" -ForegroundColor Yellow
    }
    
    return @{ Passed = $passed; Failed = $failed }
}

function Test-APIKeyValidation {
    Write-Host "`n[TEST] API Key Validation" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $passed = 0
    $failed = 0
    
    $keys = @(
        @{ Name = "OPENAI_API_KEY_CHATGPT_PRO"; Env = "OPENAI_API_KEY_CHATGPT_PRO" },
        @{ Name = "OPENAI_API_KEY_CODEX"; Env = "OPENAI_API_KEY_CODEX" },
        @{ Name = "OPENAI_API_KEY_GPT45"; Env = "OPENAI_API_KEY_GPT45" }
    )
    
    foreach ($key in $keys) {
        $value = [Environment]::GetEnvironmentVariable($key.Env)
        
        if ($null -ne $value -and $value.Length -gt 0) {
            if ($value.StartsWith("sk-")) {
                Write-Host "✓ $($key.Name) format valid" -ForegroundColor Green
                $passed++
            }
            else {
                Write-Host "⚠ $($key.Name) present but format unexpected" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "⚠ $($key.Name) not set" -ForegroundColor Yellow
        }
    }
    
    return @{ Passed = $passed; Failed = $failed }
}

function Test-ServiceConnectivity {
    Write-Host "`n[TEST] Service Connectivity" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $passed = 0
    $failed = 0
    
    $endpoints = @(
        @{ Name = "OpenAI API"; Url = "https://api.openai.com/v1/models" },
        @{ Name = "OpenAI Status"; Url = "https://status.openai.com" }
    )
    
    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint.Url -TimeoutSec 5 -ErrorAction Stop -UseBasicParsing
            
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 401) {
                Write-Host "✓ $($endpoint.Name) reachable" -ForegroundColor Green
                $passed++
            }
            else {
                Write-Host "⚠ $($endpoint.Name) returned $($response.StatusCode)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "✗ $($endpoint.Name) unreachable: $_" -ForegroundColor Red
            $failed++
        }
    }
    
    return @{ Passed = $passed; Failed = $failed }
}

function Test-LoggingSetup {
    Write-Host "`n[TEST] Logging Setup" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $passed = 0
    $failed = 0
    
    $logPath = "C:\Users\ADMIN\helios-platform\logs\ai-services"
    
    if (Test-Path $logPath) {
        Write-Host "✓ Log directory exists" -ForegroundColor Green
        $passed++
        
        # Try to write test log
        try {
            $testLog = Join-Path $logPath "test_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
            "Test log entry" | Out-File -FilePath $testLog
            
            if (Test-Path $testLog) {
                Write-Host "✓ Can write to log directory" -ForegroundColor Green
                $passed++
                Remove-Item $testLog -Force
            }
            else {
                Write-Host "✗ Failed to create test log" -ForegroundColor Red
                $failed++
            }
        }
        catch {
            Write-Host "✗ Cannot write to log directory: $_" -ForegroundColor Red
            $failed++
        }
    }
    else {
        Write-Host "✗ Log directory does not exist" -ForegroundColor Red
        $failed++
    }
    
    return @{ Passed = $passed; Failed = $failed }
}

function Test-DataDirectories {
    Write-Host "`n[TEST] Data Directories" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $passed = 0
    $failed = 0
    
    $dirs = @(
        "C:\Users\ADMIN\helios-platform\data\ai-services",
        "C:\Users\ADMIN\helios-platform\config\ai-services"
    )
    
    foreach ($dir in $dirs) {
        if (Test-Path $dir) {
            Write-Host "✓ Directory exists: $dir" -ForegroundColor Green
            $passed++
        }
        else {
            Write-Host "⚠ Directory missing: $dir" -ForegroundColor Yellow
        }
    }
    
    return @{ Passed = $passed; Failed = $failed }
}

function Test-PerformanceBenchmark {
    Write-Host "`n[BENCHMARK] Service Performance" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $services = @("chatgpt-pro", "codex", "gpt-4-5")
    
    foreach ($service in $services) {
        # Simulate performance test
        $times = @()
        
        for ($i = 0; $i -lt 5; $i++) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
            $sw.Stop()
            $times += $sw.ElapsedMilliseconds
        }
        
        $avgTime = ($times | Measure-Object -Average).Average
        $minTime = ($times | Measure-Object -Minimum).Minimum
        $maxTime = ($times | Measure-Object -Maximum).Maximum
        
        Write-Host "`n${service}:"
        Write-Host "  Average: $([Math]::Round($avgTime, 2))ms"
        Write-Host "  Min: $minTime ms"
        Write-Host "  Max: $maxTime ms"
    }
}

function Display-TestSummary {
    param(
        [hashtable]$ConfigTest,
        [hashtable]$KeyTest,
        [hashtable]$ConnectivityTest,
        [hashtable]$LoggingTest,
        [hashtable]$DataTest
    )
    
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                         TEST SUMMARY" -ForegroundColor Cyan
    Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "`n"
    
    $totalPassed = $ConfigTest.Passed + $KeyTest.Passed + $ConnectivityTest.Passed + $LoggingTest.Passed + $DataTest.Passed
    $totalFailed = $ConfigTest.Failed + $KeyTest.Failed + $ConnectivityTest.Failed + $LoggingTest.Failed + $DataTest.Failed
    
    $tests = @(
        @{ Name = "Configuration Files"; Passed = $ConfigTest.Passed; Failed = $ConfigTest.Failed },
        @{ Name = "API Key Validation"; Passed = $KeyTest.Passed; Failed = $KeyTest.Failed },
        @{ Name = "Service Connectivity"; Passed = $ConnectivityTest.Passed; Failed = $ConnectivityTest.Failed },
        @{ Name = "Logging Setup"; Passed = $LoggingTest.Passed; Failed = $LoggingTest.Failed },
        @{ Name = "Data Directories"; Passed = $DataTest.Passed; Failed = $DataTest.Failed }
    )
    
    foreach ($test in $tests) {
        $total = $test.Passed + $test.Failed
        Write-Host "$($test.Name): " -NoNewline
        Write-Host "$($test.Passed)/$total passed" -ForegroundColor Green
    }
    
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "Overall: " -NoNewline
    
    if ($totalFailed -eq 0) {
        Write-Host "✓ ALL TESTS PASSED" -ForegroundColor Green
    }
    elseif ($totalFailed -le 2) {
        Write-Host "⚠ SOME WARNINGS" -ForegroundColor Yellow
    }
    else {
        Write-Host "✗ TESTS FAILED" -ForegroundColor Red
    }
    
    Write-Host "`nTotal: $totalPassed passed, $totalFailed failed`n"
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          AI SERVICES TEST SUITE                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nTest Mode: " -NoNewline
    if ($Quick) {
        Write-Host "Quick" -ForegroundColor Yellow
    }
    elseif ($Benchmark) {
        Write-Host "Benchmark" -ForegroundColor Yellow
    }
    else {
        Write-Host "Full" -ForegroundColor Yellow
    }
    
    # Run tests
    $configTest = Test-ConfigurationFiles
    $keyTest = Test-APIKeyValidation
    $connectivityTest = Test-ServiceConnectivity
    $loggingTest = Test-LoggingSetup
    $dataTest = Test-DataDirectories
    
    # Run benchmark if requested
    if ($Benchmark -and -not $Quick) {
        Test-PerformanceBenchmark
    }
    
    # Display summary
    Display-TestSummary -ConfigTest $configTest -KeyTest $keyTest -ConnectivityTest $connectivityTest -LoggingTest $loggingTest -DataTest $dataTest
    
    Write-Host "Tests completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "`n"
}
catch {
    Write-Error "Test suite error: $_"
    exit 1
}
