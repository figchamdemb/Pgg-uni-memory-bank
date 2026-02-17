# Pgg Universal Memory-bank Kit

One-command Memory-bank bootstrap for backend, frontend, and mobile repositories.

This kit installs:
- `Memory-bank/` durable docs
- `AGENTS.md` start/end enforcement contract
- pre-commit guard + CI guard
- summary/generator scripts

Default mode is `warn` so teams can stabilize before switching to strict blocking.

## Install Commands (run in target repo root in VS Code terminal)

### Backend
```powershell
$u = "https://raw.githubusercontent.com/figchamdemb/Pgg-uni-memory-bank/main/install-backend.ps1"
$tmp = Join-Path $env:TEMP "install-backend.ps1"
Invoke-WebRequest -Uri $u -OutFile $tmp
powershell -ExecutionPolicy Bypass -File $tmp -TargetRepoPath (Get-Location).Path
```

### Frontend
```powershell
$u = "https://raw.githubusercontent.com/figchamdemb/Pgg-uni-memory-bank/main/install-frontend.ps1"
$tmp = Join-Path $env:TEMP "install-frontend.ps1"
Invoke-WebRequest -Uri $u -OutFile $tmp
powershell -ExecutionPolicy Bypass -File $tmp -TargetRepoPath (Get-Location).Path
```

### Mobile
```powershell
$u = "https://raw.githubusercontent.com/figchamdemb/Pgg-uni-memory-bank/main/install-mobile.ps1"
$tmp = Join-Path $env:TEMP "install-mobile.ps1"
Invoke-WebRequest -Uri $u -OutFile $tmp
powershell -ExecutionPolicy Bypass -File $tmp -TargetRepoPath (Get-Location).Path
```

## Enforcement Highlights
- Start-of-session: agent reads latest Memory-bank context before coding.
- End-of-session: agent must update Memory-bank before final summary.
- `warn` mode: violations are shown but not blocked.
- `strict` mode: violations fail commits/PR checks.
- Screen/Page max size policy: 500 lines.
- Tool/runtime/start-command changes must update `Memory-bank/tools-and-commands.md`.

## Switch to Strict Later
Local repo:
```powershell
git config memorybank.mode strict
```

CI:
- set repo variable `MB_ENFORCEMENT_MODE=strict`

## Standards Included
- `Memory-bank/coding-security-standards.md`
- `Memory-bank/tools-and-commands.md`
- `Memory-bank/project-details.md` for active plan/feature tracking
- `Memory-bank/mastermind.md` for options, debate, vote, final ruling

## Notes
- No secrets in Memory-bank.
- Generated memory pack is installed into target repo; universal template folder is not copied.
