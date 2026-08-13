<#
.SYNOPSIS
    End-to-end SharePoint evidence proof for the HELIOS deployment-evidence pipeline
.DESCRIPTION
    Proves the complete SharePoint evidence path against a live tenant in one run:

      1. Graph authentication and site/drive resolution
      2. Folder operations under Helios/Governance/Deployment-Evidence/<CorrelationId>
         (GitHub, Azure, Identity-RBAC, Connectors, Hermes-AIHub, Rollback, Checksums)
      3. File upload over BOTH transports:
         - direct PUT to graph.microsoft.com (small file)
         - upload session PUT to the SharePoint file-transfer host (large file)
      4. Download round-trip with SHA-256 verification
      5. Checksums manifest publication into the Checksums subfolder

    Every stage is recorded in a correlation-bound JSON proof report. An HTTP 407
    response is captured as a distinct "Blocked" verdict with proxy diagnostics
    (the known file-transfer-proxy failure mode) rather than a generic error, so
    the report shows exactly which transport is affected.

    Requires an owner/admin-consented Graph session with Sites.ReadWrite.All.
.EXAMPLE
    .\Invoke-SharePointEvidenceProof.ps1 -SiteId "contoso.sharepoint.com:/sites/Helios" `
        -CorrelationId "0dcfdc41-7e6b-478f-a53f-866cdae93ffd"
.NOTES
    Exit codes:
      0 = fully proven (all stages passed)
      2 = partially proven (folder operations passed, an upload transport was
          blocked by HTTP 407 at the file-transfer proxy)
      1 = failed (any stage failed for a non-407 reason)
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SiteId,

    [Parameter(Mandatory = $false)]
    [string]$DriveName = "Documents",

    [Parameter(Mandatory = $false)]
    [string]$EvidenceBasePath = "Helios/Governance/Deployment-Evidence",

    [Parameter(Mandatory = $false)]
    [string]$CorrelationId = ([guid]::NewGuid().ToString()),

    [Parameter(Mandatory = $false)]
    [string[]]$Subfolders = @("GitHub", "Azure", "Identity-RBAC", "Connectors", "Hermes-AIHub", "Rollback", "Checksums"),

    [Parameter(Mandatory = $false)]
    [int]$LargeFileSizeMB = 4,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLargeUpload,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\logs"
)

$ErrorActionPreference = "Stop"

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║      SHAREPOINT EVIDENCE PROOF (E2E) - HELIOS SYSTEM       ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Magenta

$script:Stages = [System.Collections.Generic.List[object]]::new()

function Get-HttpStatusFromError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        foreach ($propertyName in @("StatusCode", "ResponseStatusCode")) {
            $property = $exception.PSObject.Properties[$propertyName]
            if ($null -ne $property -and $null -ne $property.Value) {
                return [int]$property.Value
            }
        }
        if ($exception -is [System.Net.WebException] -and $null -ne $exception.Response) {
            return [int]$exception.Response.StatusCode
        }
        $exception = $exception.InnerException
    }

    if ($ErrorRecord.Exception.Message -match "\b(4\d{2}|5\d{2})\b") {
        return [int]$Matches[1]
    }
    return $null
}

function Get-ProxyDiagnostics {
    $systemProxy = $null
    try {
        $proxyUri = [System.Net.WebRequest]::DefaultWebProxy.GetProxy([uri]"https://graph.microsoft.com")
        if ($proxyUri.Host -ne "graph.microsoft.com") { $systemProxy = $proxyUri.AbsoluteUri }
    }
    catch { }

    return @{
        SystemProxy = $systemProxy
        HttpsProxy  = $env:HTTPS_PROXY
        HttpProxy   = $env:HTTP_PROXY
        NoProxy     = $env:NO_PROXY
        Guidance    = "HTTP 407 means the outbound file-transfer proxy demanded credentials. " +
                      "Allowlist *.sharepoint.com upload hosts or configure authenticated proxy " +
                      "credentials for the transfer path (see evidence-proof README)."
    }
}

function Add-ProofStage {
    param(
        [string]$Name,
        [ValidateSet("Passed", "Failed", "Blocked", "Skipped")]
        [string]$Status,
        [string]$Detail = "",
        [Nullable[int]]$HttpStatus = $null,
        [hashtable]$Diagnostics = $null
    )

    $entry = [ordered]@{
        Stage       = $Name
        Status      = $Status
        Detail      = $Detail
        HttpStatus  = $HttpStatus
        Diagnostics = $Diagnostics
        Timestamp   = (Get-Date).ToUniversalTime().ToString("o")
    }
    $script:Stages.Add([pscustomobject]$entry)

    $color = switch ($Status) {
        "Passed"  { "Green" }
        "Blocked" { "Yellow" }
        "Skipped" { "Gray" }
        default   { "Red" }
    }
    $statusSuffix = if ($null -ne $HttpStatus) { " (HTTP $HttpStatus)" } else { "" }
    Write-Host "  [$Status]$statusSuffix $Name" -ForegroundColor $color
    if ($Detail) { Write-Host "          $Detail" -ForegroundColor Gray }
}

function Invoke-ProofStage {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        $result = & $Action
        return $result
    }
    catch {
        $httpStatus = Get-HttpStatusFromError -ErrorRecord $_
        if ($httpStatus -eq 407) {
            Add-ProofStage -Name $Name -Status "Blocked" -HttpStatus 407 `
                -Detail "File-transfer proxy demanded authentication (known transport blocker)." `
                -Diagnostics (Get-ProxyDiagnostics)
        }
        else {
            Add-ProofStage -Name $Name -Status "Failed" -HttpStatus $httpStatus -Detail $_.Exception.Message
        }
        return $null
    }
}

function New-EvidencePayloadFile {
    param(
        [string]$Path,
        [int]$SizeBytes
    )

    $header = [System.Text.Encoding]::UTF8.GetBytes(
        "HELIOS SharePoint evidence proof payload`nCorrelationId: $CorrelationId`nGeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))`n"
    )
    $stream = [System.IO.File]::Create($Path)
    try {
        $stream.Write($header, 0, $header.Length)
        if ($SizeBytes -gt $header.Length) {
            $random = [System.Random]::new()
            $buffer = New-Object byte[] 65536
            $remaining = $SizeBytes - $header.Length
            while ($remaining -gt 0) {
                $random.NextBytes($buffer)
                $chunk = [Math]::Min($buffer.Length, $remaining)
                $stream.Write($buffer, 0, $chunk)
                $remaining -= $chunk
            }
        }
    }
    finally {
        $stream.Dispose()
    }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

try {
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    $runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "helios-evidence-proof-$runStamp"
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    Write-Host "[Correlation ID] $CorrelationId" -ForegroundColor Cyan
    Write-Host "[Evidence container] $EvidenceBasePath/$CorrelationId`n" -ForegroundColor Cyan

    # ── Stage 1: authentication and site/drive resolution ─────────────────
    Write-Host "Stage 1: Authentication and site resolution" -ForegroundColor Yellow

    $drive = Invoke-ProofStage -Name "Graph authentication + site/drive resolution" -Action {
        Connect-MgGraph -Scopes "Sites.ReadWrite.All" -NoWelcome -ErrorAction Stop | Out-Null
        $context = Get-MgContext
        if (-not $context) { throw "No Microsoft Graph context after Connect-MgGraph." }

        $site = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId"
        $drives = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($site.id)/drives"
        $resolved = $drives.value | Where-Object { $_.name -eq $DriveName } | Select-Object -First 1
        if (-not $resolved) {
            throw "Drive '$DriveName' not found on site '$($site.displayName)'. Available: $(($drives.value.name) -join ', ')"
        }
        Add-ProofStage -Name "Graph authentication + site/drive resolution" -Status "Passed" `
            -Detail "Site '$($site.displayName)', drive '$($resolved.name)' ($($resolved.id))"
        return $resolved
    }
    if (-not $drive) { throw "Cannot continue without a resolved drive." }

    $driveBase = "https://graph.microsoft.com/v1.0/drives/$($drive.id)"
    $containerPath = "$EvidenceBasePath/$CorrelationId"

    # ── Stage 2: folder operations ─────────────────────────────────────────
    Write-Host "`nStage 2: Folder operations" -ForegroundColor Yellow

    Invoke-ProofStage -Name "Evidence container + subfolder creation" -Action {
        $segments = ($containerPath -split "/") | Where-Object { $_ }
        $currentPath = ""
        foreach ($segment in $segments) {
            $parentUri = if ($currentPath) { "$driveBase/root:/$($currentPath):/children" } else { "$driveBase/root/children" }
            $body = @{ name = $segment; folder = @{}; "@microsoft.graph.conflictBehavior" = "replace" } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri $parentUri -Body $body -ContentType "application/json" | Out-Null
            $currentPath = if ($currentPath) { "$currentPath/$segment" } else { $segment }
        }
        foreach ($subfolder in $Subfolders) {
            $body = @{ name = $subfolder; folder = @{}; "@microsoft.graph.conflictBehavior" = "replace" } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri "$driveBase/root:/$($containerPath):/children" -Body $body -ContentType "application/json" | Out-Null
        }
        $children = Invoke-MgGraphRequest -Method GET -Uri "$driveBase/root:/$($containerPath):/children"
        $missing = $Subfolders | Where-Object { $_ -notin $children.value.name }
        if ($missing) { throw "Subfolders missing after creation: $($missing -join ', ')" }
        Add-ProofStage -Name "Evidence container + subfolder creation" -Status "Passed" `
            -Detail "$containerPath with $($Subfolders.Count) subfolders verified by listing"
    } | Out-Null

    # ── Stage 3: upload transports ─────────────────────────────────────────
    Write-Host "`nStage 3: Upload transports" -ForegroundColor Yellow

    $smallFileName = "proof-direct-put-$runStamp.txt"
    $smallFilePath = Join-Path $workDir $smallFileName
    $smallFileHash = New-EvidencePayloadFile -Path $smallFilePath -SizeBytes 2048

    $smallUpload = Invoke-ProofStage -Name "Direct PUT upload (Graph content endpoint)" -Action {
        $item = Invoke-MgGraphRequest -Method PUT `
            -Uri "$driveBase/root:/$containerPath/Connectors/$($smallFileName):/content" `
            -InputFilePath $smallFilePath -ContentType "application/octet-stream"
        Add-ProofStage -Name "Direct PUT upload (Graph content endpoint)" -Status "Passed" `
            -Detail "$smallFileName ($($item.size) bytes) at $containerPath/Connectors"
        return $item
    }

    $largeUpload = $null
    $largeFileHash = $null
    $largeFileName = "proof-upload-session-$runStamp.bin"
    if ($SkipLargeUpload) {
        Add-ProofStage -Name "Upload session (file-transfer host)" -Status "Skipped" -Detail "-SkipLargeUpload was set"
    }
    else {
        $largeFilePath = Join-Path $workDir $largeFileName
        $largeFileHash = New-EvidencePayloadFile -Path $largeFilePath -SizeBytes ($LargeFileSizeMB * 1MB)

        $largeUpload = Invoke-ProofStage -Name "Upload session (file-transfer host)" -Action {
            $sessionBody = @{ item = @{ "@microsoft.graph.conflictBehavior" = "replace"; name = $largeFileName } } | ConvertTo-Json
            $session = Invoke-MgGraphRequest -Method POST `
                -Uri "$driveBase/root:/$containerPath/Connectors/$($largeFileName):/createUploadSession" `
                -Body $sessionBody -ContentType "application/json"

            # The uploadUrl points at the SharePoint file-transfer host, not
            # graph.microsoft.com — this PUT is the transport that has been
            # returning HTTP 407 through the outbound proxy.
            $fileBytes = [System.IO.File]::ReadAllBytes($largeFilePath)
            $chunkSize = 3276800  # 3.125 MB, a multiple of 320 KiB as Graph requires
            $offset = 0
            $item = $null
            while ($offset -lt $fileBytes.Length) {
                $end = [Math]::Min($offset + $chunkSize, $fileBytes.Length) - 1
                $chunk = [byte[]]$fileBytes[$offset..$end]
                $headers = @{
                    "Content-Range" = "bytes $offset-$end/$($fileBytes.Length)"
                }
                $response = Invoke-WebRequest -Method PUT -Uri $session.uploadUrl -Headers $headers `
                    -Body $chunk -ContentType "application/octet-stream" -UseBasicParsing
                if ($response.Content) { $item = $response.Content | ConvertFrom-Json }
                $offset = $end + 1
            }
            Add-ProofStage -Name "Upload session (file-transfer host)" -Status "Passed" `
                -Detail "$largeFileName ($LargeFileSizeMB MB) via $([uri]$session.uploadUrl | Select-Object -ExpandProperty Host)"
            return $item
        }
    }

    # ── Stage 4: download round-trip with checksum verification ───────────
    Write-Host "`nStage 4: Download round-trip verification" -ForegroundColor Yellow

    $roundTrips = @(
        @{ Name = $smallFileName; ExpectedHash = $smallFileHash; Uploaded = [bool]$smallUpload }
        @{ Name = $largeFileName; ExpectedHash = $largeFileHash; Uploaded = [bool]$largeUpload }
    )
    foreach ($roundTrip in $roundTrips) {
        $stageName = "Round-trip SHA-256 verification: $($roundTrip.Name)"
        if (-not $roundTrip.Uploaded) {
            Add-ProofStage -Name $stageName -Status "Skipped" -Detail "Upload did not complete"
            continue
        }
        Invoke-ProofStage -Name $stageName -Action {
            $downloadPath = Join-Path $workDir "download-$($roundTrip.Name)"
            Invoke-MgGraphRequest -Method GET `
                -Uri "$driveBase/root:/$containerPath/Connectors/$($roundTrip.Name):/content" `
                -OutputFilePath $downloadPath
            $downloadedHash = (Get-FileHash -Path $downloadPath -Algorithm SHA256).Hash
            if ($downloadedHash -ne $roundTrip.ExpectedHash) {
                throw "Checksum mismatch: uploaded $($roundTrip.ExpectedHash), downloaded $downloadedHash"
            }
            Add-ProofStage -Name $stageName -Status "Passed" -Detail "SHA-256 $downloadedHash"
        } | Out-Null
    }

    # ── Stage 5: checksums manifest publication ────────────────────────────
    Write-Host "`nStage 5: Checksums manifest publication" -ForegroundColor Yellow

    $manifestName = "evidence-proof-checksums-$runStamp.json"
    Invoke-ProofStage -Name "Checksums manifest publication" -Action {
        $manifestPath = Join-Path $workDir $manifestName
        [ordered]@{
            CorrelationId = $CorrelationId
            GeneratedUtc  = (Get-Date).ToUniversalTime().ToString("o")
            Files         = @(
                @{ Name = $smallFileName; Sha256 = $smallFileHash }
                if ($largeFileHash) { @{ Name = $largeFileName; Sha256 = $largeFileHash } }
            )
        } | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding utf8
        Invoke-MgGraphRequest -Method PUT `
            -Uri "$driveBase/root:/$containerPath/Checksums/$($manifestName):/content" `
            -InputFilePath $manifestPath -ContentType "application/json" | Out-Null
        Add-ProofStage -Name "Checksums manifest publication" -Status "Passed" `
            -Detail "$manifestName at $containerPath/Checksums"
    } | Out-Null

    # ── Verdict and report ─────────────────────────────────────────────────
    $failed = @($script:Stages | Where-Object Status -eq "Failed")
    $blocked = @($script:Stages | Where-Object Status -eq "Blocked")

    $verdict = if ($failed.Count -gt 0) { "Failed" }
    elseif ($blocked.Count -gt 0) { "PartiallyProven-407Blocked" }
    else { "Proven" }

    $report = [ordered]@{
        Proof             = "SharePoint end-to-end evidence proof"
        Verdict           = $verdict
        CorrelationId     = $CorrelationId
        SiteId            = $SiteId
        Drive             = $DriveName
        EvidenceContainer = $containerPath
        Timestamp         = (Get-Date).ToUniversalTime().ToString("o")
        Stages            = $script:Stages
    }
    $reportPath = Join-Path $OutputPath "sharepoint-evidence-proof-$runStamp.json"
    $report | ConvertTo-Json -Depth 8 | Out-File -FilePath $reportPath -Encoding utf8

    $bannerColor = switch ($verdict) {
        "Proven" { "Green" }
        "PartiallyProven-407Blocked" { "Yellow" }
        default { "Red" }
    }
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor $bannerColor
    Write-Host ("║  VERDICT: {0,-49}║" -f $verdict) -ForegroundColor $bannerColor
    Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor $bannerColor
    Write-Host "Proof report: $reportPath" -ForegroundColor Cyan

    switch ($verdict) {
        "Proven" { exit 0 }
        "PartiallyProven-407Blocked" { exit 2 }
        default { exit 1 }
    }
}
catch {
    Write-Host "✗ Error: $_" -ForegroundColor Red
    exit 1
}
