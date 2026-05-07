# Little Signals — Backend

FastAPI service powering the Little Signals stress-detection and cycle-tracking app. Production runs on AWS Seoul (`ap-northeast-2`) on ECS Fargate with RDS Postgres, S3 for opt-in encrypted blobs, and EventBridge Scheduler for cron jobs. Locally: Docker Compose for Postgres + Adminer, Poetry for the Python app.

- **Staging**: `https://api-staging.friendlykr.com`
- **Health**: `GET /health` → `{"status": "ok", "version": "..."}`
- **API docs**: `/docs` (Swagger UI), `/redoc` (ReDoc), `/openapi.json` (raw OpenAPI 3.1)
- **WebSocket**: `wss://.../ws/realtime?token=<jwt>`

---

## Table of contents

- [1. What this service does](#1-what-this-service-does)
- [2. Architecture at a glance](#2-architecture-at-a-glance)
- [3. Tech stack](#3-tech-stack)
- [4. Project structure](#4-project-structure)
- [5. Data flow](#5-data-flow)
  - [5.1 Stress event from watch to backend](#51-stress-event-from-watch-to-backend)
  - [5.2 Opt-in raw biosignal upload](#52-opt-in-raw-biosignal-upload)
  - [5.3 Real-time fan-out (foreground vs background)](#53-real-time-fan-out-foreground-vs-background)
- [6. Database](#6-database)
  - [6.1 Schema and tables](#61-schema-and-tables)
  - [6.2 Time-series tables](#62-time-series-tables)
  - [6.3 Migrations](#63-migrations)
- [7. REST API reference](#7-rest-api-reference)
  - [7.1 Auth](#71-auth)
  - [7.2 Account](#72-account)
  - [7.3 Events](#73-events)
  - [7.4 Cycles](#74-cycles)
  - [7.5 Settings](#75-settings)
  - [7.6 Consent](#76-consent)
  - [7.7 Devices](#77-devices)
  - [7.8 Sync](#78-sync)
  - [7.9 System](#79-system)
- [8. WebSocket protocol](#8-websocket-protocol)
- [9. Authentication & authorization](#9-authentication--authorization)
- [10. AWS infrastructure](#10-aws-infrastructure)
  - [10.1 Resource inventory](#101-resource-inventory)
  - [10.2 Network topology](#102-network-topology)
  - [10.3 IAM boundaries](#103-iam-boundaries)
  - [10.4 Secrets](#104-secrets)
- [11. Background jobs](#11-background-jobs)
- [12. Observability](#12-observability)
- [13. Local development](#13-local-development)
- [14. Testing](#14-testing)
- [15. Lint & type-check](#15-lint--type-check)
- [16. Staging deployment](#16-staging-deployment)
- [17. Sprint status](#17-sprint-status)

---

## 1. What this service does

Little Signals' watch detects stress on-device and the phone displays the dashboard. The backend is intentionally narrow — it exists to:

1. **Authenticate users** anonymously first, then optionally upgrade to Google OAuth via Supabase.
2. **Persist structured app data** — stress events, cycle records, settings, consent state, FCM tokens — in a relational schema with B-tree-indexed time-series tables for high-volume rows.
3. **Sync state in real time** between watch and phone via WebSocket while the app is in the foreground, falling back to FCM push when it isn't.
4. **Receive opt-in encrypted blobs** (full app backup; raw biosignal segments) and store them in S3 — the server never holds the decryption keys.
5. **Run scheduled cleanup jobs** to honor the 30-day grace deletion and 12-month biosignal retention windows, with every hard-delete and purge written to an immutable audit table.

What this service does *not* do: ML inference (lives on the watch), heavy media processing, multi-region failover, or any business logic that could be done on-device.

---

## 2. Architecture at a glance

```
                ┌────────────────────────────────────┐
                │  Galaxy Watch 8 (Wear OS, Kotlin)  │
                │  ▸ Samsung Health Sensor SDK       │
                │  ▸ On-device Mamba inference       │
                │  ▸ Decision engine + breath UI     │
                └──────────────┬─────────────────────┘
                               │ Wearable Data Layer (BT)
                               ▼
                ┌────────────────────────────────────┐
                │  Phone (Android, Flutter)          │
                │  ▸ Encrypts opt-in blobs locally   │
                │  ▸ JWT in Android Keystore         │
                └─────┬──────────────────────┬───────┘
                      │ HTTPS (REST)         │ WSS
                      │                      │
                      ▼                      ▼
   ┌──────────────────────────────────────────────────┐
   │  AWS Seoul (ap-northeast-2)                      │
   │                                                  │
   │  Route53 → ACM → ALB                             │
   │             ├── /api/v1/*    → ECS Fargate       │
   │             ├── /ws/realtime → ECS Fargate (WS)  │
   │             └── /health, /docs, /openapi.json    │
   │                                                  │
   │  ECS Fargate (FastAPI, uvicorn, structlog)       │
   │   ├── RDS Postgres 15                          │
   │   ├── S3 sync       (opt-in encrypted backup)    │
   │   ├── S3 biosignals (opt-in raw biosignal blobs) │
   │   ├── Secrets Manager (supabase, firebase)       │
   │   └── CloudWatch Logs (backend, cron)            │
   │                                                  │
   │  EventBridge Scheduler                           │
   │   ├── purge_accounts   (daily, 03:00 UTC)        │
   │   └── purge_biosignals (every 6 hours)           │
   │     → ECS RunTask  → cron task definition        │
   │     → SQS DLQ + CloudWatch alarm on depth        │
   └──────────────────────────────────────────────────┘
                      │                      │
                      ▼                      ▼
              Supabase Auth          Firebase Cloud
              (JWT issuer)           Messaging (push)
```

All ingress is HTTPS-only via the ALB. ECS tasks live in private subnets with no public IPs. RDS is unreachable from the internet and only accepts traffic from the ECS security group.

---

## 3. Tech stack

| Layer | Choice | Notes |
| :--- | :--- | :--- |
| Language | Python 3.12 | Same toolchain as the AI/ Mamba pipeline |
| Web framework | FastAPI 0.136 | HTTP + WebSocket, auto-generated OpenAPI 3.1 |
| ASGI server | uvicorn (`[standard]`) | One worker per task in production |
| ORM | SQLAlchemy 2.0 (`asyncio`) + asyncpg | All queries are async; no sync sessions |
| Migrations | Alembic | Stamp-on-deploy via `scripts/run-staging-migration.sh` |
| Validation | Pydantic v2 + `pydantic-settings` | Env-driven settings, strict request/response models |
| Auth (verify) | `python-jose[cryptography]` | Verifies Supabase-issued JWTs against Supabase JWKS |
| Auth (issuer) | Supabase Auth | Anonymous-first JWT, Google OAuth exchange |
| Push | `firebase-admin` | FCM HTTP v1 for background notifications |
| Object storage | `boto3` + presigned URLs | S3 `sync` and S3 `biosignals` |
| Logging | `structlog` | Structured JSON to stdout → CloudWatch Logs |
| Lint / format | `ruff` (line 100, py312) | Format check is part of CI |
| Type-check | `mypy --strict` | `disallow_untyped_defs`, `warn_return_any`, Pydantic plugin |
| Tests | `pytest`, `pytest-asyncio`, `httpx`, `httpx-ws`, `respx`, `moto[s3]` | Coverage uses `sysmon` (PEP 669) so async coroutines aren't dropped |

`pyproject.toml` is the source of truth for exact versions.

---

## 4. Project structure

```text
backend/
├── app/
│   ├── main.py                # FastAPI factory, lifespan, router includes
│   ├── config.py              # Settings (pydantic-settings, env-driven)
│   ├── auth/                  # JWT verify, Supabase client, Google exchange
│   ├── account/               # /account/me, account deletion + restore
│   ├── events/                # POST/GET/PATCH/DELETE /events
│   ├── cycles/                # /cycles/period-start, /current, /history
│   ├── settings_api/          # /settings  (named to avoid stdlib clash)
│   ├── consent/               # /consent (granular toggles + audit)
│   ├── devices/               # /devices/fcm-token
│   ├── sync/                  # /sync/{upload,download}, /sync/biosignals
│   ├── realtime/              # /ws/realtime, in-memory + DB connection registry
│   ├── routers/               # Shared router glue
│   ├── schemas/               # Pydantic request/response models
│   ├── models/                # SQLAlchemy ORM models
│   ├── services/              # Business logic (audit, deletion, fcm, s3, etc.)
│   ├── observability/         # structlog setup + exception handlers
│   ├── jobs/                  # CLI entrypoints invoked by ECS RunTask
│   │   ├── purge_accounts.py
│   │   └── purge_biosignals.py
│   ├── db/                    # Engine, session, dependency injectors
│   └── tests/                 # pytest suite (fixtures in conftest.py)
├── alembic/                   # Migrations + env.py
│   └── versions/              # 5 migrations covering all current tables
├── infra/                     # Terraform (see §10)
│   ├── networking.tf          # VPC, subnets, IGW, NAT, security groups
│   ├── alb.tf                 # ALB + ACM + Route53
│   ├── ecs.tf                 # Cluster, task defs, service, IAM
│   ├── rds.tf                 # Postgres 15 instance
│   ├── s3.tf                  # sync + biosignals buckets
│   ├── ecr.tf                 # Repository + lifecycle policy
│   ├── scheduler.tf           # EventBridge + cron task + DLQ + alarm
│   ├── secrets.tf             # Secrets Manager entries
│   ├── locals.tf, main.tf, variables.tf, outputs.tf
│   └── staging.tfvars
├── scripts/                   # Bootstrap, migration runner, smoke tests
├── docs/
│   └── sprint-7-deploy-runbook.md
├── Dockerfile                 # Multi-stage build, slim runtime image
├── docker-compose.yml         # Postgres 15 + Adminer
├── Makefile                   # migrate, migrate-test, ecr-*, smoke-staging
├── alembic.ini
└── pyproject.toml
```

---

## 5. Data flow

### 5.1 Stress event from watch to backend

```
Watch detects stress (on-device Mamba)
  → Watch → Phone via Wearable Data Layer (BT)
  → Phone POST /api/v1/events  (JWT in Authorization)
  → ALB → ECS Fargate (FastAPI)
  → JWT signature verified against cached Supabase JWKS
  → Insert into stress_events (composite PK on (id, detected_at))
  → Broadcast via WebSocket to user's other connected sessions
  → 201 Created
  → structlog JSON line → CloudWatch (request_id, user_id, latency_ms)
```

### 5.2 Opt-in raw biosignal upload

```
User toggles "Contribute raw biosignals" in Settings
  → Phone generates per-user key in Android Keystore
  → Phone shows a recovery phrase, waits for user confirmation
  → Phone encrypts a 60-second window of raw signals (XChaCha20-Poly1305)
  → POST /api/v1/sync/biosignals  → backend issues a presigned PUT URL
  → Phone PUTs ciphertext to S3 (bucket: biosignals)
  → Backend records s3_object_key + signal_type + recorded_at in DB
  → Server has no decryption capability — only the user's key works
  → audit_log row: action="biosignal_upload"
```

### 5.3 Real-time fan-out (foreground vs background)

```
App in foreground:
  Phone holds WSS /ws/realtime?token=<jwt> open
  Backend marks user "online" in websocket_connections
  Backend pushes `event.created`, `cycle.updated`, `insight.ready` directly

App backgrounded:
  Phone closes WS gracefully ("bye" frame)
  Backend marks user "offline"
  Next inbound event → backend fans out via FCM HTTP v1
    using fcm_tokens registered through POST /api/v1/devices/fcm-token
  Phone wakes, receives system notification, optionally reconnects

Backend never deduplicates between WS and FCM: the foreground/background
state in `websocket_connections` is the single switch.
```

---

## 6. Database

### 6.1 Schema and tables

Single Postgres 15 logical database with enabled.

| Table | Purpose | Key columns |
| :--- | :--- | :--- |
| `users` | Account record. Anonymous-first; `supabase_user_id` is `NULL` until upgrade. | `id`, `supabase_user_id`, `anon_id`, `role`, `consent_raw_biosignals`, `deleted_at` |
| `user_settings` | Per-user preferences (1:1). | `user_id` (PK FK), notification + quiet-hours fields, `language` |
| `stress_events` | Detected stress events. Composite PK `(id, detected_at)`. | `id`, `user_id`, `detected_at`, `model_confidence`, `cycle_phase`, `log_chips`, `user_response` |
| `cycles` | Period start/end, derived phase. | `id`, `user_id`, `period_start_date`, `period_end_date`, `auto_detected` |
| `raw_biosignal_uploads` | Pointer to opt-in encrypted blobs in S3. Composite PK `(id, recorded_at)`. | `id`, `user_id`, `s3_object_key`, `signal_type`, `recorded_at`, `expires_at` |
| `sync_blobs` | Pointer to opt-in encrypted full-app backups in S3. | `id`, `user_id`, `s3_object_key`, `uploaded_at` |
| `websocket_connections` | Live WS sessions; allows fan-out to multiple devices per user. | `id`, `user_id`, `task_id`, `connected_at` |
| `fcm_tokens` | Per-device FCM registration tokens for background push. | `id`, `user_id`, `token`, `platform`, `last_seen_at` |
| `audit_log` | Append-only record of consent changes, hard-deletes, biosignal purges. | `id`, `actor_id`, `target_user_id`, `action`, `metadata`, `occurred_at` |

Free-text fields (e.g., `stress_events.log_text`) are encrypted client-side before they reach the backend. Raw biosignal blobs are encrypted with user-held keys; the server only ever sees ciphertext + object metadata.

### 6.2 Time-series tables

`stress_events` and `raw_biosignal_uploads` are append-only, time-ordered tables with composite primary keys `(id, detected_at)` / `(id, recorded_at)` and B-tree indexes on `(user_id, detected_at)` / `(user_id, recorded_at)` for window queries. They were originally specced as TimescaleDB hypertables, but AWS RDS Postgres no longer supports the `timescaledb` extension (license-related removal). Plain Postgres B-tree partitioning is adequate at the volumes we'll hit before graduation; if the data outgrows it, native declarative partitioning or a managed Timescale alternative are options.

`audit_log` is similarly a plain Postgres table with B-tree indexes on `occurred_at`, `(action, occurred_at)`, and `target_user_id`.

### 6.3 Migrations

5 Alembic revisions live in [`alembic/versions/`](alembic/versions/):

1. `09774758d188_create_users_table` — initial `users`
2. `7bdacbea490e_expand_users_and_add_user_settings` — Supabase fields + `user_settings`
3. `adbd022fc5c1_add_stress_events_and_cycles_tables` — `stress_events`, `cycles`
4. `6cd3f7dbdd70_add_websocket_connections_fcm_tokens_` — realtime + push tables + `sync_blobs` + `raw_biosignal_uploads`
5. `81190b1e74b8_add_audit_log_table` — `audit_log`

Apply locally with `make migrate`. Tests run against a separate `little_signals_test` DB; apply migrations there with `make migrate-test`. Staging migration is run as a one-off ECS task via [`scripts/run-staging-migration.sh`](scripts/run-staging-migration.sh).

---

## 7. REST API reference

All app endpoints live under `/api/v1/*`. JWT goes in the `Authorization: Bearer <jwt>` header. Pydantic-generated request/response schemas are the contract — Swagger is the live source of truth at `/docs`. Below is the inventory grouped by router:

### 7.1 Auth

Router: [`app/auth/router.py`](app/auth/router.py), prefix `/api/v1/auth`.

| Method & path | Purpose |
| :--- | :--- |
| `POST /auth/anon` | Issue a JWT for an anonymous user. Creates a `users` row with `anon_id` set, `supabase_user_id` NULL. |
| `POST /auth/google` | Exchange a Google ID token (from Google Sign-In SDK) for a Supabase JWT. Migrates the anonymous account if `Authorization` is present. |
| `POST /auth/refresh` | Refresh an expired access token using the refresh token. |
| `POST /auth/logout` | Revoke the caller's session at Supabase. |

### 7.2 Account

Router: [`app/account/router.py`](app/account/router.py), prefix `/api/v1`.

| Method & path | Purpose |
| :--- | :--- |
| `GET /account/me` | Return the authenticated user's profile (id, role, consent flags). |
| `DELETE /account` | Initiate the 30-day grace deletion. Sets `deleted_at`; data is hard-deleted later by `purge_accounts`. |
| `POST /account/restore` | Cancel a pending deletion within the grace window. |

### 7.3 Events

Router: [`app/events/router.py`](app/events/router.py), prefix `/api/v1/events`.

| Method & path | Purpose |
| :--- | :--- |
| `POST /events` | Create a stress event (typically from the phone forwarding a watch detection). |
| `GET /events` | List events for the caller; supports time-window and cycle-phase filters. |
| `GET /events/{event_id}` | Single event detail. |
| `PATCH /events/{event_id}` | Add user-supplied log chips / free text after the fact. |
| `DELETE /events/{event_id}` | User-initiated event removal. |

### 7.4 Cycles

Router: [`app/cycles/router.py`](app/cycles/router.py), prefix `/api/v1/cycles`.

| Method & path | Purpose |
| :--- | :--- |
| `POST /cycles/period-start` | Log a new period start; backend infers phase forward. |
| `GET /cycles/current` | Current cycle phase + day. |
| `GET /cycles/history` | Past cycles for the caller. |
| `PATCH /cycles/{cycle_id}` | Correct a logged cycle (sets `user_corrected = true`). |

### 7.5 Settings

Router: [`app/settings_api/router.py`](app/settings_api/router.py), prefix `/api/v1/settings`.

| Method & path | Purpose |
| :--- | :--- |
| `GET /settings` | Return the caller's `user_settings` row (creates defaults on first read). |
| `PATCH /settings` | Partial update — quiet hours, max-per-day cap, language, etc. |

### 7.6 Consent

Router: [`app/consent/router.py`](app/consent/router.py), prefix `/api/v1/consent`.

| Method & path | Purpose |
| :--- | :--- |
| `GET /consent` | Current consent flags. |
| `PATCH /consent` | Update granular consent. Every change writes an `audit_log` row. |

### 7.7 Devices

Router: [`app/devices/router.py`](app/devices/router.py), prefix `/api/v1/devices`.

| Method & path | Purpose |
| :--- | :--- |
| `POST /devices/fcm-token` | Register or refresh an FCM token for background push. |

### 7.8 Sync

Router: [`app/sync/router.py`](app/sync/router.py), prefix `/api/v1/sync`.

| Method & path | Purpose |
| :--- | :--- |
| `POST /sync/upload` | Upload an encrypted full-app backup blob. Backend issues an S3 presigned PUT URL. |
| `GET /sync/download` | Restore on a new device. Returns a presigned GET URL for the latest blob. |
| `DELETE /sync` | Wipe the caller's cloud backup (does not affect biosignals). |
| `POST /sync/biosignals` | Upload a single encrypted raw-biosignal segment (opt-in). Returns presigned PUT + records pointer. |

### 7.9 System

| Method & path | Purpose |
| :--- | :--- |
| `GET /health` | Liveness probe. Returns `{"status": "ok", "version": ...}`. Used by ALB target group. |
| `GET /` | 307 redirect to `/docs`. |
| `GET /docs`, `/redoc`, `/openapi.json` | Auto-generated FastAPI documentation. |

---

## 8. WebSocket protocol

**Endpoint:** `WSS /ws/realtime`. Defined in [`app/realtime/router.py`](app/realtime/router.py).

**Authentication:** JWT passed as a query parameter (`?token=...`) — verified at upgrade. Connections without a valid token are rejected immediately.

**Message envelope:**

```json
{
  "type": "event.created",
  "payload": { "...": "..." }
}
```

**Server → client types:**
- `event.created` — new stress event from another device
- `event.updated` — log added to an existing event
- `cycle.updated` — period start logged on another device
- `insight.ready` — weekly insight generated
- `pong` — heartbeat response

**Client → server types:**
- `ping` — heartbeat
- `subscribe` — opt-in subscription to specific event types
- `ack` — acknowledge a server message

**Lifecycle:** clients reconnect with exponential backoff (500ms → 30s cap). The server closes idle connections after ~5 minutes; clients re-establish and call `GET /events?since=...` to backfill any missed deltas.

**Connection registry:** in-memory plus `websocket_connections` rows (managed by [`app/realtime/registry.py`](app/realtime/registry.py) and [`app/realtime/cleanup.py`](app/realtime/cleanup.py)) so a multi-task ECS service can fan out to all of a user's open sessions.

---

## 9. Authentication & authorization

**Issuer:** Supabase Auth.
**Verifier:** this service, using cached Supabase JWKS via `python-jose`.

**Anonymous-first model:** the very first thing a fresh app does is `POST /api/v1/auth/anon`, which creates a `users` row with `anon_id` set and returns a JWT with `sub=anon_id, role=user`. The user can use the entire app without registering. Later, `POST /api/v1/auth/google` swaps an anonymous identity for a real one — the existing `anon_id` row is preserved, `supabase_user_id` is populated, and all downstream data references continue to point at the same `users.id`.

**Role-based access:** `users.role` is `'user'` (default) or `'admin'`. Admin endpoints (specced in §appendix B of the architecture doc; not all implemented yet) require `role='admin'`, enforced via a FastAPI dependency.

**Protected-endpoint pattern:** [`app/auth/dependencies.py`](app/auth/dependencies.py) exports `get_current_user` (required) and `get_current_user_optional` (returns `None` if no token). Routers depend on whichever they need — never parse the `Authorization` header directly.

**JWT verification path:** the JWKS is cached in-process (refresh on key-rotation 401). `httpx` fetches the JWKS over HTTPS through the NAT Gateway. There is no shared secret between Supabase and the backend — verification is purely public-key.

---

## 10. AWS infrastructure

All resources are defined in [`infra/`](infra/) as Terraform. Region: `ap-northeast-2` (Seoul). Account: separate AWS accounts per environment (currently staging only).

### 10.1 Resource inventory

| File | Resources |
| :--- | :--- |
| [`networking.tf`](infra/networking.tf) | VPC, public subnets, private subnets, IGW, NAT Gateway, EIP, route tables, security groups (`alb`, `ecs`, `rds`) |
| [`alb.tf`](infra/alb.tf) | ALB, HTTPS + HTTP→HTTPS listeners, target group, ACM certificate (DNS-validated), Route53 records |
| [`ecs.tf`](infra/ecs.tf) | ECS cluster, task definition (`backend`), service, IAM roles (`ecs_execution`, `ecs_task`), CloudWatch Log Group, secrets-pull policy |
| [`ecr.tf`](infra/ecr.tf) | ECR repository + lifecycle policy (untagged images expire) |
| [`rds.tf`](infra/rds.tf) | DB subnet group, `aws_db_instance` (`postgres` 15, `db.t4g.micro`, 20→100 GB autoscaling, 7-day backups, private) |
| [`s3.tf`](infra/s3.tf) | Two buckets (`sync`, `biosignals`) — versioning, public-access-block, SSE, lifecycle rules; IAM policy attached to `ecs_task` |
| [`scheduler.tf`](infra/scheduler.tf) | EventBridge schedule group, schedules for `purge_accounts` and `purge_biosignals`, scheduler IAM role with `ecs:RunTask` + `iam:PassRole`, separate `cron` ECS task definition, SQS DLQ, CloudWatch metric alarm on DLQ depth, separate CloudWatch Log Group for cron |
| [`secrets.tf`](infra/secrets.tf) | Secrets Manager entries: `supabase`, `firebase` |
| [`locals.tf`](infra/locals.tf), [`variables.tf`](infra/variables.tf), [`outputs.tf`](infra/outputs.tf), [`main.tf`](infra/main.tf) | Provider, naming, var defaults, terraform outputs (ECR URL, ALB DNS, etc.) |

### 10.2 Network topology

```
Internet
  │
  ▼
Route53 (api-staging.friendlykr.com)
  │
  ▼
ALB (public subnets, sg-alb)
  │  HTTP→HTTPS redirect on :80, TLS terminate on :443
  ▼
ECS Fargate tasks (private subnets, sg-ecs)
  │
  ├──► RDS Postgres (private subnets, sg-rds — only sg-ecs may connect)
  ├──► S3 sync, S3 biosignals (via NAT Gateway)
  ├──► Secrets Manager (via NAT Gateway)
  └──► External (via NAT Gateway):
       ├── Supabase JWKS
       └── Firebase Cloud Messaging
```

ECS tasks have no public IPs. RDS has `publicly_accessible = false`. Inter-AZ traffic is intra-VPC only.

### 10.3 IAM boundaries

Three distinct task/role boundaries, each scoped to what it actually needs:

- **`ecs_execution` role** — used by the ECS agent to pull images from ECR, fetch secrets from Secrets Manager, and write to CloudWatch Logs. Scoped to the specific log group + secret ARNs.
- **`ecs_task` role** — used by the running container to call S3 (presigned URLs for `sync` + `biosignals`), Secrets Manager (runtime reads), and limited CloudWatch metric writes. Has *no* `ecs:RunTask` permission — that's the scheduler's job.
- **`scheduler` role** — used by EventBridge Scheduler to launch the cron task definition. Only `ecs:RunTask` against the `cron` task ARN, `iam:PassRole` to pass the execution + task roles, and `sqs:SendMessage` to the DLQ.

The cron container reuses `ecs_task` for its runtime role so it can read DB credentials and delete S3 objects.

### 10.4 Secrets

| Secret | Contents | Consumed by |
| :--- | :--- | :--- |
| `supabase` | Supabase service-role key + project URL + JWKS URL | Backend at startup (cached) |
| `firebase` | Firebase Admin SDK service-account JSON | `app.services.fcm` |

Database credentials are injected into the ECS task as environment variables sourced from the RDS-managed secret rotation (configured via the ECS task definition's `secrets` block, not stored as a separate Secrets Manager entry by this stack).

---

## 11. Background jobs

Two scheduled jobs run as one-off ECS tasks (not Lambda — the codepath is shared with the API and we wanted Python parity).

| Job | Cadence | Entry point | What it does |
| :--- | :--- | :--- | :--- |
| `purge_accounts` | Daily, 03:00 UTC | [`app.jobs.purge_accounts`](app/jobs/purge_accounts.py) | Hard-deletes accounts whose `deleted_at` is older than the grace period; writes one `audit_log` row per deletion. |
| `purge_biosignals` | Every 6 hours | [`app.jobs.purge_biosignals`](app/jobs/purge_biosignals.py) | Deletes S3 blobs and DB pointers past their 12-month retention window (`raw_biosignal_uploads.expires_at`); writes one `audit_log` row per purge batch. |

Each invocation:

```
EventBridge Scheduler  → ecs:RunTask (cron task definition)
  → container starts → reads DB creds from Secrets Manager
  → connects to RDS, runs the job
  → on uncaught exception: ECS task fails, EventBridge sends to SQS DLQ
  → CloudWatch alarm fires when DLQ depth > 0
  → operator inspects DLQ message + cron CloudWatch Log Group
```

This replaced the in-process `_purge_loop` (Sprint 6 → Sprint 7); the move is documented in [`docs/sprint-7-deploy-runbook.md`](docs/sprint-7-deploy-runbook.md).

---

## 12. Observability

- **Logs:** `structlog` emits JSON to stdout; ECS ships stdout to CloudWatch Logs. Every request gets a `request_id`; service code threads it through ([`app/observability/logging.py`](app/observability/logging.py)).
- **Exception handlers:** centralized in [`app/observability/exception_handlers.py`](app/observability/exception_handlers.py); every uncaught exception logs with full context and returns a sanitized error to the client.
- **Audit log:** [`app/services/audit.py`](app/services/audit.py) is the single helper that writes to `audit_log`. Anything that mutates consent state, hard-deletes data, or purges biosignals must go through it.
- **Health check:** `GET /health` — used by the ALB target group. Returns 200 with version even if the DB is unreachable, so the ALB doesn't terminate the task during transient blips; deeper readiness is the operator's job (CloudWatch alarms on DB connection errors).
- **Distributed tracing & Sentry:** Sprint 8 work — wired in but the full GitHub Actions production CD path lands with that sprint.

---

## 13. Local development

Prereqs (one-time):
- Python 3.12 via pyenv
- Poetry 2.x
- Docker (Colima or Docker Desktop) with Compose v2
- Postgres 15 client (`psql`)

Install Python deps:

```bash
cd backend
poetry install
```

Bring up the dev database (Postgres 15) and Adminer:

```bash
docker compose up -d
make migrate
poetry run uvicorn app.main:app --reload
```

Defaults:

- Postgres: `localhost:5432`, user `little_signals`, password `dev_only_password`, db `little_signals_dev`
- Adminer: <http://localhost:8080>
- API: <http://localhost:8000>, Swagger at <http://localhost:8000/docs>

Tear down:

```bash
docker compose down
```

> **Port 5432 conflict?** If Homebrew Postgres is running locally (`brew services list` shows `postgresql@15` started) or another container is bound to 5432, stop it before `docker compose up`:
>
> ```bash
> brew services stop postgresql@15
> ```
>
> Restart afterward with `brew services start postgresql@15`.

---

## 14. Testing

```bash
poetry run pytest                            # full suite
poetry run pytest app/tests/test_events_router_create.py  # single file
poetry run pytest -k "audit"                 # filter
poetry run pytest --cov=app --cov-report=term-missing
```

Tests use a separate `little_signals_test` database; apply migrations there with:

```bash
make migrate-test
```

S3 calls in tests are mocked with `moto[s3]`. Outbound HTTP is mocked with `respx`. WebSocket tests use `httpx-ws`. Async tests are auto-mode (`asyncio_mode = "auto"` in `pyproject.toml`), so plain `async def test_...` works without decorators.

Coverage measurement uses PEP 669 `sys.monitoring` (`tool.coverage.run.core = "sysmon"`) so coverage isn't lost across `await` boundaries — relevant since most of the codebase is async.

---

## 15. Lint & type-check

```bash
poetry run ruff check .
poetry run ruff format --check .
poetry run mypy app/
```

Ruff config (in `pyproject.toml`): line length 100, target `py312`, lint rules `E,W,F,I,B,UP,SIM,C4`. `E501` is delegated to the formatter.

mypy is `--strict`: `disallow_untyped_defs`, `warn_return_any`, `warn_redundant_casts`, `warn_unused_ignores`, plus the Pydantic plugin. External libraries that don't ship stubs (`jose`, `structlog`, `firebase_admin`, `boto3`, `moto`) are listed under `[[tool.mypy.overrides]]` with `ignore_missing_imports = true`.

A pre-commit config (`.pre-commit-config.yaml`) wires ruff + mypy + standard hygiene checks. Install with `pre-commit install`.

---

## 16. Staging deployment

```bash
cd backend
AWS_PROFILE=little-signals-staging ./scripts/bootstrap-terraform-state.sh

cd infra
cp backend.hcl.example backend.hcl
AWS_PROFILE=little-signals-staging terraform init -backend-config=backend.hcl
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars
cd ..

AWS_PROFILE=little-signals-staging make ecr-login
AWS_PROFILE=little-signals-staging make ecr-push IMAGE_TAG=0.7.0

cd infra
ECR_URL="$(AWS_PROFILE=little-signals-staging terraform output -raw ecr_repository_url)"
AWS_PROFILE=little-signals-staging terraform apply \
  -var-file=staging.tfvars \
  -var "container_image=$ECR_URL:0.7.0"
cd ..

AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh

make smoke-staging
```

Why two `terraform apply` calls: the first provisions networking / ECR / RDS / ALB / ECS against the placeholder image in `staging.tfvars`. After `make ecr-push` lands a real image, the second apply re-points the ECS task definition at that image via `-var container_image=...` so the service actually rolls out the backend.

Expected staging URL: `https://api-staging.friendlykr.com`. Smoke output should hit `/health`, exercise an anonymous auth flow, and confirm the WebSocket upgrade.

---

## 17. Sprint status

| Sprint | Theme | Status |
| :---: | :--- | :---: |
| 0 | Foundation & verification (Watch SDK confirmed) | ✅ |
| 1 | Local API skeleton + structured logging | ✅ |
| 2 | First AWS deploy (ECS + RDS + ALB) | ✅ |
| 3 | Auth + user model (Supabase, Google OAuth, anonymous-first) | ✅ |
| 4 | Core data endpoints (events, cycles, settings, consent) | ✅ |
| 5 | Real-time + sync (WebSocket, FCM, opt-in upload) | ✅ |
| 6 | Deletion jobs (`purge_accounts`, `purge_biosignals`) | ✅ |
| 7 | EventBridge + audit (`audit_log` table, scheduler-driven cron) | ✅ |
| 8a | Observability (Sentry, OTel/X-Ray, Prometheus, alarms) | ⏳ |
| 8b | CI/CD (GitHub Actions, OIDC, staging + prod deploys) | ⏳ |
| 8c | Production environment (separate TF state, prod RDS/ECS/ALB) | ⏳ |
| 9 | Hardening + beta-ready (rate limiting, load test, admin) | ⏳ |

Latest deploy runbook: [`docs/sprint-7-deploy-runbook.md`](docs/sprint-7-deploy-runbook.md). Sprint 8a/8b runbooks live at `backend/docs/sprint-8{a,b}-*.md` locally (gitignored).

## CI/CD

CI runs on every PR and on every push to master. Three workflows live in `.github/workflows/`:

- `ci.yml` — lint, typecheck, pytest with TimescaleDB Postgres, Docker build, Trivy scan.
- `deploy-staging.yml` — fires after CI succeeds on master; deploys to staging end-to-end.
- `deploy-production.yml` — manual `workflow_dispatch`; gated on the `production` GitHub Environment approval.

Authentication uses GitHub OIDC against an IAM role (no long-lived AWS keys in the repo). One-time operator setup is captured in `backend/docs/sprint-8b-cicd-runbook.md` (gitignored, local).
