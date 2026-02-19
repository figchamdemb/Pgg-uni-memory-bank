# Non-Technical Quick Start

This guide is for first-time users.

## What You Do
1. Install `pg` once on your machine.
2. Install Memory-bank once in each project.
3. Start and end session every work shift.

## Which Terminal Should I Use?
- VS Code terminal is recommended for daily use.
- External PowerShell is also fine for first setup.
- If VS Code opens CMD by default, you can still use `pg`.

No admin is needed for normal `pg` commands.
Admin may be required only if your IT policy blocks `winget`.

## Step 1: One-Time Setup Per Machine
Open PowerShell and run:

```powershell
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) {
  winget install --id GitHub.cli -e
  Write-Host "Restart terminal, then run this block again."
  return
}
& $gh auth status
if ($LASTEXITCODE -ne 0) { & $gh auth login --web --git-protocol https --hostname github.com }

$repo = "figchamdemb/Pgg-uni-memory-bank"
$tmp = Join-Path $env:TEMP "pg-install.ps1"
& $gh api -H "Accept: application/vnd.github.raw" "/repos/$repo/contents/pg-install.ps1?ref=main" > $tmp
powershell -ExecutionPolicy Bypass -File $tmp
```

Verify:

```powershell
pg version
```

## Step 2: One-Time Setup Per Project
Open your project root folder in terminal.

If you are in CMD:

```bat
pg install backend --target "%CD%"
```

If you are in PowerShell:

```powershell
pg install backend --target (Get-Location).Path
```

If you are unsure, this works in both:

```bat
pg install backend --target .
```

Change `backend` to `frontend` or `mobile` when needed.

## Step 3: Every Work Session
Run this before coding:

```powershell
pg start -Yes
```

Optional check:

```powershell
pg status
```

Run this when ending your shift:

```powershell
pg end -Note "finished for today"
```

## Using AI Tools (Copilot/Claude/Codex/Cline)
- Start session first in terminal (`pg start -Yes`).
- Then use your normal AI chat interface.
- End session in terminal (`pg end ...`) before final summary/commit.

## Common Mistakes
- Running `pg install` every time. It is only needed once per repo.
- Running PowerShell syntax in CMD:
  - `(Get-Location).Path` is PowerShell only.
  - CMD equivalent is `%CD%`.
- Not reopening terminal after PATH changes.

## If Something Fails
Open:
- `TROUBLESHOOTING.md`
