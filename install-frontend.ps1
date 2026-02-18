[CmdletBinding()]
param(
    [string]$TargetRepoPath = ".",
    [ValidateSet("warn", "strict")]
    [string]$EnforcementMode = "warn",
    [ValidateRange(1, 365)]
    [int]$DailyKeepDays = 7,
    [switch]$SkipHookInstall,
    [switch]$Force,
    [string]$RepoSlug = "figchamdemb/Pgg-uni-memory-bank",
    [string]$Ref = "main",
    [string]$RawMbInitUrl = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP ("mb-init-" + [Guid]::NewGuid().ToString("N") + ".ps1")

if (-not [string]::IsNullOrWhiteSpace($RawMbInitUrl)) {
    Invoke-WebRequest -Uri $RawMbInitUrl -OutFile $tmp
} else {
    $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
    if (-not $gh) {
        $ghPath = "C:\Program Files\GitHub CLI\gh.exe"
        if (Test-Path -LiteralPath $ghPath) {
            $gh = $ghPath
        }
    }

    if (-not $gh) {
        throw "GitHub CLI not found. Install GitHub CLI or pass -RawMbInitUrl."
    }

    $apiPath = "/repos/$RepoSlug/contents/mb-init.ps1?ref=$Ref"
    & $gh api -H "Accept: application/vnd.github.raw" $apiPath > $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch mb-init.ps1 from $RepoSlug. Check gh auth account and repo access."
    }

    $firstLine = Get-Content -Path $tmp -TotalCount 1 -ErrorAction SilentlyContinue
    if ($firstLine -match '^\s*\{') {
        throw "Downloaded response is not a PowerShell script. Check private repo access for account in gh auth status."
    }
}

try {
    $args = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $tmp,
        "-TargetRepoPath", $TargetRepoPath,
        "-ProjectType", "frontend",
        "-EnforcementMode", $EnforcementMode,
        "-DailyKeepDays", $DailyKeepDays
    )

    if ($SkipHookInstall.IsPresent) {
        $args += "-SkipHookInstall"
    }
    if ($Force.IsPresent) {
        $args += "-Force"
    }

    & powershell @args
    if ($LASTEXITCODE -ne 0) {
        throw "Frontend install failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
