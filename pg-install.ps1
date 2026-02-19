[CmdletBinding()]
param(
    [string]$RepoSlug = "figchamdemb/Pgg-uni-memory-bank",
    [string]$Ref = "main",
    [string]$InstallDir = "",
    [string]$SourceFile = "",
    [switch]$SkipPathUpdate,
    [switch]$SkipProfileUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $HOME ".pg-cli"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
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
        throw "GitHub CLI installed but not available in this shell. Open a new terminal and retry."
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

function Ensure-UserPathContains {
    param([Parameter(Mandatory = $true)][string]$PathToAdd)

    $normalizedAdd = $PathToAdd.TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $entries = $userPath.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $exists = $false
    foreach ($entry in $entries) {
        if ($entry.TrimEnd('\') -ieq $normalizedAdd) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $PathToAdd
        } else {
            "$userPath;$PathToAdd"
        }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Host "[write] User PATH updated with: $PathToAdd"
    } else {
        Write-Host "[ok] User PATH already contains: $PathToAdd"
    }

    $sessionEntries = $env:Path.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $inSession = $false
    foreach ($entry in $sessionEntries) {
        if ($entry.TrimEnd('\') -ieq $normalizedAdd) {
            $inSession = $true
            break
        }
    }
    if (-not $inSession) {
        $env:Path = "$env:Path;$PathToAdd"
    }
}

function Ensure-ProfileFunction {
    param([Parameter(Mandatory = $true)][string]$InstalledPgPs1)

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDir = Split-Path -Path $profilePath -Parent
    Ensure-Directory -Path $profileDir

    $startMarker = "# >>> pgg-memory-bank-cli >>>"
    $endMarker = "# <<< pgg-memory-bank-cli <<<"
    $escapedPath = $InstalledPgPs1.Replace("'", "''")

    $snippet = @"
$startMarker
function pg {
    param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Args)
    & '$escapedPath' @Args
}
$endMarker
"@

    $current = ""
    if (Test-Path -LiteralPath $profilePath) {
        $current = Get-Content -Path $profilePath -Raw
    }

    if ($current -match [regex]::Escape($startMarker)) {
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($current) -and -not $current.EndsWith("`n")) {
        $current += "`r`n"
    }
    $updated = $current + $snippet + "`r`n"
    [System.IO.File]::WriteAllText($profilePath, $updated, $utf8NoBom)
    Write-Host "[write] $profilePath"
}

function Download-PgScript {
    param(
        [Parameter(Mandatory = $true)][string]$GhPath,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Branch
    )

    $tmp = Join-Path $env:TEMP ("pg-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    $apiPath = "/repos/$Repo/contents/pg.ps1?ref=$Branch"
    & $GhPath api -H "Accept: application/vnd.github.raw" $apiPath > $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download pg.ps1 from $Repo@$Branch"
    }

    $firstLine = Get-Content -Path $tmp -TotalCount 1 -ErrorAction SilentlyContinue
    if ($firstLine -match '^\s*\{') {
        throw "Downloaded response is not a PowerShell script. Verify repo access and gh account."
    }
    return $tmp
}

Ensure-Directory -Path $InstallDir

$tempPg = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($SourceFile)) {
        $resolvedSource = Resolve-Path -LiteralPath $SourceFile -ErrorAction SilentlyContinue
        if (-not $resolvedSource) {
            throw "SourceFile not found: $SourceFile"
        }
        $tempPg = $resolvedSource.Path
    } else {
        $gh = Ensure-Gh
        Ensure-GhAuth -GhPath $gh
        $tempPg = Download-PgScript -GhPath $gh -Repo $RepoSlug -Branch $Ref
    }

    $installedPgPs1 = Join-Path $InstallDir "pg.ps1"
    Copy-Item -LiteralPath $tempPg -Destination $installedPgPs1 -Force
    Write-Host "[write] $installedPgPs1"

    $pgCmdPath = Join-Path $InstallDir "pg.cmd"
    $cmdContent = @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pg.ps1" %*
'@
    [System.IO.File]::WriteAllText($pgCmdPath, $cmdContent, $utf8NoBom)
    Write-Host "[write] $pgCmdPath"

    if (-not $SkipPathUpdate.IsPresent) {
        Ensure-UserPathContains -PathToAdd $InstallDir
    } else {
        Write-Host "[skip] User PATH update skipped."
    }

    if (-not $SkipProfileUpdate.IsPresent) {
        Ensure-ProfileFunction -InstalledPgPs1 $installedPgPs1
    } else {
        Write-Host "[skip] Profile function update skipped."
    }

    Write-Host ""
    Write-Host "Global pg install complete."
    Write-Host "Try now:"
    Write-Host "  pg version"
    Write-Host "  pg install backend --target C:\path\to\repo"
    Write-Host "  cd C:\path\to\repo"
    Write-Host "  pg start -Yes"
}
finally {
    if ($tempPg -and -not [string]::IsNullOrWhiteSpace($SourceFile)) {
        # local source path, do nothing
    } elseif ($tempPg) {
        Remove-Item -LiteralPath $tempPg -Force -ErrorAction SilentlyContinue
    }
}
