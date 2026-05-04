# Sprint 0 — Foundation & Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the local dev environment, scaffold the `little-signals/backend` repository, and capture an honest "ready to start Sprint 1" snapshot — without writing any application code yet.

**Architecture:** This sprint is foundation only. No FastAPI app, no AWS, no migrations. The deliverable is: tools installed and verified, GitHub repo created with branch protection, Python project scaffolded with Poetry, Docker dev stack runnable, and the Samsung Health Sensor SDK 1.4.1 contents in repo. SDK hands-on verification (Block D in the sprint plan) is **deferred** until Galaxy Watch 8 + Android phone are available; the AAR class inspection already documented in spec Appendix C is sufficient evidence to proceed with backend work.

**Tech Stack:** Python 3.12 (via pyenv), Poetry, Docker Desktop, Postgres 15 (Homebrew + docker compose), AWS CLI v2, Terraform 1.7+ (via tfenv), GitHub CLI, ruff, mypy.

**Working directory:** `/Users/anubilegdemberel/Documents/little-signals/backend`

**Companion docs:** [`backend-architecture-spec.md`](../../backend-architecture-spec.md) v1.1, [`backend-sprint-plan.md`](../../backend-sprint-plan.md) Sprint 0.

---

## Plan revisions (from environment audit, 2026-05-04)

After writing the original plan, an audit of Anu's actual dev machine and the project context surfaced several adjustments. Tasks have been revised in place — each affected task notes "[REVISED]" with the change.

**What was already installed (Tasks 1, 5, 6, 7 → done):**
- pyenv 2.6.27 + Python 3.12.3 (Task 1)
- gh CLI 2.69.0, logged in as `nukktae` (Task 5)
- Poetry 2.3.2 (Task 6 — Poetry 2.x is compatible with the plan as written)
- Postgres 15.10 via Homebrew (Task 7)

**What changed:**
- **Docker setup is Colima, not Docker Desktop.** Task 2 revised to install the `docker-compose` plugin for the Colima setup rather than Docker Desktop.
- **AWS CLI is installed but using root credentials in `us-west-2`.** Task 3 revised to create the `anu-dev` IAM user, configure CLI as that user, and set default region to `ap-northeast-2` (Seoul) per spec.
- **GitHub repo already exists.** This project is Kookmin University 2026 capstone team 18 at `https://github.com/kookmin-sw/2026-capstone-18`. The repo is org-owned, default branch is `master`, and currently contains the ML team's WESAD / Mamba work. Task 9 revised to integrate the existing repo (clone, set remote, branch off master) instead of creating a new one. **Task 10 (branch protection) removed** — that's the school org's call, not ours.
- **Root files belong to the team.** The capstone repo already has its own `README.md`, `.gitignore`, `_config.yml`, `index.md`, `requirements.txt`, `notebooks/`, and `src/`. Task 11 revised to add backend-specific files only and merge our `.gitignore` rules into the existing one — never overwrite root files.
- **No Claude attribution.** All git commits and PR bodies in this project must NOT include any "Co-Authored-By: Claude" line, "Generated with Claude Code" footer, or other Claude mention. Hard rule.

---

## Hardware constraint note

Block D of the original sprint plan (SDK hands-on verification) requires:
1. A Galaxy Watch 8 with developer mode enabled
2. A Samsung/Android phone paired with the watch
3. A USB cable + working `adb` connection

Anu does not currently have a Galaxy phone, so **Block D and Task A.8 (Android Studio install) are deferred**. This plan covers Blocks A (sans A.8), B, and C. The deferred work is captured as Task 22 with an explicit unblock checklist.

Risk of deferral: low for backend work specifically. The spec's load-bearing claim — that the Sensor SDK exposes raw HRV/PPG/EDA/accel — is already supported by direct AAR class inspection (spec §11.3, Appendix C). What hands-on verification adds is empirical sample rates, battery impact, and IBI quality — all of which feed the ML pipeline (Nika's domain) and the Wear OS app, not the backend service.

---

## File Structure

After this sprint, the repository will contain:

```
little-signals/                  ← existing top-level dir, will become git repo root
├── .git/                        ← initialized in Task 9
├── .gitignore                   ← Task 11
├── LICENSE                      ← Task 11 (MIT)
├── README.md                    ← Task 11, polished in Task 20
└── backend/
    ├── docs/                    ← already exists (spec, sprint plan, SDK)
    │   ├── backend-architecture-spec.md
    │   ├── backend-sprint-plan.md
    │   ├── 1.4.1/               ← Samsung SDK 1.4.1 contents (already present)
    │   └── superpowers/
    │       └── plans/
    │           └── 2026-05-04-sprint-0-foundation.md   ← this file
    ├── pyproject.toml           ← Task 12
    ├── poetry.lock              ← Task 13 (auto-generated)
    ├── Dockerfile               ← Task 18
    ├── docker-compose.yml       ← Task 19
    └── app/                     ← Task 17, empty packages
        ├── __init__.py
        ├── auth/__init__.py
        ├── routers/__init__.py
        ├── models/__init__.py
        ├── schemas/__init__.py
        ├── services/__init__.py
        ├── db/__init__.py
        ├── observability/__init__.py
        └── tests/__init__.py
```

Why `backend/` as a subdirectory: leaves room for `wear-os/`, `phone/`, `infra/` siblings later without restructuring. The Wear OS engineer (when recruited) gets a clean `wear-os/` peer; the Flutter engineer gets `phone/`.

---

## Task 1: Install pyenv and Python 3.12

**Why:** System Python on macOS drifts and Apple updates break virtual envs at random. pyenv pins Python per-project.

**Files:** None (environment setup only).

- [ ] **Step 1: Install pyenv via Homebrew**

Run:
```bash
brew update && brew install pyenv
```

Expected: Homebrew installs pyenv. If already installed, output says so — that's fine.

- [ ] **Step 2: Wire pyenv into shell**

Append to `~/.zshrc` (only if not already there):
```bash
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"
```

Then reload:
```bash
source ~/.zshrc
```

- [ ] **Step 3: Install Python 3.12**

Run:
```bash
pyenv install 3.12.7
pyenv global 3.12.7
```

Expected: download and compile completes (a few minutes). `pyenv global` sets it as the default Python.

- [ ] **Step 4: Verify**

Run:
```bash
python --version
```

Expected output: `Python 3.12.7`

If the output is anything else (e.g. `Python 3.9.x` from system Python), the shell init in Step 2 isn't loading. Open a fresh terminal and try again.

---

## Task 2: [REVISED] Install docker-compose plugin for Colima

**Why:** The dev machine already runs Docker via Colima (Docker Engine 28.0.4). What's missing is the Compose v2 plugin — without it, `docker compose up` fails with `unknown command`. We need Compose for the local Postgres + Adminer stack in Task 19.

**Original plan task:** install Docker Desktop. Skipped because Colima is already working.

- [ ] **Step 1: Install docker-compose via Homebrew**

Run:
```bash
brew install docker-compose
```

This installs the standalone `docker-compose` binary AND symlinks the v2 plugin into `~/.docker/cli-plugins/`, so both `docker-compose up` and `docker compose up` will work.

- [ ] **Step 2: Wire the plugin into Colima's Docker config**

If the symlink wasn't placed automatically, do it manually:
```bash
mkdir -p ~/.docker/cli-plugins
ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
```

- [ ] **Step 3: Verify both invocation styles work**

Run:
```bash
docker compose version
docker-compose version
```

Expected: both print `Docker Compose version v2.x.x`. If the first fails with "unknown command", the symlink in Step 2 wasn't created — re-run that step.

- [ ] **Step 4: Verify Colima is running**

Run:
```bash
docker info | grep -i 'context\|server version'
```

Expected: shows `Context: colima` and a Server Version line. If Server Version is missing, run `colima start` first.

---

## Task 3: [REVISED] Move off AWS root credentials → `anu-dev` IAM user, set Seoul region

**Why:** AWS CLI v2 is already installed (v2.18.2), but it's configured with **root account credentials** in region `us-west-2`. Two problems:
1. **Root credentials are a serious security anti-pattern.** AWS strongly recommends never using root for day-to-day work — root has unrecoverable, MFA-bypassable powers. Sprint 2 will create real infrastructure with this CLI; doing so as root means a leaked key compromises the entire account permanently.
2. **Wrong region.** Spec §3 mandates Seoul (`ap-northeast-2`) for PIPA compliance. `us-west-2` would put data in Oregon — a compliance violation.

**Original plan task:** install AWS CLI + configure new IAM user. CLI install is already done; this task is now just the user creation + reconfigure.

- [ ] **Step 1: Confirm starting state**

Run:
```bash
aws sts get-caller-identity
aws configure get region
```

Expected before this task: `Arn` ends with `:root`, region is `us-west-2`.
Expected after this task: `Arn` ends with `:user/anu-dev`, region is `ap-northeast-2`.

- [ ] **Step 2: Create the `anu-dev` IAM user (manual — AWS console)**

In a browser, log into the AWS Management Console → IAM → Users → "Create user":
1. User name: `anu-dev`
2. Click "Next"
3. Permissions options: "Attach policies directly"
4. Search for and check `AdministratorAccess` (for solo build only; we'll lock this down before Sprint 7)
5. Click "Next" → "Create user"
6. On the user list, click `anu-dev` → "Security credentials" tab → "Create access key"
7. Use case: "Command Line Interface (CLI)" → check the confirmation → "Next" → "Create access key"
8. **Download the .csv** or copy both the Access Key ID and Secret Access Key into a password manager. **You will never see the secret again** after closing this page.

- [ ] **Step 3: Enable MFA on the root account (one-time hardening, while you're in IAM)**

Same console → IAM → Dashboard → "Security recommendations" → "Add MFA for root user" → follow the prompts (use an authenticator app like 1Password, Authy, or Google Authenticator).

This isn't strictly Sprint 0 work, but you're already in the IAM console and root MFA is essential before we use root for anything (e.g., billing alerts in Sprint 2).

- [ ] **Step 4: Reconfigure the CLI as `anu-dev`**

Run:
```bash
aws configure
```

Enter when prompted:
- AWS Access Key ID: (from Step 2)
- AWS Secret Access Key: (from Step 2)
- Default region name: `ap-northeast-2`
- Default output format: `json`

This overwrites `~/.aws/credentials` and `~/.aws/config`. The previous root credentials are now gone from the local machine.

- [ ] **Step 5: Verify the new identity**

Run:
```bash
aws sts get-caller-identity
aws configure get region
```

Expected:
```json
{
  "UserId": "AIDA...",
  "Account": "794038244518",
  "Arn": "arn:aws:iam::794038244518:user/anu-dev"
}
```
And region should print `ap-northeast-2`.

- [ ] **Step 6: Delete the root access keys (if any exist)**

In the AWS console → IAM → Dashboard → "Security recommendations" → if "Delete your root access keys" appears, follow it. Root should have NO active access keys at the end of this task.

This is a one-way door — once deleted, no AWS CLI can authenticate as root again, which is exactly what we want.

---

## Task 4: Install Terraform via tfenv

**Why:** Sprint 2 onwards uses Terraform for all AWS infra. tfenv lets us pin the version per-project.

- [ ] **Step 1: Install tfenv**

Run:
```bash
brew install tfenv
```

- [ ] **Step 2: Install Terraform 1.7.5 (current stable)**

Run:
```bash
tfenv install 1.7.5
tfenv use 1.7.5
```

- [ ] **Step 3: Verify**

Run:
```bash
terraform version
```

Expected: `Terraform v1.7.5`

---

## Task 5: Install GitHub CLI and authenticate

**Why:** Task 9 creates the repo via `gh`; faster than the web UI and scriptable.

- [ ] **Step 1: Install gh**

Run:
```bash
brew install gh
```

- [ ] **Step 2: Authenticate**

Run:
```bash
gh auth login
```

Choose:
- GitHub.com
- HTTPS
- Authenticate Git with GitHub credentials: Yes
- Login with web browser (opens browser, paste one-time code)

- [ ] **Step 3: Verify**

Run:
```bash
gh auth status
```

Expected: shows `Logged in to github.com as <username>`. If not, repeat Step 2.

---

## Task 6: Install Poetry

**Why:** Per spec §5.3, Poetry manages Python dependencies and virtualenvs. Pip + requirements.txt is too primitive for a multi-environment project.

- [ ] **Step 1: Install via official installer**

Run:
```bash
curl -sSL https://install.python-poetry.org | python3 -
```

This installs Poetry to `~/.local/bin/poetry`. The Homebrew version of Poetry is sometimes out of date, so we use the official installer.

- [ ] **Step 2: Add Poetry to PATH**

Append to `~/.zshrc` if missing:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

Reload:
```bash
source ~/.zshrc
```

- [ ] **Step 3: Configure Poetry to create venv inside project**

Run:
```bash
poetry config virtualenvs.in-project true
```

This creates `.venv/` inside the project directory (cleaner than the global pypoetry cache, easier for VS Code to discover).

- [ ] **Step 4: Verify**

Run:
```bash
poetry --version
```

Expected: `Poetry (version 1.8.x)` or newer.

---

## Task 7: Install Postgres 15 locally

**Why:** Sometimes you want to `psql` directly without Docker overhead. Sprint 1 uses docker-compose Postgres for the app, but `psql` client + occasional ad-hoc local DB is useful.

- [ ] **Step 1: Install via Homebrew**

Run:
```bash
brew install postgresql@15
```

- [ ] **Step 2: Start the service (optional, for ad-hoc use)**

Run:
```bash
brew services start postgresql@15
```

(If you don't want it auto-starting, skip this — `psql` client still works against docker-compose Postgres.)

- [ ] **Step 3: Add psql to PATH**

Postgres 15 is keg-only on Homebrew. Append to `~/.zshrc`:
```bash
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
```

(On Intel Macs, replace `/opt/homebrew` with `/usr/local`.)

Reload:
```bash
source ~/.zshrc
```

- [ ] **Step 4: Verify**

Run:
```bash
psql --version
```

Expected: `psql (PostgreSQL) 15.x`

---

## Task 8: [DEFERRED] Android Studio + Galaxy Watch 8 USB setup

**Status:** BLOCKED — no Galaxy Watch 8 + Android phone available.

**Skip this task entirely until prerequisites are met.** Installing Android Studio without target hardware adds 5+ GB of bloat to the dev machine for no current benefit.

Unblock prerequisites (re-open this task when all are true):
1. Galaxy Watch 8 acquired (own, borrowed, or via the Wear OS engineer's setup)
2. Android phone paired with the watch (any modern Samsung/Pixel with USB debugging)
3. USB-C cable for Watch 8 charging dock
4. Windows or Mac machine where `adb` can talk to the watch in dev mode

Re-attempt path: see Task 22.

---

## Task 9: [REVISED] Integrate the existing capstone repo, branch off master

**Why:** This project already has a GitHub repo at `https://github.com/kookmin-sw/2026-capstone-18` containing the ML team's work (`src/` Mamba model, `notebooks/`, `requirements.txt`, root `README.md`). Anu's backend goes alongside. We are NOT creating a new repo. Default branch is `master`. We work on a feature branch and PR back.

**Original plan task:** create a new private GitHub repo. Replaced with this integration step.

**Files:**
- The working directory `/Users/anubilegdemberel/Documents/little-signals/` becomes a clone of the capstone repo.
- Existing local docs at `backend/docs/` (spec, sprint plan, SDK extraction, this plan) are preserved by moving aside, then back.

- [ ] **Step 1: Back up the existing local `backend/` directory**

Run:
```bash
mv /Users/anubilegdemberel/Documents/little-signals/backend /tmp/ls-backend-backup
ls /tmp/ls-backend-backup/docs/
```

Expected: lists `1.4.1`, `backend-architecture-spec.md`, `backend-sprint-plan.md`, `superpowers`. The local working dir is now empty.

- [ ] **Step 2: Remove the empty working dir, then clone the capstone repo into it**

Run:
```bash
rmdir /Users/anubilegdemberel/Documents/little-signals
git clone https://github.com/kookmin-sw/2026-capstone-18.git /Users/anubilegdemberel/Documents/little-signals
cd /Users/anubilegdemberel/Documents/little-signals
git status
```

Expected: clone succeeds, `git status` shows "On branch master" and "nothing to commit, working tree clean."

- [ ] **Step 3: Configure local git user**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals
git config user.name "Anu Bilegdemberel"
git config user.email "anu.bnda@gmail.com"
```

These are local-only (don't override global git config).

- [ ] **Step 4: Create and switch to feature branch `sprint-0-foundation`**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals
git checkout -b sprint-0-foundation
git status
```

Expected: "On branch sprint-0-foundation". All subsequent Sprint 0 commits go here, not master.

- [ ] **Step 5: Restore the backed-up `backend/` directory**

Run:
```bash
mv /tmp/ls-backend-backup /Users/anubilegdemberel/Documents/little-signals/backend
ls /Users/anubilegdemberel/Documents/little-signals/backend/docs/
```

Expected: backend dir is back in place with all local docs intact.

- [ ] **Step 6: Verify the working tree state**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals
git status
```

Expected: shows untracked `backend/` directory. The capstone files (`src/`, `notebooks/`, root `README.md`, etc.) are tracked and unchanged.

- [ ] **Step 7: Stage and commit the docs**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals
git add backend/docs
git commit -m "docs(backend): add architecture spec, sprint plan, Sensor SDK 1.4.1 reference"
```

The commit message has NO Co-Authored-By trailer, no Claude mention. Per project rule.

- [ ] **Step 8: Push the feature branch**

Run:
```bash
git push -u origin sprint-0-foundation
```

Expected: push succeeds. The branch now exists on the remote and can be opened as a PR later (after the rest of Sprint 0 is done).

---

## Task 10: [REMOVED] Branch protection — not our call

The original Task 10 configured branch protection on `main`. This is removed because:
- The capstone repo is org-owned by `kookmin-sw`, not by Anu.
- Branch protection settings are the school org's responsibility, not ours.
- The PR-based workflow we already follow (branch off master, push to feature branch, open PR) is sufficient discipline.

Skip and proceed to Task 11.

---

## Task 11: [REVISED] Append backend-specific rules to existing root `.gitignore`

**Why:** The capstone repo already has a root `README.md` (team's GitHub Classroom intro page in Korean) and a root `.gitignore` (covers ML basics: `data/`, `checkpoints/`, `*.npy`, `*.pt`, etc.). We do NOT overwrite either — those are the team's. We only need to add backend-specific patterns (`.venv/`, `.pytest_cache/`, Terraform state, Docker) that the existing file doesn't cover.

We also do NOT add a root `LICENSE` — that's a team-level decision and shouldn't be made unilaterally by the backend dev. Skipping.

**Original plan task:** create `.gitignore`, `LICENSE`, `README.md` at the repo root. Replaced with a single append to `.gitignore`.

**Files:**
- Modify: `/Users/anubilegdemberel/Documents/little-signals/.gitignore` (append only)

- [ ] **Step 1: Inspect what's already in the root .gitignore**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals
cat .gitignore
```

Expected: shows the team's existing rules (`data/`, `checkpoints/`, `*.npy`, `__pycache__/`, `.env`, `venv/`, etc.).

- [ ] **Step 2: Append backend-specific rules**

Append this block to `/Users/anubilegdemberel/Documents/little-signals/.gitignore`:
```
# =========================
# Backend (Python + FastAPI + Terraform + Docker)
# Added for backend/ subdirectory; complements existing ML rules above.
# =========================
.venv/
*.egg-info/
.pytest_cache/
.mypy_cache/
.ruff_cache/
.coverage
htmlcov/
dist/
build/

# IDEs
.vscode/
.idea/
*.swp

# OS
Thumbs.db

# Terraform (Sprint 2+)
**/.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
!*.tfvars.example

# Docker
docker-compose.override.yml
```

Note: don't duplicate rules that are already in the team's section (e.g., `__pycache__/`, `.env`, `venv/`, `.DS_Store` are already covered).

- [ ] **Step 3: Commit**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals
git add .gitignore
git commit -m "chore(backend): extend .gitignore for Python venv, Terraform, Docker artifacts"
```

No Co-Authored-By trailer. No Claude mention. Per project rule.

The backend feature branch already exists from Task 9; we'll push at the end (after Task 20 batches scaffolding into a logical commit).

---

## Task 12: Initialize pyproject.toml with Poetry

**Why:** Establishes the Python project root in `backend/` with Python 3.12 pinned.

**Files:**
- Create: `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`

- [ ] **Step 1: Create pyproject.toml**

Create `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`:
```toml
[tool.poetry]
name = "little-signals-backend"
version = "0.1.0"
description = "Backend service for Project Phase — stress detection and cycle tracking."
authors = ["Anu Bilegdemberel <anu.bnda@gmail.com>"]
license = "MIT"
readme = "README.md"
package-mode = false

[tool.poetry.dependencies]
python = "^3.12"

[tool.poetry.group.dev.dependencies]

[build-system]
requires = ["poetry-core>=1.0.0"]
build-backend = "poetry.core.masonry.api"
```

`package-mode = false` tells Poetry this is an application, not a library — it skips the package-build steps and keeps things simple.

- [ ] **Step 2: Verify Poetry accepts it**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
poetry install
```

Expected: creates `.venv/` inside `backend/`, installs nothing yet (no deps), prints `Installing dependencies from lock file` or similar. No errors.

- [ ] **Step 3: Verify the venv works**

Run:
```bash
poetry run python --version
```

Expected: `Python 3.12.7`

---

## Task 13: Add core runtime dependencies

**Why:** These are the libraries the app code in Sprint 1 will import. Adding them now means Sprint 1 can start writing code immediately.

Per spec §5.3.

**Files:**
- Modify: `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`

- [ ] **Step 1: Add core dependencies via Poetry**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
poetry add fastapi uvicorn[standard] sqlalchemy[asyncio] asyncpg alembic pydantic pydantic-settings python-jose[cryptography] structlog
```

Expected: Poetry resolves and installs each package, updates `pyproject.toml` and creates `poetry.lock`. The `[standard]` extras pull uvicorn's HTTP/WebSocket fast path; `[asyncio]` pulls SQLAlchemy 2.0 async support; `[cryptography]` pulls the JOSE crypto backend.

- [ ] **Step 2: Verify dependencies installed cleanly**

Run:
```bash
poetry run python -c "import fastapi, sqlalchemy, asyncpg, alembic, pydantic, jose, structlog; print('all imports ok')"
```

Expected: prints `all imports ok`. Any ImportError means a package didn't install — re-check Step 1.

---

## Task 14: Add dev dependencies

**Why:** ruff, mypy, pytest are the tools spec §5.3 names for lint/type/test. They go in the `dev` group so they don't ship in production Docker images.

**Files:**
- Modify: `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`

- [ ] **Step 1: Add dev dependencies**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
poetry add --group dev ruff mypy pytest pytest-asyncio pytest-cov httpx
```

Expected: same as Task 13 — installs successfully and updates `pyproject.toml` with a `[tool.poetry.group.dev.dependencies]` section.

- [ ] **Step 2: Verify**

Run:
```bash
poetry run ruff --version
poetry run mypy --version
poetry run pytest --version
```

Expected: each prints its version. ruff should be 0.4.x or newer; mypy 1.10.x or newer; pytest 8.x or newer.

---

## Task 15: Configure ruff

**Why:** Without configuration, ruff applies default rules which may not match the codebase style. We pin: line length 100 (room for expressive type hints), Python 3.12 target, common rule selection.

**Files:**
- Modify: `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`

- [ ] **Step 1: Append ruff config to pyproject.toml**

Add this at the end of `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`:
```toml
[tool.ruff]
line-length = 100
target-version = "py312"
extend-exclude = [".venv", "alembic/versions"]

[tool.ruff.lint]
select = [
    "E",    # pycodestyle errors
    "W",    # pycodestyle warnings
    "F",    # pyflakes
    "I",    # isort (import ordering)
    "B",    # flake8-bugbear (likely bugs)
    "UP",   # pyupgrade (modernize syntax)
    "SIM",  # flake8-simplify
    "C4",   # flake8-comprehensions
]
ignore = [
    "E501",  # line too long — handled by formatter
]

[tool.ruff.format]
quote-style = "double"
```

- [ ] **Step 2: Verify ruff runs cleanly on the (currently empty) project**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
poetry run ruff check .
```

Expected: `All checks passed!` (or no output and exit code 0). Since there's no Python code yet, this is a smoke test only.

---

## Task 16: Configure mypy

**Why:** Strict type-checking from day one is cheaper than retrofitting later. Spec §15.5 also relies on Pydantic + mypy for input validation correctness.

**Files:**
- Modify: `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`

- [ ] **Step 1: Append mypy config to pyproject.toml**

Add this at the end of `/Users/anubilegdemberel/Documents/little-signals/backend/pyproject.toml`:
```toml
[tool.mypy]
python_version = "3.12"
strict = true
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
no_implicit_optional = true
check_untyped_defs = true
warn_redundant_casts = true
warn_unused_ignores = true
plugins = ["pydantic.mypy"]

[[tool.mypy.overrides]]
module = ["jose.*", "structlog.*"]
ignore_missing_imports = true

[tool.pytest.ini_options]
asyncio_mode = "auto"
addopts = "-ra --strict-markers"
testpaths = ["app/tests"]
```

`strict = true` plus the per-rule overrides matches what spec §15.5 implies. The `pydantic.mypy` plugin is critical — without it, mypy can't reason about Pydantic v2 model fields correctly. The `pytest.ini_options` block is added here too so pytest knows where tests live (Sprint 1 will populate `app/tests/`).

- [ ] **Step 2: Verify mypy runs cleanly on empty project**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
poetry run mypy app/ 2>&1 || echo "no app dir yet, expected"
```

Expected: error like `app/: error: Cannot find implementation` because `app/` doesn't exist yet — that's expected. The next task creates it.

---

## Task 17: Create directory scaffolding

**Why:** Spec §5.4 defines the canonical layout. Creating it as empty packages now means Sprint 1 puts files in the right place from the first commit.

**Files:**
- Create: `/Users/anubilegdemberel/Documents/little-signals/backend/app/__init__.py` and 8 sibling package init files

- [ ] **Step 1: Create directory tree**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
mkdir -p app/auth app/routers app/models app/schemas app/services app/db app/observability app/tests
```

- [ ] **Step 2: Create `__init__.py` in each package**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
touch app/__init__.py \
      app/auth/__init__.py \
      app/routers/__init__.py \
      app/models/__init__.py \
      app/schemas/__init__.py \
      app/services/__init__.py \
      app/db/__init__.py \
      app/observability/__init__.py \
      app/tests/__init__.py
```

- [ ] **Step 3: Verify mypy now finds the package**

Run:
```bash
poetry run mypy app/
```

Expected: `Success: no issues found in 9 source files` (or similar count). All `__init__.py` files are empty so there's nothing to type-check, but mypy walks the tree without errors.

- [ ] **Step 4: Verify ruff also walks cleanly**

Run:
```bash
poetry run ruff check app/
```

Expected: `All checks passed!`

---

## Task 18: Create initial Dockerfile

**Why:** Sprint 2 pushes this image to ECR. Multi-stage build keeps the production image small (no Poetry, no dev deps).

**Files:**
- Create: `/Users/anubilegdemberel/Documents/little-signals/backend/Dockerfile`

- [ ] **Step 1: Write Dockerfile**

Create `/Users/anubilegdemberel/Documents/little-signals/backend/Dockerfile`:
```dockerfile
# Stage 1: build dependencies
FROM python:3.12-slim AS builder

ENV POETRY_VERSION=1.8.3 \
    POETRY_HOME=/opt/poetry \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends curl build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="$POETRY_HOME/bin:$PATH"

WORKDIR /app
COPY pyproject.toml poetry.lock ./
RUN poetry install --only main --no-root

# Stage 2: runtime
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash app

WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --chown=app:app app/ ./app/

USER app
EXPOSE 8000

# Sprint 1 will add a real entrypoint; for now this is a placeholder
# that proves the image builds and runs.
CMD ["python", "-c", "print('little-signals backend container — replace CMD in Sprint 1')"]
```

The `curl` in the runtime stage is there so health checks can later be `curl localhost:8000/health` from inside the container. Non-root `app` user is required for ECS Fargate best-practice (and good hygiene anyway).

- [ ] **Step 2: Build the image**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
docker build -t little-signals-backend:0.1.0-sprint0 .
```

Expected: build completes in 1-3 minutes (first time pulls Python image; subsequent builds are cached). Final line shows `Successfully tagged little-signals-backend:0.1.0-sprint0`.

- [ ] **Step 3: Run the container to verify it starts**

Run:
```bash
docker run --rm little-signals-backend:0.1.0-sprint0
```

Expected: prints `little-signals backend container — replace CMD in Sprint 1` and exits 0.

If the build fails, the most common cause is `poetry.lock` being out of sync with `pyproject.toml` — run `poetry lock --no-update` and rebuild.

---

## Task 19: Create docker-compose.yml for local dev stack

**Why:** Sprint 1 needs Postgres on `localhost:5432` and Adminer (web UI) on `localhost:8080` for poking at the DB. `docker compose up` is the standard local-dev command.

**Files:**
- Create: `/Users/anubilegdemberel/Documents/little-signals/backend/docker-compose.yml`

- [ ] **Step 1: Write docker-compose.yml**

Create `/Users/anubilegdemberel/Documents/little-signals/backend/docker-compose.yml`:
```yaml
services:
  postgres:
    image: timescale/timescaledb:latest-pg15
    container_name: little-signals-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: little_signals
      POSTGRES_PASSWORD: dev_only_password
      POSTGRES_DB: little_signals_dev
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U little_signals -d little_signals_dev"]
      interval: 5s
      timeout: 5s
      retries: 5

  adminer:
    image: adminer:4
    container_name: little-signals-adminer
    restart: unless-stopped
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
```

Using the `timescale/timescaledb:latest-pg15` image instead of plain `postgres:15` means the TimescaleDB extension is preinstalled — no manual `CREATE EXTENSION` step needed in local dev. Spec §6.2 and §6.4 require TimescaleDB.

- [ ] **Step 2: Bring the stack up**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals/backend
docker compose up -d
```

Expected: pulls the timescale and adminer images, starts both containers in the background. Output shows `Started` for each.

- [ ] **Step 3: Verify Postgres is reachable**

Run:
```bash
psql "postgresql://little_signals:dev_only_password@localhost:5432/little_signals_dev" -c "SELECT version();"
```

Expected: prints the Postgres version line. If `psql: command not found`, re-check Task 7 Step 3 (PATH).

- [ ] **Step 4: Verify TimescaleDB is available**

Run:
```bash
psql "postgresql://little_signals:dev_only_password@localhost:5432/little_signals_dev" \
  -c "CREATE EXTENSION IF NOT EXISTS timescaledb; SELECT extversion FROM pg_extension WHERE extname='timescaledb';"
```

Expected: prints a TimescaleDB version (e.g. `2.14.2`). Confirms spec §6.2 prerequisite is met locally.

- [ ] **Step 5: Verify Adminer**

Open http://localhost:8080 in a browser. Log in with:
- System: PostgreSQL
- Server: `postgres` (Docker network name) or `host.docker.internal`
- Username: `little_signals`
- Password: `dev_only_password`
- Database: `little_signals_dev`

Expected: Adminer dashboard loads showing the empty database.

- [ ] **Step 6: Tear down (so it's not always running)**

Run:
```bash
docker compose down
```

Expected: containers stop and are removed. The named volume `postgres_data` persists, so data survives across `down`/`up` cycles.

---

## Task 20: [REVISED] Write backend README only (root README belongs to the team)

**Why:** Future-Anu and onboarding engineers need a one-page "how do I run this locally" reference for the backend specifically. The root README is the team's capstone intro page and we don't touch it.

**Original plan task:** wrote both root and backend READMEs. Now backend-only.

**Files:**
- Create: `/Users/anubilegdemberel/Documents/little-signals/backend/README.md`

- [ ] **Step 1: Write backend/README.md**

Create `/Users/anubilegdemberel/Documents/little-signals/backend/README.md`:
```markdown
# little-signals — Backend

FastAPI service for Project Phase. Runs on AWS Seoul (ECS Fargate + RDS Postgres + TimescaleDB) in production. Locally: Docker for Postgres, Poetry for the Python app.

See [`docs/backend-architecture-spec.md`](docs/backend-architecture-spec.md) for the architecture and [`docs/backend-sprint-plan.md`](docs/backend-sprint-plan.md) for the build plan.

## Setup

Prereqs (one-time):
- Python 3.12 via pyenv
- Poetry 1.8+ (Poetry 2.x also works)
- Docker (Colima or Docker Desktop) with Compose v2 plugin
- Postgres 15 client (`psql`)

Install Python deps:
```bash
cd backend
poetry install
```

## Run locally

Bring up Postgres + Adminer:
```bash
docker compose up -d
```

Postgres is on `localhost:5432` (user `little_signals`, password `dev_only_password`, db `little_signals_dev`). Adminer is on http://localhost:8080.

Tear down:
```bash
docker compose down
```

> **Note:** The FastAPI app itself is not yet implemented — Sprint 1 adds `app/main.py` and a working `/health` endpoint. For now this README is forward-looking.

## Run tests

```bash
poetry run pytest
```

(No tests yet — Sprint 1.)

## Lint and type-check

```bash
poetry run ruff check .
poetry run ruff format --check .
poetry run mypy app/
```

## Deploy

Production deployment lives on AWS Seoul (`ap-northeast-2`) via Terraform + ECS Fargate. Sprint 2 wires this up. Until then there is no deploy.

## Sprint status

Currently in **Sprint 0 — Foundation & Verification**. See [`docs/superpowers/plans/`](docs/superpowers/plans/) for the active plan.
```

- [ ] **Step 2: Stage and commit all the scaffolding**

Run:
```bash
cd /Users/anubilegdemberel/Documents/little-signals
git add backend/pyproject.toml backend/poetry.lock backend/Dockerfile backend/docker-compose.yml backend/README.md backend/app/
git commit -m "feat(backend): scaffold Python project, Docker dev stack, package layout"
git push origin sprint-0-foundation
```

Expected: push succeeds onto the `sprint-0-foundation` feature branch (created in Task 9). The commit contains `pyproject.toml`, `poetry.lock`, `Dockerfile`, `docker-compose.yml`, backend `README.md`, and the empty package tree under `app/`.

**Important:** the commit message has NO Co-Authored-By trailer, no Claude mention, no robot emoji. Per project rule.

A PR will be opened against `master` after Sprint 0 is fully complete (DoD verified in Task 23). Don't open the PR yet — Sprint 0 is one logical PR, not many small ones.

---

## Task 21: Save the original SDK package alongside extracted contents

**Why:** The extracted `1.4.1/` directory at `backend/docs/1.4.1/` is in repo. Confirm the spec's claims about the AAR are still verifiable against repo contents.

**Files:**
- Verify: `/Users/anubilegdemberel/Documents/little-signals/backend/docs/1.4.1/libs/samsung-health-sensor-api-1.4.1.aar`

- [ ] **Step 1: Confirm the AAR is present and intact**

Run:
```bash
ls -la /Users/anubilegdemberel/Documents/little-signals/backend/docs/1.4.1/libs/
```

Expected: shows `samsung-health-sensor-api-1.4.1.aar` with non-zero size.

- [ ] **Step 2: Confirm the spec's claimed `HealthTrackerType` enum values exist in the AAR**

The AAR is a zip file containing `classes.jar`, which is also a zip. Run:
```bash
cd /tmp && rm -rf sdk-verify && mkdir sdk-verify && cd sdk-verify
cp /Users/anubilegdemberel/Documents/little-signals/backend/docs/1.4.1/libs/samsung-health-sensor-api-1.4.1.aar ./sensor.aar
unzip -q sensor.aar -d aar-contents
cd aar-contents && unzip -q classes.jar -d classes
find classes -name "HealthTrackerType*"
```

Expected: prints one or more `.class` files matching `HealthTrackerType`. Confirms the enum exists. The spec's Appendix C names the values (PPG_CONTINUOUS, EDA_CONTINUOUS, ACCELEROMETER_CONTINUOUS, HEART_RATE_CONTINUOUS, etc.) — those came from disassembling these class files.

- [ ] **Step 3: (Optional) javap inspection if a JDK is installed**

If `javap` is on the path:
```bash
javap classes/com/samsung/android/service/health/tracking/data/HealthTrackerType.class | head -30
```

Expected: prints the enum constants. If `javap` is not installed, skip — the file existence in Step 2 is sufficient ground-truth.

- [ ] **Step 4: Cleanup**

Run:
```bash
cd /tmp && rm -rf sdk-verify
```

This task does not produce a commit — it's verification that the spec's foundation hasn't drifted from the artifact in repo.

---

## Task 22: [DEFERRED] Block D — SDK hands-on verification

**Status:** BLOCKED.

**Prerequisites (all must be true to unblock):**
1. Galaxy Watch 8 with developer mode enabled and recognized in `adb devices`
2. Samsung or Pixel phone, USB-debug enabled, paired with the watch over Bluetooth
3. Android Studio installed (sprint plan A.8)
4. The "Transfer heart rate from Galaxy Watch to mobile" code lab project bootstrapped in Android Studio with the SDK AAR added as a dependency

**When unblocked, the original sprint plan tasks D.1–D.9 apply verbatim** (see [`backend-sprint-plan.md`](../../backend-sprint-plan.md) Sprint 0 Block D). Briefly:
- D.1: Enable dev mode on watch → confirm in `adb devices`
- D.2: Wear OS project compiles with SDK AAR
- D.3: Heart rate streams to phone via the code lab
- D.4–D.6: Add raw PPG green, EDA, accelerometer streams to logcat
- D.7: Document observed sample rates in `backend/docs/sdk-verification-notes.md`
- D.8: 1-hour wear test, log battery drop
- D.9: Share with Nika so she can confirm sample-rate compatibility

**Decision rule for whether to proceed to Sprint 1 without Block D done:**
Yes — proceed. Backend work in Sprints 1–8 is independent of these empirical verifications. The risks Block D would surface are:
- Sample-rate mismatch with Nika's training data → ML team problem, not backend
- Battery drop unacceptable → Wear OS optimization problem, not backend
- IBI quality too low → ML team problem, not backend
- Bluetooth reliability → Wear OS problem; backend already plans for offline buffering (spec §11.10)

The one scenario where backend would have to change: if hands-on testing reveals the SDK doesn't actually deliver continuous data and we have to switch to polling Health Data SDK aggregates. Direct AAR class inspection (spec Appendix C) makes this very unlikely. Acceptable risk to proceed.

**When this task unblocks**, run it before any further architectural decisions that depend on watch-side data shape (Sprint 5 real-time, Sprint 6 raw biosignal upload).

---

## Task 23: Sprint 0 Definition of Done

Run through the sprint plan's Sprint 0 DoD checklist explicitly. This is verification, not new work.

- [ ] **All laptop tools installed and confirmed working**
  - `python --version` → 3.12.7 (Task 1)
  - `docker run hello-world` → succeeds (Task 2)
  - `aws sts get-caller-identity` → returns `anu-dev` ARN (Task 3)
  - `terraform version` → 1.7.5 (Task 4)
  - `gh auth status` → logged in (Task 5)
  - `poetry --version` → 1.8.x+ (Task 6)
  - `psql --version` → 15.x (Task 7)

- [ ] **GitHub repo exists with branch protection, scaffolded structure, first commit**
  - `gh repo view <username>/little-signals` shows the repo
  - Settings → Branches shows protection on main
  - `git log --oneline` shows at least 3 commits (placeholder, license/readme, scaffold)

- [ ] **`poetry install` works in a fresh clone**
  - Test: `cd /tmp && git clone <repo-url> ls-test && cd ls-test/backend && poetry install`
  - Expected: completes without errors. Then `rm -rf /tmp/ls-test`.

- [ ] **`docker compose up` brings up local Postgres**
  - Test: `cd backend && docker compose up -d && docker compose ps`
  - Expected: both `postgres` and `adminer` show `Up (healthy)`.
  - Tear down: `docker compose down`.

- [ ] **No application code written yet** (this is correct — Sprint 0 is foundation only)
  - `find backend/app -name "*.py" -not -name "__init__.py"` returns no results.

- [ ] **Block D (SDK hands-on) deferred and tracked**
  - Task 22 is documented with prerequisites and an explicit unblock path.

- [ ] **Architecture spec rename and contradictions cleaned**
  - This was done before this plan started (rename, slowapi backend alignment, §10.4 cleanup, §11.6 → §12.6 reference fix). No further action — just confirm the file at `backend/docs/backend-architecture-spec.md` is current.

When every checkbox above is ticked, Sprint 0 is done. Move to Sprint 1.

---

## Risks to watch (this sprint specifically)

- **AWS root account hygiene.** Task 3 creates an IAM user but assumes the AWS account has billing alerts and root MFA already set up. If not, do those before Sprint 2 (sprint plan covers this in Sprint 2 Block A).
- **Homebrew Python conflicts with pyenv.** If `which python` shows `/opt/homebrew/bin/python` after Task 1, the shell init didn't take effect. Re-check `~/.zshrc` order — pyenv init must come *after* Homebrew's PATH adjustments.
- **Docker Desktop license.** Free for personal/portfolio projects; if Anu's setup later involves an employer that needs commercial Docker licensing, switch to OrbStack or Colima. Not a Sprint 0 problem.
- **Branch protection blocking the first push.** Documented in Task 11 Step 4 with the PR fallback.
- **Adminer image security.** Adminer 4 has had CVEs. It's local-dev-only here (never exposed to the internet) so the risk is contained, but don't copy this `docker-compose.yml` into a shared environment.

---

## Out of scope for this sprint (don't do these now)

These belong to later sprints. Resist the urge to start them in Sprint 0:
- Writing any FastAPI route — Sprint 1
- Setting up `.env.example` — Sprint 1
- Pre-commit hooks — Sprint 1 Block E
- Makefile / justfile — Sprint 1 Block D.6
- Alembic init — Sprint 1 Block B.6
- Any AWS resources — Sprint 2
- Sentry / OTEL — Sprint 7

Adding any of these now violates the YAGNI principle and creates work that will need to be redone or moved.

---

*End of Sprint 0 plan.*
