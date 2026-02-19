param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "start", "end", "status", "help", "version")]
    [string]$Command = "help",

    [Alias("t")]
    [string]$Target = "",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DefaultRepoSlug = "figchamdemb/Pgg-uni-memory-bank"
$DefaultRef = "main"

function Show-Help {
    Write-Host "pg - Memory-bank CLI"
    Write-Host ""
    Write-Host "One-time global setup:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\pg-install.ps1"
    Write-Host ""
    Write-Host "Install into current repo:"
    Write-Host "  pg install backend"
    Write-Host "  pg install frontend"
    Write-Host "  pg install mobile"
    Write-Host ""
    Write-Host "Install into specific path:"
    Write-Host "  pg install backend --target C:\path\to\repo"
    Write-Host ""
    Write-Host "Session commands (inside an installed repo):"
    Write-Host "  pg start -Yes"
    Write-Host "  pg status"
    Write-Host "  pg end -Note ""finished for today"""
    Write-Host ""
    Write-Host "Session commands from anywhere (explicit target):"
    Write-Host "  pg start --target C:\path\to\repo -Yes"
    Write-Host "  pg status --target C:\path\to\repo"
    Write-Host "  pg end --target C:\path\to\repo -Note ""finished for today"""
    Write-Host ""
    Write-Host "Optional install flags:"
    Write-Host "  --mode warn|strict"
    Write-Host "  --keep-days 7"
    Write-Host "  --repo <owner/repo>"
    Write-Host "  --ref <branch>"
}

function Get-GhPath {
    $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
    if ($gh) {
        return $gh
    }

    $fallback = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path -LiteralPath $fallback) {
        return $fallback
    }
    return $null
}

function Ensure-Gh {
    $gh = Get-GhPath
    if ($gh) {
        return $gh
    }

    $winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
    if (-not $winget) {
        throw "GitHub CLI not found and winget is unavailable. Install GitHub CLI manually."
    }

    Write-Host "GitHub CLI not found. Installing via winget..."
    & $winget install --id GitHub.cli -e
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install GitHub CLI."
    }

    $gh = Get-GhPath
    if (-not $gh) {
        throw "GitHub CLI installed but not available in current shell. Open a new terminal and retry."
    }
    return $gh
}

function Ensure-GhAuth {
    param([Parameter(Mandatory = $true)][string]$GhPath)

    & $GhPath auth status *> $null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    Write-Host "GitHub CLI is not authenticated. Opening login flow..."
    & $GhPath auth login --web --git-protocol https --hostname github.com
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI login failed."
    }
}

function Parse-InstallArgs {
    param(
        [string[]]$Args,
        [string]$DefaultTarget = ""
    )

    $projectType = "backend"
    $targetPath = if (-not [string]::IsNullOrWhiteSpace($DefaultTarget)) { $DefaultTarget } else { (Get-Location).Path }
    $mode = "warn"
    $keepDays = 7
    $repo = $env:PG_MB_REPO
    if (-not $repo) { $repo = $DefaultRepoSlug }
    $ref = $env:PG_MB_REF
    if (-not $ref) { $ref = $DefaultRef }

    $i = 0
    if ($Args.Count -gt 0 -and $Args[0] -in @("backend", "frontend", "mobile")) {
        $projectType = $Args[0]
        $i = 1
    }

    while ($i -lt $Args.Count) {
        switch ($Args[$i]) {
            "--target" {
                $i++
                if ($i -ge $Args.Count) { throw "--target requires a value." }
                $targetPath = $Args[$i]
            }
            "--mode" {
                $i++
                if ($i -ge $Args.Count) { throw "--mode requires a value." }
                $mode = $Args[$i].ToLowerInvariant()
                if ($mode -notin @("warn", "strict")) {
                    throw "Invalid mode: $mode. Allowed: warn|strict"
                }
            }
            "--keep-days" {
                $i++
                if ($i -ge $Args.Count) { throw "--keep-days requires a value." }
                $keepDays = [int]$Args[$i]
                if ($keepDays -lt 1 -or $keepDays -gt 365) {
                    throw "--keep-days must be between 1 and 365."
                }
            }
            "--repo" {
                $i++
                if ($i -ge $Args.Count) { throw "--repo requires a value." }
                $repo = $Args[$i]
            }
            "--ref" {
                $i++
                if ($i -ge $Args.Count) { throw "--ref requires a value." }
                $ref = $Args[$i]
            }
            default {
                throw "Unknown install argument: $($Args[$i])"
            }
        }
        $i++
    }

    return [PSCustomObject]@{
        ProjectType = $projectType
        TargetPath = $targetPath
        Mode = $mode
        KeepDays = $keepDays
        Repo = $repo
        Ref = $ref
    }
}

function Invoke-RemoteInstall {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectType,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][int]$KeepDays,
        [Parameter(Mandatory = $true)][string]$RepoSlug,
        [Parameter(Mandatory = $true)][string]$Ref
    )

    $gh = Ensure-Gh
    Ensure-GhAuth -GhPath $gh

    $installerName = switch ($ProjectType) {
        "backend" { "install-backend.ps1" }
        "frontend" { "install-frontend.ps1" }
        "mobile" { "install-mobile.ps1" }
        default { throw "Unsupported project type: $ProjectType" }
    }

    $tmp = Join-Path $env:TEMP ("$installerName-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    try {
        $apiPath = "/repos/$RepoSlug/contents/${installerName}?ref=$Ref"
        & $gh api -H "Accept: application/vnd.github.raw" $apiPath > $tmp
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download $installerName from $RepoSlug@$Ref"
        }

        $firstLine = Get-Content -Path $tmp -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -match '^\s*\{') {
            throw "Downloaded response is not a PowerShell script. Verify repo access and gh account."
        }

        $resolvedTarget = Resolve-Path -LiteralPath $TargetPath -ErrorAction SilentlyContinue
        if (-not $resolvedTarget) {
            throw "Target path not found: $TargetPath"
        }

        & powershell -ExecutionPolicy Bypass -File $tmp `
            -TargetRepoPath $resolvedTarget.Path `
            -EnforcementMode $Mode `
            -DailyKeepDays $KeepDays `
            -RepoSlug $RepoSlug `
            -Ref $Ref

        if ($LASTEXITCODE -ne 0) {
            throw "Installer failed with exit code $LASTEXITCODE."
        }

        Write-Host ""
        Write-Host "Install complete."
        Write-Host "Run in target repo:"
        Write-Host "  .\pg.ps1 start -Yes"
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Find-LocalRepoRoot {
    param([string]$StartPath = "")

    $dir = $StartPath
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $dir = (Get-Location).Path
    }

    while ($true) {
        $scriptsPg = Join-Path $dir "scripts\pg.ps1"
        if (Test-Path -LiteralPath $scriptsPg) {
            return $dir
        }
        $parent = Split-Path -Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) {
            break
        }
        $dir = $parent
    }
    return $null
}

function Parse-LocalArgs {
    param(
        [string[]]$Args,
        [string]$DefaultTarget = ""
    )

    $targetPath = if (-not [string]::IsNullOrWhiteSpace($DefaultTarget)) { $DefaultTarget } else { $null }
    $forward = New-Object System.Collections.Generic.List[string]

    $i = 0
    while ($i -lt $Args.Count) {
        $token = $Args[$i]
        if ($token -in @("--target", "-target")) {
            $i++
            if ($i -ge $Args.Count) {
                throw "--target requires a value."
            }
            $targetPath = $Args[$i]
        }
        else {
            $forward.Add($token)
        }
        $i++
    }

    return [PSCustomObject]@{
        TargetPath = $targetPath
        ForwardArgs = $forward.ToArray()
    }
}

function Invoke-LocalCommand {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("start", "end", "status")]
        [string]$LocalCommand,
        [string[]]$Args,
        [string]$DefaultTarget = ""
    )

    $parsed = Parse-LocalArgs -Args $Args -DefaultTarget $DefaultTarget
    $searchPath = ""
    if (-not [string]::IsNullOrWhiteSpace($parsed.TargetPath)) {
        $resolvedTarget = Resolve-Path -LiteralPath $parsed.TargetPath -ErrorAction SilentlyContinue
        if (-not $resolvedTarget) {
            throw "Target path not found: $($parsed.TargetPath)"
        }
        $searchPath = $resolvedTarget.Path
    }

    $repoRoot = Find-LocalRepoRoot -StartPath $searchPath
    if (-not $repoRoot) {
        throw "No Memory-bank repo found. Run in repo root, or pass --target <path>, or run 'pg install backend' first."
    }

    $localPg = Join-Path $repoRoot "scripts\pg.ps1"
    & powershell -ExecutionPolicy Bypass -File $localPg $LocalCommand @($parsed.ForwardArgs)
    exit $LASTEXITCODE
}

switch ($Command) {
    "help" {
        Show-Help
        exit 0
    }
    "version" {
        Write-Host "pg version: 1.0.0"
        Write-Host "default repo: $DefaultRepoSlug"
        exit 0
    }
    "install" {
        $opts = Parse-InstallArgs -Args $Rest -DefaultTarget $Target
        Invoke-RemoteInstall -ProjectType $opts.ProjectType -TargetPath $opts.TargetPath -Mode $opts.Mode -KeepDays $opts.KeepDays -RepoSlug $opts.Repo -Ref $opts.Ref
        exit 0
    }
    "start" { Invoke-LocalCommand -LocalCommand "start" -Args $Rest -DefaultTarget $Target }
    "end" { Invoke-LocalCommand -LocalCommand "end" -Args $Rest -DefaultTarget $Target }
    "status" { Invoke-LocalCommand -LocalCommand "status" -Args $Rest -DefaultTarget $Target }
    default {
        Show-Help
        exit 1
    }
}
