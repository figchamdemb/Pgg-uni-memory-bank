# GitHub Distribution + Team Install

LAST_UPDATED_UTC: 2026-02-17 04:05
OWNER: Universal template

## Goal
Store your universal Memory-bank kit in GitHub so any developer can install it into any repo with one command.

## Recommended GitHub Repo
Create a dedicated repo, for example:
- `egov-memory-bank-standard`

Put these files at repo root:
- `pg-install.ps1`
- `pg.ps1`
- `mb-init.ps1`
- `mb-install-from-github.ps1`
- `install-backend.ps1`
- `install-frontend.ps1`
- `install-mobile.ps1`
- `Memory-bank Automation + Guard Setup (universal).md`
- `GitHub Distribution + Team Install.md`
- `Recommended folder layout (universal).txt`
- `universal Agent System Prompt.txt`
- `UNIVERSAL REVIEWER AGENT PROMPT.txt`

Important:
- Keep filenames exactly as above.
- Keep `mb-init.ps1` at repo root for a clean raw URL.

## One-Time Publish
From local universal folder:
1. Copy files into your new GitHub repo.
2. Commit and push.
3. Confirm raw URL works in browser:
   - `https://raw.githubusercontent.com/<ORG>/<REPO>/<BRANCH>/mb-init.ps1`

## Developer Install (VS Code Terminal, inside target repo)
Run this command (PowerShell):

```powershell
$u = "https://raw.githubusercontent.com/<ORG>/<REPO>/<BRANCH>/mb-init.ps1"
$tmp = Join-Path $env:TEMP "mb-init.ps1"
Invoke-WebRequest -Uri $u -OutFile $tmp
powershell -ExecutionPolicy Bypass -File $tmp `
  -TargetRepoPath (Get-Location).Path `
  -ProjectType backend `
  -EnforcementMode warn `
  -DailyKeepDays 7
```

Replace:
- `<ORG>` with your GitHub org/user
- `<REPO>` with your standard repo name
- `<BRANCH>` with `main` (or your default branch)

## One-Time Global `pg` Command Setup (recommended)
Run once per machine:

```powershell
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { winget install --id GitHub.cli -e; return }
& $gh auth status
if ($LASTEXITCODE -ne 0) { & $gh auth login --web --git-protocol https --hostname github.com }

$repo = "<ORG>/<REPO>"
$tmp = Join-Path $env:TEMP "pg-install.ps1"
& $gh api -H "Accept: application/vnd.github.raw" "/repos/$repo/contents/pg-install.ps1?ref=<BRANCH>" > $tmp
powershell -ExecutionPolicy Bypass -File $tmp -RepoSlug $repo -Ref "<BRANCH>"
```

Then usage is short:

```powershell
pg install backend
cd C:\path\to\target-repo
pg start -Yes
pg status
pg end -Note "finished for today"
```

## One Command Per Project Type (recommended)
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

## Optional Wrapper Install (same flow, more reusable)
Use the helper script:

```powershell
$installUrl = "https://raw.githubusercontent.com/<ORG>/<REPO>/<BRANCH>/mb-install-from-github.ps1"
$tmp = Join-Path $env:TEMP "mb-install-from-github.ps1"
Invoke-WebRequest -Uri $installUrl -OutFile $tmp
powershell -ExecutionPolicy Bypass -File $tmp `
  -RawMbInitUrl "https://raw.githubusercontent.com/<ORG>/<REPO>/<BRANCH>/mb-init.ps1" `
  -TargetRepoPath (Get-Location).Path `
  -ProjectType backend `
  -EnforcementMode warn `
  -DailyKeepDays 7
```

## Project Type Selection
- `backend`: Java/Spring, Node/Nest backend, APIs, DB migrations
- `frontend`: Next.js/React/Vue web UI
- `mobile`: Android/iOS/React Native/Flutter

## Enforcement Mode
- Start with `warn` (recommended now)
- Move to `strict` later when stable:
  - local: `git config memorybank.mode strict`
  - CI: set repo variable `MB_ENFORCEMENT_MODE=strict`

## What gets installed
- `Memory-bank/` docs + templates + daily pointer
- `Memory-bank/tools-and-commands.md` (runtime + startup command inventory)
- `Memory-bank/coding-security-standards.md` (security + 500-line screen/page policy)
- root `AGENTS.md`
- `scripts/memory_bank_guard.py`
- `scripts/generate_memory_bank.py`
- `scripts/build_<project>_summary.py`
- `scripts/start_memory_bank_session.py`
- `scripts/start_memory_bank_session.ps1`
- `scripts/end_memory_bank_session.py`
- `scripts/end_memory_bank_session.ps1`
- `scripts/session_status.py`
- `scripts/pg.ps1`
- root `pg.ps1` and `pg.cmd`
- `.githooks/pre-commit`
- `.github/workflows/memory-bank-guard.yml`

## Extra Enforcement Included
- Session must be started before coding:
  - `pg start -Yes`
- Guard checks session-state freshness:
  - max 5 commits per session (default)
  - max 12 hours per session (default)
  - this session check is blocking even when mode is `warn`
- Screen/Page files above 500 lines are flagged by guard and CI.
  - `warn` mode: warning only
  - `strict` mode: commit/PR fails
- Tooling/runtime/start command changes require `Memory-bank/tools-and-commands.md` update.

## Daily Commands for Developers (simple)
From repo root:
- Start: `pg start -Yes`
- Status: `pg status`
- End: `pg end -Note "finished for today"`

## Team Policy
For consistency across agents (Codex/Claude/Copilot):
1. Every repo installs from the same GitHub standard.
2. Every code task starts by reading Memory-bank files.
3. Every code task ends by updating Memory-bank before summary.
4. Keep mode `warn` until team is stable, then flip to `strict`.

## Monorepo / Branch Notes
- If your backend is a subfolder inside a larger git repo, install with:
  - `-TargetRepoPath <subfolder path>`
- Hook installer now sets `core.hooksPath` to the correct relative subfolder path.
- You can run on any branch (`main`, `police`, feature branches). It updates the same branch state, no separate Memory-bank is required unless you intentionally use a different target folder.
