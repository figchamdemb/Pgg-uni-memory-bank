# Troubleshooting Guide

Use this page when setup or commands fail.

## Quick Check
Run:

```powershell
pg version
```

If this fails, see the first error below.

## Error: `pg : The term 'pg' is not recognized`
Meaning:
- Global CLI is not installed in this terminal session.

Fix:
1. Run machine setup from `NON_TECHNICAL_QUICKSTART.md`.
2. Close and reopen terminal.
3. Verify:

```powershell
pg version
```

Temporary workaround for current terminal:

```powershell
$env:Path += ";$HOME\.pg-cli"
pg version
```

## Error: `gh : The term 'gh' is not recognized`
Meaning:
- GitHub CLI is not installed or not in PATH.

Fix:

```powershell
winget install --id GitHub.cli -e
```

Then close and reopen terminal.

## Error: `Target path not found: (Get-Location).Path`
Meaning:
- You ran PowerShell syntax in CMD.

Fix:
- CMD:

```bat
pg install backend --target "%CD%"
```

- PowerShell:

```powershell
pg install backend --target (Get-Location).Path
```

Cross-shell safe:

```bat
pg install backend --target .
```

## Error: `Cannot validate argument on parameter 'Command' ... "install" ...`
Meaning:
- Old local `scripts/pg.ps1` file is handling command.

Fix:
1. Update from latest kit:

```powershell
pg install backend --target .
```

2. If still not fixed, run global command directly:

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.pg-cli\pg.ps1" install backend --target .
```

## Error: `gh: Not Found (HTTP 404)`
Meaning:
- Wrong repo slug, wrong branch, or no access to private repo.

Fix:
1. Confirm repo exists and filename exists.
2. Confirm you are logged in with approved account:

```powershell
gh auth status
```

3. Ask owner to add you as collaborator and accept invite.

## Error: `Permission denied` / HTTP 403
Meaning:
- You are authenticated but not authorized for private repo.

Fix:
1. Owner adds your GitHub account to private repo access.
2. You accept invitation.
3. Re-login if needed:

```powershell
gh auth logout -h github.com
gh auth login --web --git-protocol https --hostname github.com
```

## Error: PowerShell shows `>>`
Meaning:
- You are in continuation mode (incomplete command).

Fix:
1. Press `Ctrl + C`.
2. Run the command again as one complete line.

## Warning: `Target is not inside a git work tree; skipped hook installation.`
Meaning:
- Memory-bank files were created, but git hooks were not installed.

Fix:

```powershell
git init
powershell -ExecutionPolicy Bypass -File .\scripts\install_memory_bank_hooks.ps1 -Mode warn
```

Verify:

```powershell
git config --get core.hooksPath
```

## `pg install` vs `pg start`
- `pg install`: one-time per repo.
- `pg start`: every work session before coding.
- `pg end`: at end of shift/session.

## Still Stuck
Collect these outputs and send to support:

```powershell
pg version
gh auth status
git config --get core.hooksPath
git config --get memorybank.mode
```
