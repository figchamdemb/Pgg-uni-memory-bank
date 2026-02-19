# Pgg Universal Memory-bank Kit

One-command Memory-bank bootstrap for backend, frontend, and mobile repositories.

## Quick Links
- Non-technical setup: `NON_TECHNICAL_QUICKSTART.md`
- Error guide: `TROUBLESHOOTING.md`
- Team distribution: `GitHub Distribution + Team Install.md`

## What This Installs
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

## Terminal and Permissions
- You can run this from VS Code terminal or external terminal.
- Normal user permissions are enough for `pg` commands.
- Admin is only needed if your machine policy blocks `winget` or app install.
- If VS Code does not detect new PATH after install, close and reopen VS Code terminal.

## Setup Order
1. One-time per machine: install global `pg` command.
2. One-time per repo: run `pg install backend|frontend|mobile`.
3. Every work session: run `pg start -Yes` before coding, and `pg end` when done.

## One-Time Global CLI Setup
Run once on each developer machine (PowerShell):

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

Verify:

```powershell
pg version
```

## Repo Install Commands
Run in target repo root.

Backend:

```powershell
pg install backend
```

Frontend:

```powershell
pg install frontend
```

Mobile:

```powershell
pg install mobile
```

If terminal is CMD and you need explicit target path:

```bat
pg install backend --target "%CD%"
```

If terminal is PowerShell and you need explicit target path:

```powershell
pg install backend --target (Get-Location).Path
```

Cross-shell safe option:

```bat
pg install backend --target .
```

## Daily Session Commands
Run in target repo root before coding:

```powershell
pg start -Yes
```

Status:

```powershell
pg status
```

End of shift:

```powershell
pg end -Note "finished for today"
```

Important:
- `pg install` is not a daily command.
- Use `pg install` only first time per repo or when refreshing templates.

## LLM Workflow Clarification
- Best practice: you run `pg start -Yes` in terminal first, then use your AI chat.
- At end, run `pg end ...` in terminal before final summary or commit.
- If your agent has terminal execution access, it can run these commands too.

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

## Notes
- No secrets in Memory-bank.
- Generated memory pack is installed into target repo; universal template folder is not copied.
