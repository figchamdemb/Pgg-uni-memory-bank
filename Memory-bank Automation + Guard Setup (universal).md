# Memory-bank Automation + Guard Setup (universal)

LAST_UPDATED_UTC: 2026-02-17 02:35
OWNER: Universal template

## Goal
Make Memory-bank updates automatic and enforceable so agents do not skip updates between sessions or model switches.

This guide is reusable for:
- backend projects
- frontend projects
- mobile projects

## What must exist in every new project
1. `Memory-bank/` (the durable docs)
   - include `project-details.md`
   - include `tools-and-commands.md`
   - include `coding-security-standards.md`
2. `AGENTS.md` (agent behavior contract)
3. `scripts/` (generation + guard scripts)
   - include `start_memory_bank_session.ps1`
   - include `end_memory_bank_session.ps1`
   - include `session_status.py`
   - include `pg.ps1`
4. `.githooks/pre-commit` (local enforcement)
5. `.github/workflows/memory-bank-guard.yml` (PR enforcement)

## Why this works
- `AGENTS.md` forces start/end protocol in agent reasoning.
- `pre-commit` blocks local commits missing Memory-bank updates.
- CI workflow enforces policy at PR level.
- Daily retention script keeps Memory-bank lean over time.

---

## One-Command Bootstrap (recommended)
Use the universal bootstrap script:
- `.claude/.universal Memory-bank standard/mb-init.ps1`
- Team GitHub distribution guide:
  - `.claude/.universal Memory-bank standard/GitHub Distribution + Team Install.md`

Default behavior:
- scaffolds full starter pack into target repo
- default enforcement mode is `warn` (non-blocking)
- installs `.githooks` automatically if target repo has `.git`
- preserves existing files unless `-Force` is used

Quick start from workspace root:
```powershell
powershell -ExecutionPolicy Bypass -File ".claude/.universal Memory-bank standard/mb-init.ps1" `
  -TargetRepoPath "C:\path\to\repo" `
  -ProjectType backend `
  -EnforcementMode warn `
  -DailyKeepDays 7
```

If already inside target repo:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\ebrim\Desktop\WORKING-PRO\.claude\.universal Memory-bank standard\mb-init.ps1"
```

Switch to strict later:
```powershell
git config memorybank.mode strict
```

---

## New Project Bootstrap (CLI + VS Code)
Run in repository root (once per repo):

1. Create/copy required files:
   - `Memory-bank/` templates
   - `AGENTS.md`
   - `scripts/*` guard + generation scripts
   - `.githooks/pre-commit`
   - `.github/workflows/memory-bank-guard.yml`
2. Install hook path:
   - Windows:
     - `powershell -ExecutionPolicy Bypass -File scripts/install_memory_bank_hooks.ps1`
   - macOS/Linux:
     - `bash scripts/install_memory_bank_hooks.sh`
   - Equivalent git command:
     - `git config core.hooksPath .githooks`
3. Verify:
   - `git config --get core.hooksPath` -> `.githooks`
4. Start coding session (required):
   - `.\pg.ps1 start -Yes`
5. Optional day-close:
   - `.\pg.ps1 end -Note "finished for today"`

Important:
- Git hooks are per-repository (`.git/config`), not global by default.
- VS Code uses the same git config; once installed, commits from VS Code are enforced too.

---

## Required `AGENTS.md` policy (minimum)
Use a root-level `AGENTS.md` with these mandatory points:

1. Start-of-session:
   - read `Memory-bank/daily/LATEST.md`
   - read latest daily file
   - read `project-spec.md`, `structure-and-db.md`
   - read latest entries in `agentsGlobal-memory.md`, decisions in `mastermind.md`
2. End-of-session when code changed:
   - update relevant Memory-bank docs
   - append `agentsGlobal-memory.md`
   - update `daily/YYYY-MM-DD.md` and `daily/LATEST.md`
3. If DB migration changed:
   - must update `Memory-bank/db-schema/*.md`
4. No secrets in Memory-bank.

---

## Local Guard Script Blueprint
Create `scripts/memory_bank_guard.py` that checks staged files.

Minimum checks:
0. Session state exists and is fresh (`Memory-bank/_generated/session-state.json`).
   - default: max 5 commits per session
   - default: max 12 hours per session
   - this check is blocking in both `warn` and `strict` modes
1. If code files changed outside `Memory-bank/`, require staged Memory-bank update.
2. If migration files changed, require staged `Memory-bank/db-schema/*.md`.
3. Require staged:
   - `Memory-bank/agentsGlobal-memory.md`
   - `Memory-bank/daily/LATEST.md`
   - `Memory-bank/daily/<today>.md`
4. If tooling/runtime/start commands changed, require staged `Memory-bank/tools-and-commands.md`.
5. Enforce screen/page max 500 lines (warn in warn mode, fail in strict mode).
6. Allow emergency bypass:
   - `SKIP_MEMORY_BANK_GUARD=1`

Pre-commit file:
- `.githooks/pre-commit`
```bash
#!/usr/bin/env bash
set -euo pipefail
python scripts/memory_bank_guard.py
```

Windows installer template (`scripts/install_memory_bank_hooks.ps1`):
```powershell
$repoRoot = Split-Path -Parent $PSScriptRoot
git -C $repoRoot config core.hooksPath .githooks
Write-Host "hooksPath=.githooks configured"
```

macOS/Linux installer template (`scripts/install_memory_bank_hooks.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$repo_root" config core.hooksPath .githooks
echo "hooksPath=.githooks configured"
```

---

## CI / PR Guard (warn vs strict)
Create `.github/workflows/memory-bank-guard.yml`.

Recommended dual mode:
- `warn`: comment/warn only, does not fail PR
- `strict`: fail workflow and block merge

Example policy flag:
- repo variable `MB_ENFORCEMENT_MODE=warn|strict`

Pseudo-logic:
1. Get changed files in PR.
2. Detect backend/frontend/mobile code change.
3. If code changed and Memory-bank not changed:
   - in `warn` -> emit warning, success exit
   - in `strict` -> fail job
4. If migration changed and db-schema doc not changed:
   - same warn/strict behavior

This satisfies: enforce by default, but avoid breaking serious PRs when you temporarily run warn mode.

Copy-paste starter workflow:
```yaml
name: Memory-bank Guard

on:
  pull_request:
    branches: [ main, master, develop ]

jobs:
  memory-bank-guard:
    runs-on: ubuntu-latest
    env:
      MB_ENFORCEMENT_MODE: ${{ vars.MB_ENFORCEMENT_MODE || 'warn' }} # warn|strict
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Collect changed files
        id: changes
        run: |
          git fetch origin "${{ github.base_ref }}" --depth=1
          git diff --name-only "origin/${{ github.base_ref }}...HEAD" > changed.txt
          echo "changed_count=$(wc -l < changed.txt)" >> "$GITHUB_OUTPUT"
          cat changed.txt

      - name: Evaluate policy
        run: |
          python - <<'PY'
          from pathlib import Path
          import os, sys

          changed = [x.strip() for x in Path("changed.txt").read_text().splitlines() if x.strip()]
          code_ext = {".java",".kt",".ts",".tsx",".js",".jsx",".sql",".yml",".yaml",".properties",".xml"}
          code_changed = any((Path(p).suffix.lower() in code_ext) and not p.startswith("Memory-bank/") for p in changed)
          migration_changed = any("/db/migration/" in p and p.endswith(".sql") for p in changed)

          mb_changed = any(p.startswith("Memory-bank/") for p in changed)
          db_doc_changed = any(p.startswith("Memory-bank/db-schema/") and p.endswith(".md") for p in changed)
          agents_log_changed = "Memory-bank/agentsGlobal-memory.md" in changed
          latest_changed = "Memory-bank/daily/LATEST.md" in changed

          missing = []
          if code_changed and not mb_changed:
            missing.append("code changed but Memory-bank not updated")
          if migration_changed and not db_doc_changed:
            missing.append("migration changed but db-schema docs not updated")
          if code_changed and not agents_log_changed:
            missing.append("agentsGlobal-memory.md not updated")
          if code_changed and not latest_changed:
            missing.append("daily/LATEST.md not updated")

          if not missing:
            print("PASS")
            sys.exit(0)

          mode = os.getenv("MB_ENFORCEMENT_MODE", "warn").lower()
          print("MEMORY-BANK POLICY ISSUES:")
          for m in missing:
            print("-", m)

          if mode == "strict":
            sys.exit(1)
          print("WARN MODE: workflow passes, but update Memory-bank before merge.")
          sys.exit(0)
          PY
```

---

## Generation Script Profiles

### A) Backend profile (primary)
Use:
- `scripts/build_backend_summary.py`
- `scripts/generate_memory_bank.py`

Expected output:
- `Memory-bank/_generated/backend-summary.json`
- `Memory-bank/db-schema/*.md`
- `Memory-bank/code-tree/*-tree.md`
- root Memory-bank files and daily updates

### B) Frontend profile
Create:
- `scripts/build_frontend_summary.py`
- `scripts/generate_memory_bank.py` (frontend mode)

Typical sections:
- route/page tree
- component ownership map
- state management map
- API client map
- build/test/lint command inventory

### C) Mobile profile
Create:
- `scripts/build_mobile_summary.py`
- `scripts/generate_memory_bank.py` (mobile mode)

Typical sections:
- screen/navigation tree
- native module usage
- permissions map
- API + offline storage map
- build flavor/signing checklist (without secrets)

Design rule:
- keep one generator entrypoint if possible (`generate_memory_bank.py`)
- use summary builders per domain (`build_backend_summary.py`, `build_frontend_summary.py`, `build_mobile_summary.py`)

---

## Daily Retention (auto-clean)
In generator:
1. Keep only last N daily files (default 7)
2. Delete older `daily/YYYY-MM-DD.md` files
3. Keep `daily/LATEST.md` always

Optional env override:
- `MEMORY_BANK_DAILY_KEEP_DAYS=14`

---

## End-to-End command contract (new repo)
1. `python scripts/build_<domain>_summary.py`
2. `python scripts/generate_memory_bank.py`
3. `powershell -ExecutionPolicy Bypass -File scripts/install_memory_bank_hooks.ps1` (or bash installer)
4. `.\pg.ps1 start -Yes`
5. Commit
6. `.\pg.ps1 end -Note "finished for today"` (recommended at shift end)
7. PR -> CI guard validates Memory-bank policy

---

## Global usage note
If you want this to apply to every new repository without re-explaining in chat:
1. Keep this universal folder as your source template.
2. At project start, copy this enforcement pack into repo root.
3. Ensure repo has root `AGENTS.md`.
4. Install hooks once per repo.
5. Enable CI guard workflow.

This gives persistent local memory behavior without needing a custom plugin.
