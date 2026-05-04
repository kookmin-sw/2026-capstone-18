# Backend Architecture Specification
## Project Phase (working title)

**Status:** v1.1 — pre-build technical specification with Galaxy Watch 8 integration confirmed
**Date:** May 4, 2026
**Author:** Anu
**Audience:** backend engineering team, Wear OS engineering team, code reviewers, capstone advisor
**Companion to:** `PRD-project-phase-v1.md`, `PRD-supplement-stories-and-screens.md`

**v1.1 changelog:**
- Added Section 11: Galaxy Watch 8 Integration (Wear OS + Samsung Health Sensor SDK)
- Confirmed Sensor SDK 1.4.1 raw data access for all required channels via inspection of actual SDK package
- Clarified team role gap: Wear OS / Android engineer needed (was implicit, now explicit)
- Subsequent sections renumbered (12–20)

---

## How to Read This Document

This spec defines the backend system supporting Project Phase. It feeds directly into PRD §8 (Architecture & Technical Approach) and replaces any earlier informal architecture sketches.

The document is organized so that an engineer can find what they need without reading linearly:
- **Sections 1–3** — context, principles, constraints
- **Sections 4–10** — the full stack, layer by layer
- **Sections 11–14** — operations: privacy, observability, CI/CD, security
- **Section 15** — what's explicitly out of scope and why

Decisions in this document were made through a structured 10-question brainstorming process. The reasoning behind each major choice is preserved so future-team-members can understand *why*, not just *what*.

---

## Table of Contents

1. [Context & Goals](#1-context--goals)
2. [Design Principles](#2-design-principles)
3. [Constraints](#3-constraints)
4. [System Overview](#4-system-overview)
5. [Language, Runtime & Framework](#5-language-runtime--framework)
6. [Database Layer](#6-database-layer)
7. [API Design](#7-api-design)
8. [Authentication & Authorization](#8-authentication--authorization)
9. [Hosting & Deployment](#9-hosting--deployment)
10. [Real-Time Architecture](#10-real-time-architecture)
11. [Galaxy Watch 8 Integration (NEW)](#11-galaxy-watch-8-integration)
12. [Data Privacy & Encryption](#12-data-privacy--encryption)
13. [Observability](#13-observability)
14. [CI/CD & Infrastructure as Code](#14-cicd--infrastructure-as-code)
15. [Security Hardening](#15-security-hardening)
16. [Team & Ownership](#16-team--ownership)
17. [Out of Scope (and Why)](#17-out-of-scope-and-why)
18. [Decision Log](#18-decision-log)
19. [Open Questions](#19-open-questions)
20. [Appendix A: Cost Estimate](#appendix-a-cost-estimate)
21. [Appendix B: Endpoint Inventory](#appendix-b-endpoint-inventory)
22. [Appendix C: Sensor SDK Verification Notes](#appendix-c-sensor-sdk-verification-notes)

---

## 1. Context & Goals

### What I'm Building

A custom backend supporting the Project Phase mobile app — a women-focused stress detection and cycle tracking application running on Galaxy Watch 8 + Android. The backend handles authentication, data persistence, real-time event sync between watch and phone, encrypted opt-in biosignal storage, and admin tooling for the beta cohort.

### Why a Custom Backend (not Firebase)

This is a portfolio capstone project. Building a custom backend is itself a learning goal and a portfolio artifact demonstrating senior-level backend engineering. The choice is deliberate: a Firebase-based version would ship faster but would not exercise or showcase the engineering skills I'm trying to demonstrate.

The product would work on Firebase. It works *better as a portfolio piece* on a custom backend. Both can be true.

### Primary Goals

1. **Serve the v1 product reliably** — 100 beta users, ~70% Korean university students, on-device-first architecture
2. **Demonstrate senior-grade backend engineering** — architecture, observability, privacy, CI/CD all visible to reviewers
3. **Comply with Korean PIPA** — Seoul region hosting, audit logging, explicit retention policies, opt-in consent
4. **Stay buildable in 12 weeks** — disciplined scope, no infrastructure built for problems I don't have

### Non-Goals

- Production-scale architecture (the system does not need to handle 1M users in v1)
- Multi-region deployment (Seoul only)
- Custom authentication implementation (delegated to Supabase)
- On-backend ML inference (lives on-device per privacy posture)
- Background workers / Celery (no async workload justifies them in v1)

---

## 2. Design Principles

### 2.1 Privacy by architecture, not by promise

Every design decision must hold up if AWS, Supabase, or my own application were compromised. Privacy is enforced through encryption keys users hold, on-device ML, opt-in raw data — not through "we promise we won't look." This is the post-Flo standard for women's health data.

### 2.2 Build only what the product needs

Resist scope creep dressed up as "could be useful." Every component added must justify itself against POC scope. Senior engineering is knowing what *not* to build.

### 2.3 Operational concerns are first-class

Logs, metrics, traces, and CI/CD are designed at the same time as the application code. Observability is not a v2 retrofit. A backend without observability is unfinished, not minimal.

### 2.4 Standard tools, used well

Prefer mature, widely-known tools (Postgres, FastAPI, Terraform, GitHub Actions) over novel ones. Demonstrate skill through *how* the tools are used, not which exotic ones are picked.

### 2.5 Document the why, not just the what

Decisions are preserved with their reasoning so future-me, future teammates, and reviewers can understand *why* each choice was made. This is itself a senior-engineering signal.

---

## 3. Constraints

### Functional
- Korean Gen MZ women, 19–28, university students or early-career professionals
- 100 beta users for the de-risking pilot, scaling target ~10K users by end of v1.5
- On-device ML inference (per PRD §11 privacy posture)
- Korean primary, English secondary
- Android only for v1 (iOS / Apple Watch is v2)

### Regulatory
- Korean PIPA compliance (data residency, consent, audit, retention)
- Seoul region hosting required for sensitive data

### Operational
- 12-week build timeline
- Solo-or-small-team backend ownership (Anu primary, optional teammate)
- POC budget: target ≤$100/month at beta scale, ≤$300/month at scale-out

### Strategic
- Strong portfolio surface (capstone defense, Korean enterprise interviews)
- Must coexist with Wear OS native app (Kotlin) and Flutter phone app

---

## 4. System Overview

### 4.1 Component diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  CLIENT LAYER                                                   │
│                                                                 │
│  Galaxy Watch 8 (Wear OS native, Kotlin)                        │
│    └── Bluetooth/Android Data Layer ──► Phone                   │
│                                                                 │
│  Phone (Flutter, Android)                                       │
│    ├── REST calls ───────────► API server                       │
│    ├── WebSocket (foreground) ─► API server                     │
│    └── FCM (background)    ◄── from API server via Firebase     │
│                                                                 │
│  Admin Web UI (separate frontend, teammate-led)                 │
│    └── REST calls ───────────► API server (admin endpoints)     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS / WSS
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  AWS SEOUL (ap-northeast-2)                                     │
│                                                                 │
│  Application Load Balancer                                      │
│    ├── /api/v1/*       routes to ECS Fargate (FastAPI)          │
│    ├── /ws/realtime    routes to ECS Fargate (FastAPI WS)       │
│    └── /admin/*        routes to ECS Fargate (admin endpoints)  │
│                                                                 │
│            │                                                    │
│            ▼                                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ ECS Fargate (FastAPI app, Python 3.12, uvicorn)          │   │
│  │ Auto-scaling 1–4 tasks                                   │   │
│  │ structlog → CloudWatch                                   │   │
│  │ OpenTelemetry → X-Ray                                    │   │
│  │ Sentry SDK → Sentry.io                                   │   │
│  │ /health and /metrics endpoints                           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│       ┌──────────────────┼─────────────────────┐                │
│       ▼                  ▼                     ▼                │
│  ┌──────────┐    ┌────────────┐         ┌──────────────────┐    │
│  │ RDS      │    │ S3 Seoul   │         │ EventBridge      │    │
│  │ Postgres │    │ Encrypted  │         │ + Lambda         │    │
│  │ +Timescale    │ at rest    │         │ (cron jobs)      │    │
│  └──────────┘    └────────────┘         └──────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

EXTERNAL:
  Supabase Auth (JWT issuer)
  Firebase Cloud Messaging (background push)
  Sentry.io (error tracking)
  Anthropic / OpenAI for LLM     ← deferred to v2
  
PIPELINE:
  GitHub → GitHub Actions
    → CI: ruff + mypy + pytest + Trivy
    → ECR: build + push image
    → ECS staging (auto)
    → Manual approval
    → ECS production
  
  Infrastructure: Terraform (in /infra dir of same repo)
```

### 4.2 Data flow: a stress event from watch to backend

```
Galaxy Watch detects stress event (on-device ML)
   ↓
Watch syncs event to phone via Android Data Layer (Bluetooth)
   ↓
Phone receives event in Flutter app
   ↓
Flutter app sends POST /api/v1/events to backend
   (JWT in Authorization header, payload = anonymized event)
   ↓
ALB routes to ECS Fargate task
   ↓
FastAPI receives request, validates JWT (signature check via Supabase JWKS)
   ↓
FastAPI writes event to RDS Postgres (events table, hypertable)
   ↓
FastAPI broadcasts event via WebSocket to any other connected devices
   ↓
FastAPI returns 201 Created
   ↓
structlog logs event creation (JSON, with trace_id)
   ↓
OpenTelemetry trace recorded in X-Ray
```

### 4.3 Data flow: user opts in to raw biosignal contribution

```
User toggles "Contribute raw biosignals" in privacy settings
   ↓
Flutter generates encryption key on-device (Android Keystore)
   ↓
Flutter shows recovery phrase to user (BIP-39 12 words)
   ↓
User confirms phrase saved
   ↓
Flutter encrypts raw biosignal blobs using user-held key (XChaCha20-Poly1305)
   ↓
Flutter uploads encrypted ciphertext to S3 via presigned URL
   ↓
Backend stores S3 object key + metadata in RDS
   (server cannot decrypt — only the user can)
   ↓
Audit log row created: "user X enabled raw biosignal contribution at T"
```

---

## 5. Language, Runtime & Framework

### 5.1 Decision

**Python 3.12 + FastAPI**

### 5.2 Rationale

Python keeps the ML pipeline (Nika's work) and the API in the same language. The Mamba model lives in Python; the data preprocessing lives in Python; the API serving the model lives in Python. One language, one toolchain, one set of dependencies.

FastAPI specifically because:
- Native async support (matches WebSocket needs)
- Automatic OpenAPI/Swagger generation from route definitions
- Pydantic-based request/response validation (type-safe)
- First-class WebSocket support
- Strong ecosystem for everything else we need (SQLAlchemy, Alembic, Sentry, OpenTelemetry)

### 5.3 Stack components

| Component | Library | Purpose |
|---|---|---|
| Web framework | FastAPI | HTTP + WebSocket |
| ASGI server | uvicorn (production via gunicorn) | Process management |
| ORM | SQLAlchemy 2.0 + asyncpg | Database access |
| Migrations | Alembic | Schema evolution |
| Validation | Pydantic v2 | Request/response models |
| Auth verification | python-jose | JWT signature validation |
| Logging | structlog | Structured JSON logs |
| Tracing | opentelemetry-instrumentation-fastapi | Distributed tracing |
| Errors | sentry-sdk | Error capture |
| Linting | ruff | Fast Python linter |
| Type checking | mypy | Static type analysis |
| Testing | pytest + pytest-asyncio + httpx | Unit + integration tests |

### 5.4 Project structure

```
backend/
├── app/
│   ├── main.py              # FastAPI app entrypoint
│   ├── config.py            # Settings (env-based)
│   ├── auth/                # JWT verification, role checks
│   ├── routers/             # Route handlers grouped by resource
│   │   ├── events.py
│   │   ├── cycles.py
│   │   ├── insights.py
│   │   ├── settings.py
│   │   ├── sync.py
│   │   ├── admin.py
│   │   └── realtime.py      # WebSocket handlers
│   ├── models/              # SQLAlchemy models
│   ├── schemas/             # Pydantic request/response schemas
│   ├── services/            # Business logic layer
│   ├── db/                  # Database connection, session management
│   ├── observability/       # Logging, tracing, metrics setup
│   └── tests/               # pytest tests
├── infra/                   # Terraform IaC
├── .github/workflows/       # CI/CD pipeline definitions
├── Dockerfile
├── docker-compose.yml       # Local dev
├── pyproject.toml           # Dependencies + tool config
├── alembic.ini              # Migration config
└── README.md
```

---

## 6. Database Layer

### 6.1 Decision

**PostgreSQL 15 with TimescaleDB extension, hosted on AWS RDS in Seoul region.**

### 6.2 Rationale

Most of the data is relational — users, settings, cycle records. Some of it is time-series — stress events, sensor readings, notification history. Postgres handles both, and TimescaleDB makes the time-series portions efficient through hypertables.

TimescaleDB is a Postgres extension, not a separate database. There is no migration risk; everything is still standard SQL. The only "lock-in" is the hypertable feature, which can be reverted to standard Postgres tables with a one-line ALTER if needed later.

### 6.3 Schema sketch

```sql
-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY,
    supabase_user_id UUID UNIQUE,         -- NULL for anonymous users
    anon_id UUID UNIQUE,                  -- Set for anonymous users
    role TEXT DEFAULT 'user',             -- 'user' or 'admin'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    consent_raw_biosignals BOOLEAN DEFAULT FALSE,
    consent_revoked_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ                -- 30-day grace period delete
);

-- Stress events (TimescaleDB hypertable)
CREATE TABLE stress_events (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    detected_at TIMESTAMPTZ NOT NULL,
    model_confidence FLOAT,
    cycle_phase TEXT,                     -- 'menstrual', 'follicular', etc.
    cycle_day INT,
    logged BOOLEAN DEFAULT FALSE,
    log_chips TEXT[],                     -- Array of selected chip categories
    log_text TEXT,                        -- Optional free text (encrypted at rest)
    notified BOOLEAN DEFAULT FALSE,
    user_response TEXT,                   -- 'breathe', 'log', 'skip', 'ignore'
    created_at TIMESTAMPTZ DEFAULT NOW()
);
SELECT create_hypertable('stress_events', 'detected_at');

-- Cycle records
CREATE TABLE cycles (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    period_start_date DATE NOT NULL,
    period_end_date DATE,
    cycle_length_days INT,
    auto_detected BOOLEAN DEFAULT FALSE,
    user_corrected BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Weekly insights (cached after generation)
CREATE TABLE insights (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    week_start_date DATE NOT NULL,
    insight_text TEXT NOT NULL,
    pattern_type TEXT,                    -- 'recurring_time', 'cycle_phase', etc.
    cold_start BOOLEAN DEFAULT FALSE,     -- True if framed cautiously
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Raw biosignal blob references (opt-in only)
CREATE TABLE raw_biosignal_uploads (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    s3_object_key TEXT NOT NULL,
    signal_type TEXT NOT NULL,            -- 'hrv', 'ppg', 'eda', 'temp', 'accel'
    recorded_at TIMESTAMPTZ NOT NULL,
    uploaded_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ                -- Auto-purge after 12 months
);
SELECT create_hypertable('raw_biosignal_uploads', 'recorded_at');

-- User settings
CREATE TABLE user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    notification_max_per_day INT DEFAULT 5,    -- Soft backstop, post-Ulpan refactor
    stress_threshold FLOAT DEFAULT 0.75,
    quiet_hours_start TIME DEFAULT '22:00',
    quiet_hours_end TIME DEFAULT '08:00',
    silence_during_meeting BOOLEAN DEFAULT TRUE,
    silence_during_exercise BOOLEAN DEFAULT TRUE,
    consent_audit_logging BOOLEAN DEFAULT TRUE,
    language TEXT DEFAULT 'ko'
);

-- Audit log (immutable, append-only)
CREATE TABLE audit_log (
    id UUID PRIMARY KEY,
    user_id UUID,
    actor_id UUID,                        -- Same as user_id unless admin action
    action TEXT NOT NULL,                 -- 'consent_granted', 'data_accessed', etc.
    resource_type TEXT,
    resource_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
SELECT create_hypertable('audit_log', 'created_at');
```

### 6.4 RDS instance sizing

| Environment | Instance | Storage | Estimated cost |
|---|---|---|---|
| Production | db.t4g.small (2 vCPU, 2GB RAM) | 20GB gp3 | ~$25/month |
| Staging | db.t4g.micro (1 vCPU, 1GB RAM) | 10GB gp3 | ~$13/month |

TimescaleDB is installed via the RDS Custom Parameter Group + `CREATE EXTENSION timescaledb`. Verified compatible with RDS Postgres 15.

### 6.5 Backups

- Automated daily snapshots, 7-day retention
- Point-in-time recovery enabled (5-minute granularity)
- Manual snapshots before any destructive migration
- Backup restore tested at least once before production launch

---

## 7. API Design

### 7.1 Decision

**REST + WebSockets, both on FastAPI.**

### 7.2 Rationale

REST handles all CRUD operations cleanly. FastAPI's auto-generated OpenAPI spec gives us free Swagger UI and type-safe client codegen for Flutter. WebSockets handle the real-time channel for events flowing between watch, phone, and (in v2) multi-device sync.

GraphQL was rejected — the data model is simple enough that REST is more honest. gRPC was rejected — mobile client support is weaker.

### 7.3 REST endpoint inventory

See Appendix B for full endpoint list with request/response schemas.

Grouped by resource:
- `/auth/*` — anonymous issue, social OAuth exchange, refresh, logout
- `/account/*` — registration, deletion, anonymous-to-registered migration
- `/events/*` — stress event CRUD
- `/cycles/*` — period log, current phase, history
- `/insights/*` — weekly reports, history, feedback
- `/settings/*` — user preferences
- `/sync/*` — encrypted backup (opt-in)
- `/admin/*` — admin-only endpoints (RBAC-protected)

### 7.4 WebSocket protocol

**Endpoint:** `WSS /ws/realtime`

**Authentication:** JWT in query string on connection (`?token=...`), validated on connect, rejected if invalid.

**Message format:** JSON, all messages have `type` and `payload`:

```json
{
  "type": "event.created",
  "payload": {
    "event_id": "uuid",
    "detected_at": "2026-05-04T14:23:15Z",
    "cycle_phase": "luteal",
    "model_confidence": 0.82
  }
}
```

**Server → client message types:**
- `event.created` — new stress event from another device
- `event.updated` — log added to existing event
- `cycle.updated` — period start logged on another device
- `insight.ready` — weekly insight generated
- `pong` — heartbeat response

**Client → server message types:**
- `ping` — heartbeat
- `subscribe` — subscribe to specific event types
- `ack` — acknowledge receipt of server message

**Reconnection:** Exponential backoff on client (500ms, 1s, 2s, 4s, 8s, 16s, max 30s). Server gracefully closes idle connections after 5 minutes; client reconnects.

### 7.5 Versioning

URL-based versioning: `/api/v1/...`. v2 will live at `/api/v2/...` with v1 maintained for backward compatibility for at least 6 months after v2 GA.

### 7.6 Rate limiting

`slowapi` with Postgres backend (no Redis dependency in v1), configured per-endpoint:
- Auth endpoints: 10 req/min per IP
- Standard endpoints: 100 req/min per user
- WebSocket: 1 connection per user, 10 messages/sec

---

## 8. Authentication & Authorization

### 8.1 Decision

**Supabase Auth as JWT issuer; FastAPI verifies signatures and enforces authorization.**

### 8.2 Rationale

Auth is the highest-risk-per-line-of-code area to roll yourself. Mistakes here become security holes. Supabase Auth gives us battle-tested JWT issuance, Google/Apple OAuth integration, password reset flows, email verification — all production-grade. We avoid the trap of rolling our own auth while still demonstrating senior engineering through how we *use* the auth system (anonymous-first conversion, role-based access, audit logging).

Supabase users live in our own Postgres database (Supabase is essentially a managed Postgres extension), so there is minimal vendor lock-in. We can self-host or migrate later without changing client code.

### 8.3 Anonymous-first model

```
User opens app for the first time
   ↓
Phone calls POST /auth/anon
   ↓
Backend creates user row (anon_id set, supabase_user_id NULL)
   ↓
Backend issues JWT with sub=anon_id, role='user'
   ↓
Phone stores JWT in Android Keystore
   ↓
User uses app, all data tied to anon_id
   
USER DECIDES TO REGISTER (e.g., wants cloud sync)
   ↓
Phone shows Google/Apple OAuth flow
   ↓
Phone gets Google ID token from Google Sign-In SDK
   ↓
Phone calls POST /auth/google with ID token
   ↓
Backend verifies token with Google
   ↓
Backend checks if Google user already exists in users table:
   - If yes → reject (account already exists)
   - If no → migrate: link supabase_user_id to existing anon row
   ↓
Backend issues new JWT with sub=user_id, role='user'
   ↓
Phone discards old anon JWT, stores new one
```

### 8.4 JWT structure

| Claim | Value |
|---|---|
| `sub` | User ID (anon_id or supabase_user_id) |
| `iss` | `https://<project>.supabase.co/auth/v1` |
| `aud` | `authenticated` |
| `role` | `user` or `admin` |
| `iat` | Issue time |
| `exp` | Expiry (15 min for access tokens) |
| `is_anonymous` | `true` for anonymous users |

### 8.5 Token lifecycle

- Access token: 15 min expiry, sent in `Authorization: Bearer <token>` header
- Refresh token: 30 days, stored in Android Keystore, used to get new access tokens
- Refresh tokens are rotated (each refresh issues a new refresh token, old one invalidated)
- Logout revokes all tokens for the user (revocation list in Redis)

### 8.6 Role-based access control

Two roles in v1: `user` and `admin`.

`admin` role is set manually in the database for team members. There is no self-service admin signup.

Admin endpoints are protected by a FastAPI dependency that checks role:

```python
async def require_admin(user: User = Depends(get_current_user)):
    if user.role != 'admin':
        raise HTTPException(403, "Admin access required")
    return user
```

---

## 9. Hosting & Deployment

### 9.1 Decision

**AWS ECS Fargate in Seoul region (ap-northeast-2).**

### 9.2 Rationale

Korean enterprises (Samsung, Naver, Kakao, Coupang) overwhelmingly use AWS for international workloads. AWS Seoul knowledge transfers directly to Korean job market value. ECS Fargate is serverless containers — we get the simplicity of "push image, AWS runs it" without managing EC2 instances or Kubernetes.

Cloud Run (GCP) would be cheaper and slightly easier, but the AWS portfolio signal is more durable for Korean career trajectory.

### 9.3 AWS resources

| Resource | Purpose | Sizing |
|---|---|---|
| VPC | Network isolation | Single VPC, 3 AZs |
| Public subnets | ALB | 3 (one per AZ) |
| Private subnets | ECS tasks, RDS | 3 (one per AZ) |
| NAT Gateway | Outbound internet from private subnet | 1 (cost optimization) |
| Application Load Balancer | TLS termination, routing | Standard |
| ECS Cluster | Container orchestration | 1 cluster, multiple services |
| ECS Service: API | FastAPI app | 1–4 Fargate tasks, auto-scaling |
| ECR | Container registry | 1 repository |
| RDS Postgres | Primary database | Section 6.4 |
| S3 | Encrypted backups + raw biosignal blobs | 1 bucket, lifecycle policies |
| AWS KMS | Encryption keys for standard data | 1 customer-managed key |
| AWS Secrets Manager | DB passwords, API keys | Multiple secrets |
| CloudWatch | Logs, metrics, alarms | Standard |
| X-Ray | Distributed tracing | Standard |
| EventBridge | Cron job scheduling | Multiple rules |
| Lambda | Cron job execution | Multiple functions |
| Route 53 | DNS | 1 hosted zone |
| ACM | TLS certificates | 1 cert (api.domain.com) |

### 9.4 Network topology

```
Internet
   ↓
Route 53 → ALB (public subnet)
   ↓
ECS Fargate tasks (private subnet)
   ↓
   ├── RDS Postgres (private subnet, no public access)
   ├── S3 (via VPC endpoint, no internet egress)
   ├── Secrets Manager (via VPC endpoint)
   └── External services (via NAT Gateway):
       ├── Supabase (auth verification)
       ├── Sentry (error reporting)
       └── FCM (push notifications)
```

All ingress is HTTPS-only via ALB. ECS tasks have no public IPs. RDS is unreachable from the internet.

### 9.5 Auto-scaling

ECS service scales based on CPU utilization and request count:
- Min: 1 task
- Max: 4 tasks
- Target CPU: 60%
- Scale-out cooldown: 60 sec
- Scale-in cooldown: 300 sec

For POC scale (100 beta users), 1 task is plenty most of the time. Auto-scaling exists for safety, not necessity.

---

## 10. Real-Time Architecture

### 10.1 Decision

**WebSocket (foreground) + FCM (background) hybrid.**

### 10.2 Rationale

Android aggressively kills background WebSocket connections to save battery. Fighting Android is a losing battle; standard practice is to use Firebase Cloud Messaging (FCM) when the app is in the background and WebSocket only when the app is in the foreground. Slack, KakaoTalk, Instagram, and every major Android app uses this pattern.

### 10.3 Connection lifecycle

```
App in foreground:
   Phone has WebSocket open to backend (WSS /ws/realtime)
   Real-time events flow through WebSocket
   Heartbeat every 30 sec
   
App goes to background:
   Phone closes WebSocket gracefully (sends "bye" message)
   Backend marks user as "offline" in connection registry
   
Backend has new event for user (e.g., notification fired):
   Backend checks connection registry
   If user offline → sends FCM push via Firebase Admin SDK
   Phone receives FCM push, displays system notification
   
User taps notification or opens app:
   Phone reconnects WebSocket
   Phone fetches missed events via REST (GET /events?since=...)
   Connection registry updated
```

### 10.4 Connection registry

Stored in Postgres as a small `websocket_connections` table mapping user_id → active connection IDs (with task_id for multi-task scenarios). Allows the backend to broadcast events to specific users across all their devices. Volume is low at POC scale (a few hundred concurrent rows), so a dedicated cache is unnecessary. If scale forces migration later, ElastiCache (Redis) becomes worth introducing — but only at that point, not preemptively.

### 10.5 Authentication on WebSocket

JWT passed as query parameter on connection:
```
WSS /ws/realtime?token=<jwt>
```
Validated on connect via the same `python-jose` flow as REST. Rejected connections are closed with code 1008 (policy violation).

---

## 11. Galaxy Watch 8 Integration

### 11.1 Decision

**Path C — Hybrid architecture.** A native Wear OS app (Kotlin) on the Galaxy Watch 8 reads raw sensor data via Samsung Health Sensor SDK 1.4.1, runs on-device ML inference, and surfaces real-time notifications and the breathing exercise on the watch face. The Flutter phone app handles all heavy UX (dashboard, calendar, insights, settings). Watch and phone communicate via Android's Wearable Data Layer.

### 11.2 Rationale

A real-time stress detection product cannot be built on aggregated health data. The ML model needs raw HRV, PPG, EDA, accelerometer, and skin temperature signals. The Sensor SDK provides exactly this; the Health Data SDK does not.

Putting the notification and breathing exercise on the watch face (not just the phone) is what makes the BeReal-style ritual feel native. A user in a meeting with their phone on the desk should feel a gentle wrist tap and tap "breathe," not have to fish out their phone. This is a load-bearing UX decision that requires a Wear OS app.

The phone is *not* eliminated: cycle calendar, weekly insights, settings, history, and account flows all live on the phone. The watch handles the moment of detection and reflection; the phone handles everything that happens before and after.

### 11.3 SDK verification (May 4, 2026)

Samsung Health Sensor SDK package version 1.4.1 (`samsung-health-sensor-sdk-v1_4_1.zip`) was inspected directly. The following data types are confirmed available via `HealthTrackerType` enum:

| Data type | Constant | What we use it for |
|---|---|---|
| Heart rate + IBI | `HEART_RATE`, `HEART_RATE_CONTINUOUS` | HRV computation (the foundation) |
| PPG green | `PPG_GREEN`, `PPG_CONTINUOUS` | Raw optical signal for model input |
| PPG IR / Red | `PPG_IR`, `PPG_RED` | Additional PPG channels |
| ECG | `ECG_ON_DEMAND` | Not used in v1 (on-demand only) |
| EDA | `EDA_CONTINUOUS` | Skin conductance — the second core stress signal |
| Accelerometer | `ACCELEROMETER`, `ACCELEROMETER_CONTINUOUS` | Activity gating + motion artifact filtering |
| Skin temperature | `SKIN_TEMPERATURE_CONTINUOUS` | Cycle phase detection (period start) |
| BIA | `BIA_ON_DEMAND` | Not used in v1 |
| SpO2 | `SPO2`, `SPO2_ON_DEMAND` | Not used in v1 |
| Sweat loss | `SWEAT_LOSS` | Not used in v1 |

The four channels we actually need for the v1 stress detection model — PPG (continuous), heart rate including IBI list, EDA (continuous), and accelerometer (continuous) — are all confirmed available as continuous event streams. The Sensor SDK delivers exactly the architecture the project requires.

The specific value keys exposed for our channels:

```kotlin
// HeartRateSet
ValueKey.HeartRateSet.HEART_RATE          // BPM
ValueKey.HeartRateSet.HEART_RATE_STATUS   // Quality flag
ValueKey.HeartRateSet.IBI_LIST            // List of inter-beat intervals (ms) ← HRV input
ValueKey.HeartRateSet.IBI_STATUS_LIST     // Per-IBI quality flags

// PpgGreenSet
ValueKey.PpgGreenSet.PPG_GREEN            // Raw green PPG samples
ValueKey.PpgGreenSet.STATUS

// EdaSet
ValueKey.EdaSet.SKIN_CONDUCTANCE          // EDA value
ValueKey.EdaSet.STATUS

// AccelerometerSet
ValueKey.AccelerometerSet.ACCELEROMETER_X
ValueKey.AccelerometerSet.ACCELEROMETER_Y
ValueKey.AccelerometerSet.ACCELEROMETER_Z

// SkinTemperatureSet
ValueKey.SkinTemperatureSet.OBJECT_TEMPERATURE   // Skin temp
ValueKey.SkinTemperatureSet.AMBIENT_TEMPERATURE  // Ambient (for noise calibration)
ValueKey.SkinTemperatureSet.STATUS
```

### 11.4 SDK access model

The Sensor SDK ships as a public AAR file (`samsung-health-sensor-api-1.4.1.aar`). Development and testing on a developer-mode-enabled Galaxy Watch 8 do not require partnership approval; the SDK can be downloaded, integrated, and exercised against real sensors immediately.

For public distribution to beta users and beyond, partner registration is required (Samsung's standard distribution gate). We will apply for partner registration during weeks 6–10 of the build, while the de-risking pilot runs internally on developer-mode watches. Academic backing from Kookmin University strengthens the application.

### 11.5 Architecture — what runs where

```
┌─────────────────────────────────────────────────────────────┐
│  GALAXY WATCH 8 (Wear OS native, Kotlin)                    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Samsung Health Sensor SDK 1.4.1                     │    │
│  │   - HealthTrackingService (entry point)             │    │
│  │   - Continuous trackers: PPG, HR+IBI, EDA, ACC, TEMP│    │
│  │   - Connection callback model                       │    │
│  └─────────────────────────────────────────────────────┘    │
│             │ (raw sensor events)                           │
│             ▼                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Signal Preprocessor (Kotlin)                        │    │
│  │   - 60-second sliding windows                       │    │
│  │   - Personal baseline tracker (5-min EMA on live    │    │
│  │     stream — NOT broken by training fracture)       │    │
│  │   - Activity gate (suppress during exercise)        │    │
│  └─────────────────────────────────────────────────────┘    │
│             │                                               │
│             ▼                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Stress Detection Model (ONNX Runtime Mobile)        │    │
│  │   - 4-channel Mamba classifier                      │    │
│  │   - On-device inference                             │    │
│  │   - Output: P(stress) per 60s window                │    │
│  └─────────────────────────────────────────────────────┘    │
│             │                                               │
│             ▼                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Decision Engine (Kotlin)                            │    │
│  │   - Confidence thresholding                         │    │
│  │   - Hysteresis (sustained signal requirement)       │    │
│  │   - Daily soft cap (post-Ulpan refactor)            │    │
│  │   - Phase-aware threshold modulation                │    │
│  └─────────────────────────────────────────────────────┘    │
│             │                                               │
│        ┌────┴────┐                                          │
│        ▼         ▼                                          │
│  ┌──────────┐ ┌────────────────────────────────────────┐    │
│  │ Watch UI │ │ Wearable Data Layer (sync to phone)    │    │
│  │ (notif + │ │   - Stress events                      │    │
│  │ breathe) │ │   - Cycle phase auto-detection results │    │
│  └──────────┘ │   - Opt-in raw biosignal blobs         │    │
│               └────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Bluetooth (Android Data Layer)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  PHONE (Flutter)                                            │
│                                                             │
│  ├─► Receives events from watch                             │
│  ├─► Renders dashboard, calendar, insights                  │
│  ├─► Settings, account, premium, history                    │
│  └─► REST + WebSocket to backend                            │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ HTTPS / WSS
                         ▼
                AWS Seoul backend (sections 4–10)
```

**Critical insight from this architecture:** the EMA baseline tracking that "fractured training data" supposedly broke can be fully reconstructed at inference time on the watch's continuous live stream. The fracture problem is a *training data* problem, not a *deployment* problem. Live Galaxy Watch 8 sensor data is continuous; the watch can compute a real 5-minute rolling baseline from the moment the user puts on the watch. This was the central technical insight of the earlier brainstorming on stress detection accuracy.

### 11.6 Sample rates and battery considerations

Samsung's continuous trackers run at relatively low sample rates by design — the SDK explicitly emphasizes that "the SDK's continuous tracker gathers sensor data in an application processor without waking up the CPU and sends an event at specific periods to a watch application," which minimizes battery consumption.

Expected sample rates (to be verified empirically during SDK testing):
- PPG: ~25 Hz continuous
- Heart rate + IBI: event-driven (one event per heartbeat for IBI)
- EDA: ~25 Hz continuous
- Accelerometer: ~25 Hz continuous
- Skin temperature: ~1 Hz continuous

The Mamba model was trained on WorkStress3D and similar datasets at comparable sample rates (Empatica E4 native rates), so the inference-time data should match the training-time data shape with minimal resampling. Nika needs to confirm sample-rate compatibility during her audit.

Battery impact target: <5% per day from continuous monitoring. The Sensor SDK is engineered for this; Samsung explicitly designed continuous trackers to run on the application processor without waking the CPU.

### 11.7 Wearable Data Layer protocol

Watch-to-phone communication uses Android's official Wearable Data Layer API, specifically:
- `MessageClient` for low-latency event notifications (stress event detected → phone)
- `DataClient` for syncing structured records (event details, cycle data)
- `ChannelClient` for streaming raw biosignal blobs (only when user has opted into raw data contribution)

Message types defined for the watch ↔ phone protocol:

| Message | Direction | Purpose |
|---|---|---|
| `STRESS_EVENT_DETECTED` | Watch → Phone | New stress event for backend sync |
| `CYCLE_TEMP_SHIFT` | Watch → Phone | Skin temp shift suggesting period start |
| `LOG_LATER_REQUEST` | Phone → Watch | User wants to log on phone instead |
| `SETTINGS_UPDATED` | Phone → Watch | New thresholds, quiet hours, etc. |
| `RAW_BLOB_AVAILABLE` | Watch → Phone | Encrypted raw biosignal blob ready for upload |
| `MODEL_UPDATE_AVAILABLE` | Phone → Watch | New ONNX model file from backend |

All payloads are JSON-serialized, signed with a shared key derived from the user's session.

### 11.8 Permissions model

Wear OS app requires the following permissions, requested at first launch with clear explanation:

```xml
<uses-permission android:name="com.samsung.android.service.health.permission.HEALTH"/>
<uses-permission android:name="com.samsung.wearable.healthtracking.SENSOR_DATA"/>
<uses-permission android:name="android.permission.BODY_SENSORS"/>
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
```

User-facing explanation matches the brand voice (per notification engagement spec):
> *"We need to read your heart, sweat, and movement signals. They never leave your watch unless you explicitly opt in to share them."*

If permissions are denied, the app falls back to a degraded mode that uses Samsung's pre-computed stress score from Health Data SDK on the phone — same product UX, weaker model. This is the safety net, not the default path.

### 11.9 ML model deployment and updates

The ONNX model file ships with the watch app initially. Future model updates (e.g., the v2 retrained female-only model) flow as:

```
Backend stores model file in S3 (Seoul, public read with version tag)
   ↓
Phone polls /api/v1/model/version on weekly schedule
   ↓
If new version: phone downloads ONNX file
   ↓
Phone sends MODEL_UPDATE_AVAILABLE to watch via DataClient
   ↓
Watch fetches new model from phone, validates checksum
   ↓
Watch hot-swaps model on next inference
```

Model versions are tagged semantically (e.g., `1.0.0-wesad-baseline`, `1.1.0-stresspredict-female-tuned`). Backend tracks per-user model version in the user_settings table.

### 11.10 Failure modes and degraded operation

| Failure | What happens | User experience |
|---|---|---|
| Watch loses Bluetooth to phone | Watch buffers events locally (up to 1000 events / 24h) | Notifications still fire on watch; sync resumes when reconnected |
| Sensor returns invalid readings | Status flags filter out bad samples in Preprocessor | No false positives from sensor errors |
| Watch battery <15% | Reduce continuous monitoring to event-driven only | User notified; tracking degraded but not dead |
| User denies sensor permission | Fall back to Samsung Health Data SDK stress score | Lower-fidelity product but functional |
| Sensor SDK service unavailable | Show diagnostic error, offer reconnect | Clear error state, not silent failure |

### 11.11 What's not in v1

- ECG-based stress detection (more accurate but requires user to actively place finger on watch — breaks the passive-monitoring UX)
- BIA-based body composition (not relevant to product)
- SpO2-based stress correlation (research is weak)
- Sweat loss after running workout (not relevant)
- On-watch full app UI (dashboard, calendar, etc.) — those live on the phone

These are deliberate scope cuts. The watch does the four things it does best (sensor reading, ML inference, notification firing, breathing exercise) and nothing else.

---

## 12. Data Privacy & Encryption

### 12.1 Decision

**Defensible-grade privacy: AWS KMS for standard data, user-held keys for opt-in raw biosignals, app-level audit logging, explicit retention policies.**

### 12.2 Rationale

Women's health data is the most politically sensitive consumer data category in 2026. Flo's $56M class-action settlement reset baseline expectations. Korean PIPA has specific requirements around sensitive personal information. Privacy by architecture (not promise) is the only defensible position.

### 12.3 Data classification

| Class | Examples | Encryption | Retention |
|---|---|---|---|
| **Standard** | Stress events, cycle data, settings, audit log | AWS KMS at rest | While account active |
| **Sensitive** | Free-text logs, chip selections | AWS KMS at rest, app-level encryption for free text | While account active |
| **Highly sensitive** | Raw biosignals (opt-in only) | User-held keys (E2E) | 12 months auto-purge |

### 12.4 Encryption details

**Standard data (RDS Postgres):**
- Database-level encryption at rest via AWS KMS (customer-managed key)
- TLS 1.3 in transit
- Free-text log fields additionally encrypted at the application layer using AWS KMS envelope encryption (so even DB admins can't read them)

**Raw biosignal blobs (S3):**
- User generates encryption key on device (Android Keystore + BIP-39 12-word recovery phrase)
- Phone encrypts blob with XChaCha20-Poly1305 AEAD before upload
- Phone uploads ciphertext to S3 via presigned URL
- Backend stores S3 object key, never sees plaintext
- User can revoke consent → deletes all their raw biosignal objects from S3

### 12.5 Audit logging

Every operation that touches sensitive data writes to the immutable `audit_log` table:

| Event | Logged |
|---|---|
| User logs in | Yes |
| User views own data | No (too noisy) |
| User exports their data | Yes |
| User deletes account | Yes |
| User grants/revokes consent | Yes |
| Admin queries any user's data | Yes (with admin's user_id as actor_id) |
| Background job processes user data | Yes |

The `audit_log` table is append-only by application convention. Periodic check via Lambda verifies no rows have been deleted (integrity check).

### 12.6 Data retention

| Data type | Retention |
|---|---|
| User account | While active; 30-day grace period after deletion request |
| Stress events | While account active |
| Cycle data | While account active |
| Free-text logs | While account active |
| Raw biosignals | 12 months from upload, auto-purged |
| Audit log | 24 months |
| Backups | 7 days (daily snapshot) |
| Application logs | 30 days in CloudWatch |

Retention enforced by EventBridge + Lambda jobs running daily.

### 12.7 Subprocessor disclosure

Listed in privacy policy:
- AWS (hosting + storage, Seoul region)
- Supabase (auth)
- Sentry (error tracking)
- Firebase (push notification delivery only)

Each subprocessor's role is described plainly. No surprise data sharing.

### 12.8 PIPA compliance

- Explicit informed consent flow during onboarding
- Sensitive data category designation for cycle and biosignal data
- Korean-language privacy policy reviewed by Korean legal counsel before launch
- Data processor agreements with each subprocessor
- User rights (access, correction, deletion, portability) all surfaced in settings UI
- Data breach notification process documented (to KCC within 24 hours)

---

## 13. Observability

### 13.1 Decision

**CloudWatch + structlog + Sentry + OpenTelemetry/X-Ray.**

### 13.2 Rationale

A backend without observability is unfinished. The four-tool stack covers the four observability pillars (logs, errors, traces, metrics) with industry-standard tools.

### 13.3 Logging

- **Library:** `structlog`
- **Format:** JSON
- **Destination:** CloudWatch Logs (auto-captured from stdout)
- **Retention:** 30 days
- **Required fields per log:** `timestamp`, `level`, `event`, `user_id` (where applicable), `trace_id`

Example:
```json
{
  "timestamp": "2026-05-04T14:23:15.123Z",
  "level": "INFO",
  "event": "stress_event_created",
  "user_id": "abc123",
  "trace_id": "def456",
  "event_id": "ghi789",
  "cycle_phase": "luteal",
  "model_confidence": 0.82
}
```

### 13.4 Error tracking

- **Service:** Sentry.io (free tier, 5,000 errors/month)
- **SDK:** `sentry-sdk[fastapi]`
- **Captures:** All unhandled exceptions, plus explicit `capture_message` for warnings
- **Includes:** Stack trace, request context, user_id (anonymized), trace_id
- **Excludes:** PII (free-text logs, identifiers beyond user_id)

### 13.5 Distributed tracing

- **Library:** `opentelemetry-instrumentation-fastapi` + `opentelemetry-instrumentation-sqlalchemy`
- **Backend:** AWS X-Ray
- **Spans created automatically:** HTTP requests, DB queries, outbound HTTP calls
- **Custom spans:** `with tracer.start_as_current_span("process_stress_event"):`

### 13.6 Metrics

- **Built-in CloudWatch:** Request rate, latency p50/p95/p99, error rate (per ALB target group)
- **Custom Prometheus metrics:** Exposed at `/metrics` endpoint
  - `stress_events_created_total` (counter)
  - `weekly_insights_generated_total` (counter)
  - `notifications_sent_total{type=fcm|websocket}` (counter)
  - `db_query_duration_seconds` (histogram)
  - `active_websocket_connections` (gauge)
- Scraped by CloudWatch Container Insights or pulled into Grafana Cloud (free tier)

### 13.7 Health checks

- `/health` returns 200 with simple JSON: `{"status": "ok", "version": "1.0.0", "git_sha": "..."}`
- ALB target health check polls every 30 sec
- ECS uses health check for task lifecycle

### 13.8 Alerts (CloudWatch Alarms)

| Alarm | Condition | Action |
|---|---|---|
| High error rate | Error rate > 5% for 5 min | Email + SNS |
| High latency | p99 latency > 2s for 5 min | Email |
| DB connection saturation | DB connections > 80% capacity | Email |
| Failed deploys | ECS service deployment failure | Email |
| Low disk space | RDS storage > 85% used | Email |

---

## 14. CI/CD & Infrastructure as Code

### 14.1 Decision

**GitHub Actions for CI/CD; Terraform for infrastructure; staging + production environments.**

### 14.2 Rationale

GitHub Actions is the standard CI/CD platform; integrates natively with the GitHub repo. Terraform is the universal IaC standard (more transferable than CDK or Pulumi). Staging environment is the difference between safe deployment and YOLO deployment.

### 14.3 Repository structure

```
project-phase-backend/
├── app/                # Python application code
├── infra/              # Terraform IaC
│   ├── main.tf
│   ├── networking.tf
│   ├── ecs.tf
│   ├── rds.tf
│   ├── s3.tf
│   ├── lambda.tf
│   ├── monitoring.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── staging.tfvars
│   └── production.tfvars
├── .github/workflows/
│   ├── ci.yml          # Runs on every PR
│   ├── deploy-staging.yml
│   └── deploy-production.yml
├── Dockerfile
├── docker-compose.yml  # Local dev (Postgres + app)
└── README.md
```

### 14.4 CI pipeline (`.github/workflows/ci.yml`)

Triggered on every PR:

1. Lint with ruff
2. Type-check with mypy
3. Run pytest with coverage
4. Build Docker image
5. Scan image for CVEs with Trivy

PR cannot be merged unless all checks pass.

### 14.5 CD pipeline

**Staging deploy** (auto on merge to main):
1. Build Docker image
2. Tag with git SHA
3. Push to ECR
4. Run Alembic migrations against staging DB
5. Update ECS staging service to new image
6. Run smoke tests against staging
7. Notify Slack channel

**Production deploy** (manual approval after staging green):
1. Manual approval gate in GitHub Actions UI
2. Same steps as staging, but against production
3. Blue/green deployment via ECS (zero-downtime)
4. Post-deploy smoke tests
5. Auto-rollback if health checks fail

### 14.6 Terraform workflow

- All AWS resources defined in `/infra`
- State stored in S3 backend (separate bucket from app data) with DynamoDB locking
- `terraform plan` runs in CI on PRs touching `/infra` directory
- `terraform apply` runs only on manual workflow dispatch (cannot accidentally apply via merge)
- Two state files: `staging` and `production`

### 14.7 Environments

| Element | Staging | Production |
|---|---|---|
| ECS task count | 1 | 1–4 (auto-scaled) |
| RDS instance | db.t4g.micro | db.t4g.small |
| Domain | api-staging.domain.com | api.domain.com |
| Secrets | Separate Secrets Manager paths | Separate Secrets Manager paths |
| Database | Separate RDS instance | Separate RDS instance |
| Estimated cost | ~$30/month | ~$60/month |

Both in Seoul region. Both fully isolated from each other.

---

## 15. Security Hardening

### 15.1 Secrets management

- **AWS Secrets Manager** for all secrets (DB passwords, JWT signing keys, Sentry DSN, FCM credentials)
- ECS task definitions reference secrets by ARN; values never appear in code, env files, or logs
- Secrets rotated every 90 days (DB password) or 365 days (others)

### 15.2 Network security

- All ingress via ALB on port 443 only
- ECS tasks have no public IPs
- RDS is in private subnet, security group allows only ECS task security group
- NAT Gateway for outbound; no direct internet from private subnet

### 15.3 IAM

- Principle of least privilege
- ECS task role has only the specific permissions it needs (S3 PutObject on specific bucket, Secrets Manager GetSecretValue on specific secrets, etc.)
- No `*` permissions
- Admin actions require MFA

### 15.4 Dependency management

- `pip-audit` runs in CI; PR fails if known CVEs in dependencies
- Dependabot enabled for automated dependency PRs
- Trivy scans Docker images for CVEs before deploy

### 15.5 Input validation

- All request bodies validated by Pydantic schemas
- Strict typing throughout
- SQL injection impossible (SQLAlchemy parameterized queries)
- XSS not relevant (no HTML rendering server-side)

### 15.6 Rate limiting

- `slowapi` library with Postgres backend (no Redis dependency)
- Per-IP and per-user limits
- Specific tighter limits on auth endpoints (10/min) and write endpoints (50/min)

### 15.7 CORS

- Only the admin web UI origin allowed for cross-origin requests
- Mobile apps don't trigger CORS (native HTTP clients)

---

## 16. Team & Ownership

### 16.1 Why this section exists

Earlier versions of this spec did not name owners for each workstream. Adding the Galaxy Watch 8 integration surfaced a real gap: the Wear OS / Android engineer role was implicit but unassigned. This section makes ownership explicit so the team can plan accordingly.

### 16.2 Roles needed

| Role | Owns | Skills required | Status |
|---|---|---|---|
| Product / engineering lead | Overall direction, backend architecture, integration glue | Python, AWS, system design | Anu |
| ML / data engineer | Stress detection model, dataset audit, model training and ONNX export | Python, PyTorch / state-space models, biosignal processing | Nika |
| UI/UX designer | All user-facing visual design, screen flows, design system | Figma, design systems, mobile UX | Ulpan |
| Backend engineer | FastAPI service, database schema, API endpoints, AWS deployment | Python, FastAPI, PostgreSQL, AWS | TBC — possibly Anu solo |
| Wear OS / Android engineer | Wear OS app on Galaxy Watch 8, Sensor SDK integration, watch ↔ phone protocol | Kotlin, Android, Wear OS, Wearable Data Layer API | **TBC — gap surfaced by SDK verification step** |
| Phone (Flutter) engineer | Flutter Android app, all 35 screens, watch event handling | Dart, Flutter, Android platform channels | TBC |
| Admin UI engineer | Admin web frontend | React or similar | TBC — teammate-led per Decision 9 |

### 16.3 Critical gap: Wear OS engineer

The Wear OS / Android engineer role is the highest-priority hire/recruit on the team right now. Reasons:

- The watch app is on the critical path for the entire product (sensor data + notifications + breathing exercise all live there)
- It's an 8-week workstream, not a side task
- Kotlin + Wear OS + Sensor SDK is a specific skill set most generalists don't have

**Action:** before the build starts, identify a Wear OS engineer. Options in order of preference:
1. A teammate from Anu's Kookmin network who has Android experience and is willing to learn Wear OS
2. A paid collaborator (freelance or part-time student)
3. Anu learns Wear OS and does it herself (adds significant time, but possible)

The minimum-viable starting point: Anu personally runs the SDK verification step (download SDK, run sample app on Galaxy Watch 8, confirm raw sensor access) so she has firsthand knowledge of the constraints before recruiting.

### 16.4 Ownership boundaries

To avoid stepping on each other:

- **Backend ↔ Wear OS:** owned by different people; communicate via REST API contracts (OpenAPI spec)
- **Wear OS ↔ Phone (Flutter):** communicate via Wearable Data Layer protocol (Section 11.7); message types defined jointly by Wear OS engineer and Flutter engineer
- **Phone (Flutter) ↔ Backend:** REST + WebSocket; OpenAPI spec is source of truth
- **ML model file:** Nika produces ONNX file, Anu deploys to S3, Wear OS engineer integrates ONNX Runtime Mobile

Each interface is defined as a contract between two roles. Changes to a contract require both sides to agree.

---

## 17. Out of Scope (and Why)

| Item | Reason |
|---|---|
| Background workers (Celery + Redis) | No async workload justifies them; Lambda is sufficient |
| LLM-generated insights | Privacy architecture is real engineering; deferred to v2 with a clear path |
| ML model serving on backend | On-device inference per privacy posture |
| GraphQL | Data model is simple enough that REST is more honest |
| iOS / Apple Watch | Android-only for v1 (PRD §3.3) |
| Multi-region deployment | Seoul only, sufficient for Korean ICP |
| Email/SMS verification | Google/Apple OAuth handles identity verification |
| Payment / subscription handling | Free tier only in v1; premium is v1.5+ |
| Search indexing (Elasticsearch) | Postgres full-text is sufficient at POC scale |
| Public API for third parties | v3+ |
| Webhooks | v3+ |
| Provider portal (OBGYN dashboard) | v2 (PRD §15) |

---

## 18. Decision Log

This section preserves the reasoning behind major architectural choices. Future-me and reviewers can understand *why*, not just *what*.

| # | Decision | Alternatives considered | Why this choice |
|---|---|---|---|
| 1 | Custom backend, not Firebase | Firebase, Supabase, Firebase + custom | Portfolio capstone goal — custom backend itself is a learning artifact |
| 2 | Python + FastAPI | Go, TypeScript, Kotlin | ML/API in same language; Mamba model is Python anyway |
| 3 | Postgres + TimescaleDB | Vanilla Postgres, MongoDB, MySQL | Time-series biosignal data is the right shape; portfolio signal |
| 4 | REST + WebSockets | REST-only, GraphQL | Real-time use case is real; FastAPI native support; clean separation |
| 5 | Supabase Auth | Custom JWT, Auth0, Clerk | Auth is too risky to roll yourself; Supabase has minimal lock-in |
| 6 | AWS Seoul | GCP Cloud Run, Naver Cloud, self-hosted | Korean enterprise interview signal; PIPA-compliant residency |
| 7 | Stress events + opt-in raw biosignals | Events-only, full upload | Privacy-first with v2 ML flywheel; PIPA-defensible |
| 8 | On-device ML only | Hybrid, backend-only | Privacy posture; simpler backend; lower cost |
| 9 | Custom admin UI | Read-only endpoints + Metabase | Teammate-led; specific reason given |
| 10 | Defensible-grade privacy | Light-grade, mix | Coherent with opt-in raw biosignal architecture |
| 11 | WebSocket + FCM hybrid | WebSocket-only, FCM-only | Standard Android pattern; battery-friendly |
| 12 | Full observability stack | CloudWatch-only, Datadog | Senior-engineer signal; all open-source or free-tier |
| 13 | GitHub Actions + Terraform + staging | Various lighter alternatives | Consistent with senior-engineering signal of rest of stack |
| 14 | EventBridge + Lambda for cron, no Celery | Celery + Redis | Without LLM, no async workload justifies Celery |
| 15 | LLM insights deferred to v2 | LLM in v1 | Scope discipline; privacy architecture deferred |
| 16 | Path C hybrid Wear OS architecture | Watch-as-sensor-only (Path B), different wearable (Path C) | Real-time notification on watch face is load-bearing UX; Sensor SDK 1.4.1 verified to provide all required raw channels |
| 17 | Use Samsung Health Sensor SDK 1.4.1 (not Health Data SDK) | Health Data SDK only, custom hardware | Sensor SDK provides raw HRV/PPG/EDA/accel needed for the model; Health Data SDK only gives aggregated metrics |
| 18 | EMA baseline at inference time, not training time | Retrain on continuous data, drop EMA entirely | Watch provides continuous stream; fracture is training-only, solved at inference |

---

## 19. Open Questions

These need resolution but are not blocking the start of v1 build:

| # | Question | Owner | Decision needed by |
|---|---|---|---|
| 1 | Final domain name | Anu | Week 6 |
| 2 | Specific Korean legal counsel for privacy policy review | Anu | Week 8 |
| 3 | Backend engineer teammate confirmed? Or solo? | Anu | Week 1 |
| 4 | **Wear OS / Android engineer recruited** (gap surfaced by SDK verification) | Anu | Week 1 — highest priority |
| 5 | Admin UI tech stack (React, Next.js, etc.) | Admin UI teammate | Week 4 |
| 6 | Beta cohort recruitment plan beyond Kookmin | Anu | Week 8 |
| 7 | TLS certificate management (manual ACM or DNS-validated automation) | Anu | Week 2 |
| 8 | Database backup restore drill timing | Anu | Week 10 |
| 9 | Anu's hands-on SDK verification (run "Transfer heart rate" code lab on Watch 8) | Anu | Week 0 — before any architecture work locks |
| 10 | Sample rate compatibility check between Sensor SDK output and Nika's training data | Nika | Week 1 |
| 11 | Samsung partner registration application timing (needed before public distribution, not for development) | Anu | Week 6–10 |

---

## Appendix A: Cost Estimate

POC scale (100 beta users):

| Service | Estimate |
|---|---|
| ECS Fargate (production) | $30/month |
| ECS Fargate (staging) | $10/month |
| RDS Postgres (production, db.t4g.small) | $25/month |
| RDS Postgres (staging, db.t4g.micro) | $13/month |
| ALB | $20/month |
| NAT Gateway | $33/month |
| S3 (events + opt-in biosignals) | $5/month |
| Data transfer | $5/month |
| CloudWatch Logs | $5/month |
| Other (KMS, EventBridge, Lambda, Secrets Manager) | $5/month |
| **AWS Total** | **~$150/month** |
| Supabase Auth (free tier) | $0 |
| Sentry (free tier) | $0 |
| Firebase FCM (free tier) | $0 |
| **Grand Total** | **~$150/month** |

Higher than initial estimate due to NAT Gateway ($33/month is unavoidable for private subnet outbound).

Cost optimization opportunities for after v1 ships:
- Replace NAT Gateway with VPC Endpoints for S3, Secrets Manager (saves ~$25/month)
- Use Fargate Spot for staging (saves ~$5/month)
- Drop staging environment entirely between releases (saves ~$23/month)

---

## Appendix B: Endpoint Inventory

Full REST endpoint list with HTTP methods. Detailed request/response schemas live in OpenAPI spec generated by FastAPI at runtime; this is the high-level inventory.

### Auth (5 endpoints)
- `POST /api/v1/auth/anon` — Issue JWT for anonymous user
- `POST /api/v1/auth/google` — Exchange Google ID token for JWT
- `POST /api/v1/auth/apple` — Exchange Apple ID token for JWT (forward-compat for v2)
- `POST /api/v1/auth/refresh` — Refresh expired access token
- `POST /api/v1/auth/logout` — Revoke session

### Account (3 endpoints)
- `POST /api/v1/account/migrate` — Link anonymous data to registered account
- `DELETE /api/v1/account` — Initiate account deletion (30-day grace)
- `POST /api/v1/account/restore` — Cancel pending deletion within grace period

### Events (5 endpoints)
- `POST /api/v1/events` — Create stress event
- `GET /api/v1/events` — List events with filters
- `GET /api/v1/events/{id}` — Single event detail
- `PATCH /api/v1/events/{id}` — Add log details after the fact
- `DELETE /api/v1/events/{id}` — User deletes event

### Cycles (4 endpoints)
- `POST /api/v1/cycles/period-start` — Log period start
- `GET /api/v1/cycles/current` — Current phase + day
- `GET /api/v1/cycles/history` — Past cycles
- `PATCH /api/v1/cycles/{id}` — Correct logged cycle

### Insights (3 endpoints)
- `GET /api/v1/insights/weekly` — Current week
- `GET /api/v1/insights/history` — Past weekly insights
- `POST /api/v1/insights/{id}/feedback` — User feedback on insight

### Settings (2 endpoints)
- `GET /api/v1/settings` — User preferences
- `PATCH /api/v1/settings` — Update preferences

### Sync (4 endpoints)
- `POST /api/v1/sync/upload` — Upload encrypted backup
- `GET /api/v1/sync/download` — Restore on new device
- `DELETE /api/v1/sync` — Wipe cloud backup
- `POST /api/v1/sync/biosignals` — Upload encrypted raw biosignal blob

### Consent (2 endpoints)
- `GET /api/v1/consent` — Current consent state
- `PATCH /api/v1/consent` — Update granular consent toggles

### Admin (5 endpoints, RBAC-protected)
- `GET /api/v1/admin/users` — List beta users (with consent)
- `GET /api/v1/admin/users/{id}` — User detail
- `GET /api/v1/admin/metrics/retention` — Cohort retention
- `GET /api/v1/admin/metrics/notifications` — Notification stats
- `GET /api/v1/admin/metrics/aggregate` — System-wide metrics

### WebSocket
- `WSS /ws/realtime` — Real-time event channel

### System
- `GET /health` — Health check
- `GET /metrics` — Prometheus metrics
- `GET /docs` — Swagger UI (disabled in production)

**Total: ~33 REST endpoints + 1 WebSocket + 3 system endpoints.**

---

## Appendix C: Sensor SDK Verification Notes

### C.1 What was verified

On May 4, 2026, Samsung Health Sensor SDK package version 1.4.1 (`samsung-health-sensor-sdk-v1_4_1.zip`) was inspected directly to confirm what data types and APIs are actually available before locking the integration architecture.

### C.2 Package contents

```
samsung-health-sensor-sdk-v1_4_1.zip
└── 1.4.1/
    ├── Announcement.txt              (open-source license disclosures)
    ├── docs/
    │   ├── api-reference.html        (redirect to online docs)
    │   └── programming-guide.html    (redirect to online docs)
    ├── libs/
    │   └── samsung-health-sensor-api-1.4.1.aar    (the actual SDK library)
    └── sample-codes/
        ├── ecg-monitor.html
        ├── measure-skin-temperature.html
        ├── measure-spo2-and-hr.html
        ├── measure-spo2.html
        ├── sweat-loss-monitor.html
        ├── track-heart-rate-with-off-body-sensor.html
        └── transfer-hr-from-watch-to-phone.html
```

The `.html` files in `docs/` and `sample-codes/` are redirects to the online Samsung Developer documentation. The actual SDK code lives in the AAR file.

### C.3 SDK API confirmed via class inspection

The AAR was extracted and the contained `classes.jar` examined. Confirmed package: `com.samsung.android.service.health.tracking.*`

Top-level entry points:
- `HealthTrackingService` — main service class, connection management
- `HealthTracker` — per-data-type tracker
- `HealthTrackerCapability` — query what the device supports
- `ConnectionListener` — service connection callbacks
- `HealthTrackerException` — error handling

Data type enum (`HealthTrackerType`) values confirmed:
```
ACCELEROMETER
ACCELEROMETER_CONTINUOUS
BIA_ON_DEMAND
ECG_ON_DEMAND
EDA_CONTINUOUS
HEART_RATE
HEART_RATE_CONTINUOUS
MF_BIA_ON_DEMAND
PPG_CONTINUOUS
PPG_GREEN
PPG_IR
PPG_ON_DEMAND
PPG_RED
SKIN_TEMPERATURE
SKIN_TEMPERATURE_CONTINUOUS
SKIN_TEMPERATURE_ON_DEMAND
SPO2
SPO2_ON_DEMAND
SWEAT_LOSS
```

ValueKey classes confirmed for each channel we need:
- `HeartRateSet`: HEART_RATE, HEART_RATE_STATUS, IBI_LIST, IBI_STATUS_LIST
- `PpgGreenSet`: PPG_GREEN, STATUS
- `EdaSet`: SKIN_CONDUCTANCE, STATUS
- `AccelerometerSet`: ACCELEROMETER_X, ACCELEROMETER_Y, ACCELEROMETER_Z
- `SkinTemperatureSet`: OBJECT_TEMPERATURE, AMBIENT_TEMPERATURE, STATUS

This confirms the four channels needed by the v1 stress detection model (PPG continuous, HR with IBI list, EDA continuous, accelerometer continuous) are all available as live event streams. Skin temperature for cycle phase detection is also available.

### C.4 What still needs hands-on verification

The class inspection confirms the API surface exists. It does not confirm:

1. **Actual sample rates delivered** when the Watch 8 is worn on a real wrist
2. **Battery impact** of running all four trackers continuously for 24 hours
3. **Quality of IBI data** — how often `IBI_STATUS_LIST` flags samples as low-quality on a real user during real activity
4. **Connection reliability** — how the Wearable Data Layer behaves under realistic Bluetooth conditions
5. **Permission UX** — what the Samsung permission dialogs actually look like to a Korean Gen MZ user

These can only be verified by running the SDK on a real device. The "Transfer heart rate from Galaxy Watch to mobile" code lab is the recommended starting point — it exercises the entire watch → phone data pipeline end-to-end.

**Recommendation:** Anu personally runs that code lab in week 0, before any architecture work starts. Half a day of hands-on verification de-risks the entire integration.

### C.5 Distribution gate

For development and testing on developer-mode Galaxy Watch 8 devices, no Samsung approval is required. The SDK is publicly downloadable.

For public distribution (Galaxy Store, Play Store), partner registration is required. This is a standard Samsung Health distribution gate, not a research-grade approval. Korean academic projects with university backing have a relatively clear path through this process.

Plan: develop and test on developer-mode devices throughout build (weeks 1–8). Submit partner registration during the de-risking pilot phase (weeks 6–10) so distribution access is granted before public beta launch.

### C.6 Honest acknowledgment

An earlier version of this conversation incorrectly stated that Sensor SDK access required upfront partnership approval and was uncertain to obtain. That was wrong, derived from outdated information about an earlier "Privileged Health SDK." Direct inspection of the SDK package and verification against current Samsung Developer documentation corrected this.

The lesson: when a load-bearing architectural decision rests on what an external system does or doesn't allow, verify against current source documentation before designing around the assumed constraint. This appendix exists partly to prevent that mistake from recurring on this project.

---

*End of Backend Architecture Specification*
