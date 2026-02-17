[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RawMbInitUrl,
    [string]$TargetRepoPath = ".",
    [ValidateSet("backend", "frontend", "mobile")]
    [string]$ProjectType = "backend",
    [ValidateSet("warn", "strict")]
    [string]$EnforcementMode = "warn",
    [ValidateRange(1, 365)]
    [int]$DailyKeepDays = 7,
    [switch]$SkipHookInstall,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedTarget = Resolve-Path -LiteralPath $TargetRepoPath -ErrorAction SilentlyContinue
if (-not $resolvedTarget) {
    throw "TargetRepoPath not found: $TargetRepoPath"
}

$target = $resolvedTarget.Path
$tempScript = Join-Path $env:TEMP ("mb-init-" + [Guid]::NewGuid().ToString("N") + ".ps1")

Write-Host "Downloading mb-init script..."
Write-Host "Source: $RawMbInitUrl"
Invoke-WebRequest -Uri $RawMbInitUrl -OutFile $tempScript

if (-not (Test-Path -LiteralPath $tempScript)) {
    throw "Failed to download mb-init script."
}

try {
    Write-Host "Running mb-init for target repo: $target"
    $args = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $tempScript,
        "-TargetRepoPath", $target,
        "-ProjectType", $ProjectType,
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
        throw "mb-init execution failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Install complete."
Write-Host "Repo: $target"
Write-Host "Type: $ProjectType"
Write-Host "Mode: $EnforcementMode"
