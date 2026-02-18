[CmdletBinding()]
param(
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

$repoRoot = $resolvedTarget.Path
$today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$nowUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm")
$buildScriptName = "build_$ProjectType`_summary.py"
$shouldInstallHooks = -not $SkipHookInstall.IsPresent
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$script:writeCount = 0
$script:overwriteCount = 0
$script:skipCount = 0

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Apply-Tokens {
    param([Parameter(Mandatory = $true)][string]$Text)
    $result = $Text.Replace("__TODAY__", $today)
    $result = $result.Replace("__NOW_UTC__", $nowUtc)
    $result = $result.Replace("__PROJECT_TYPE__", $ProjectType)
    $result = $result.Replace("__ENFORCEMENT_MODE__", $EnforcementMode)
    $result = $result.Replace("__DAILY_KEEP_DAYS__", [string]$DailyKeepDays)
    $result = $result.Replace("__BUILD_SCRIPT__", $buildScriptName)
    return $result
}

function Write-ManagedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$LfOnly
    )

    $exists = Test-Path -LiteralPath $Path
    if ($exists -and -not $Force) {
        $script:skipCount++
        Write-Host "[skip] $Path"
        return
    }

    $parent = Split-Path -Path $Path -Parent
    if ($parent) {
        Ensure-Directory -Path $parent
    }

    $text = $Content
    if ($LfOnly) {
        $text = ($text -replace "`r`n", "`n" -replace "`r", "`n")
    }

    [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)

    if ($exists) {
        $script:overwriteCount++
        Write-Host "[overwrite] $Path"
    } else {
        $script:writeCount++
        Write-Host "[write] $Path"
    }
}

$dirs = @(
    (Join-Path $repoRoot "Memory-bank"),
    (Join-Path $repoRoot "Memory-bank\daily"),
    (Join-Path $repoRoot "Memory-bank\db-schema"),
    (Join-Path $repoRoot "Memory-bank\code-tree"),
    (Join-Path $repoRoot "Memory-bank\_generated"),
    (Join-Path $repoRoot "scripts"),
    (Join-Path $repoRoot ".githooks"),
    (Join-Path $repoRoot ".github"),
    (Join-Path $repoRoot ".github\workflows")
)

foreach ($dir in $dirs) {
    Ensure-Directory -Path $dir
}

$agentsTemplate = @'
# AGENTS.md - Memory-bank Enforced Workflow

This repository requires `Memory-bank/` updates for every coding session.

## Mandatory Start Protocol
1. Read `Memory-bank/daily/LATEST.md`.
2. Read the latest daily report referenced there.
3. Read `Memory-bank/project-spec.md`.
4. Read `Memory-bank/project-details.md`.
5. Read `Memory-bank/structure-and-db.md`.
6. Read recent entries in `Memory-bank/agentsGlobal-memory.md`.
7. Read `Memory-bank/tools-and-commands.md` (runtime/tool/start commands).
8. Read `Memory-bank/coding-security-standards.md`.
9. Check `Memory-bank/mastermind.md` for open decisions.

## Mandatory End Protocol (before final summary to user)
If code changed:
1. Update relevant Memory-bank docs:
   - `Memory-bank/structure-and-db.md`
   - `Memory-bank/db-schema/*.md` when schema/migration changed
   - `Memory-bank/code-tree/*-tree.md` when structure changed
   - `Memory-bank/project-details.md` when scope/plan/features changed
   - `Memory-bank/tools-and-commands.md` when runtime/tool/start commands changed
2. Append one entry to `Memory-bank/agentsGlobal-memory.md`.
3. Update `Memory-bank/daily/__TODAY__.md`.
4. Update `Memory-bank/daily/LATEST.md`.
5. Run:
   - `python scripts/__BUILD_SCRIPT__`
   - `python scripts/generate_memory_bank.py --profile __PROJECT_TYPE__ --keep-days __DAILY_KEEP_DAYS__`

If these steps are not complete, the task is incomplete.

## Enforcement
- Local hook: `.githooks/pre-commit` runs `scripts/memory_bank_guard.py`.
- Mode is `warn` or `strict` (current default: `__ENFORCEMENT_MODE__`).
- CI guard: `.github/workflows/memory-bank-guard.yml`.
- Screen/Page file size guard:
  - max 500 lines for `screen/page` files (warn in warn mode, fail in strict mode).

## Commands
- Install hooks:
  - `powershell -ExecutionPolicy Bypass -File scripts/install_memory_bank_hooks.ps1 -Mode __ENFORCEMENT_MODE__`
- Optional bypass (emergency only):
  - `SKIP_MEMORY_BANK_GUARD=1`
'@

$copilotInstructionsTemplate = @'
# Copilot Repository Instructions

Follow `AGENTS.md` and treat `Memory-bank/` as mandatory project context.

Before proposing or changing code:
1. Read `Memory-bank/daily/LATEST.md` and latest daily file.
2. Read `Memory-bank/project-spec.md`.
3. Read `Memory-bank/structure-and-db.md`.
4. Read latest entries in `Memory-bank/agentsGlobal-memory.md`.
5. Check `Memory-bank/mastermind.md` for open decisions.

If code changes:
1. Update relevant Memory-bank docs.
2. Append `Memory-bank/agentsGlobal-memory.md`.
3. Update `Memory-bank/daily/YYYY-MM-DD.md` and `Memory-bank/daily/LATEST.md`.
4. If SQL migrations changed, update `Memory-bank/db-schema/*.md`.

Quality constraints:
- No secrets in code or Memory-bank docs.
- Keep files modular and maintainable.
- Screen/page files should stay <= 500 lines where feasible.
'@

$claudeInstructionsTemplate = @'
# Claude Repo Instructions

Primary policy file: `AGENTS.md`.

Mandatory start protocol:
1. `Memory-bank/daily/LATEST.md`
2. latest daily report
3. `Memory-bank/project-spec.md`
4. `Memory-bank/structure-and-db.md`
5. latest `Memory-bank/agentsGlobal-memory.md` entries
6. relevant decisions in `Memory-bank/mastermind.md`

Mandatory end protocol for code changes:
1. Update matching Memory-bank docs (`structure-and-db`, `db-schema`, `code-tree` as needed).
2. Append `Memory-bank/agentsGlobal-memory.md`.
3. Update `Memory-bank/daily/YYYY-MM-DD.md` and `Memory-bank/daily/LATEST.md`.
4. If migration changed, update `Memory-bank/db-schema/*.md`.

Enforcement:
- Local pre-commit hook runs `scripts/memory_bank_guard.py`.
- CI guard workflow validates Memory-bank updates on pull requests.
'@

$clineRulesTemplate = @'
Follow AGENTS.md in this repository.

Start-of-session (required):
- Read Memory-bank/daily/LATEST.md and latest daily file.
- Read Memory-bank/project-spec.md and Memory-bank/structure-and-db.md.
- Read latest Memory-bank/agentsGlobal-memory.md entries.
- Check Memory-bank/mastermind.md for open decisions.

End-of-session for code changes (required):
- Update relevant Memory-bank docs.
- Append Memory-bank/agentsGlobal-memory.md.
- Update Memory-bank/daily/YYYY-MM-DD.md and Memory-bank/daily/LATEST.md.
- If db migration changed, update Memory-bank/db-schema/*.md.

Never add secrets to code or Memory-bank docs.
'@

$geminiInstructionsTemplate = @'
# Gemini Repo Instructions

Use `AGENTS.md` as the primary policy contract for this repository.

Mandatory start-of-session:
1. Read `Memory-bank/daily/LATEST.md` and the latest daily report.
2. Read `Memory-bank/project-spec.md`.
3. Read `Memory-bank/structure-and-db.md`.
4. Read latest entries in `Memory-bank/agentsGlobal-memory.md`.
5. Check `Memory-bank/mastermind.md` for open decisions.

Mandatory end-of-session when code changed:
1. Update relevant Memory-bank docs (`structure-and-db`, `db-schema`, `code-tree`).
2. Append `Memory-bank/agentsGlobal-memory.md`.
3. Update `Memory-bank/daily/YYYY-MM-DD.md`.
4. Update `Memory-bank/daily/LATEST.md`.

Rules:
- Never add secrets to Memory-bank or code.
- If SQL migrations change, update `Memory-bank/db-schema/*.md` in the same session.
- Respect local hook and CI Memory-bank guards.
'@

$antigravityInstructionsTemplate = @'
# Antigravity Repo Instructions

Follow repository policy from `AGENTS.md`.

Before coding:
- Read Memory-bank context:
  - `Memory-bank/daily/LATEST.md` and latest daily report
  - `Memory-bank/project-spec.md`
  - `Memory-bank/structure-and-db.md`
  - latest `Memory-bank/agentsGlobal-memory.md` entries
  - relevant `Memory-bank/mastermind.md` decisions

After coding:
- Update matching Memory-bank docs.
- Append `Memory-bank/agentsGlobal-memory.md`.
- Update today's `Memory-bank/daily/YYYY-MM-DD.md`.
- Update `Memory-bank/daily/LATEST.md`.
- If migration files changed, update `Memory-bank/db-schema/*.md`.

Enforcement:
- local: `.githooks/pre-commit` -> `scripts/memory_bank_guard.py`
- PR: `.github/workflows/memory-bank-guard.yml`
'@

$mbReadmeTemplate = @'
# Memory-bank - Universal Standard

LAST_UPDATED_UTC: __NOW_UTC__
PROJECT_TYPE: __PROJECT_TYPE__

## Purpose
Memory-bank is the durable project memory for humans and AI agents.
It reduces context loss, improves handover quality, and keeps code/documentation in sync.

## Source-of-Truth Order
1. `project-spec.md`
2. `project-details.md`
3. `structure-and-db.md`
4. `db-schema/*.md`
5. `code-tree/*.md`
6. `tools-and-commands.md`
7. `coding-security-standards.md`
8. `agentsGlobal-memory.md`
9. `mastermind.md`
10. `daily/*.md` (derived convenience reports)

## Non-Negotiables
- No secrets in Memory-bank.
- If plan/scope/features change, update `project-details.md`.
- If code structure changes, update `structure-and-db.md` and relevant `code-tree/*.md`.
- If DB/migrations change, update `db-schema/*.md` and `structure-and-db.md`.
- If tools/runtime/start commands change, update `tools-and-commands.md`.
- Keep docs concise and current.
'@

$projectDetailsTemplate = @'
# Project Details - Scope, Plan, Feature Status

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: mb-init

## Purpose
Track execution-level project details that change over time:
- active plan
- planned features
- in-progress work
- completed milestones

This file is the operational bridge between product intent and implementation.

## Current Plan (Rolling)
| Plan Item | Status | Owner | Target Date | Notes |
|---|---|---|---|---|
| Initialize Memory-bank standards | Done | Platform | __TODAY__ | Bootstrapped |
| Fill project-specific plan | Planned | Team | <date> | |

## Feature Backlog Snapshot
| Feature | Priority | Status | Components | Decision Link |
|---|---|---|---|---|
| <feature-name> | High/Med/Low | Planned/In Progress/Done | <services/apps> | mastermind.md |

## Change Triggers (Mandatory Updates)
Update this file whenever:
- a new feature is approved
- a plan item status changes
- scope changes (in/out)
- milestone dates shift materially

## Next Planning Review
- Date:
- Owners:
- Open risks:
'@

$toolsTemplate = @'
# Tools & Commands

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: mb-init
PROJECT_TYPE: __PROJECT_TYPE__

## Purpose
Single source for local run commands, tool inventory, and environment versions.
Update this whenever runtime, dependencies, or service startup commands change.

## Runtime Versions
| Tool | Version | Where Used | Notes |
|---|---|---|---|
| Java | <e.g. 17/21> | backend | |
| Node.js | <e.g. 20> | frontend/tooling | |
| Python | <e.g. 3.11> | scripts | |
| Docker Desktop | <version> | local infra | |
| PostgreSQL | <version> | database | |

## Core Start Commands
### Project bootstrap
- Build summary:
  - `python scripts/__BUILD_SCRIPT__`
- Generate/update memory bank:
  - `python scripts/generate_memory_bank.py --profile __PROJECT_TYPE__ --keep-days __DAILY_KEEP_DAYS__`
- Install hooks:
  - `powershell -ExecutionPolicy Bypass -File scripts/install_memory_bank_hooks.ps1 -Mode __ENFORCEMENT_MODE__`

### Backend examples (edit for repo)
- Start core service:
  - `./gradlew.bat bootRun` or `mvn spring-boot:run`
- Redis via docker:
  - `docker run --name redis-local -p 6379:6379 -d redis:7`
- Kafka via docker compose:
  - `docker compose up -d kafka zookeeper`

### Frontend examples (edit for repo)
- Install:
  - `npm install`
- Run dev:
  - `npm run dev`

### Mobile examples (edit for repo)
- Android debug build:
  - `./gradlew.bat assembleDebug`
- React Native metro:
  - `npm start`

## Tooling Inventory
| Capability | Tool | Enabled (Y/N) | Config Path |
|---|---|---|---|
| Cache | Redis | N | |
| Event streaming | Kafka | N | |
| Circuit breaker | Resilience4j | N | |
| Containerization | Docker | Y | |
| API gateway | <tool> | N | |

## Update Rules
- If `pom.xml`, `build.gradle*`, `package.json`, `docker-compose*`, workflow/runtime configs change, update this file in the same session.
- Do not store secrets or private tokens in command examples.
'@

$standardsTemplate = @'
# Coding & Security Standards

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: mb-init

## Code Size Limits (Mandatory)
- Screen/Page files (mobile + web): max 500 lines.
- Preferred range for screen/page files: 100-450 lines.
- If a screen/page exceeds 500 lines:
  - split UI sections/components
  - move business logic to services/helpers/viewmodels
  - keep navigation shell thin

## Backend Engineering Baseline
- Prefer small services/controllers with clear single responsibility.
- Validate all external input.
- Use structured logging and predictable error mapping.
- Keep auth/authorization checks explicit and centralized.
- Do not hardcode credentials, secrets, keys, or private endpoints.

## Security Baseline
- Use strong key algorithms for signing/encryption (RSA/ECDSA as applicable).
- Keep private keys in env/vault/KMS only.
- Use least-privilege DB and service credentials.
- Ensure TLS for service-to-service and client transport.
- Keep dependency versions patched and reviewed.

## Maintainability Rules
- New code should be modular, testable, and easy to review.
- Prefer reuse over duplication.
- Reject giant files when refactoring is feasible.

## Team Decision Process (Mastermind)
- Record architectural debates in `mastermind.md`.
- Capture options, risks, and final ruling.
- If reviewers disagree, document votes and rationale; implement winning decision.
'@

$projectSpecTemplate = @'
# Project Spec - Intent, Actors, Flows

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: mb-init

## Purpose
Define WHAT the system should do and WHY.

## Scope
- In-scope:
- Out-of-scope:

## Actors
| Actor | Capabilities | Notes |
|---|---|---|
| User |  |  |
| Admin |  |  |
| System Agent |  |  |

## Core Flows
### Flow 1
1. ...
2. ...

### Flow 2
1. ...
2. ...

## Business Rules
- Rule:
- Rule:
'@

$structureTemplate = @'
# Structure & DB - Authoritative Snapshot

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: mb-init
PROJECT_TYPE: __PROJECT_TYPE__

## System Inventory
| Component | Type | Responsibility | Tech | Detail Doc |
|---|---|---|---|---|
| <component-name> | __PROJECT_TYPE__ |  |  | `Memory-bank/code-tree/<component-name>-tree.md` |

## High-Level Flow
- Client -> API/Service -> DB -> Integration

## Schemas / Data Stores (Index)
| Schema or Store | Owned By | Count | Detail Doc |
|---|---|---:|---|
| <schema-name> | <component-name> | 0 | `Memory-bank/db-schema/<schema-name>.md` |

## Notes
- Keep this file as a compact index.
- Full details belong in `db-schema/*.md` and `code-tree/*.md`.
'@

$agentsGlobalTemplate = @'
# Agents Global Memory - Change Log (Append-Only)

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: mb-init

## Rules
- Append-only.
- No secrets.
- Keep entries concise and anchored by file path + symbol/migration.

---

### [__NOW_UTC__ UTC] - mb-init
Scope:
- Components: bootstrap
- Files touched: Memory-bank starter pack

Summary:
- Initialized Memory-bank baseline and enforcement templates.

Anchors:
- `AGENTS.md`
- `scripts/memory_bank_guard.py`
- `.githooks/pre-commit`
- `.github/workflows/memory-bank-guard.yml`
'@

$mastermindTemplate = @'
# Mastermind - Decisions & Verification (Append-Only)

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: mb-init

## Decision Log

### Topic: Memory-bank Enforcement Bootstrapped
Date_UTC: __TODAY__
Owner: mb-init

Options:
1. Warn mode first, then strict.
2. Strict from day one.

Voting:
| Reviewer | Vote | Rationale |
|---|---|---|
| Reviewer A | Option 1 | Lower rollout friction |
| Reviewer B | Option 1 | Easier adoption |

Decision:
- Bootstrap with default mode `__ENFORCEMENT_MODE__` (Option 1).

Rationale:
- Start with warnings until process is stable, then move to strict mode.

Risks:
- Warning mode can allow drift if ignored.

Mitigation:
- Flip mode to strict after team baseline is stable.

Final Ruling:
- Option 1 approved by majority vote.
'@

$latestTemplate = @'
# Latest Daily Report Pointer

Latest: __TODAY__
File: Memory-bank/daily/__TODAY__.md
'@

$dailyTemplate = @'
# End-of-Day Report - __TODAY__

AUTHOR: mb-init
LAST_UPDATED_UTC: __NOW_UTC__

## Work Summary
- Initialized Memory-bank starter pack.

## Changes Index
### Component: bootstrap
- Paths:
  - Memory-bank/
  - scripts/
  - .githooks/
  - .github/workflows/

## Documentation Updated
- [x] project-spec.md
- [x] project-details.md
- [x] structure-and-db.md
- [x] tools-and-commands.md
- [x] coding-security-standards.md
- [x] agentsGlobal-memory.md
- [x] mastermind.md

## Next Session Start Here
1. Read `Memory-bank/daily/LATEST.md`.
2. Read `Memory-bank/project-spec.md`.
3. Read `Memory-bank/structure-and-db.md`.
4. Continue from latest `agentsGlobal-memory.md` entry.
'@

$dbTemplate = @'
# DB Schema - <schema-name>

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: <agent-or-human>

## Purpose
Full schema details for `<schema-name>`.

## Migration Source
- Path: `<repo-path>/db/migration`
- Latest migration: `V__...`

## Tables (Index)
| Table | Purpose | Primary Key | Notes |
|---|---|---|---|

## Tables (Columns)
### table: <table_name>
| column | type | constraints | description |
|---|---|---|---|
'@

$treeTemplate = @'
# Code Tree - <component-name>

LAST_UPDATED_UTC: __NOW_UTC__
UPDATED_BY: <agent-or-human>

## Root Path
- <repo-relative-path>

## Tree (Key Paths)
- src/
  - ...

## Key Files
| File | Purpose | Notes |
|---|---|---|
'@

$enforcementTemplate = @'
# Memory-bank Enforcement

LAST_UPDATED_UTC: __NOW_UTC__
DEFAULT_MODE: __ENFORCEMENT_MODE__
PROJECT_TYPE: __PROJECT_TYPE__

## Modes
- `warn`: show policy violations but do not block commits/CI.
- `strict`: fail guard checks and block until Memory-bank is updated.

## Current Local Setup
- Hook path: `.githooks`
- Guard script: `scripts/memory_bank_guard.py`
- Installer: `scripts/install_memory_bank_hooks.ps1`

## Switch Mode
- Local repo:
  - `git config memorybank.mode strict`
  - `git config memorybank.mode warn`
- CI:
  - Set repo variable `MB_ENFORCEMENT_MODE` to `warn` or `strict`.
'@

$guardTemplate = @'
from __future__ import annotations

import argparse
import datetime as dt
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEMORY_BANK = ROOT / "Memory-bank"
DEFAULT_MODE = "__ENFORCEMENT_MODE__"
DEFAULT_PROFILE = "__PROJECT_TYPE__"

COMMON_CODE_EXT = {
    ".java", ".kt", ".kts", ".xml", ".yml", ".yaml", ".properties", ".sql",
    ".js", ".jsx", ".ts", ".tsx", ".css", ".scss", ".sass", ".less", ".html",
    ".json", ".mdx", ".vue", ".svelte", ".dart", ".swift", ".m", ".mm",
    ".gradle", ".rb", ".go", ".py", ".sh", ".ps1",
}

CONFIG_FILE_NAMES = {
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "package.json",
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "docker-compose.yml",
    "docker-compose.yaml",
    "Dockerfile",
}

TOOLING_HINTS = (
    "docker-compose",
    "gradle",
    "mvnw",
    "pom.xml",
    "package.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    ".tool-versions",
    ".nvmrc",
    "application.yml",
    "application.yaml",
    "application.properties",
)

MAX_SCREEN_PAGE_LINES = 500


def run_git(args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def staged_files() -> list[str]:
    out = run_git(["diff", "--cached", "--name-only", "--diff-filter=ACMR"])
    if not out:
        return []
    return [line.strip().replace("\\", "/") for line in out.splitlines() if line.strip()]


def is_code_change(path: str) -> bool:
    if path.startswith("Memory-bank/") or path.startswith(".github/") or path.startswith(".githooks/"):
        return False
    p = Path(path)
    if p.name in CONFIG_FILE_NAMES:
        return True
    return p.suffix.lower() in COMMON_CODE_EXT


def is_migration_change(path: str) -> bool:
    lower = path.lower()
    return lower.endswith(".sql") and ("db/migration/" in lower or "migrations/" in lower)


def is_tooling_change(path: str) -> bool:
    lower = path.lower()
    name = Path(path).name.lower()
    if name in {x.lower() for x in CONFIG_FILE_NAMES}:
        return True
    return any(hint in lower for hint in TOOLING_HINTS)


def is_screen_or_page_file(path: str) -> bool:
    lower = path.lower()
    name = Path(path).name.lower()
    if "/screens/" in lower or "/screen/" in lower or "/pages/" in lower:
        return True
    if name in {"page.tsx", "page.jsx", "page.ts", "page.js", "page.kt", "page.swift"}:
        return True
    if name.endswith("screen.kt") or name.endswith("screen.tsx") or name.endswith("screen.jsx"):
        return True
    return False


def line_count(path: Path) -> int:
    try:
        return len(path.read_text(encoding="utf-8", errors="ignore").splitlines())
    except OSError:
        return 0


def parse_mode(cli_mode: str | None) -> str:
    if cli_mode:
        return cli_mode
    env_mode = os.getenv("MB_ENFORCEMENT_MODE", "").strip().lower()
    if env_mode in {"warn", "strict"}:
        return env_mode
    git_mode = run_git(["config", "--get", "memorybank.mode"]).strip().lower()
    if git_mode in {"warn", "strict"}:
        return git_mode
    return DEFAULT_MODE


def today_utc() -> str:
    return dt.datetime.now(dt.UTC).strftime("%Y-%m-%d")


def main() -> int:
    parser = argparse.ArgumentParser(description="Memory-bank pre-commit guard")
    parser.add_argument("--mode", choices=("warn", "strict"), default=None)
    args = parser.parse_args()

    mode = parse_mode(args.mode)
    if os.getenv("SKIP_MEMORY_BANK_GUARD") == "1":
        print("[memory-bank-guard] bypassed via SKIP_MEMORY_BANK_GUARD=1")
        return 0

    if not MEMORY_BANK.exists():
        message = "[memory-bank-guard] Memory-bank folder is missing."
        if mode == "strict":
            print(message)
            return 1
        print(f"{message} WARN mode allows commit.")
        return 0

    staged = staged_files()
    if not staged:
        return 0

    code_changes = [p for p in staged if is_code_change(p)]
    if not code_changes:
        return 0

    migration_changes = [p for p in staged if is_migration_change(p)]
    tooling_changes = [p for p in staged if is_tooling_change(p)]
    errors: list[str] = []
    warnings: list[str] = []

    if not any(p.startswith("Memory-bank/") for p in staged):
        errors.append("Code changed but no Memory-bank file is staged.")

    if migration_changes and not any(
        p.startswith("Memory-bank/db-schema/") and p.endswith(".md") for p in staged
    ):
        errors.append("Migration changed but no db-schema markdown file is staged.")

    if "Memory-bank/agentsGlobal-memory.md" not in staged:
        errors.append("Missing staged update: Memory-bank/agentsGlobal-memory.md")

    today = today_utc()
    if f"Memory-bank/daily/{today}.md" not in staged:
        errors.append(f"Missing staged update: Memory-bank/daily/{today}.md")
    if "Memory-bank/daily/LATEST.md" not in staged:
        errors.append("Missing staged update: Memory-bank/daily/LATEST.md")

    if "Memory-bank/project-details.md" not in staged:
        errors.append(
            "Missing staged update: Memory-bank/project-details.md "
            "(track plan/feature status or note 'no plan changes')."
        )

    if tooling_changes and "Memory-bank/tools-and-commands.md" not in staged:
        errors.append("Tooling/runtime/start-command changes detected but Memory-bank/tools-and-commands.md is not staged.")

    oversized_screen_files: list[tuple[str, int]] = []
    for path in code_changes:
        if not is_screen_or_page_file(path):
            continue
        abs_path = ROOT / path
        lines = line_count(abs_path)
        if lines > MAX_SCREEN_PAGE_LINES:
            oversized_screen_files.append((path, lines))

    for path, lines in oversized_screen_files:
        warnings.append(
            f"Screen/Page file exceeds {MAX_SCREEN_PAGE_LINES} lines: {path} ({lines} lines). Refactor to <= {MAX_SCREEN_PAGE_LINES}."
        )

    if mode == "strict" and warnings:
        errors.extend(warnings)

    if not errors and not warnings:
        print(f"[memory-bank-guard] PASS ({mode})")
        return 0

    print(f"[memory-bank-guard] POLICY ISSUES ({mode})")
    for idx, err in enumerate(errors, start=1):
        print(f"{idx}. {err}")
    if warnings and mode != "strict":
        print("\nWarnings:")
        for idx, warning in enumerate(warnings, start=1):
            print(f"{idx}. {warning}")

    print("\nQuick fix:")
    print("1) python scripts/__BUILD_SCRIPT__")
    print("2) python scripts/generate_memory_bank.py --profile __PROJECT_TYPE__ --keep-days __DAILY_KEEP_DAYS__")
    print("3) stage Memory-bank updates and commit again")

    if mode == "strict":
        return 1

    print("WARN mode active: commit is allowed, but update Memory-bank immediately.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
'@

$hookInstallPsTemplate = @'
param(
    [ValidateSet("warn", "strict")]
    [string]$Mode = "__ENFORCEMENT_MODE__",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$hooksDir = Join-Path $repoRoot ".githooks"
$preCommitPath = Join-Path $hooksDir "pre-commit"

if (-not (Test-Path -LiteralPath $preCommitPath)) {
    if (-not $Force) {
        throw "Missing hook file: $preCommitPath. Re-run with -Force to create it."
    }

    New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    $hookContent = @"
#!/usr/bin/env bash
set -euo pipefail

python scripts/memory_bank_guard.py
"@
    [System.IO.File]::WriteAllText($preCommitPath, ($hookContent -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
}

& git -C $repoRoot config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set core.hooksPath to .githooks"
}

& git -C $repoRoot config memorybank.mode $Mode
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set memorybank.mode to $Mode"
}

Write-Host "Configured core.hooksPath=.githooks"
Write-Host "Configured memorybank.mode=$Mode"
'@

$hookInstallShTemplate = @'
#!/usr/bin/env bash
set -euo pipefail

mode="${1:-__ENFORCEMENT_MODE__}"
if [[ "$mode" != "warn" && "$mode" != "strict" ]]; then
  echo "Invalid mode: $mode (allowed: warn|strict)"
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$repo_root" config core.hooksPath .githooks
git -C "$repo_root" config memorybank.mode "$mode"

echo "Configured core.hooksPath=.githooks"
echo "Configured memorybank.mode=$mode"
'@

$preCommitTemplate = @'
#!/usr/bin/env bash
set -euo pipefail

python scripts/memory_bank_guard.py
'@

$generateTemplate = @'
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEMORY_BANK = ROOT / "Memory-bank"
DAILY_DIR = MEMORY_BANK / "daily"
GENERATED_DIR = MEMORY_BANK / "_generated"
DEFAULT_PROFILE = "__PROJECT_TYPE__"
DEFAULT_KEEP_DAYS = __DAILY_KEEP_DAYS__


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def ensure_file(path: Path, content: str) -> None:
    ensure_dir(path.parent)
    if not path.exists():
        path.write_text(content, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate/update Memory-bank daily pointers")
    parser.add_argument("--profile", default=DEFAULT_PROFILE, choices=("backend", "frontend", "mobile"))
    parser.add_argument(
        "--keep-days",
        type=int,
        default=int(os.getenv("MEMORY_BANK_DAILY_KEEP_DAYS", str(DEFAULT_KEEP_DAYS))),
        help="How many daily reports to keep",
    )
    parser.add_argument("--author", default=os.getenv("MEMORY_BANK_AUTHOR", "agent"))
    return parser.parse_args()


def daily_report_content(day: str, now_utc: str, author: str) -> str:
    return (
        f"# End-of-Day Report - {day}\n\n"
        f"AUTHOR: {author}\n"
        f"LAST_UPDATED_UTC: {now_utc}\n\n"
        "## Work Summary\n"
        "- Session summary goes here.\n\n"
        "## Changes Index\n"
        "- Paths: \n"
        "- Symbols/anchors: \n\n"
        "## Documentation Updated\n"
        "- [ ] structure-and-db.md\n"
        "- [ ] db-schema/*.md\n"
        "- [ ] code-tree/*.md\n"
        "- [ ] agentsGlobal-memory.md\n"
        "- [ ] daily/LATEST.md\n"
    )


def latest_pointer_content(day: str) -> str:
    return (
        "# Latest Daily Report Pointer\n\n"
        f"Latest: {day}\n"
        f"File: Memory-bank/daily/{day}.md\n"
    )


def cleanup_daily_files(keep_days: int) -> list[str]:
    keep_days = max(1, keep_days)
    dated_files: list[tuple[dt.date, Path]] = []
    for path in DAILY_DIR.glob("*.md"):
        if path.name == "LATEST.md":
            continue
        try:
            dated_files.append((dt.date.fromisoformat(path.stem), path))
        except ValueError:
            continue

    dated_files.sort(key=lambda x: x[0], reverse=True)
    removed: list[str] = []
    for _, path in dated_files[keep_days:]:
        removed.append(path.name)
        path.unlink(missing_ok=True)
    return removed


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(dt.timezone.utc)
    day = now.strftime("%Y-%m-%d")
    now_utc = now.strftime("%Y-%m-%d %H:%M")

    ensure_dir(MEMORY_BANK)
    ensure_dir(DAILY_DIR)
    ensure_dir(MEMORY_BANK / "db-schema")
    ensure_dir(MEMORY_BANK / "code-tree")
    ensure_dir(GENERATED_DIR)

    daily_file = DAILY_DIR / f"{day}.md"
    ensure_file(daily_file, daily_report_content(day, now_utc, args.author))

    latest_file = DAILY_DIR / "LATEST.md"
    latest_file.write_text(latest_pointer_content(day), encoding="utf-8")

    removed = cleanup_daily_files(args.keep_days)

    generated_state = {
        "generated_at_utc": now_utc,
        "profile": args.profile,
        "keep_days": args.keep_days,
        "daily_file": f"Memory-bank/daily/{day}.md",
        "removed_daily_files": removed,
    }
    (GENERATED_DIR / "memory-bank-state.json").write_text(
        json.dumps(generated_state, indent=2),
        encoding="utf-8",
    )

    print("Memory-bank generation complete.")
    print(f"- profile: {args.profile}")
    print(f"- latest: Memory-bank/daily/{day}.md")
    if removed:
        print(f"- removed old daily files: {', '.join(removed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$buildSummaryTemplate = @'
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = "__PROJECT_TYPE__"
OUTPUT = ROOT / "Memory-bank" / "_generated" / f"{PROFILE}-summary.json"

IGNORE_DIRS = {
    ".git",
    ".idea",
    ".vscode",
    "node_modules",
    "target",
    "build",
    "dist",
    "coverage",
    ".gradle",
    ".next",
    ".venv",
    "venv",
}

MARKER_FILES = {
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "package.json",
    "pubspec.yaml",
}


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def top_level_entries() -> list[str]:
    items = []
    for entry in ROOT.iterdir():
        if entry.name in IGNORE_DIRS:
            continue
        items.append(entry.name)
    return sorted(items)


def component_roots() -> list[str]:
    components = set()
    for marker in MARKER_FILES:
        for file in ROOT.rglob(marker):
            if any(part in IGNORE_DIRS for part in file.parts):
                continue
            components.add(relative(file.parent))
    return sorted(components)


def migration_files(limit: int = 250) -> list[str]:
    files = []
    for path in ROOT.rglob("*.sql"):
        rel = relative(path).lower()
        if "migration" not in rel:
            continue
        files.append(rel)
        if len(files) >= limit:
            break
    return sorted(files)


def main() -> int:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "profile": PROFILE,
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M"),
        "repo_root": str(ROOT),
        "top_level_entries": top_level_entries(),
        "component_roots": component_roots(),
        "migration_files": migration_files(),
    }
    OUTPUT.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(f"Summary written: {relative(OUTPUT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$workflowTemplate = @'
name: Memory-bank Guard

on:
  pull_request:
    branches: [ main, master, develop ]

jobs:
  memory-bank-guard:
    runs-on: ubuntu-latest
    env:
      MB_ENFORCEMENT_MODE: ${{ vars.MB_ENFORCEMENT_MODE || '__ENFORCEMENT_MODE__' }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Collect changed files
        run: |
          git fetch origin "${{ github.base_ref }}" --depth=1
          git diff --name-only "origin/${{ github.base_ref }}...HEAD" > changed.txt
          cat changed.txt

      - name: Evaluate Memory-bank policy
        run: |
          python - <<'PY'
          from pathlib import Path
          import os
          import sys

          changed = [x.strip() for x in Path("changed.txt").read_text().splitlines() if x.strip()]
          code_ext = {
              ".java",".kt",".kts",".xml",".yml",".yaml",".properties",".sql",
              ".js",".jsx",".ts",".tsx",".css",".scss",".sass",".less",".html",
              ".dart",".swift",".m",".mm",".py",".go",".rb",".ps1",".sh"
          }
          config_names = {
              "pom.xml","build.gradle","build.gradle.kts","settings.gradle",
              "package.json","docker-compose.yml","docker-compose.yaml","Dockerfile"
          }

          def is_code(path: str) -> bool:
            if path.startswith("Memory-bank/") or path.startswith(".github/") or path.startswith(".githooks/"):
              return False
            p = Path(path)
            if p.name in config_names:
              return True
            return p.suffix.lower() in code_ext

          code_changed = any(is_code(p) for p in changed)
          migration_changed = any(("db/migration/" in p.lower() or "migrations/" in p.lower()) and p.lower().endswith(".sql") for p in changed)
          tooling_changed = any(
            any(h in p.lower() for h in (
              "docker-compose", "gradle", "mvnw", "pom.xml", "package.json",
              "pnpm-lock.yaml", "yarn.lock", ".tool-versions", ".nvmrc",
              "application.yml", "application.yaml", "application.properties"
            ))
            for p in changed
          )
          mb_changed = any(p.startswith("Memory-bank/") for p in changed)
          db_doc_changed = any(p.startswith("Memory-bank/db-schema/") and p.endswith(".md") for p in changed)
          tools_doc_changed = "Memory-bank/tools-and-commands.md" in changed
          project_details_changed = "Memory-bank/project-details.md" in changed
          agents_log_changed = "Memory-bank/agentsGlobal-memory.md" in changed
          latest_changed = "Memory-bank/daily/LATEST.md" in changed

          def is_screen_or_page(path: str) -> bool:
            lower = path.lower()
            name = Path(path).name.lower()
            if "/screens/" in lower or "/screen/" in lower or "/pages/" in lower:
              return True
            if name in {"page.tsx","page.jsx","page.ts","page.js","page.kt","page.swift"}:
              return True
            if name.endswith("screen.kt") or name.endswith("screen.tsx") or name.endswith("screen.jsx"):
              return True
            return False

          oversized = []
          for path in changed:
            if not is_screen_or_page(path):
              continue
            file_path = Path(path)
            if not file_path.exists():
              continue
            try:
              lines = len(file_path.read_text(encoding="utf-8", errors="ignore").splitlines())
            except OSError:
              continue
            if lines > 500:
              oversized.append((path, lines))

          missing = []
          if code_changed and not mb_changed:
            missing.append("code changed but Memory-bank/* was not updated")
          if migration_changed and not db_doc_changed:
            missing.append("migration changed but Memory-bank/db-schema/*.md was not updated")
          if tooling_changed and not tools_doc_changed:
            missing.append("tooling/runtime/start commands changed but Memory-bank/tools-and-commands.md was not updated")
          if code_changed and not project_details_changed:
            missing.append("project-details.md not updated (required for active plan/feature tracking)")
          if code_changed and not agents_log_changed:
            missing.append("agentsGlobal-memory.md was not updated")
          if code_changed and not latest_changed:
            missing.append("daily/LATEST.md was not updated")
          if oversized:
            details = ", ".join([f"{p}={n}" for p, n in oversized])
            missing.append(f"screen/page file exceeds 500 lines ({details})")

          if not missing:
            print("PASS")
            sys.exit(0)

          print("MEMORY-BANK POLICY ISSUES:")
          for item in missing:
            print("-", item)

          mode = os.getenv("MB_ENFORCEMENT_MODE", "__ENFORCEMENT_MODE__").lower()
          if mode == "strict":
            sys.exit(1)
          print("WARN mode active: workflow passes, update Memory-bank before merge.")
          sys.exit(0)
          PY
'@

$files = @(
    @{ Path = "AGENTS.md"; Content = $agentsTemplate; LfOnly = $false },
    @{ Path = ".github/copilot-instructions.md"; Content = $copilotInstructionsTemplate; LfOnly = $false },
    @{ Path = "CLAUDE.md"; Content = $claudeInstructionsTemplate; LfOnly = $false },
    @{ Path = ".clinerules"; Content = $clineRulesTemplate; LfOnly = $false },
    @{ Path = "GEMINI.md"; Content = $geminiInstructionsTemplate; LfOnly = $false },
    @{ Path = "ANTIGRAVITY.md"; Content = $antigravityInstructionsTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\README.md"; Content = $mbReadmeTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\project-spec.md"; Content = $projectSpecTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\project-details.md"; Content = $projectDetailsTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\structure-and-db.md"; Content = $structureTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\tools-and-commands.md"; Content = $toolsTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\coding-security-standards.md"; Content = $standardsTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\agentsGlobal-memory.md"; Content = $agentsGlobalTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\mastermind.md"; Content = $mastermindTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\ENFORCEMENT.md"; Content = $enforcementTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\daily\LATEST.md"; Content = $latestTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\daily\$today.md"; Content = $dailyTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\db-schema\_TEMPLATE-schema.md"; Content = $dbTemplate; LfOnly = $false },
    @{ Path = "Memory-bank\code-tree\_TEMPLATE-service-tree.md"; Content = $treeTemplate; LfOnly = $false },
    @{ Path = "scripts\memory_bank_guard.py"; Content = $guardTemplate; LfOnly = $true },
    @{ Path = "scripts\install_memory_bank_hooks.ps1"; Content = $hookInstallPsTemplate; LfOnly = $false },
    @{ Path = "scripts\install_memory_bank_hooks.sh"; Content = $hookInstallShTemplate; LfOnly = $true },
    @{ Path = ".githooks\pre-commit"; Content = $preCommitTemplate; LfOnly = $true },
    @{ Path = "scripts\generate_memory_bank.py"; Content = $generateTemplate; LfOnly = $true },
    @{ Path = ("scripts\" + $buildScriptName); Content = $buildSummaryTemplate; LfOnly = $true },
    @{ Path = ".github\workflows\memory-bank-guard.yml"; Content = $workflowTemplate; LfOnly = $true }
)

foreach ($item in $files) {
    $relativePath = [string]$item.Path
    $destination = Join-Path $repoRoot $relativePath
    $template = [string]$item.Content
    $content = Apply-Tokens -Text $template
    $lfOnly = [bool]$item.LfOnly
    Write-ManagedFile -Path $destination -Content $content -LfOnly:$lfOnly
}

$isGitRepo = Test-Path -LiteralPath (Join-Path $repoRoot ".git")
if ($shouldInstallHooks -and $isGitRepo) {
    $installer = Join-Path $repoRoot "scripts\install_memory_bank_hooks.ps1"
    if ($Force.IsPresent) {
        & powershell -ExecutionPolicy Bypass -File $installer -Mode $EnforcementMode -Force
    } else {
        & powershell -ExecutionPolicy Bypass -File $installer -Mode $EnforcementMode
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Hook installation failed with exit code $LASTEXITCODE."
    }
} elseif ($shouldInstallHooks -and -not $isGitRepo) {
    Write-Warning "Target is not a git repository (.git missing); skipped hook installation."
}

Write-Host ""
Write-Host "Memory-bank bootstrap complete."
Write-Host "Target: $repoRoot"
Write-Host "Project type: $ProjectType"
Write-Host "Mode: $EnforcementMode"
Write-Host "Daily keep days: $DailyKeepDays"
Write-Host "Files written: $script:writeCount"
Write-Host "Files overwritten: $script:overwriteCount"
Write-Host "Files skipped: $script:skipCount"
Write-Host ""
Write-Host "Next commands:"
Write-Host "1) python scripts/$buildScriptName"
Write-Host "2) python scripts/generate_memory_bank.py --profile $ProjectType --keep-days $DailyKeepDays"
Write-Host "3) git add . && git commit -m ""chore: initialize memory-bank enforcement"""
