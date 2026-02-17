[CmdletBinding()]
param(
    [string]$TargetRepoPath = ".",
    [ValidateSet("warn", "strict")]
    [string]$EnforcementMode = "warn",
    [ValidateRange(1, 365)]
    [int]$DailyKeepDays = 7,
    [switch]$SkipHookInstall,
    [switch]$Force,
    [string]$RawBaseUrl = "https://raw.githubusercontent.com/figchamdemb/Pgg-uni-memory-bank/main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP ("mb-install-from-github-" + [Guid]::NewGuid().ToString("N") + ".ps1")
Invoke-WebRequest -Uri "$RawBaseUrl/mb-install-from-github.ps1" -OutFile $tmp

try {
    $args = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $tmp,
        "-RawMbInitUrl", "$RawBaseUrl/mb-init.ps1",
        "-TargetRepoPath", $TargetRepoPath,
        "-ProjectType", "backend",
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
        throw "Backend install failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
