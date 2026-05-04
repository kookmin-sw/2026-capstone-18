# Backend Sprint Plan
## Project Phase — Solo Build with Claude Code

**Status:** v1 sprint plan
**Date:** May 4, 2026
**Author:** Anu (solo backend developer)
**Tooling:** Claude Code as primary AI pair
**Companion to:** `backend-architecture-spec.md` v1.1

---

## How to Read This Document

This plan breaks the entire backend build into **8 sprints**. Each sprint is approximately 2 weeks of focused solo work, but **the plan is not pinned to calendar dates** — you move to the next sprint when the current one's "Definition of Done" is met, not when a date arrives.

Each sprint contains:
- **Sprint goal** — what's true at the end that wasn't true at the start
- **Why this sprint comes here** — why this work, in this order
- **Atomic tasks** — small enough that each is a single Claude Code session or a focused solo block
- **Dependencies** — what must be true before starting, what must be true to finish
- **Definition of Done** — concrete checks you can run
- **Risks to watch** — what tends to go wrong on solo builds at this stage
- **Claude Code usage patterns** — how to use Claude Code effectively for this sprint specifically

The 8 sprints build the backend from empty repository to production deployment with full observability. Some sprints are mostly infrastructure; some are mostly code. The order is deliberate — earlier work unblocks later work.

---

## Solo + Claude Code: Working Patterns That Apply Everywhere

Before the sprints, a few patterns that apply to the whole plan. These are not optional reminders; they're the operating model.

### Pattern 1: Read before you write

For every task, before asking Claude Code to write code, share with it:
- The relevant spec section from `backend-architecture-spec.md`
- The current state of the file you're editing (if any)
- The specific acceptance criteria from this sprint plan

Claude Code without context produces generic code. Claude Code with context produces *your* code.

### Pattern 2: One concern per session

Don't ask Claude Code to "build the auth system." Ask it to "write the JWT verification dependency for FastAPI." Small, atomic prompts produce reviewable, reliable code. Big, vague prompts produce sprawling code that you don't fully understand.

### Pattern 3: Test-first when reasonable

When the task is "implement X," consider asking Claude Code first: "write the test for X based on these acceptance criteria, before implementation." Then implement against the test. This catches a lot of "does this actually do what I want" early.

### Pattern 4: Commit small

End every Claude Code session with a working commit, even if the feature isn't done. A solo developer's worst enemy is a 4-day uncommitted mess. Small commits = ability to back out one mistake without losing a day.

### Pattern 5: When stuck, document the question

If you're stuck and Claude Code isn't unsticking you, write down the actual question — *"why does ECS task fail to pull from ECR even though IAM policy looks right?"* — and search for it. Then try again with the more precise question to Claude Code. Vague stuckness produces vague fixes.

### Pattern 6: Deploy early, deploy often

The first deploy to AWS is the hardest. Do it as early as possible (Sprint 2), even if the app is trivial. Subsequent deploys then become easier. Don't save deployment for the end.

---

## Sprint Map (Overview)

| Sprint | Theme | What's true at end |
|---|---|---|
| **Sprint 0** | Foundation & verification | Working laptop dev environment, SDK verified on Watch 8, repo scaffolded |
| **Sprint 1** | Local API skeleton | FastAPI app runs locally, talks to local Postgres, has `/health` endpoint, structured logging |
| **Sprint 2** | First AWS deploy | Bare FastAPI app deployed to AWS Seoul ECS Fargate, reachable via HTTPS, RDS connected |
| **Sprint 3** | Auth + user model | Anonymous-first JWT flow works end-to-end, Supabase Auth integrated, Google OAuth working |
| **Sprint 4** | Core data endpoints | Stress events + cycle data + settings endpoints all working with full test coverage |
| **Sprint 5** | Real-time + sync | WebSocket channel working, FCM background push integrated, opt-in raw biosignal flow |
| **Sprint 6** | Privacy + audit | E2E encryption for raw biosignals, audit logging, retention jobs, consent management |
| **Sprint 7** | Observability + CI/CD | Sentry, OpenTelemetry, full GitHub Actions pipeline with staging+prod, alerts wired up |
| **Sprint 8** | Hardening + beta-ready | Rate limiting, security audit, load testing, admin endpoints, data export, docs |

---

## Sprint 0 — Foundation & Verification

### Sprint goal
At the end of this sprint, you can build, run, and test code locally on your laptop. The Galaxy Watch 8 has been hands-on verified to expose raw sensor data via the Sensor SDK. The repository exists with a clean scaffolding. Nothing is deployed yet, nothing is fancy. **You're set up to start real work.**

### Why this sprint comes first
Solo developers often skip Sprint 0 and pay for it for weeks. Setting up tooling is unsexy but required. The SDK verification specifically belongs here because if it fails (which we don't expect, but you haven't run it yet), the entire architecture changes — better to find out before any code is written.

### Tasks

**Block A: Local environment setup**

| # | Task | DoD |
|---|---|---|
| A.1 | Install Python 3.12 via pyenv (not system Python) | `python --version` returns 3.12.x |
| A.2 | Install Docker Desktop on Mac, configure with reasonable memory (6GB+) | `docker run hello-world` works |
| A.3 | Install AWS CLI v2, configure with new IAM user `anu-dev` having admin access | `aws sts get-caller-identity` returns the user |
| A.4 | Install Terraform via tfenv, version 1.7+ | `terraform version` works |
| A.5 | Install GitHub CLI (`gh`), authenticate | `gh auth status` shows logged in |
| A.6 | Install poetry (Python dependency manager) | `poetry --version` works |
| A.7 | Install Postgres 15 locally via Homebrew (for local dev when Docker is overkill) | `psql --version` works |
| A.8 | Install Android Studio + Watch 8 USB driver setup | Can see Watch 8 in `adb devices` |

**Block B: GitHub repo + Claude Code setup**

| # | Task | DoD |
|---|---|---|
| B.1 | Create private GitHub repo `project-phase-backend` | Repo exists, you're owner |
| B.2 | Configure branch protection on `main`: require PR, require CI passing (CI doesn't exist yet, but rule is there) | Settings show protection enabled |
| B.3 | Set up Claude Code on your laptop, verify it can read/write to local repo | Run a trivial test prompt and review output |
| B.4 | Clone repo, initialize with `.gitignore`, README skeleton, LICENSE (MIT or Apache 2.0) | First commit landed via PR |
| B.5 | Create `docs/` directory in repo, copy in the architecture spec, PRD, and supplements as reference for Claude Code | Files visible in repo |

**Block C: Repository scaffolding**

| # | Task | DoD |
|---|---|---|
| C.1 | Initialize `pyproject.toml` with poetry, define Python 3.12 | `poetry install` works on empty project |
| C.2 | Add core dependencies: fastapi, uvicorn, sqlalchemy, asyncpg, alembic, pydantic, python-jose, structlog | All install cleanly |
| C.3 | Add dev dependencies: ruff, mypy, pytest, pytest-asyncio, httpx, pytest-cov | All install cleanly |
| C.4 | Configure ruff via `pyproject.toml` with sensible defaults (line length 100, target py312) | `ruff check .` runs (no errors yet because no code) |
| C.5 | Configure mypy with strict settings | `mypy .` runs |
| C.6 | Create the directory structure from spec §5.4 | Directories exist as empty packages with `__init__.py` |
| C.7 | Create initial `Dockerfile` for the FastAPI app (multi-stage build) | `docker build .` succeeds |
| C.8 | Create `docker-compose.yml` for local dev: app + postgres + adminer | `docker compose up` brings up Postgres at localhost:5432 |
| C.9 | Write README skeleton with sections: Setup, Run Locally, Run Tests, Deploy | First useful README committed |

**Block D: Samsung Health Sensor SDK hands-on verification**

This is in Sprint 0 because it determines whether the architecture as designed actually works. If it fails, you need to know now.

| # | Task | DoD |
|---|---|---|
| D.1 | Enable developer mode on Galaxy Watch 8 (Samsung docs walk through this) | Watch shows in `adb devices` |
| D.2 | Open Android Studio, create a Wear OS project, add the Sensor SDK AAR as a dependency | Project compiles |
| D.3 | Run the "Transfer heart rate from Galaxy Watch to mobile" code lab end-to-end | Heart rate appears on a paired phone in real time |
| D.4 | Modify the code lab to also read raw PPG green channel | PPG values stream to logcat |
| D.5 | Modify to read EDA values | EDA values stream to logcat |
| D.6 | Modify to read accelerometer continuous values | Accel x/y/z stream to logcat |
| D.7 | Document observed sample rates per channel in `docs/sdk-verification-notes.md` | File committed with empirical sample rates |
| D.8 | Wear the watch for 1 hour while reading all 4 channels, note battery drop | Battery impact measured |
| D.9 | Share verification results with Nika so she can confirm sample-rate compatibility with her model | Slack/KakaoTalk message sent with the document |

**Definition of Done for Sprint 0**

- [ ] All laptop tools installed and confirmed working
- [ ] GitHub repo exists with branch protection, scaffolded structure, first commit
- [ ] `poetry install` works in a fresh clone
- [ ] `docker compose up` brings up local Postgres
- [ ] Galaxy Watch 8 streams raw HRV/PPG/EDA/accel via SDK to a phone in real time
- [ ] Sample rates documented and shared with Nika
- [ ] No code written yet — that's correct, this sprint is foundation only

### Risks to watch
- **AWS account setup taking longer than expected** if you need to do KYC for new IAM user
- **Watch USB driver issues on Mac** — sometimes requires installing Samsung-specific drivers separately
- **SDK code lab errors** — they're written for older Wear OS versions; you may need to update Gradle/Kotlin versions
- **"I'll just start writing code" temptation** — resist; finish Sprint 0 first

### Claude Code usage this sprint
- Use Claude Code to scaffold the repo structure (`pyproject.toml`, `Dockerfile`, `docker-compose.yml`)
- Use Claude Code to translate the spec §5.4 directory structure into actual directory creation commands
- **Don't yet use Claude Code for the SDK verification** — that's Kotlin/Wear OS work in Android Studio, not Python work; do it yourself with the Samsung code labs as guidance

---

## Sprint 1 — Local API Skeleton

### Sprint goal
A bare FastAPI app runs on your laptop. It connects to a local Postgres database. It has one trivial endpoint (`/health`) and one trivial database model (a User). It logs structured JSON. It runs tests that pass. **You can build → test → run → repeat in under 30 seconds.**

### Why this sprint comes second
Before any AWS work, prove the local development loop works. Solo developers who skip this and try to debug AWS deployment failures with broken local code lose days.

### Tasks

**Block A: FastAPI app entrypoint**

| # | Task | DoD |
|---|---|---|
| A.1 | Create `app/main.py` with minimal FastAPI app | `uvicorn app.main:app --reload` runs |
| A.2 | Create `app/config.py` with Pydantic Settings, env-based config | Settings loaded from `.env` file |
| A.3 | Add `.env.example` with all required env vars (no secrets) | Committed |
| A.4 | Create `/health` endpoint returning `{"status": "ok", "version": "0.1.0"}` | `curl localhost:8000/health` works |
| A.5 | Add OpenAPI metadata (title, description, version) | Swagger UI at `/docs` shows correct info |
| A.6 | Add automatic redirect from `/` to `/docs` for dev convenience | Visiting `/` shows Swagger |

**Block B: Database connection layer**

| # | Task | DoD |
|---|---|---|
| B.1 | Create `app/db/session.py` with async SQLAlchemy 2.0 setup | Module imports without errors |
| B.2 | Create `app/db/base.py` with declarative base class | `Base` exportable |
| B.3 | Add database URL to settings, default to local docker compose Postgres | Settings load DB URL correctly |
| B.4 | Create `app/db/dependencies.py` with FastAPI dependency for DB session | `Depends(get_db)` works in routes |
| B.5 | Create first model in `app/models/user.py` (just id, created_at — minimal) | Model imports cleanly |
| B.6 | Initialize Alembic, configure for async | `alembic init` ran, configuration in repo |
| B.7 | Generate initial migration creating `users` table | Migration file exists |
| B.8 | Run migration against local Postgres | `users` table exists in DB |
| B.9 | Add a temporary endpoint `POST /test/users` that creates a user and returns the ID | Works end-to-end via curl |
| B.10 | Verify the user persists across app restarts | Restart, query DB, user still there |

**Block C: Structured logging**

| # | Task | DoD |
|---|---|---|
| C.1 | Configure `structlog` in `app/observability/logging.py` | Module sets up structlog at import time |
| C.2 | Configure JSON output processor for production-like logs | Logs come out as JSON |
| C.3 | Add request ID middleware that generates UUID per request, attaches to log context | Each request log line has a `request_id` field |
| C.4 | Wire logger into one route, log creation events | Hitting endpoint produces JSON log line |
| C.5 | Add log level config (INFO default, DEBUG via env var) | Setting `LOG_LEVEL=DEBUG` produces more logs |

**Block D: Testing setup**

| # | Task | DoD |
|---|---|---|
| D.1 | Configure pytest with async support, coverage reporting | `pytest` runs (no tests yet) |
| D.2 | Create `tests/conftest.py` with async test client fixture | Fixture works in trivial test |
| D.3 | Create `tests/test_health.py` with one test for the health endpoint | `pytest` shows 1 passing test |
| D.4 | Create test database fixture using docker compose Postgres | DB tests can run |
| D.5 | Write a test for the `POST /test/users` endpoint | Test creates user, checks DB, passes |
| D.6 | Add a Makefile or `justfile` with common commands: `make test`, `make run`, `make lint`, `make migrate` | All commands work |

**Block E: Pre-commit hygiene**

| # | Task | DoD |
|---|---|---|
| E.1 | Configure pre-commit hooks: ruff format, ruff lint, mypy | `pre-commit install` works |
| E.2 | Run `pre-commit run --all-files` on the repo, fix any issues | Clean run |
| E.3 | Configure VS Code settings (or your editor) for ruff format on save | Editor formats on save |

**Definition of Done for Sprint 1**

- [ ] `make run` brings up FastAPI app on `localhost:8000`
- [ ] `curl localhost:8000/health` returns 200 with JSON
- [ ] Visiting `/docs` shows Swagger UI with the health endpoint
- [ ] `make test` runs and passes at least 2 tests
- [ ] `make lint` passes with no warnings
- [ ] Logs come out as JSON
- [ ] Local Postgres has a `users` table
- [ ] Pre-commit hooks block commits with style violations

### Risks to watch
- **SQLAlchemy 2.0 async syntax confusion** — it changed significantly from 1.x; make sure Claude Code is using the new syntax
- **Pydantic v2 vs v1 confusion** — same problem; v2 is the current standard
- **Mixing sync and async DB access** — keep everything async to avoid deadlocks

### Claude Code usage this sprint
- Have Claude Code generate the initial FastAPI skeleton, but **review every line yourself** — this code becomes load-bearing
- Use Claude Code to write the first test, then ask "based on this test pattern, give me a template for future endpoint tests"
- When stuck on async SQLAlchemy syntax, ask Claude Code to show you working examples — async patterns are where most beginners trip

---

## Sprint 2 — First AWS Deploy

### Sprint goal
The same FastAPI app from Sprint 1 is now deployed to AWS Seoul. It runs on ECS Fargate. It connects to RDS Postgres. It's reachable via HTTPS at a real domain. The deployment is reproducible — you could destroy everything and rebuild it from Terraform in 30 minutes. **You've gone from local-only to "real internet endpoint" without writing more application code.**

### Why this sprint comes third
Deploy early. The first AWS deploy is the hardest deploy you'll ever do on the project. Doing it on a trivial app means the bugs you hit are AWS bugs, not "is my code broken or is AWS broken" bugs. After this, every subsequent deploy is easy.

### Tasks

**Block A: AWS account preparation**

| # | Task | DoD |
|---|---|---|
| A.1 | Set up AWS Organizations if not already (separate billing account from personal) | Multi-account structure exists |
| A.2 | Create dedicated AWS account for Project Phase, OR use existing with naming convention | Account selected |
| A.3 | Set up billing alerts at $50, $100, $200 thresholds | Alerts configured in AWS Budgets |
| A.4 | Enable CloudTrail for audit logging | CloudTrail logging to S3 |
| A.5 | Set up MFA on root account, lock root credentials | Root has MFA, you don't use root for anything |
| A.6 | Create dedicated IAM user `terraform-deploy` with programmatic access | Access key + secret obtained |

**Block B: Terraform foundation**

| # | Task | DoD |
|---|---|---|
| B.1 | Create `infra/` directory in repo | Exists |
| B.2 | Create S3 bucket for Terraform state (separate from app data) | Bucket exists in Seoul region |
| B.3 | Create DynamoDB table for state locking | Table exists |
| B.4 | Configure S3 backend in `infra/backend.tf` | Backend block correct |
| B.5 | Configure AWS provider in `infra/providers.tf` with Seoul region | Provider configured |
| B.6 | Create `infra/variables.tf` with environment variable, tags | Variables defined |
| B.7 | Run `terraform init`, verify state stored in S3 | `terraform init` succeeds |

**Block C: Networking layer (VPC, subnets, security)**

| # | Task | DoD |
|---|---|---|
| C.1 | Define VPC in `infra/networking.tf`: 3 AZs, /16 CIDR | VPC plan looks right |
| C.2 | Define 3 public subnets (one per AZ) for ALB | Subnets defined |
| C.3 | Define 3 private subnets (one per AZ) for ECS + RDS | Private subnets defined |
| C.4 | Define internet gateway for public subnets | IGW defined |
| C.5 | Define single NAT gateway in one public subnet (cost optimization) | NAT defined |
| C.6 | Define route tables for public and private subnets | Route tables correct |
| C.7 | Define security group for ALB (allow 443 from internet) | SG exists |
| C.8 | Define security group for ECS tasks (allow from ALB SG only) | SG exists |
| C.9 | Define security group for RDS (allow from ECS SG only) | SG exists |
| C.10 | Run `terraform plan`, review output carefully | Plan creates resources sensibly |
| C.11 | Run `terraform apply`, networking exists | All resources visible in AWS console |

**Block D: Container registry + initial deploy**

| # | Task | DoD |
|---|---|---|
| D.1 | Define ECR repository in `infra/ecr.tf` | ECR repo exists |
| D.2 | Build Docker image locally | `docker build .` succeeds |
| D.3 | Tag image with `0.1.0` and `latest` | Tags applied |
| D.4 | Authenticate Docker to ECR via AWS CLI | `docker login` to ECR succeeds |
| D.5 | Push image to ECR | Image visible in ECR console |

**Block E: RDS Postgres + TimescaleDB**

| # | Task | DoD |
|---|---|---|
| E.1 | Define DB subnet group in `infra/rds.tf` | Subnet group covers private subnets |
| E.2 | Define RDS parameter group with TimescaleDB shared_preload_libraries | Parameter group correct |
| E.3 | Define RDS instance: db.t4g.small Postgres 15, multi-AZ off (cost), encryption on | Instance defined |
| E.4 | Master password stored in AWS Secrets Manager (define separately) | Secret exists |
| E.5 | RDS instance reads password from Secrets Manager | Database created |
| E.6 | Run `terraform apply`, RDS instance up | Instance visible, status "available" |
| E.7 | Create temporary EC2 bastion host or use Session Manager to connect to RDS | Can `psql` to RDS |
| E.8 | Install TimescaleDB extension manually: `CREATE EXTENSION IF NOT EXISTS timescaledb` | Extension installed |
| E.9 | Run Alembic migration against RDS | `users` table exists in RDS |

**Block F: ECS Fargate service**

| # | Task | DoD |
|---|---|---|
| F.1 | Define ECS cluster in `infra/ecs.tf` | Cluster exists |
| F.2 | Define IAM role for ECS task execution (pull from ECR, write logs) | Role exists |
| F.3 | Define IAM role for ECS task itself (read Secrets Manager only) | Role exists |
| F.4 | Define CloudWatch log group for the service | Log group exists |
| F.5 | Define ECS task definition: image URI, env vars, secrets refs, log config | Task def registered |
| F.6 | Define ECS service: 1 task, runs in private subnets | Service running |
| F.7 | Verify task starts and stays running | ECS console shows healthy task |
| F.8 | Check CloudWatch logs — see app logs | Logs visible |

**Block G: Application Load Balancer + HTTPS**

| # | Task | DoD |
|---|---|---|
| G.1 | Buy or use existing domain (e.g., `projectphase.app`) | Domain available |
| G.2 | Create Route 53 hosted zone | Zone exists |
| G.3 | If domain registered elsewhere, update nameservers to Route 53 | DNS resolves |
| G.4 | Request ACM certificate for `*.projectphase.app` (DNS validation) | Cert issued |
| G.5 | Define ALB in `infra/alb.tf` | ALB exists |
| G.6 | Define target group for ECS service | Target group exists |
| G.7 | Define ALB listener on 443 with cert | Listener active |
| G.8 | Define listener on 80 redirecting to 443 | Redirect works |
| G.9 | Update ECS service to register tasks in target group | Tasks healthy in TG |
| G.10 | Define Route 53 A record (alias) for `api-staging.projectphase.app` → ALB | Domain resolves |
| G.11 | Test: `curl https://api-staging.projectphase.app/health` | Returns 200 |

**Block H: Documentation**

| # | Task | DoD |
|---|---|---|
| H.1 | Update README with deploy instructions | Step-by-step correct |
| H.2 | Document Terraform plan/apply workflow in `infra/README.md` | Future-you can follow it |
| H.3 | Document how to connect to RDS via Session Manager | Steps clear |

**Definition of Done for Sprint 2**

- [ ] `curl https://api-staging.projectphase.app/health` returns 200 with the JSON from your local app
- [ ] Logs from the ECS task appear in CloudWatch
- [ ] You can `terraform destroy` and `terraform apply` and rebuild everything
- [ ] RDS instance is reachable from ECS, not from internet
- [ ] No secrets in code; all in Secrets Manager
- [ ] AWS billing dashboard shows expected resources, no surprises

### Risks to watch
- **NAT Gateway cost surprise** — $33/month minimum just for the NAT. Make sure you understand this is the real cost before deploying.
- **ECR push permission errors** — IAM is unforgiving here. The `docker login` step often fails on first attempt.
- **RDS in private subnet feels stuck** — you can't `psql` from your laptop. Use Session Manager or a temporary bastion. Don't try to make RDS public.
- **DNS propagation delays** — once Route 53 is set, can take up to an hour for global DNS to propagate. Don't think it's broken if it doesn't work in 5 minutes.
- **Spending $5–15 in this sprint just on AWS resources** — this is normal and expected.

### Claude Code usage this sprint
- Use Claude Code heavily for **Terraform** — it's a domain where Claude Code is genuinely strong, knows the patterns, and you can iterate quickly
- Have Claude Code review your Terraform plan output before applying ("does this plan make sense for the goals I described?")
- Use Claude Code to draft the IAM policies, but **carefully review** — IAM is the most security-sensitive area and over-permissive policies are a real risk

---

## Sprint 3 — Auth + User Model

### Sprint goal
A user can use the app anonymously (gets a JWT, all data tied to anon ID), and convert to a registered account via Google OAuth without losing data. JWT verification works on every protected endpoint. **The full anonymous-first identity model is functional end-to-end.**

### Why this sprint comes fourth
Auth is the foundation for every other endpoint. Until it works, nothing can be properly protected, and you can't write the "for the current user, do X" patterns that all subsequent endpoints need.

### Tasks

**Block A: Supabase project setup**

| # | Task | DoD |
|---|---|---|
| A.1 | Create Supabase project (free tier, choose closest region — Seoul if available, else Tokyo) | Project exists |
| A.2 | Configure Supabase Auth: enable email, Google, Apple providers | Settings saved |
| A.3 | Configure Google OAuth in Google Cloud Console (separate from your AWS account) | OAuth client created |
| A.4 | Configure Apple Sign In credentials (deferred to v2 build but configure the placeholder) | Apple developer team set up if you have one |
| A.5 | Note Supabase project URL, anon key, JWT secret | Stored in password manager |
| A.6 | Add Supabase secrets to AWS Secrets Manager | Secrets added |
| A.7 | Update ECS task definition to inject Supabase env vars | New task definition deployed |

**Block B: User model expansion**

| # | Task | DoD |
|---|---|---|
| B.1 | Expand `User` model with all fields from spec §6.3 | Model matches spec |
| B.2 | Add `UserSettings` model with fields from spec §6.3 | Model exists |
| B.3 | Generate Alembic migration for the changes | Migration generated |
| B.4 | Apply migration to local DB and to staging RDS | Both schemas updated |
| B.5 | Write unit tests for model relationships | Tests pass |

**Block C: JWT verification dependency**

| # | Task | DoD |
|---|---|---|
| C.1 | Create `app/auth/jwt.py` with JWT verification using `python-jose` | Module imports |
| C.2 | Fetch Supabase JWKS at startup, cache in memory | Caching works |
| C.3 | Implement `verify_jwt(token: str) -> dict` that validates signature, claims, expiry | Returns claims dict on valid, raises on invalid |
| C.4 | Create FastAPI dependency `get_current_user_id(request) -> UUID` | Returns user ID from valid JWT |
| C.5 | Create dependency `get_current_user(db, user_id) -> User` | Returns User from DB |
| C.6 | Create dependency `require_admin(user: User) -> User` | Raises 403 if not admin |
| C.7 | Write tests with mock JWTs (signed with test key) | Tests cover valid, expired, malformed, wrong issuer |

**Block D: Anonymous auth flow**

| # | Task | DoD |
|---|---|---|
| D.1 | Create `POST /api/v1/auth/anon` endpoint | Endpoint exists |
| D.2 | Endpoint creates a new user with anon_id (UUID), supabase_user_id NULL | User created in DB |
| D.3 | Endpoint mints a JWT (using Supabase admin API or self-signed if Supabase doesn't support anon) | JWT returned |
| D.4 | Test: hit endpoint, get JWT, decode it, see anon_id | Test passes |
| D.5 | Verify: same anon JWT can hit a protected endpoint | Test passes |

*Decision check during this block:* Supabase Auth's "anonymous" sign-in is a real feature in their newer versions. Check whether to use that or implement custom anonymous JWT issuance. Document the choice in `docs/auth-decisions.md`.

**Block E: Google OAuth conversion flow**

| # | Task | DoD |
|---|---|---|
| E.1 | Create `POST /api/v1/auth/google` endpoint accepting `id_token` from client | Endpoint exists |
| E.2 | Verify Google ID token using Google's public keys | Verification works |
| E.3 | Extract email and Google sub from verified token | Extraction works |
| E.4 | Check if user already exists with this Google ID | Lookup logic correct |
| E.5 | If not, and there's a current anon JWT in the request, MIGRATE: link supabase_user_id to anon user | Migration logic works |
| E.6 | If yes, return error (account already exists) — TBD: should this just log them in instead? | Logic decided and documented |
| E.7 | Mint new JWT with full registered user claims | New JWT returned |
| E.8 | Write tests covering: new user, existing user, anon-to-registered migration | Tests pass |

**Block F: Account management endpoints**

| # | Task | DoD |
|---|---|---|
| F.1 | Create `POST /api/v1/auth/refresh` endpoint | Refresh works |
| F.2 | Create `POST /api/v1/auth/logout` (revoke session) | Logout works |
| F.3 | Create `DELETE /api/v1/account` (initiate deletion with 30-day grace) | Sets `deleted_at`, doesn't actually delete data |
| F.4 | Create `POST /api/v1/account/restore` (cancel deletion within grace) | Restore works |
| F.5 | All of these have full test coverage | Tests pass |

**Block G: Authorization patterns**

| # | Task | DoD |
|---|---|---|
| G.1 | Create a protected test endpoint `GET /api/v1/me` returning current user | Returns user info for valid JWT |
| G.2 | Verify it returns 401 with no token, 401 with bad token, 200 with good token | All three tested |
| G.3 | Document the auth dependency pattern for future endpoints | `docs/auth-patterns.md` written |

**Definition of Done for Sprint 3**

- [ ] `POST /auth/anon` returns a JWT for a new anonymous user
- [ ] That JWT can be used to hit `/me` and get user info
- [ ] `POST /auth/google` with a real Google ID token creates a registered user (or migrates existing anon)
- [ ] Account deletion sets a flag but data persists (30-day grace)
- [ ] All auth endpoints have ≥80% test coverage
- [ ] Auth pattern is documented for use in future sprints

### Risks to watch
- **JWT validation footguns** — wrong audience, wrong issuer, expired tokens. These produce confusing errors. Test all the edge cases.
- **Google OAuth client secret leaking** — never put it in code. Always Secrets Manager.
- **Migrating anon → registered without losing data** — the test for this is critical. If it fails silently, real users lose data.
- **Supabase regional latency** — if Supabase doesn't have Seoul, your auth calls go to Tokyo. Latency is fine but worth measuring.

### Claude Code usage this sprint
- Auth is exactly where Claude Code's strict-correctness matters most. Be explicit: "write the JWT verification code that handles these specific failure cases: invalid signature, expired, wrong issuer, malformed token."
- Have Claude Code write the tests *first* for auth flows, then implement against them.
- For Google OAuth specifically, ask Claude Code for the modern (2024+) approach — older OAuth patterns are deprecated.

---

## Sprint 4 — Core Data Endpoints

### Sprint goal
The three core resource families — stress events, cycle data, settings — are fully functional. Each has CRUD endpoints, all protected by auth, all backed by the database, all with test coverage. **A real user could (in theory) use the API to live the entire core product loop.**

### Why this sprint comes fifth
With auth working, the rest of the API follows a pattern. Build the patterns once on the highest-value endpoints. Each subsequent sprint refines or extends, but the basics are here.

### Tasks

**Block A: Stress events**

| # | Task | DoD |
|---|---|---|
| A.1 | Create `StressEvent` model per spec §6.3 | Model exists |
| A.2 | Convert `stress_events` table to TimescaleDB hypertable in migration | `create_hypertable` ran |
| A.3 | Create Pydantic schemas: `StressEventCreate`, `StressEventResponse`, `StressEventUpdate`, `StressEventFilter` | Schemas exist |
| A.4 | Create `POST /api/v1/events` endpoint | Creates event, returns 201 |
| A.5 | Validate ownership: user can only create events tied to their own user_id | Test confirms this |
| A.6 | Create `GET /api/v1/events` with filters: date range, logged status, cycle phase, chip categories | All filters work |
| A.7 | Implement pagination (cursor-based using `detected_at`) | Works for >100 events |
| A.8 | Create `GET /api/v1/events/{id}` | Returns single event |
| A.9 | Create `PATCH /api/v1/events/{id}` for adding logs after the fact | Late logging works |
| A.10 | Create `DELETE /api/v1/events/{id}` | Deletes event |
| A.11 | All endpoints respect ownership (user can only access their own events) | Tests verify this |
| A.12 | Tests for happy path + edge cases for each endpoint | ≥85% coverage |

**Block B: Cycle data**

| # | Task | DoD |
|---|---|---|
| B.1 | Create `Cycle` model per spec §6.3 | Model exists |
| B.2 | Schemas: `CyclePeriodStart`, `CycleResponse`, `CycleUpdate`, `CycleImport` | Schemas exist |
| B.3 | Create `POST /api/v1/cycles/period-start` (manual or auto-detected flag) | Period logging works |
| B.4 | Create `GET /api/v1/cycles/current` (current phase + day calculation) | Phase math correct |
| B.5 | Create `GET /api/v1/cycles/history` | Returns past cycles |
| B.6 | Create `PATCH /api/v1/cycles/{id}` for corrections | Override works |
| B.7 | Phase calculation utility: given today + period_start_date + cycle_length, return phase + day | Pure function tested |
| B.8 | Tests including phase calculation edge cases (irregular cycles, missing data) | ≥85% coverage |

**Block C: Settings**

| # | Task | DoD |
|---|---|---|
| C.1 | Schemas: `UserSettingsResponse`, `UserSettingsUpdate` | Schemas exist |
| C.2 | Create `GET /api/v1/settings` | Returns current settings |
| C.3 | Create `PATCH /api/v1/settings` | Updates settings |
| C.4 | When user is created, default settings row is created | Verified in test |
| C.5 | Validation: notification cap 1–10, threshold 0.0–1.0, etc. | Bad inputs rejected |
| C.6 | Tests | ≥85% coverage |

**Block D: Consent management**

| # | Task | DoD |
|---|---|---|
| D.1 | Schemas: `ConsentResponse`, `ConsentUpdate` (with granular per-channel raw biosignal toggles) | Schemas exist |
| D.2 | Create `GET /api/v1/consent` | Returns current consent state |
| D.3 | Create `PATCH /api/v1/consent` | Updates consent |
| D.4 | When user revokes raw biosignal consent, schedule deletion of accumulated raw data (Sprint 6 will implement the actual deletion) | At minimum, mark a flag |
| D.5 | Tests | ≥85% coverage |

**Block E: Cross-cutting concerns**

| # | Task | DoD |
|---|---|---|
| E.1 | Define standard error response schema | Schema exists |
| E.2 | Add exception handlers for common cases (404, 403, 422) | Consistent error responses |
| E.3 | Add request validation logging (log when Pydantic rejects a request) | Logs visible |
| E.4 | Verify OpenAPI spec at `/docs` covers all endpoints with examples | Swagger looks polished |
| E.5 | Run all tests, generate coverage report | ≥85% on new code |

**Block F: Deploy and smoke test**

| # | Task | DoD |
|---|---|---|
| F.1 | Build new image, push to ECR with tag `0.4.0` | Image in ECR |
| F.2 | Update ECS task definition (still manual at this point) | New task running |
| F.3 | Run smoke tests against staging: create user via anon auth, log event, log period, retrieve all | All work |
| F.4 | Verify CloudWatch logs show structured logs for all operations | Logs look right |

**Definition of Done for Sprint 4**

- [ ] All endpoints from spec Appendix B sections "Events," "Cycles," "Settings," "Consent" exist
- [ ] All endpoints are auth-protected
- [ ] All endpoints respect ownership
- [ ] OpenAPI spec at `/docs` is complete and renders well
- [ ] Tests cover ≥85% of new code
- [ ] Smoke tests pass against staging deployment

### Risks to watch
- **Phase calculation bugs** — cycle phase math is surprisingly tricky. Edge cases: cycle hasn't started yet, last cycle was incomplete, irregular intervals. Test thoroughly.
- **N+1 query problems** — when listing events, make sure you're not making one DB query per event.
- **Forgetting ownership checks** — easy to write `GET /events/{id}` that returns *anyone's* event. Test that user A can't read user B's data.
- **Hypertable issues** — TimescaleDB hypertables behave slightly differently than regular tables in some SQLAlchemy operations. Test inserts work.

### Claude Code usage this sprint
- This is a sprint where Claude Code can produce code very fast — use it for the boilerplate (Pydantic schemas, basic CRUD)
- Be careful with ownership checks — review every endpoint that accepts an ID parameter and confirm the ownership check is there
- Use Claude Code to write parameterized tests for filter combinations (it's great at "give me 8 test cases covering these combinations")

---

## Sprint 5 — Real-Time + Sync

### Sprint goal
The phone can connect to the backend via WebSocket for real-time push when in foreground, and receive FCM push notifications when in background. Opt-in raw biosignal upload works end-to-end with encrypted blobs in S3. **The watch → phone → backend → other devices loop is functional.**

### Why this sprint comes sixth
This is where the architecture gets interesting and where the highest-leverage portfolio surface lives. WebSocket + FCM hybrid is a real Android engineering pattern, not a tutorial pattern.

### Tasks

**Block A: WebSocket endpoint**

| # | Task | DoD |
|---|---|---|
| A.1 | Create `app/routers/realtime.py` with WebSocket endpoint at `/ws/realtime` | Endpoint exists |
| A.2 | Authenticate on connect: extract JWT from query string, validate, reject if invalid | Bad JWT closes with 1008 |
| A.3 | Maintain connection registry in Postgres (user_id → set of connection IDs) | Registry table created |
| A.4 | On connect, register connection | Visible in DB |
| A.5 | On disconnect, unregister | Cleaned up |
| A.6 | Implement heartbeat (ping/pong every 30 sec) | Heartbeat works |
| A.7 | Implement message types from spec §10: event.created, event.updated, etc. | All defined |
| A.8 | Implement broadcast helper: given user_id and message, send to all their connections | Helper works |
| A.9 | Wire stress event creation to broadcast event.created via WebSocket | Real-time push works |
| A.10 | Test with two simulated connections (multi-device case) | Both receive |

**Block B: Connection registry hygiene**

| # | Task | DoD |
|---|---|---|
| B.1 | Add cleanup job: connections idle >5 min get marked stale, force-disconnected | Job logic exists |
| B.2 | Add periodic vacuum: stale rows deleted from registry | Cleanup works |
| B.3 | Handle ECS task restarts: on startup, app clears its own connection rows | No stale connections after restart |

**Block C: Firebase Cloud Messaging integration**

| # | Task | DoD |
|---|---|---|
| C.1 | Create Firebase project, configure Android app | Firebase project exists |
| C.2 | Generate FCM service account credentials | JSON file obtained |
| C.3 | Store credentials in AWS Secrets Manager | Secret created |
| C.4 | Add `firebase-admin` to dependencies | Installed |
| C.5 | Initialize Firebase Admin SDK at app startup | Initializes cleanly |
| C.6 | Create `FCMTokens` model: user_id, fcm_token, platform, last_seen | Model exists |
| C.7 | Create `POST /api/v1/devices/fcm-token` for phone to register its token | Endpoint works |
| C.8 | Create helper: `send_fcm_to_user(user_id, payload)` | Helper works |
| C.9 | Test: register a token, trigger a send, verify delivery in Firebase console | Works |

**Block D: WebSocket vs FCM routing logic**

| # | Task | DoD |
|---|---|---|
| D.1 | Create `notification_service.py` with `notify_user(user_id, event)` function | Service exists |
| D.2 | Logic: if user has active WebSocket → send via WebSocket; else send via FCM | Routing works |
| D.3 | Wire all event-creating endpoints to use this service | Replaces direct broadcast |
| D.4 | Test with two scenarios: connected user (WS) and disconnected user (FCM) | Both work |

**Block E: Sync endpoints (encrypted backup)**

| # | Task | DoD |
|---|---|---|
| E.1 | Create S3 bucket for backups in Seoul region (defined in Terraform) | Bucket exists |
| E.2 | Configure bucket: SSE-KMS encryption, versioning enabled, public access blocked | Settings correct |
| E.3 | Create `POST /api/v1/sync/upload` accepting encrypted blob and metadata | Endpoint exists |
| E.4 | Generate presigned URLs for direct client → S3 upload (avoids backend bandwidth) | Presigned URL works |
| E.5 | Backend stores S3 object key + metadata in DB | Reference saved |
| E.6 | Create `GET /api/v1/sync/download` returning presigned download URL | Works |
| E.7 | Create `DELETE /api/v1/sync` (delete all user backups) | Works |
| E.8 | Tests | ≥80% coverage |

**Block F: Opt-in raw biosignal upload**

| # | Task | DoD |
|---|---|---|
| F.1 | Create `RawBiosignalUpload` model | Exists |
| F.2 | Convert to hypertable | Done |
| F.3 | Create `POST /api/v1/sync/biosignals` with consent check | Rejects if consent off |
| F.4 | Use presigned URL pattern for direct phone → S3 upload | Works |
| F.5 | Backend never sees plaintext (only object key + metadata) | Verified by inspection |
| F.6 | When user revokes consent, mark uploads as pending-deletion | Logic correct |
| F.7 | Tests | ≥80% coverage |

**Block G: Smoke test the whole real-time loop**

| # | Task | DoD |
|---|---|---|
| G.1 | Write a test script: simulate two clients (e.g., websockets-cli) | Script exists |
| G.2 | Client A creates an event via REST | Created |
| G.3 | Client B (same user, on WebSocket) receives the event in real time | Received |
| G.4 | Client B disconnects, Client A creates another event, FCM delivery logged | Logged |

**Definition of Done for Sprint 5**

- [ ] WebSocket connection authenticated, registered, heartbeated, cleaned up
- [ ] Real-time event push works between two simulated devices
- [ ] FCM push works when WebSocket isn't available
- [ ] Encrypted backup upload via presigned S3 URLs works
- [ ] Opt-in raw biosignal flow blocked without consent, works with consent
- [ ] All deployed to staging and smoke-tested

### Risks to watch
- **WebSocket scaling on Fargate** — single ECS task can hold a few thousand WebSockets. Monitor connections per task.
- **Firebase Admin SDK initialization in async context** — sometimes needs special handling. Test in async path.
- **Presigned URL expiry timing** — if too short, mobile uploads fail on slow networks. Default to 1 hour.
- **S3 bucket misconfiguration** — public access *anywhere* in this bucket is a critical security issue.

### Claude Code usage this sprint
- WebSocket auth via query string is a specific pattern. Ask Claude Code for the FastAPI pattern explicitly.
- Presigned URL generation is well-documented. Have Claude Code show you the boto3 example.
- The notification routing logic (WebSocket vs FCM) is a pattern Claude Code has seen many times — leverage that.

---

## Sprint 6 — Privacy + Audit

### Sprint goal
The privacy architecture that's currently described in the spec actually exists in code. Audit logging captures every consent change. Retention jobs auto-purge old data. User-held key encryption for raw biosignals is verified end-to-end. **The privacy story you can tell about the product is true at the code level.**

### Why this sprint comes seventh
You can't ship without this. PIPA compliance, post-Flo trust, and capstone-grade privacy all require this work. It's also the most distinctive engineering on the project — every other backend has CRUD; few have proper audit + retention + E2E.

### Tasks

**Block A: Audit logging**

| # | Task | DoD |
|---|---|---|
| A.1 | Create `AuditLog` model per spec §6.3 | Model exists |
| A.2 | Convert to hypertable | Done |
| A.3 | Create `audit_service.py` with `log_event(user_id, action, resource_type, resource_id, metadata)` | Helper exists |
| A.4 | Wire helper into events: consent change, data access (admin only), account deletion, export | All wired |
| A.5 | Make audit log append-only at DB level (deny DELETE/UPDATE on the table for app role) | Permissions enforced |
| A.6 | Add scheduled integrity check (Sprint 8 will wire this up properly) | Stub function exists |
| A.7 | Tests verifying every protected action writes an audit log | All pass |

**Block B: User-held key encryption (server-side support)**

| # | Task | DoD |
|---|---|---|
| B.1 | Document the encryption protocol clearly: client uses XChaCha20-Poly1305 with user-derived key | `docs/encryption-protocol.md` written |
| B.2 | Backend stores only: ciphertext blob ref (S3 key), nonce (in metadata), version | Schema correct |
| B.3 | Verify backend never has access to encryption key (only client + Android Keystore) | Architecture verified |
| B.4 | Build a test client (Python) that encrypts a blob, uploads, downloads, decrypts | End-to-end works |
| B.5 | Confirm S3 contents are unreadable without key | Manual test |

**Block C: Application-layer encryption for sensitive fields**

| # | Task | DoD |
|---|---|---|
| C.1 | Define which fields need extra app-layer encryption (free-text logs primarily) | List in `docs/data-classification.md` |
| C.2 | Create AWS KMS key for app-layer envelope encryption | Key exists |
| C.3 | Create `crypto_service.py` with `encrypt_field(plaintext) -> ciphertext` and reverse | Functions exist |
| C.4 | Use SQLAlchemy TypeDecorator for transparent encryption on the `log_text` column | Field encrypted at rest |
| C.5 | Verify: query DB directly, see ciphertext; via app, see plaintext | Behavior correct |
| C.6 | Tests | ≥80% coverage |

**Block D: Retention policies**

| # | Task | DoD |
|---|---|---|
| D.1 | Document retention table from spec §12.6 in code as constants | Constants in `app/config/retention.py` |
| D.2 | Create Lambda functions in Terraform for each retention job:
- Purge raw biosignals older than 12 months
- Permanent delete of accounts past 30-day grace
- Audit log archival (>24 months) | Lambdas defined |
| D.3 | Create EventBridge rules to schedule each Lambda daily at 03:00 Seoul | Rules defined |
| D.4 | IAM roles for Lambdas with least privilege (read DB, delete specific S3 prefixes) | Roles correct |
| D.5 | Test each Lambda manually before scheduling | All work |
| D.6 | CloudWatch alarms if any Lambda fails | Alarms wired |

**Block E: Account deletion completion**

| # | Task | DoD |
|---|---|---|
| E.1 | Lambda: find users with `deleted_at` > 30 days ago | Query correct |
| E.2 | Lambda: cascade delete all user data:
- stress_events, cycles, insights, settings, audit_log entries (after copy)
- raw biosignal S3 blobs
- backup S3 blobs
- FCM tokens, sync records | All cleaned up |
| E.3 | Audit log entries for that user MOVED to a separate `archived_audit_log` (long-term retention) | Archive works |
| E.4 | Test: simulate user deletion, run job, verify total wipeout | Verified |

**Block F: Data export**

| # | Task | DoD |
|---|---|---|
| F.1 | Create `POST /api/v1/account/export` endpoint | Endpoint exists |
| F.2 | Generates JSON export of all user data | Export complete |
| F.3 | Optional CSV export | CSV works |
| F.4 | Stores export in S3, returns presigned download URL valid 24h | Works |
| F.5 | Audit log entry created | Entry exists |
| F.6 | Tests | ≥80% coverage |

**Block G: PIPA compliance documentation**

| # | Task | DoD |
|---|---|---|
| G.1 | Draft Korean-language privacy policy (placeholder, will need legal review) | Draft committed |
| G.2 | Subprocessor list documented | List complete |
| G.3 | Data flow diagram: where data lives, who can access | Diagram in `docs/pipa-compliance.md` |
| G.4 | DPIA-lite: Data Protection Impact Assessment for sensitive data | Document committed |

**Definition of Done for Sprint 6**

- [ ] Every consent change creates an audit log entry
- [ ] DELETE on `audit_log` is denied at DB role level
- [ ] User-held key encryption works end-to-end (test client proves it)
- [ ] Free-text log fields are encrypted at rest (verified by direct DB query)
- [ ] All retention Lambdas exist, are scheduled, and tested
- [ ] User can export full data as JSON or CSV
- [ ] Account deletion past grace period actually removes all data

### Risks to watch
- **Encryption mistakes are silent until disaster** — test that the encrypted form really is opaque and that decryption really works for known plaintexts.
- **Cascade deletion missing tables** — every time a new model is added later, you need to add it to the deletion logic. Document this clearly.
- **Lambda IAM over-permission** — easy to give Lambda * permissions. Don't.
- **Privacy policy claims vs reality drift** — if the policy says "we delete data within 30 days" and the Lambda doesn't run, you're lying. Wire alarms.

### Claude Code usage this sprint
- Crypto code is exactly where you should NOT trust Claude Code blindly. Use it to draft, then review carefully against known-good references.
- For Lambda + EventBridge + IAM, Claude Code is genuinely strong. Use freely.
- The privacy policy draft can be done with Claude Code as a starting point but needs human and legal review.

---

## Sprint 7 — Observability + CI/CD

### Sprint goal
The full senior-engineering observability stack is wired and working: structured logs in CloudWatch, errors in Sentry, distributed tracing in X-Ray, metrics in CloudWatch + Prometheus. Every commit runs through CI; merges to main deploy to staging automatically; production deploys require manual approval. **You can deploy with confidence and debug production issues without SSH.**

### Why this sprint comes eighth
Observability is most valuable once there's enough surface area to observe. Doing it last would be wrong (you'd lose data from the build), but doing it first would be premature (no tracing usefulness without endpoints). After Sprint 6, the system is rich enough that observability adds real value.

### Tasks

**Block A: Sentry integration**

| # | Task | DoD |
|---|---|---|
| A.1 | Create Sentry account, set up project for Project Phase | Project exists |
| A.2 | Get DSN, store in Secrets Manager | Stored |
| A.3 | Add `sentry-sdk[fastapi]` to dependencies | Installed |
| A.4 | Initialize Sentry SDK in `app/main.py` with FastAPI integration | Configured |
| A.5 | Configure: capture user_id (anonymized), trace_id, environment | Captured correctly |
| A.6 | Configure: scrub PII (free text logs, emails) from event data | Verified |
| A.7 | Test: trigger an exception in staging, verify it appears in Sentry | Works |
| A.8 | Set up Sentry alerts: critical errors → email | Configured |

**Block B: OpenTelemetry distributed tracing**

| # | Task | DoD |
|---|---|---|
| B.1 | Add `opentelemetry-instrumentation-fastapi` and `opentelemetry-instrumentation-sqlalchemy` | Installed |
| B.2 | Configure OTEL to export to AWS X-Ray | Config correct |
| B.3 | Auto-instrument FastAPI: every request gets a span | Spans created |
| B.4 | Auto-instrument SQLAlchemy: every query gets a span | Query spans |
| B.5 | Add manual spans for high-value operations (notification dispatch, encryption ops) | Custom spans |
| B.6 | Verify traces appear in X-Ray console | Works |
| B.7 | Test: hit a slow endpoint, see the bottleneck in X-Ray | Useful info |

**Block C: Prometheus metrics**

| # | Task | DoD |
|---|---|---|
| C.1 | Add `prometheus-fastapi-instrumentator` | Installed |
| C.2 | Expose `/metrics` endpoint | Endpoint works |
| C.3 | Add custom counters: events_created_total, notifications_sent_total{type=ws|fcm}, etc. | Counters exist |
| C.4 | Add custom histograms: db_query_duration_seconds, notification_dispatch_duration_seconds | Histograms exist |
| C.5 | Verify metrics scrapeable: `curl /metrics` returns Prometheus format | Works |
| C.6 | Set up CloudWatch Container Insights to scrape (or sidecar) | Metrics in CloudWatch |

**Block D: CloudWatch alarms**

| # | Task | DoD |
|---|---|---|
| D.1 | Define alarms in Terraform per spec §13.8 | All defined |
| D.2 | High error rate (>5% for 5 min) | Alarm exists |
| D.3 | High latency (p99 > 2s for 5 min) | Alarm exists |
| D.4 | DB connection saturation (>80%) | Alarm exists |
| D.5 | Failed deployments | Alarm exists |
| D.6 | Low disk on RDS (>85%) | Alarm exists |
| D.7 | SNS topic for alarm notifications, subscribe your email | Subscribed |
| D.8 | Test: trigger an alarm condition manually, verify email received | Works |

**Block E: GitHub Actions CI**

| # | Task | DoD |
|---|---|---|
| E.1 | Create `.github/workflows/ci.yml` | File exists |
| E.2 | Trigger: pull request to main, push to main | Triggers correct |
| E.3 | Job: lint with ruff | Job runs |
| E.4 | Job: type-check with mypy | Job runs |
| E.5 | Job: pytest with coverage report | Tests run |
| E.6 | Job: build Docker image (don't push) | Build succeeds |
| E.7 | Job: Trivy scan of built image | Scan runs |
| E.8 | Coverage report uploaded to PR as comment | Visible |
| E.9 | Verify branch protection requires CI to pass | Cannot merge with red CI |

**Block F: GitHub Actions CD to staging**

| # | Task | DoD |
|---|---|---|
| F.1 | Create `.github/workflows/deploy-staging.yml` | File exists |
| F.2 | Trigger: push to main (after CI passes) | Triggers correct |
| F.3 | Build Docker image with git SHA tag | Image tagged |
| F.4 | Push to ECR | Pushed |
| F.5 | Run Alembic migrations against staging DB | Migrations applied |
| F.6 | Update ECS staging service via AWS CLI or task definition update | Service updated |
| F.7 | Wait for service stable | Deployment confirmed |
| F.8 | Run smoke tests against staging | Smoke tests pass |
| F.9 | Notify via Slack/email | Notification fires |
| F.10 | Auth: GitHub Actions uses OIDC to assume IAM role (no long-lived keys) | OIDC working |

**Block G: GitHub Actions CD to production**

| # | Task | DoD |
|---|---|---|
| G.1 | Create `.github/workflows/deploy-production.yml` | File exists |
| G.2 | Trigger: workflow_dispatch (manual) | Manual trigger only |
| G.3 | Require approval gate (GitHub Environments feature) | Approval required |
| G.4 | Same steps as staging but against production | Steps match |
| G.5 | Blue/green deployment via ECS (zero-downtime) | Configured |
| G.6 | Auto-rollback on health check failure | Rollback works |
| G.7 | Test: do a full prod deploy of current code | Live in prod |

**Block H: Production environment setup**

| # | Task | DoD |
|---|---|---|
| H.1 | Define production environment in Terraform (separate state file) | State separate |
| H.2 | Production RDS instance (slightly larger) | Exists |
| H.3 | Production ECS service | Exists |
| H.4 | Production ALB and Route 53 records (`api.projectphase.app`) | DNS works |
| H.5 | Production secrets (separate from staging) | Separated |
| H.6 | Smoke test production end-to-end | Works |

**Definition of Done for Sprint 7**

- [ ] Sentry receiving events from staging and production
- [ ] X-Ray showing traces from staging and production
- [ ] `/metrics` endpoint exposing Prometheus metrics, scraped by CloudWatch
- [ ] All alarms defined and tested
- [ ] Push to main → automatic staging deploy
- [ ] Manual workflow → production deploy (with approval)
- [ ] Both environments healthy and serving traffic

### Risks to watch
- **OpenTelemetry overhead** — instrumenting everything has cost. Sample at <100% if needed.
- **Sentry quota** — free tier has limits. Don't capture every minor warning.
- **GitHub Actions OIDC setup** — finicky to configure first time. Docs are good but require careful reading.
- **Production deploy on first attempt** — won't work. Plan for 2–3 attempts to get it stable.

### Claude Code usage this sprint
- GitHub Actions YAML is verbose and Claude Code is excellent at it. Use heavily.
- For Sentry/OTEL configuration, the libraries' docs are the source of truth — have Claude Code reference them rather than guess.
- Terraform additions for production are mostly copies of staging with different variables. Use Claude Code for the boilerplate.

---

## Sprint 8 — Hardening + Beta-Ready

### Sprint goal
The backend is ready for real beta users. Rate limiting prevents abuse. Admin endpoints enable team operations. Security audit complete. Load testing confirms it handles 100 concurrent users. Documentation complete enough for someone else to onboard. **You could hand the codebase to a senior engineer for review and not be embarrassed.**

### Why this sprint comes ninth (last)
Hardening is meaningless before there's something to harden. By Sprint 8, every feature is in place; this sprint polishes the surface so it's robust.

### Tasks

**Block A: Rate limiting**

| # | Task | DoD |
|---|---|---|
| A.1 | Add `slowapi` dependency | Installed |
| A.2 | Configure slowapi with Postgres backend (no Redis dependency) | Configured |
| A.3 | Apply rate limits per spec §7.6:
- Auth endpoints: 10/min per IP
- Standard endpoints: 100/min per user
- WebSocket: 1 connection per user, 10 messages/sec | All applied |
| A.4 | Custom 429 response with retry-after header | Correct response |
| A.5 | Tests for rate limit behavior | Tests pass |

**Block B: Admin endpoints**

| # | Task | DoD |
|---|---|---|
| B.1 | Create `app/routers/admin.py` with admin endpoints (RBAC-protected) | File exists |
| B.2 | `GET /api/v1/admin/users` — list all users with pagination | Works |
| B.3 | `GET /api/v1/admin/users/{id}` — single user detail (audit-logged!) | Works, audit captured |
| B.4 | `GET /api/v1/admin/metrics/retention` — cohort retention | Computes correctly |
| B.5 | `GET /api/v1/admin/metrics/notifications` — notification stats | Works |
| B.6 | `GET /api/v1/admin/metrics/aggregate` — system-wide metrics | Works |
| B.7 | All endpoints write audit log entries | Verified |
| B.8 | Document how to grant admin role to a user (manual SQL update) | Documented |

**Block C: Security audit**

| # | Task | DoD |
|---|---|---|
| C.1 | Run `pip-audit` on production dependencies, fix any CVEs | Clean run |
| C.2 | Run Trivy scan on production Docker image, fix any high CVEs | Clean run |
| C.3 | Review IAM policies for least privilege (line by line) | Documented review |
| C.4 | Verify all secrets in Secrets Manager (none in code, .env, env vars) | Audit clean |
| C.5 | Check that ALB only accepts TLS 1.2+ | Configured |
| C.6 | Verify CORS allows only the admin UI origin in production | Correct |
| C.7 | Verify `/docs` is disabled in production (or password-protected) | Disabled |
| C.8 | Check audit log integrity verification job runs | Verified |
| C.9 | Test: try to access another user's data, gets 403 | Verified |
| C.10 | Test: try to inject SQL via input, gets sanitized | Verified |

**Block D: Load testing**

| # | Task | DoD |
|---|---|---|
| D.1 | Set up `locust` for load testing | Installed |
| D.2 | Write locust scenarios:
- Anonymous user signup + first event creation
- Returning user logging in + reading dashboard data
- WebSocket connection + receiving events | All scripts ready |
| D.3 | Run against staging at 100 concurrent users | Test runs |
| D.4 | Measure: p50, p95, p99 latency for each operation | Recorded |
| D.5 | Check: no errors at 100 concurrent | Confirmed |
| D.6 | Stretch: run at 500 concurrent, find break point | Documented |
| D.7 | Tune ECS service auto-scaling based on findings | Tuned |

**Block E: Backup and recovery drill**

| # | Task | DoD |
|---|---|---|
| E.1 | Document backup procedure (RDS automated, point-in-time recovery) | `docs/backup-recovery.md` |
| E.2 | Practice restore: create test database from a snapshot | Works |
| E.3 | Practice point-in-time recovery to a specific timestamp | Works |
| E.4 | Document the runbook step-by-step | Runbook complete |

**Block F: API documentation polish**

| # | Task | DoD |
|---|---|---|
| F.1 | Review Swagger UI at staging — every endpoint has description, examples, response schemas | All polished |
| F.2 | Add `/docs` for staging only (not production) | Configured |
| F.3 | Generate static OpenAPI spec, commit to repo | `openapi.json` in repo |
| F.4 | Generate Flutter client from OpenAPI spec, commit to a separate repo for the phone team | Client generated |

**Block G: Operational documentation**

| # | Task | DoD |
|---|---|---|
| G.1 | `docs/runbook.md` — step-by-step for: deploy, rollback, restore from backup, run a Lambda manually, look up a user, grant admin role | Complete |
| G.2 | `docs/incident-response.md` — what to do if: app is down, DB is unreachable, certificate expires, S3 is breached | Complete |
| G.3 | `docs/onboarding.md` — for a hypothetical new engineer joining the project | Complete |
| G.4 | README updated with current state | Polished |
| G.5 | All decisions in spec reflected in code structure | Audit complete |

**Block H: Beta readiness checklist**

| # | Task | DoD |
|---|---|---|
| H.1 | Both environments (staging + production) healthy | Confirmed |
| H.2 | All endpoints tested via smoke tests | Pass |
| H.3 | All alarms tested manually | Trigger + email received |
| H.4 | Privacy policy reviewed (at least by you, ideally by Korean legal counsel) | Reviewed |
| H.5 | Subprocessor list current | Updated |
| H.6 | Data export tested with real user | Works |
| H.7 | Account deletion + grace period tested | Works |
| H.8 | Beta user invitation flow tested (probably just admin-creates-user for now) | Works |

**Definition of Done for Sprint 8**

- [ ] Rate limiting enforced on all endpoints
- [ ] Admin endpoints functional and audit-logged
- [ ] Security audit complete with no critical findings
- [ ] Load test confirms 100 concurrent users handled
- [ ] Backup restore procedure tested end-to-end
- [ ] API docs polished
- [ ] Operational runbooks complete
- [ ] Production fully ready for beta launch

### Risks to watch
- **Rate limit too tight, blocks legit users** — start permissive, tighten based on real usage
- **Admin endpoints leaking too much data** — audit them carefully
- **Load test reveals real bottlenecks** — better now than during beta
- **Documentation gets stale immediately** — accept this; it's a starting point, not forever

### Claude Code usage this sprint
- Documentation is high-leverage Claude Code work. Have it draft, you refine.
- Locust scripts are standard patterns; Claude Code can produce them quickly.
- Security audit checklist: Claude Code can suggest, but you must personally verify each item.

---

## Cross-Sprint Concerns

### What carries through every sprint

**Migrations:** Every schema change ships as an Alembic migration in the same PR as the code change. Never edit the database directly in any environment.

**Tests:** Every PR adds tests. Coverage threshold of 80% in CI; fail the PR if it drops.

**Logs:** Every important action logs structured JSON with at least: event name, user_id, trace_id, relevant context. No `print()` ever.

**Commits:** Conventional commits format (`feat:`, `fix:`, `chore:`). Subject line under 72 chars.

**Branches:** Feature branches off main. PRs auto-deploy to staging on merge. Production deploy is manual.

**Code review:** Solo developer doesn't have a reviewer, so use Claude Code as the reviewer. After implementing a feature, ask Claude Code: "review this PR diff for issues, security, performance, missing tests."

### What you should accept will go wrong

**AWS bills will surprise you.** Expect $50–80/month at low volume. NAT Gateway is the biggest single cost.

**You will deploy a bug to staging.** That's why staging exists.

**You will deploy a bug to production.** Have rollback plan. Use it without shame.

**You will hit a Sprint and want to skip ahead.** Don't. The order matters.

**Some sprints will take 3 weeks instead of 2.** That's fine. The plan isn't pinned to dates.

**Claude Code will sometimes confidently write wrong code.** Read everything it writes. Test everything it writes. Trust nothing it writes blindly.

---

## Sprint 0 Pre-Flight Check

Before you start Sprint 0, confirm:

1. You have a Galaxy Watch 8 (yours or borrowed)
2. You have an AWS account with billing set up
3. You have a domain name (or are willing to buy one) — `projectphase.app` or similar
4. You have Claude Code installed and licensed
5. You have GitHub Pro (for branch protection) or are okay with public repo
6. You have at least 6 weeks of focused build time roughly available (this is 8 sprints × 2 weeks; some will overrun)

If any of these are no, resolve them first.

---

## Final Note

This plan is **detailed but not rigid**. Sprints are units of focus, not contracts. If during Sprint 4 you discover that the WebSocket pattern from Sprint 5 would change Sprint 4 design, pull it forward. If during Sprint 6 you realize a retention policy is wrong, fix the retention policy now.

The plan is the map. The territory is what you discover when you actually build it. The map should serve the territory, not the other way around.

You have the spec. You have the plan. You have Claude Code. You have eight sprints of work in front of you.

Go.

---

*End of Backend Sprint Plan*
