[CmdletBinding()]
param(
    [string]$TargetRepoPath = ".",
    [ValidateSet("backend", "frontend", "mobile")]
    [string]$ProjectType = "backend",
    [ValidateSet("warn", "strict")]
    [string]$EnforcementMode = "warn",
    [ValidateRange(1, 365)]
    [int]$DailyKeepDays = 7,
    [ValidateRange(1, 100)]
    [int]$SessionMaxCommits = 5,
    [ValidateRange(1, 168)]
    [int]$SessionMaxHours = 12,
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
    $result = $result.Replace("__SESSION_MAX_COMMITS__", [string]$SessionMaxCommits)
    $result = $result.Replace("__SESSION_MAX_HOURS__", [string]$SessionMaxHours)
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
0. Run `.\pg.ps1 start -Yes` (or `powershell -ExecutionPolicy Bypass -File scripts/start_memory_bank_session.ps1`).
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
- Start session (required before coding):
  - `.\pg.ps1 start -Yes`
  - `powershell -ExecutionPolicy Bypass -File scripts/start_memory_bank_session.ps1`
- End session:
  - `.\pg.ps1 end -Note "finished for today"`
- Session status:
  - `.\pg.ps1 status`
- Install hooks:
  - `powershell -ExecutionPolicy Bypass -File scripts/install_memory_bank_hooks.ps1 -Mode __ENFORCEMENT_MODE__`
- Optional bypass (emergency only):
  - `SKIP_MEMORY_BANK_GUARD=1`
'@

$copilotInstructionsTemplate = @'
# Copilot Repository Instructions

Follow `AGENTS.md` and treat `Memory-bank/` as mandatory project context.

Before proposing or changing code:
0. Run `.\pg.ps1 start -Yes`.
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
0. `.\pg.ps1 start -Yes`
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
- Run `.\pg.ps1 start -Yes`.
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
0. Run `.\pg.ps1 start -Yes`.
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
- Run `.\pg.ps1 start -Yes`.
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
- Simple command (recommended):
  - `.\pg.ps1 start -Yes`
- End shift/session:
  - `.\pg.ps1 end -Note "finished for today"`
- Session status:
  - `.\pg.ps1 status`
- Start session (required before coding):
  - `powershell -ExecutionPolicy Bypass -File scripts/start_memory_bank_session.ps1`
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
- Session script: `scripts/start_memory_bank_session.ps1`
- Simple CLI wrapper: `pg.ps1` / `pg.cmd`
- Session limits: max `__SESSION_MAX_COMMITS__` commits, max `__SESSION_MAX_HOURS__` hours per session

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
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEMORY_BANK = ROOT / "Memory-bank"
DEFAULT_MODE = "__ENFORCEMENT_MODE__"
DEFAULT_PROFILE = "__PROJECT_TYPE__"
SESSION_STATE = MEMORY_BANK / "_generated" / "session-state.json"
DEFAULT_MAX_SESSION_COMMITS = __SESSION_MAX_COMMITS__
DEFAULT_MAX_SESSION_HOURS = __SESSION_MAX_HOURS__

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
    prefix = run_git(["rev-parse", "--show-prefix"]).strip().replace("\\", "/")
    if prefix and not prefix.endswith("/"):
        prefix += "/"
    staged: list[str] = []
    for raw in out.splitlines():
        path = raw.strip().replace("\\", "/")
        if not path:
            continue
        if prefix:
            if not path.startswith(prefix):
                continue
            path = path[len(prefix):]
        if path.startswith("../") or not path:
            continue
        staged.append(path)
    return staged


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


def parse_iso_utc(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    normalized = value.strip().replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.UTC)
    return parsed.astimezone(dt.UTC)


def load_session_state() -> dict:
    if not SESSION_STATE.exists():
        return {}
    try:
        return json.loads(SESSION_STATE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def parse_positive_int(value: object, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    if parsed < 1:
        return default
    return parsed


def commits_since_anchor(anchor: str) -> int | None:
    if not anchor:
        return 0
    head = run_git(["rev-parse", "HEAD"]).strip()
    if not head:
        return 0
    if head == anchor:
        return 0
    if not run_git(["rev-parse", "--verify", anchor]).strip():
        return None
    out = run_git(["rev-list", "--count", f"{anchor}..HEAD"]).strip()
    if not out:
        return None
    try:
        return int(out)
    except ValueError:
        return None


def validate_session() -> list[str]:
    errors: list[str] = []
    state = load_session_state()
    command = ".\\pg.ps1 start -Yes"

    if not state:
        errors.append(
            "Session is not started. Run start session command before coding:\n"
            f"- {command}"
        )
        return errors

    started_at = parse_iso_utc(str(state.get("started_at_utc", "")).strip())
    if started_at is None:
        errors.append(
            "Session state is invalid (missing/invalid started_at_utc). Re-run:\n"
            f"- {command}"
        )
        return errors

    max_hours = parse_positive_int(state.get("max_hours"), DEFAULT_MAX_SESSION_HOURS)
    age_hours = (dt.datetime.now(dt.UTC) - started_at).total_seconds() / 3600.0
    if age_hours > max_hours:
        errors.append(
            f"Session is stale ({age_hours:.1f}h old, limit {max_hours}h). Re-run:\n"
            f"- {command}"
        )

    anchor = str(state.get("anchor_commit", "")).strip()
    max_commits = parse_positive_int(state.get("max_commits"), DEFAULT_MAX_SESSION_COMMITS)
    commits_used = commits_since_anchor(anchor)
    if commits_used is None:
        errors.append(
            "Session anchor commit is invalid (history changed). Re-run:\n"
            f"- {command}"
        )
    elif commits_used >= max_commits:
        errors.append(
            f"Session commit budget reached ({commits_used}/{max_commits}). Re-run:\n"
            f"- {command}"
        )

    return errors


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
    session_errors = validate_session()
    errors.extend(session_errors)

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
    print("0) .\\pg.ps1 start -Yes")
    print("1) python scripts/__BUILD_SCRIPT__")
    print("2) python scripts/generate_memory_bank.py --profile __PROJECT_TYPE__ --keep-days __DAILY_KEEP_DAYS__")
    print("3) stage Memory-bank updates and commit again")

    if session_errors:
        print("Session policy is blocking in all modes. Start a fresh session first.")
        return 1

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

$projectRoot = Split-Path -Parent $PSScriptRoot
$hooksDir = Join-Path $projectRoot ".githooks"
$preCommitPath = Join-Path $hooksDir "pre-commit"
$guardScriptPath = Join-Path $projectRoot "scripts/memory_bank_guard.py"

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString())
}

$gitTopLevel = & git -C $projectRoot rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitTopLevel)) {
    throw "Could not resolve git top-level from: $projectRoot"
}
$gitTopLevel = $gitTopLevel.Trim()

$hooksPathRelative = (Get-RelativePath -BasePath $gitTopLevel -TargetPath $hooksDir).Replace("\", "/")
$guardPathRelative = (Get-RelativePath -BasePath $gitTopLevel -TargetPath $guardScriptPath).Replace("\", "/")
if ([string]::IsNullOrWhiteSpace($hooksPathRelative) -or $hooksPathRelative -eq ".") {
    $hooksPathRelative = ".githooks"
}

New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null

$hookTemplate = @"
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
python "$repo_root/__GUARD_PATH__"
"@
$hookContent = $hookTemplate.Replace("__GUARD_PATH__", $guardPathRelative)

if (-not (Test-Path -LiteralPath $preCommitPath) -or $Force) {
    [System.IO.File]::WriteAllText($preCommitPath, ($hookContent -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote pre-commit hook: $preCommitPath"
} else {
    $existing = [System.IO.File]::ReadAllText($preCommitPath, [System.Text.Encoding]::UTF8)
    if (($existing -replace "`r`n", "`n") -ne ($hookContent -replace "`r`n", "`n")) {
        [System.IO.File]::WriteAllText($preCommitPath, ($hookContent -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
        Write-Host "Updated pre-commit hook: $preCommitPath"
    } else {
        Write-Host "Pre-commit hook already up to date: $preCommitPath"
    }
}

& git -C $gitTopLevel config core.hooksPath $hooksPathRelative
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set core.hooksPath to $hooksPathRelative"
}

& git -C $gitTopLevel config memorybank.mode $Mode
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set memorybank.mode to $Mode"
}

Write-Host "Configured core.hooksPath=$hooksPathRelative"
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

project_root="$(cd "$(dirname "$0")/.." && pwd)"
git_root="$(git -C "$project_root" rev-parse --show-toplevel)"
hooks_dir="$project_root/.githooks"
guard_script="$project_root/scripts/memory_bank_guard.py"

mkdir -p "$hooks_dir"

if command -v python3 >/dev/null 2>&1; then
  pybin="python3"
else
  pybin="python"
fi

guard_rel="$(python - <<PY
import os
print(os.path.relpath(r"$guard_script", r"$git_root").replace("\\\\", "/"))
PY
)"

hooks_rel="$(python - <<PY
import os
print(os.path.relpath(r"$hooks_dir", r"$git_root").replace("\\\\", "/"))
PY
)"

cat > "$hooks_dir/pre-commit" <<EOF
#!/usr/bin/env bash
set -euo pipefail

repo_root="\$(git rev-parse --show-toplevel)"
$pybin "\$repo_root/$guard_rel"
EOF

chmod +x "$hooks_dir/pre-commit"

git -C "$git_root" config core.hooksPath "$hooks_rel"
git -C "$git_root" config memorybank.mode "$mode"

echo "Configured core.hooksPath=$hooks_rel"
echo "Configured memorybank.mode=$mode"
'@

$preCommitTemplate = @'
#!/usr/bin/env bash
set -euo pipefail

hook_dir="$(cd "$(dirname "$0")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  pybin="python3"
else
  pybin="python"
fi

"$pybin" "$hook_dir/../scripts/memory_bank_guard.py"
'@

$startSessionPyTemplate = @'
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEMORY_BANK = ROOT / "Memory-bank"
DAILY_DIR = MEMORY_BANK / "daily"
GENERATED_DIR = MEMORY_BANK / "_generated"
DEFAULT_PROFILE = "__PROJECT_TYPE__"
DEFAULT_KEEP_DAYS = __DAILY_KEEP_DAYS__
DEFAULT_MAX_COMMITS = __SESSION_MAX_COMMITS__
DEFAULT_MAX_HOURS = __SESSION_MAX_HOURS__

START_DOCS = [
    "Memory-bank/daily/LATEST.md",
    "Memory-bank/project-spec.md",
    "Memory-bank/project-details.md",
    "Memory-bank/structure-and-db.md",
    "Memory-bank/tools-and-commands.md",
    "Memory-bank/agentsGlobal-memory.md",
    "Memory-bank/mastermind.md",
]


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Start Memory-bank session")
    parser.add_argument("--profile", default=DEFAULT_PROFILE, choices=("backend", "frontend", "mobile"))
    parser.add_argument("--max-commits", type=int, default=DEFAULT_MAX_COMMITS)
    parser.add_argument("--max-hours", type=int, default=DEFAULT_MAX_HOURS)
    parser.add_argument("--author", default="agent")
    parser.add_argument("--ack-read", action="store_true", help="Non-interactive read acknowledgment")
    return parser.parse_args()


def ensure_daily(day: str, now_utc: str) -> None:
    DAILY_DIR.mkdir(parents=True, exist_ok=True)
    today_file = DAILY_DIR / f"{day}.md"
    if not today_file.exists():
        today_file.write_text(
            (
                f"# End-of-Day Report - {day}\n\n"
                f"AUTHOR: session-start\n"
                f"LAST_UPDATED_UTC: {now_utc}\n\n"
                "## Work Summary\n"
                "- Session initialized.\n\n"
                "## Documentation Updated\n"
                "- [ ] agentsGlobal-memory.md\n"
                "- [ ] daily/LATEST.md\n"
            ),
            encoding="utf-8",
        )
    latest_file = DAILY_DIR / "LATEST.md"
    latest_file.write_text(
        (
            "# Latest Daily Report Pointer\n\n"
            f"Latest: {day}\n"
            f"File: Memory-bank/daily/{day}.md\n"
        ),
        encoding="utf-8",
    )


def confirm_read(assume_yes: bool) -> bool:
    print("Read these before coding:")
    for doc in START_DOCS:
        print(f"- {doc}")
    if assume_yes:
        return True
    try:
        answer = input("Type 'yes' to confirm you will read/start from these docs: ").strip().lower()
    except EOFError:
        return False
    return answer in {"y", "yes"}


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(dt.timezone.utc)
    day = now.strftime("%Y-%m-%d")
    now_utc = now.strftime("%Y-%m-%d %H:%M")

    if args.max_commits < 1:
        print("max-commits must be >= 1")
        return 1
    if args.max_hours < 1:
        print("max-hours must be >= 1")
        return 1

    if not confirm_read(args.ack_read):
        print("Session start cancelled. Memory-bank read acknowledgment is required.")
        return 1

    MEMORY_BANK.mkdir(parents=True, exist_ok=True)
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    ensure_daily(day, now_utc)

    anchor_commit = run_git(["rev-parse", "HEAD"])
    expires_at = (now + dt.timedelta(hours=args.max_hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
    state = {
        "started_at_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "expires_at_utc": expires_at,
        "profile": args.profile,
        "author": args.author,
        "max_commits": args.max_commits,
        "max_hours": args.max_hours,
        "anchor_commit": anchor_commit,
        "required_start_docs": START_DOCS,
        "daily_keep_days": DEFAULT_KEEP_DAYS,
    }
    session_path = GENERATED_DIR / "session-state.json"
    session_path.write_text(json.dumps(state, indent=2), encoding="utf-8")

    print("Memory-bank session started.")
    print(f"- state: {session_path.relative_to(ROOT)}")
    print(f"- expires_utc: {expires_at}")
    print(f"- commit_budget: {args.max_commits}")
    print("- next: start coding, then keep Memory-bank docs updated before commit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$startSessionPsTemplate = @'
param(
    [ValidateRange(1, 1000)]
    [int]$MaxCommits = __SESSION_MAX_COMMITS__,
    [ValidateRange(1, 168)]
    [int]$MaxHours = __SESSION_MAX_HOURS__,
    [string]$Author = "agent",
    [switch]$Yes,
    [switch]$SkipRefresh
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    if (-not $SkipRefresh.IsPresent) {
        & python "scripts/__BUILD_SCRIPT__"
        if ($LASTEXITCODE -ne 0) {
            throw "__BUILD_SCRIPT__ failed. Aborting session start."
        }

        & python "scripts/generate_memory_bank.py" "--profile" "__PROJECT_TYPE__" "--keep-days" "__DAILY_KEEP_DAYS__"
        if ($LASTEXITCODE -ne 0) {
            throw "generate_memory_bank.py failed. Aborting session start."
        }
    }

    $argsList = @(
        "scripts/start_memory_bank_session.py",
        "--profile", "__PROJECT_TYPE__",
        "--max-commits", "$MaxCommits",
        "--max-hours", "$MaxHours",
        "--author", "$Author"
    )
    if ($Yes.IsPresent) {
        $argsList += "--ack-read"
    }

    & python @argsList
    if ($LASTEXITCODE -ne 0) {
        throw "start_memory_bank_session.py failed."
    }

    Write-Host "Session bootstrap complete."
    Write-Host "Mode: __ENFORCEMENT_MODE__"
    Write-Host "Commit budget: $MaxCommits"
    Write-Host "Hour budget: $MaxHours"
}
finally {
    Pop-Location
}
'@

$startSessionShTemplate = @'
#!/usr/bin/env bash
set -euo pipefail

max_commits="${MB_SESSION_MAX_COMMITS:-__SESSION_MAX_COMMITS__}"
max_hours="${MB_SESSION_MAX_HOURS:-__SESSION_MAX_HOURS__}"
author="${MB_SESSION_AUTHOR:-agent}"
yes_flag=""
skip_refresh="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      yes_flag="--ack-read"
      shift
      ;;
    --skip-refresh)
      skip_refresh="1"
      shift
      ;;
    --max-commits)
      max_commits="$2"
      shift 2
      ;;
    --max-hours)
      max_hours="$2"
      shift 2
      ;;
    --author)
      author="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ "$skip_refresh" != "1" ]]; then
  python "scripts/__BUILD_SCRIPT__"
  python "scripts/generate_memory_bank.py" --profile "__PROJECT_TYPE__" --keep-days "__DAILY_KEEP_DAYS__"
fi

python "scripts/start_memory_bank_session.py" \
  --profile "__PROJECT_TYPE__" \
  --max-commits "$max_commits" \
  --max-hours "$max_hours" \
  --author "$author" \
  $yes_flag
'@

$endSessionPyTemplate = @'
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEMORY_BANK = ROOT / "Memory-bank"
GENERATED_DIR = MEMORY_BANK / "_generated"
DAILY_DIR = MEMORY_BANK / "daily"
SESSION_PATH = GENERATED_DIR / "session-state.json"
LAST_SESSION_PATH = GENERATED_DIR / "last-session.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="End Memory-bank session")
    parser.add_argument("--author", default="agent")
    parser.add_argument("--note", default="")
    parser.add_argument("--keep-state", action="store_true")
    return parser.parse_args()


def ensure_daily(day: str, now_utc: str) -> Path:
    DAILY_DIR.mkdir(parents=True, exist_ok=True)
    daily_file = DAILY_DIR / f"{day}.md"
    if not daily_file.exists():
        daily_file.write_text(
            (
                f"# End-of-Day Report - {day}\n\n"
                f"AUTHOR: session-end\n"
                f"LAST_UPDATED_UTC: {now_utc}\n\n"
                "## Work Summary\n"
                "- Session ended.\n"
            ),
            encoding="utf-8",
        )
    latest = DAILY_DIR / "LATEST.md"
    latest.write_text(
        (
            "# Latest Daily Report Pointer\n\n"
            f"Latest: {day}\n"
            f"File: Memory-bank/daily/{day}.md\n"
        ),
        encoding="utf-8",
    )
    return daily_file


def append_session_event(daily_file: Path, now_utc: str, author: str, note: str) -> None:
    existing = daily_file.read_text(encoding="utf-8")
    if "## Session Events" not in existing:
        existing = existing.rstrip() + "\n\n## Session Events\n"
    line = f"- [{now_utc} UTC] Session ended by `{author}`"
    if note.strip():
        line += f" - {note.strip()}"
    daily_file.write_text(existing.rstrip() + "\n" + line + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(dt.timezone.utc)
    now_iso = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    now_utc = now.strftime("%Y-%m-%d %H:%M")
    day = now.strftime("%Y-%m-%d")

    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    MEMORY_BANK.mkdir(parents=True, exist_ok=True)

    state: dict = {}
    if SESSION_PATH.exists():
        try:
            state = json.loads(SESSION_PATH.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            state = {}

    state["ended_at_utc"] = now_iso
    state["ended_by"] = args.author
    state["end_note"] = args.note

    LAST_SESSION_PATH.write_text(json.dumps(state, indent=2), encoding="utf-8")

    daily_file = ensure_daily(day, now_utc)
    append_session_event(daily_file, now_utc, args.author, args.note)

    if SESSION_PATH.exists() and not args.keep_state:
        SESSION_PATH.unlink(missing_ok=True)

    print("Memory-bank session ended.")
    print(f"- last_session: {LAST_SESSION_PATH.relative_to(ROOT)}")
    if not args.keep_state:
        print("- session-state: closed")
    else:
        print("- session-state: kept (--keep-state)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$endSessionPsTemplate = @'
param(
    [string]$Author = "agent",
    [string]$Note = "",
    [switch]$SkipRefresh,
    [switch]$KeepState
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    if (-not $SkipRefresh.IsPresent) {
        & python "scripts/__BUILD_SCRIPT__"
        if ($LASTEXITCODE -ne 0) {
            throw "__BUILD_SCRIPT__ failed. Aborting session end."
        }

        & python "scripts/generate_memory_bank.py" "--profile" "__PROJECT_TYPE__" "--keep-days" "__DAILY_KEEP_DAYS__"
        if ($LASTEXITCODE -ne 0) {
            throw "generate_memory_bank.py failed. Aborting session end."
        }
    }

    $argsList = @(
        "scripts/end_memory_bank_session.py",
        "--author", "$Author"
    )
    if ($Note -ne "") {
        $argsList += @("--note", "$Note")
    }
    if ($KeepState.IsPresent) {
        $argsList += "--keep-state"
    }

    & python @argsList
    if ($LASTEXITCODE -ne 0) {
        throw "end_memory_bank_session.py failed."
    }
}
finally {
    Pop-Location
}
'@

$sessionStatusPyTemplate = @'
from __future__ import annotations

import datetime as dt
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATE_PATH = ROOT / "Memory-bank" / "_generated" / "session-state.json"


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


def parse_iso_utc(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    normalized = value.strip().replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.UTC)
    return parsed.astimezone(dt.UTC)


def commits_since_anchor(anchor: str) -> int | None:
    if not anchor:
        return 0
    head = run_git(["rev-parse", "HEAD"]).strip()
    if not head:
        return 0
    if head == anchor:
        return 0
    if not run_git(["rev-parse", "--verify", anchor]).strip():
        return None
    out = run_git(["rev-list", "--count", f"{anchor}..HEAD"]).strip()
    if not out:
        return None
    try:
        return int(out)
    except ValueError:
        return None


def main() -> int:
    if not STATE_PATH.exists():
        print("Session status: NONE")
        print("Run: .\\pg.ps1 start -Yes")
        return 1

    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        print("Session status: INVALID (JSON parse error)")
        return 2

    started_at = parse_iso_utc(str(state.get("started_at_utc", "")).strip())
    expires_at = parse_iso_utc(str(state.get("expires_at_utc", "")).strip())
    max_commits = int(state.get("max_commits", __SESSION_MAX_COMMITS__))
    anchor = str(state.get("anchor_commit", "")).strip()
    commits_used = commits_since_anchor(anchor)

    print("Session status: ACTIVE")
    print(f"- state_file: {STATE_PATH.relative_to(ROOT)}")
    if started_at:
        age_hours = (dt.datetime.now(dt.UTC) - started_at).total_seconds() / 3600.0
        print(f"- started_at_utc: {started_at.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"- age_hours: {age_hours:.2f}")
    if expires_at:
        print(f"- expires_at_utc: {expires_at.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"- max_commits: {max_commits}")
    if commits_used is None:
        print("- commits_used: unknown (anchor not found)")
    else:
        remaining = max_commits - commits_used
        print(f"- commits_used: {commits_used}")
        print(f"- commits_remaining: {remaining}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$pgScriptTemplate = @'
param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "start", "end", "status", "help")]
    [string]$Command = "help",

    [ValidateRange(1, 1000)]
    [int]$MaxCommits = __SESSION_MAX_COMMITS__,

    [ValidateRange(1, 168)]
    [int]$MaxHours = __SESSION_MAX_HOURS__,

    [string]$Author = "agent",
    [string]$Note = "",
    [switch]$Yes,
    [switch]$SkipRefresh,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host "pg command usage:"
    Write-Host "  .\pg.ps1 install backend"
    Write-Host "  .\pg.ps1 start -Yes"
    Write-Host "  .\pg.ps1 end -Note ""finished for today"""
    Write-Host "  .\pg.ps1 status"
    Write-Host ""
    Write-Host "Note: install delegates to global CLI if available (~\.pg-cli\pg.ps1)."
}

$scriptDir = $PSScriptRoot

switch ($Command) {
    "install" {
        $globalPg = Join-Path $HOME ".pg-cli\pg.ps1"
        if (-not (Test-Path -LiteralPath $globalPg)) {
            throw "Install command requires global pg CLI. Run pg-install.ps1 once on this machine."
        }
        Write-Host "Delegating install to global pg CLI..."
        & powershell -ExecutionPolicy Bypass -File $globalPg "install" @Rest
        exit $LASTEXITCODE
    }
    "start" {
        $args = @{
            MaxCommits = $MaxCommits
            MaxHours = $MaxHours
            Author = $Author
            SkipRefresh = $SkipRefresh.IsPresent
        }
        if ($Yes.IsPresent) {
            $args["Yes"] = $true
        }
        & (Join-Path $scriptDir "start_memory_bank_session.ps1") @args
        exit $LASTEXITCODE
    }
    "end" {
        $args = @{
            Author = $Author
            Note = $Note
            SkipRefresh = $SkipRefresh.IsPresent
        }
        & (Join-Path $scriptDir "end_memory_bank_session.ps1") @args
        exit $LASTEXITCODE
    }
    "status" {
        & python (Join-Path $scriptDir "session_status.py")
        exit $LASTEXITCODE
    }
    default {
        Show-Help
        exit 0
    }
}
'@

$pgRootPsTemplate = @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "scripts\pg.ps1"

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing command script: $scriptPath"
}

& powershell -ExecutionPolicy Bypass -File $scriptPath @Arguments
exit $LASTEXITCODE
'@

$pgRootCmdTemplate = @'
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\pg.ps1" %*
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
    @{ Path = "scripts\start_memory_bank_session.py"; Content = $startSessionPyTemplate; LfOnly = $true },
    @{ Path = "scripts\start_memory_bank_session.ps1"; Content = $startSessionPsTemplate; LfOnly = $false },
    @{ Path = "scripts\start_memory_bank_session.sh"; Content = $startSessionShTemplate; LfOnly = $true },
    @{ Path = "scripts\end_memory_bank_session.py"; Content = $endSessionPyTemplate; LfOnly = $true },
    @{ Path = "scripts\end_memory_bank_session.ps1"; Content = $endSessionPsTemplate; LfOnly = $false },
    @{ Path = "scripts\session_status.py"; Content = $sessionStatusPyTemplate; LfOnly = $true },
    @{ Path = "scripts\pg.ps1"; Content = $pgScriptTemplate; LfOnly = $false },
    @{ Path = "pg.ps1"; Content = $pgRootPsTemplate; LfOnly = $false },
    @{ Path = "pg.cmd"; Content = $pgRootCmdTemplate; LfOnly = $false },
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

$insideGitWorkTree = $false
& git -C $repoRoot rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -eq 0) {
    $insideGitWorkTree = $true
}

if ($shouldInstallHooks -and $insideGitWorkTree) {
    $installer = Join-Path $repoRoot "scripts\install_memory_bank_hooks.ps1"
    if ($Force.IsPresent) {
        & powershell -ExecutionPolicy Bypass -File $installer -Mode $EnforcementMode -Force
    } else {
        & powershell -ExecutionPolicy Bypass -File $installer -Mode $EnforcementMode
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Hook installation failed with exit code $LASTEXITCODE."
    }
} elseif ($shouldInstallHooks -and -not $insideGitWorkTree) {
    Write-Warning "Target is not inside a git work tree; skipped hook installation."
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
Write-Host "1) .\pg.ps1 start -Yes"
Write-Host "2) .\pg.ps1 status"
Write-Host "3) .\pg.ps1 end -Note ""finished for today"""
Write-Host "4) git add . && git commit -m ""chore: initialize memory-bank enforcement"""
