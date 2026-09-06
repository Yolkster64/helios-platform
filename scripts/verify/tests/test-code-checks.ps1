#Requires -Version 7
Import-Module Pester -MinimumVersion 5.4.0

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'code-checks.ps1')
}

function script:New-CodeChecksTestRepo {
    $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $repo | Out-Null
    & git -C $repo init -b main | Out-Null
    & git -C $repo config user.name 'Test User'
    & git -C $repo config user.email 'test@example.com'
    $repo
}

function script:Add-TrackedFile {
    param(
        [string]$Repo,
        [string]$RelativePath,
        [string]$Content
    )

    $path = Join-Path $Repo $RelativePath
    $parent = Split-Path -Parent $path
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $path -Value $Content -Encoding utf8
}

function script:Commit-Repo {
    param(
        [string]$Repo,
        [string]$Message
    )

    & git -C $Repo add .
    & git -C $Repo commit -m $Message | Out-Null
}

Describe 'Get-CodeCheckTargetFiles' {
    It 'returns all tracked PowerShell files for workflow_dispatch' {
        $repo = New-CodeChecksTestRepo
        Add-TrackedFile -Repo $repo -RelativePath 'scripts/a.ps1' -Content 'Write-Host "a"'
        Add-TrackedFile -Repo $repo -RelativePath 'modules/b.psm1' -Content 'function Invoke-B { }'
        Add-TrackedFile -Repo $repo -RelativePath 'notes.txt' -Content 'ignore'
        Commit-Repo -Repo $repo -Message 'initial'

        $targets = Get-CodeCheckTargetFiles -RepoRoot $repo -EventName 'workflow_dispatch'

        $targets | Should -Be @('modules/b.psm1', 'scripts/a.ps1')
    }

    It 'returns added and renamed PowerShell files for pull_request and excludes deletions' {
        $repo = New-CodeChecksTestRepo
        Add-TrackedFile -Repo $repo -RelativePath 'alpha.ps1' -Content 'Write-Host "alpha"'
        Add-TrackedFile -Repo $repo -RelativePath 'delete-me.ps1' -Content 'Write-Host "gone"'
        Commit-Repo -Repo $repo -Message 'base'

        & git -C $repo checkout -b feature | Out-Null
        & git -C $repo mv 'alpha.ps1' 'renamed script.ps1'
        & git -C $repo rm 'delete-me.ps1' | Out-Null
        Add-TrackedFile -Repo $repo -RelativePath 'new script.ps1' -Content 'Write-Host "new"'
        Commit-Repo -Repo $repo -Message 'feature'

        $targets = Get-CodeCheckTargetFiles -RepoRoot $repo -EventName 'pull_request' -BaseRef 'main'

        $targets | Should -Be @('new script.ps1', 'renamed script.ps1')
    }

    It 'falls back to a full tracked scan for new branch pushes' {
        $repo = New-CodeChecksTestRepo
        Add-TrackedFile -Repo $repo -RelativePath 'scripts/a.ps1' -Content 'Write-Host "a"'
        Commit-Repo -Repo $repo -Message 'initial'

        $targets = Get-CodeCheckTargetFiles -RepoRoot $repo -EventName 'push' -Before ('0' * 40)

        $targets | Should -Be @('scripts/a.ps1')
    }

    It 'fails clearly when the pull request base ref cannot be resolved' {
        $repo = New-CodeChecksTestRepo
        Add-TrackedFile -Repo $repo -RelativePath 'scripts/a.ps1' -Content 'Write-Host "a"'
        Commit-Repo -Repo $repo -Message 'initial'

        { Get-CodeCheckTargetFiles -RepoRoot $repo -EventName 'pull_request' -BaseRef 'missing' } |
            Should -Throw '*Could not resolve pull request base ref*'
    }

    It 'rejects unsafe pull request base refs before fetch' {
        $repo = New-CodeChecksTestRepo
        Add-TrackedFile -Repo $repo -RelativePath 'scripts/a.ps1' -Content 'Write-Host "a"'
        Commit-Repo -Repo $repo -Message 'initial'

        { Get-CodeCheckTargetFiles -RepoRoot $repo -EventName 'pull_request' -BaseRef 'main:evil' } |
            Should -Throw '*Unsafe pull request base ref*'
    }
}

Describe 'Test-PowerShellSyntax' {
    It 'fails on parser errors instead of tokenizing successfully' {
        $repo = New-CodeChecksTestRepo
        Add-TrackedFile -Repo $repo -RelativePath 'broken.ps1' -Content 'if ($true) { Write-Host "oops"'
        Commit-Repo -Repo $repo -Message 'broken'

        $result = Test-PowerShellSyntax -RepoRoot $repo -Paths @('broken.ps1')

        $result.Status | Should -Be 'fail'
        $result.Messages.Count | Should -BeGreaterThan 0
        $result.Messages[0] | Should -Match 'broken\.ps1:'
    }
}
