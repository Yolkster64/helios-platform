#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate code snippets using Codex AI
    
.DESCRIPTION
    Generates production-ready code snippets for common HELIOS Platform build tasks
    using Codex API. Supports multiple languages and complexity levels.
    
.PARAMETER Description
    Natural language description of code to generate
    
.PARAMETER Language
    Programming language: powershell, bash, csharp, python
    
.PARAMETER Complexity
    Complexity level: simple, intermediate, advanced
    
.PARAMETER SaveFile
    If specified, saves generated code to file
    
.PARAMETER DryRun
    If specified, simulates without API calls
    
.EXAMPLE
    .\generate-code-snippets.ps1 -Description "Create parallel build runner"
    .\generate-code-snippets.ps1 -Description "Cache management utility" -Language powershell -SaveFile
    
.NOTES
    Author: HELIOS Platform
    Version: 1.0.0
    Requires: PowerShell 7.0+
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Description,
    
    [ValidateSet("powershell", "bash", "csharp", "python")]
    [string]$Language = "powershell",
    
    [ValidateSet("simple", "intermediate", "advanced")]
    [string]$Complexity = "intermediate",
    
    [switch]$SaveFile,
    [switch]$DryRun,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$apiClientPath = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "config\api-clients.ps1"
. $apiClientPath

if ($Verbose) {
    [Environment]::SetEnvironmentVariable("DEBUG_MODE", "true")
}

$LANGUAGE_CONTEXTS = @{
    powershell = @"
# PowerShell Build Script Template
# Used for: Windows build automation, cross-platform build orchestration
# Standards: PSScriptAnalyzer compliant, error handling, logging

Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
"@
    bash = @"
#!/bin/bash
# Bash Build Script Template
# Used for: Linux/macOS build automation
# Standards: POSIX compliant, error handling, logging

set -euo pipefail
"@
    csharp = @"
// C# Build Utility Template
// Used for: Custom build tools, MSBuild tasks
// Standards: .NET 6+, async/await, proper error handling

using System;
using System.Threading.Tasks;
"@
    python = @"
#!/usr/bin/env python3
# Python Build Utility
# Used for: Cross-platform scripting, automation
# Standards: Python 3.8+, type hints, error handling

import sys
import logging
"@
}

function Generate-CodeSnippet {
    param(
        [string]$Description,
        [string]$Language,
        [string]$Complexity,
        [bool]$DryRun = $false
    )
    
    Write-LogEntry -Level "INFO" -Message "Generating code snippet" -Context @{
        description = $Description
        language = $Language
        complexity = $Complexity
    }
    
    $prompt = @"
Generate a production-ready $Language code snippet for the HELIOS Platform build system:

Description: $Description
Complexity Level: $Complexity
Context:
$($LANGUAGE_CONTEXTS[$Language])

Requirements:
1. **Quality**: Production-ready, well-structured code
2. **Error Handling**: Comprehensive error handling
3. **Documentation**: Clear comments explaining logic
4. **Performance**: Optimized for performance
5. **Maintainability**: Follow language conventions
6. **Testing**: Include test examples if applicable

For complexity level '$Complexity':
- simple: Basic functionality, minimal dependencies
- intermediate: Standard patterns, common libraries
- advanced: Complex patterns, optimization, advanced features

Include:
- Complete implementation
- Usage examples
- Error handling
- Configuration options
- Performance considerations
"@
    
    $request = @{
        model = Get-ConfigValue -Key "CODEX_ENGINE" -Default "code-davinci-002"
        prompt = $prompt
        max_tokens = [int](Get-ConfigValue -Key "CODEX_MAX_TOKENS" -Default "2048")
        temperature = [float](Get-ConfigValue -Key "CODEX_TEMPERATURE" -Default "0.5")
        stop = @('```', "# End of code")
    }
    
    try {
        $startTime = Get-Date
        $response = Invoke-OpenAIRequest -Endpoint "/engines/$($request.model)/completions" `
                                        -Body $request `
                                        -MaxRetries 3 `
                                        -DryRun $DryRun
        $elapsed = (Get-Date) - $startTime
        
        Log-APICall -Service "codex" `
                   -Action "Generate-Snippet" `
                   -Status "success" `
                   -Duration $elapsed.TotalMilliseconds `
                   -DryRun $DryRun
        
        return $response
    }
    catch {
        Write-LogEntry -Level "ERROR" -Message "Code generation failed: $($_.Exception.Message)"
        throw $_
    }
}

function Format-CodeOutput {
    param([object]$Response, [string]$Language)
    
    if ($Response.isDryRun) {
        return @"
# Generated Code Snippet ($Language)
# This is a placeholder for generated code

# Your implementation would appear here
# with full error handling, documentation, and examples
"@
    }
    
    $content = if ($Response.content.choices) {
        $Response.content.choices[0].text
    } else {
        $Response.content
    }
    
    return $content
}

function Save-CodeSnippet {
    param(
        [string]$Code,
        [string]$Language,
        [string]$Description
    )
    
    $extensions = @{
        powershell = "ps1"
        bash = "sh"
        csharp = "cs"
        python = "py"
    }
    
    $ext = $extensions[$Language]
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "generated_snippet_${Language}_${timestamp}.$ext"
    $filepath = Join-Path (Get-ConfigValue -Key "LOG_DIR" -Default "./logs") $filename
    
    $header = @"
# Generated Code Snippet
# Language: $Language
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Description: $Description
# ============================================================================

"@
    
    $fullContent = $header + $Code
    Set-Content -Path $filepath -Value $fullContent
    
    Write-LogEntry -Level "INFO" -Message "Code snippet saved: $filename"
    return $filepath
}

function Main {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Codex Code Generation" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "[DRY RUN MODE]`n" -ForegroundColor Yellow
    }
    
    try {
        Write-Host "Generating $Language code ($Complexity complexity)..." -ForegroundColor Magenta
        Write-Host "Description: $Description`n" -ForegroundColor Gray
        
        $snippet = Generate-CodeSnippet -Description $Description `
                                       -Language $Language `
                                       -Complexity $Complexity `
                                       -DryRun $DryRun
        
        $formatted = Format-CodeOutput -Response $snippet -Language $Language
        
        Write-Host "[Generated Code]`n" -ForegroundColor Green
        Write-Host $formatted
        
        if ($SaveFile) {
            $savedPath = Save-CodeSnippet -Code $formatted -Language $Language -Description $Description
            Write-Host "`n✓ Code saved to: $savedPath" -ForegroundColor Green
        }
        
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host "  Generation Complete ✓" -ForegroundColor Green
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
    }
    catch {
        Write-Host "`n✗ ERROR: $($_.Exception.Message)`n" -ForegroundColor Red
        exit 1
    }
}

Main
