# Pgg Universal Memory-bank Kit

One-command Memory-bank bootstrap for backend, frontend, and mobile repositories.

This kit installs:
- `Memory-bank/` durable docs
- `AGENTS.md` start/end enforcement contract
- cross-agent instruction files:
  - `.github/copilot-instructions.md`
  - `.clinerules`
  - `CLAUDE.md`
  - `GEMINI.md`
  - `ANTIGRAVITY.md`
- pre-commit guard + CI guard
- summary/generator scripts

Default mode is `warn` so teams can stabilize before switching to strict blocking.

New in this version:
- one-time global CLI installer: `pg-install.ps1`
- global command after install: `pg install`, `pg start`, `pg end`, `pg status`
- one-command session bootstrap: `scripts/start_memory_bank_session.ps1`
- simple CLI wrapper: `pg.ps1` / `pg.cmd`
- session enforcement in guard:
  - session must be started
  - session expires after `12` hours (default)
  - session expires after `5` commits from anchor (default)
  - session policy is blocking even in `warn` mode
- nested monorepo-safe hook installation (`core.hooksPath` is set correctly even when target is a subfolder)

## One-Time Global CLI Setup (recommended)
Run once on each developer machine:

```powershell
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) {
  winget install --id GitHub.cli -e
  Write-Host "Restart terminal, then run this command again."
  return
}
& $gh auth status
if ($LASTEXITCODE -ne 0) { & $gh auth login --web --git-protocol https --hostname github.com }

$repo = "figchamdemb/Pgg-uni-memory-bank"
$tmp = Join-Path $env:TEMP "pg-install.ps1"
& $gh api -H "Accept: application/vnd.github.raw" "/repos/$repo/contents/pg-install.ps1?ref=main" > $tmp
powershell -ExecutionPolicy Bypass -File $tmp
```

After this, you can use `pg` directly (no `.\`).

## Install Commands (after global setup)
Run in target repo root:

### Backend
```powershell
pg install backend
```

### Frontend
```powershell
pg install frontend
```

### Mobile
```powershell
pg install mobile
```

Optional:
- `pg install backend --mode warn --keep-days 7`
- `pg install backend --target C:\path\to\repo`

## Legacy Direct Install Commands (without global setup)
Run these only if you do not want the global `pg` command.

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

## Start Every Session (required)

Run this in the target repo before coding:

```powershell
pg start -Yes
```

End shift:

```powershell
pg end -Note "finished for today"
```

Session status:

```powershell
pg status
```

From outside repo root, you can target explicitly:

```powershell
pg start --target C:\path\to\repo -Yes
```

This command:
- refreshes summary + memory docs
- updates `daily/LATEST.md`
- writes `Memory-bank/_generated/session-state.json`
- sets session budget used by guard

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
