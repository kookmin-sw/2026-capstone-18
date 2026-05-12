# Little Signals — Full System Audit (2026-05-12)

**Environment:** Staging only (no real users)
**Subsystems:** Python/FastAPI Backend · AWS Terraform Infra · Wear OS Watch (Kotlin)
**Method:** Three parallel subagents (backend, infra, watch) + coordinator cross-cutting pass

Detailed per-subsystem findings are in sibling files:
- `docs/audit/2026-05-12-backend-findings.md`
- `docs/audit/2026-05-12-infra-findings.md`
- `docs/audit/2026-05-12-watch-findings.md`
- `docs/audit/2026-05-12-cross-cutting-findings.md`

---

## Executive Summary

The audit surfaced **5 critical, 16 high, 29 medium, 14 low, and 11 informational findings** across all subsystems. Three issues demand immediate attention before any demo or real-user traffic: (1) **every successful range-report API call returns HTTP 500** due to a double-commit bug — this is a broken core feature right now; (2) **the watch silently discards biometric data** whenever Bluetooth connectivity drops because `drain()` is called before confirming the send succeeded — data loss is permanent; (3) **the `send_morning_tips` and `send_sleep_nudges` jobs have no EventBridge schedule rules** — these user-facing features have never fired. The infra posture is solid for staging (no public RDS, no public S3, no hardcoded secrets, Trivy scan on every build); the main infra gaps are the missing ECS circuit breaker, no autoscaling, and a OIDC trust that lets any PR contributor assume the staging deploy role. The watch codebase shows the footprint of a short-duration research tool being pushed toward always-on sleep tracking without the necessary architectural changes (bounded buffers, local persistence, reconnect logic, sequence numbers).

---

## Backend Findings

*(Full findings in `docs/audit/2026-05-12-backend-findings.md`)*

### Security

### 🟠 High — JWT bearer token passed in WebSocket query parameter

**File:** `backend/app/realtime/router.py:55`
**Lens:** Security | **Subsystem:** Backend

**What:** The WebSocket endpoint `/ws/realtime` authenticates via a `token` query parameter, logging the JWT in access logs and OTel spans.
**Why it matters:** Bearer tokens are stored in plain text in CloudWatch and any log aggregation system.
**Recommended fix:** Accept the token in the first WebSocket message payload instead of the URL.

---

### 🟠 High — No rate limiting on auth endpoints

**File:** `backend/app/auth/router.py` (entire file)
**Lens:** Security | **Subsystem:** Backend

**What:** No rate limiting on `/auth/anon`, `/auth/google`, `/auth/email/login`, or `/auth/email/signup`.
**Why it matters:** Unlimited `/auth/anon` calls create Supabase users on demand; `/auth/email/login` is a credential-stuffing vector.
**Recommended fix:** Add `slowapi` or AWS WAF cap (~10 req/min per IP on auth endpoints).

---

### 🟡 Medium — `/docs` and `/openapi.json` exposed unconditionally

**File:** `backend/app/main.py:82`
**Lens:** Security | **Subsystem:** Backend

**What:** Swagger UI and OpenAPI schema are enabled in all environments including production.
**Why it matters:** Exposes full API surface map to attackers.
**Recommended fix:** Disable in production: `docs_url=None if settings.environment == "production" else "/docs"`.

---

### 🟡 Medium — `supabase_jwt_secret` loaded but never used

**File:** `backend/app/config.py:45`
**Lens:** Security | **Subsystem:** Backend

**What:** Field exists and is injected from Secrets Manager, but the JWKS flow is the real gate — HS256 verification is retired.
**Why it matters:** Operational overhead + misleads future developers.
**Recommended fix:** Remove the field from `Settings` and from Secrets Manager templates; add a comment in `jwt.py`.

---

### 🟡 Medium — Google JWKS cache never expires; stale key after rotation could lock out users

**File:** `backend/app/auth/google.py:24`
**Lens:** Security | **Subsystem:** Backend

**What:** Module-level JWKS dict filled once, never evicted; same pattern in `jwt.py:25`.
**Why it matters:** Long-lived processes won't pick up rotated Google keys automatically.
**Recommended fix:** Use `cachetools.TTLCache` with 3600s TTL.

---

### 🟡 Medium — Error detail exposes internal exception message to clients

**File:** `backend/app/observability/exception_handlers.py:79`
**Lens:** Security | **Subsystem:** Backend

**What:** Catch-all 500 handler includes `str(exc)` in the `detail` field returned to the client.
**Why it matters:** Leaks DB query fragments, S3 paths, internal service URLs.
**Recommended fix:** Return `"detail": "an unexpected error occurred"` to clients; keep full exception in log.

---

### 🟢 Low — `role` column has no DB check constraint

**File:** `backend/app/models/user.py:46`
**Lens:** Security | **Subsystem:** Backend

**What:** `require_admin` relies on application-level string comparison with no storage-level enforcement.
**Recommended fix:** `ALTER TABLE users ADD CONSTRAINT ck_users_role CHECK (role IN ('user', 'admin'));`

---

### 🟢 Low — AI serve endpoint (`/api/v1/ml-demo/run`) has no authentication

**File:** `AI/serve/router.py:33`
**Lens:** Security | **Subsystem:** Backend (AI)

**What:** ML demo endpoint accepts arbitrary uploads with no JWT verification.
**Recommended fix:** Add shared API key header check or enforce network-level isolation.

---

### Reliability

### 🔴 Critical — Double-commit in `GET /reports/range` causes 500 on every successful generation

**File:** `backend/app/reports/router.py:179`
**Lens:** Reliability | **Subsystem:** Backend

**What:** Handler calls `await db.commit()` at line 179; `get_db` teardown calls it again. SQLAlchemy raises `InvalidRequestError: Can't operate on a closed transaction`.
**Why it matters:** Every successful range-report request returns HTTP 500 — this feature is completely broken.
**Recommended fix:** Remove the inline `await db.commit()` from the router; `get_db` already commits at request end.

---

### 🔴 Critical — `run_weekly_reports_job` commits partial state on per-user failure

**File:** `backend/app/jobs/weekly_reports_job.py:56`
**Lens:** Reliability | **Subsystem:** Backend

**What:** Loop catches per-user exceptions and continues; `db.commit()` at line 63 commits all successful flushes even if failures occurred — partial all-or-nothing contract violation.
**Why it matters:** Failed job appears partially successful; next run may find inconsistent state.
**Recommended fix:** Use `async with db.begin_nested()` per user (savepoint) or move commit to individual user scope.

---

### 🟠 High — Firebase init failure silently swallows; all FCM sends no-op

**File:** `backend/app/services/fcm.py:52`
**Lens:** Reliability | **Subsystem:** Backend

**What:** If `firebase_admin.initialize_app()` raises, `_initialized = True` is still set; subsequent sends call the messaging module but the app isn't initialized — exception caught and logged as warning only.
**Why it matters:** Bad Firebase credentials silently kill all push notifications with no alerting.
**Recommended fix:** On init failure, keep `_initialized = False`; `send_to_user` short-circuits with a real error.

---

### 🟠 High — `_sweep_loop` swallows all exceptions silently, masking DB issues

**File:** `backend/app/main.py:59`
**Lens:** Reliability | **Subsystem:** Backend

**What:** `except Exception` logs but has no counter, no alert, no back-off — 1440 log lines/day during a DB outage.
**Recommended fix:** Emit `websocket_sweep_errors_total` Prometheus counter; add exponential back-off.

---

### 🟡 Medium — Sleep log unique constraint exists only in migration, not ORM model

**File:** `backend/app/models/sleep_log.py`
**Lens:** Reliability | **Subsystem:** Backend

**What:** Unique index `uq_sleep_logs_user_ended` exists in migration but not in `__table_args__`; autogenerate would silently drop it.
**Recommended fix:** Add `UniqueConstraint("user_id", "ended_on", name="uq_sleep_logs_user_ended")` to `__table_args__`.

---

### 🟡 Medium — Scheduler jobs have no retry or dead-letter mechanism (backend view)

**File:** `backend/app/jobs/` (all job files)
**Lens:** Reliability | **Subsystem:** Backend

**What:** Job files have no retry logic; if EventBridge fires and the ECS task exits non-zero the run is lost.
**Recommended fix:** Configure EventBridge Scheduler retry policy (3 retries, 5 min back-off) — see also cross-cutting finding for missing schedule rules.

---

### 🟡 Medium — `ensure_user_settings` has a TOCTOU race on new users

**File:** `backend/app/services/user_settings.py:18`
**Lens:** Reliability | **Subsystem:** Backend

**What:** SELECT then INSERT pattern; two concurrent first-requests for same new user both attempt INSERT → `IntegrityError`.
**Recommended fix:** Use `INSERT ... ON CONFLICT DO NOTHING RETURNING *` or savepoint+retry.

---

### 🟡 Medium — `purge_expired_accounts` holds one long transaction while deleting S3 objects

**File:** `backend/app/services/deletion.py:77`
**Lens:** Reliability | **Subsystem:** Backend

**What:** All user deletions + S3 calls in one transaction; long lock on `users` table.
**Recommended fix:** Batch 10 users per commit; job is idempotent.

---

### 🟢 Low — `touch_heartbeat` non-atomic read-modify-write

**File:** `backend/app/realtime/registry.py:33`
**Lens:** Reliability | **Subsystem:** Backend

**What:** SELECT then UPDATE for heartbeat — lost update under concurrent pings.
**Recommended fix:** Direct `UPDATE websocket_connections SET last_seen_at = now() WHERE id = :id`.

---

### Cost & Architecture

### 🟡 Medium — `alembic/env.py` missing 7 of 14 models for autogenerate

**File:** `backend/alembic/env.py:17`
**Lens:** Cost | **Subsystem:** Backend

**What:** `AuditLog, PatternTip, WeeklyReport, RangeReport, SleepLog, TriggerCategory, UserSettings` not imported; autogenerate would generate incorrect migrations.
**Recommended fix:** Import all models or use `from app.models import *` with explicit `__all__`.

---

### 🟡 Medium — Morning tips pollute `pattern_tips` table with no expiry

**File:** `backend/app/services/ai/morning_tip.py:58`
**Lens:** Cost | **Subsystem:** Backend

**What:** Synthetic `morning:YYYY-MM-DD` keys accumulate as one row/day/user with no pruning.
**Recommended fix:** Dedicated `morning_tips` table or purge step for `morning:*` keys older than 7 days.

---

### 🟡 Medium — `compute_patterns` called multiple times per request; no memoization

**File:** `backend/app/services/ai/range_report.py:100`
**Lens:** Cost | **Subsystem:** Backend

**What:** Repeated `compute_patterns` calls issue 3–4 DB queries each time.
**Recommended fix:** Cache result within request context using `functools.lru_cache` keyed on `(user_id, frm, to)`.

---

### 🟢 Low — `require_admin` dependency defined but no route uses it

**File:** `backend/app/auth/dependencies.py:105`
**Lens:** Cost | **Subsystem:** Backend

**What:** Dead code — no router depends on it.
**Recommended fix:** Wire to intended admin routes or remove.

---

### ℹ️ Info — `content_hash` in sync upload accepted but never verified

**File:** `backend/app/schemas/sync.py:17`
**Lens:** Cost | **Subsystem:** Backend

**What:** Required field silently discarded; integrity check not happening.

---

### Correctness & Data Integrity

### 🔴 Critical — `SleepLog.rating` has no Python-level enum; relies solely on DB check constraint

**File:** `backend/app/models/sleep_log.py:39`, `backend/app/schemas/sleep_logs.py:52`
**Lens:** Correctness | **Subsystem:** Backend

**What:** `SleepLogResponse.rating` typed as plain `str`; if DB check constraint is accidentally dropped, invalid ratings flow through the entire analytics pipeline silently.
**Recommended fix:** Add Python-level `Enum` or `CheckConstraint` to the ORM model and use it in the response schema.

---

### 🟠 High — Naive `datetime` from biosignal `recorded_at` could corrupt `expires_at`

**File:** `backend/app/schemas/sync.py:43`
**Lens:** Correctness | **Subsystem:** Backend

**What:** `BiosignalUploadRequest.recorded_at` accepts naive datetimes; stored in a `DateTime(timezone=True)` column, producing wrong `expires_at` (consent compliance risk).
**Recommended fix:** Use `pydantic.AwareDatetime` for `recorded_at`.

---

### 🟠 High — `weekly_reports_job` user_id typed as `Any`; version-bump could silently break reports

**File:** `backend/app/jobs/weekly_reports_job.py:51`
**Lens:** Correctness | **Subsystem:** Backend

**What:** `.scalars().all()` return type is `Sequence[Any]`; UUID assumption could break on SQLAlchemy/asyncpg version bump.
**Recommended fix:** Explicitly cast: `uid = uuid.UUID(str(uid))` before passing to the generator.

---

### 🟡 Medium — `RangeReport.takeaways` and `WeeklyReport.takeaways` missing `server_default`

**File:** `backend/app/models/range_report.py:37`
**Lens:** Correctness | **Subsystem:** Backend

**What:** Python-side `default=list` but no `server_default`; raw SQL inserts fail with NOT NULL violation.
**Recommended fix:** Add `server_default=text("'[]'::jsonb")` to both model columns.

---

### 🟡 Medium — `avg_rating` uses non-deterministic set-based `max`; O(n²) and tie-flipping

**File:** `backend/app/services/ai/range_report.py:109`
**Lens:** Correctness | **Subsystem:** Backend

**What:** `max({s.rating for s in sleeps}, key=[s.rating for s in sleeps].count)` is O(n²) and non-deterministic on tie.
**Recommended fix:** `collections.Counter(s.rating for s in sleeps).most_common(1)[0][0]`.

---

### 🟡 Medium — `SleepLog` missing index on `user_id`

**File:** `backend/app/models/sleep_log.py`
**Lens:** Correctness | **Subsystem:** Backend

**What:** No standalone index on `user_id`; queries filtering only by `user_id` can't use the composite unique index efficiently.
**Recommended fix:** Add `index=True` to `user_id` column or `Index("ix_sleep_logs_user_id", "user_id")`.

---

### 🟢 Low — `AuditLog` has no index on `occurred_at` or `target_user_id`

**File:** `backend/app/models/audit_log.py`
**Lens:** Correctness | **Subsystem:** Backend

**Recommended fix:** `Index("ix_audit_log_target_user_occurred", "target_user_id", "occurred_at")`.

---

### Quality

### 🟡 Medium — `_try_parse_payload` uses fragile `strip("\`")` instead of regex for JSON fence

**File:** `backend/app/services/ai/morning_tip.py:232`
**Lens:** Quality | **Subsystem:** Backend

**Recommended fix:** `re.sub(r'^```(?:json)?\n?', '', re.sub(r'\n?```$', '', text.strip()))`.

---

### 🟢 Low — `_EVENTS_CAP` naming and comment inconsistency

**File:** `backend/app/services/ai/range_report.py:116`
**Lens:** Quality | **Subsystem:** Backend

**Recommended fix:** Rename to `_EVENTS_DISPLAY_CAP`; add comment about ascending order.

---

### 🟢 Low — Inconsistent sleep log filter dimension (`fell_asleep_at` vs `ended_on`)

**File:** `backend/app/sleep/router.py:100`
**Lens:** Quality | **Subsystem:** Backend

**What:** List endpoint uses datetime range; dashboard uses `ended_on` date — different "in range" semantics for same data.

---

### ℹ️ Info — Alembic `env.py` import correctness depends on `app/models/__init__.py` completeness

**File:** `backend/alembic/env.py:17`
**Lens:** Correctness | **Subsystem:** Backend

---

---

## Infra Findings

*(Full findings in `docs/audit/2026-05-12-infra-findings.md`)*

### Security

### 🟡 Medium — OIDC staging trust allows `pull_request` sub-claim

**File:** `backend/infra/oidc.tf` — data "aws_iam_policy_document" "gha_staging_assume_role"
**Lens:** Security | **Subsystem:** Infra

**What:** Any contributor who opens a PR can assume the staging deploy role (ECR push, ECS RunTask).
**Recommended fix:** Remove `pull_request` sub; restrict to `refs/heads/master` and `environment:staging` only.

---

### 🟡 Medium — OTel collector sidecar pinned to `latest` tag

**File:** `backend/infra/ecs.tf` — resource "aws_ecs_task_definition" "backend"
**Lens:** Security | **Subsystem:** Infra

**Recommended fix:** Pin to specific version, e.g., `aws-otel-collector:v0.40.0`.

---

### 🟡 Medium — `ml_demo_image` default is `hello-world:latest` from public registry with backend IAM permissions

**File:** `backend/infra/ml_demo.tf`
**Lens:** Security | **Subsystem:** Infra

**Recommended fix:** Set real ECR URI in `staging.tfvars` or add separate minimal task role for ml_demo.

---

### 🟡 Medium — ECS task role X-Ray/logs policy uses `resources = ["*"]`

**File:** `backend/infra/ecs.tf` — data "aws_iam_policy_document" "ecs_task_xray"
**Lens:** Security | **Subsystem:** Infra

**Recommended fix:** Scope log write permissions to specific log group ARNs.

---

### 🟢 Low — ECR repos use `MUTABLE` image tags

**File:** `backend/infra/ecr.tf`
**Lens:** Security | **Subsystem:** Infra

**Recommended fix:** Set `image_tag_mutability = "IMMUTABLE"` on both repos.

---

### 🟢 Low — ALB access logging not enabled

**File:** `backend/infra/alb.tf`
**Lens:** Security | **Subsystem:** Infra

**Recommended fix:** Add `access_logs { bucket = <log-bucket> enabled = true }` block.

---

### 🟢 Low — `alert_email` personal address committed to `staging.tfvars`

**File:** `backend/infra/staging.tfvars`
**Lens:** Security | **Subsystem:** Infra

**Recommended fix:** Move to GitHub Actions secret.

---

### ℹ️ Info — S3 `sync` bucket has no object-expiry lifecycle rule

**File:** `backend/infra/s3.tf`
**Lens:** Security | **Subsystem:** Infra

---

### Reliability

### 🟠 High — ECS service has no autoscaling and `desired_count = 1` (single point of failure)

**File:** `backend/infra/ecs.tf` — resource "aws_ecs_service" "backend"
**Lens:** Reliability | **Subsystem:** Infra

**What:** No `aws_appautoscaling_target` or policy; single Fargate task is SPOF.
**Recommended fix:** Add autoscaling (min=1, max=3) + CPU-based policy.

---

### 🟠 High — ECS service has no deployment circuit breaker

**File:** `backend/infra/ecs.tf` — resource "aws_ecs_service" "backend"
**Lens:** Reliability | **Subsystem:** Infra

**What:** A bad deploy loops indefinitely without auto-rollback.
**Recommended fix:** `deployment_circuit_breaker { enable = true rollback = true }`.

---

### 🟠 High — Production deploy workflow: ECS networking discovery fails if prod service doesn't yet exist

**File:** `.github/workflows/deploy-production.yml`
**Lens:** CI/CD | **Subsystem:** Infra

**What:** `describe-services` on non-existent service returns empty → migration task fails with missing network config.
**Recommended fix:** Add explicit check that service exists, or document Terraform must be applied first.

---

### 🟡 Medium — RDS single-AZ (no failover standby)

**File:** `backend/infra/rds.tf`
**Lens:** Reliability | **Subsystem:** Infra

**Recommended fix:** Document `multi_az = true` as required in `production.tfvars`.

---

### 🟡 Medium — RDS `deletion_protection = false` + `skip_final_snapshot = true` in staging

**File:** `backend/infra/staging.tfvars`
**Lens:** Reliability | **Subsystem:** Infra

**Recommended fix:** Set `deletion_protection = true`; `skip_final_snapshot = false`.

---

### 🟡 Medium — No CloudWatch alarm for RDS CPU utilization

**File:** `backend/infra/monitoring.tf`
**Lens:** Reliability | **Subsystem:** Infra

**Recommended fix:** Add `aws_cloudwatch_metric_alarm.rds_cpu` at 80% for 2×5 min.

---

### 🟡 Medium — Single NAT Gateway covers all AZs (AZ-failure = full internet outage for ECS)

**File:** `backend/infra/networking.tf`
**Lens:** Reliability | **Subsystem:** Infra

**Recommended fix:** One NAT per AZ for production; document staging trade-off.

---

### 🟢 Low — ECS cluster has no Container Insights enabled

**File:** `backend/infra/ecs.tf` — resource "aws_ecs_cluster" "main"
**Lens:** Reliability | **Subsystem:** Infra

**Recommended fix:** `setting { name = "containerInsights" value = "enabled" }`.

---

### ℹ️ Info — ECS service has no `health_check_grace_period_seconds`

**File:** `backend/infra/ecs.tf` — resource "aws_ecs_service" "backend"
**Lens:** Reliability | **Subsystem:** Infra

**Recommended fix:** Add `health_check_grace_period_seconds = 60`.

---

### Cost & Architecture

### 🟡 Medium — ml_demo service permanently running (ephemeral with `desired_count = 1`)

**File:** `backend/infra/ml_demo.tf`
**Lens:** Cost | **Subsystem:** Infra

**What:** ~$7–10/month Fargate cost for a placeholder container that exits immediately (see Correctness below).
**Recommended fix:** Set `desired_count = 0` or add `count = var.ml_demo_enabled ? 1 : 0`.

---

### 🟡 Medium — `common_tags.Sprint` hardcoded to `"2"` since Sprint 2

**File:** `backend/infra/locals.tf`
**Lens:** Cost | **Subsystem:** Infra

**Recommended fix:** Remove Sprint tag or make it a variable.

---

### 🟢 Low — ECS task sizing undocumented for production planning

**File:** `backend/infra/ecs.tf`
**Lens:** Cost | **Subsystem:** Infra

**Recommended fix:** Enable Container Insights, capture 30-day baseline, then size production.

---

### ℹ️ Info — RDS `db.t4g.micro` correctly sized for staging

---

### Correctness

### 🟡 Medium — `staging.tfvars` has no `ml_demo_image` override; service runs `hello-world` and cycles continuously

**File:** `backend/infra/staging.tfvars`
**Lens:** Correctness | **Subsystem:** Infra

**Recommended fix:** Add real ECR URI or set `desired_count = 0`.

---

### 🟡 Medium — `container_image` in `staging.tfvars` is the Python stdlib bootstrap placeholder

**File:** `backend/infra/staging.tfvars`
**Lens:** Correctness | **Subsystem:** Infra

**What:** Correct for first bootstrap, but must never be committed after first real deploy.
**Recommended fix:** Document clearly or remove from committed tfvars.

---

### 🟡 Medium — OIDC thumbprint is a single legacy SHA1 value

**File:** `backend/infra/oidc.tf`
**Lens:** Correctness | **Subsystem:** Infra

**Recommended fix:** Add second GitHub OIDC thumbprint `1c58a3a8518e8759bf075b76b750d4f2df264fcd`.

---

### 🟢 Low — Required variables all covered in `staging.tfvars` ✅

---

### 🟢 Low — Scheduler cron expressions are valid EventBridge syntax ✅

---

### CI/CD

### 🟠 High — Production deploy has no automatic rollback after smoke test failure

**File:** `.github/workflows/deploy-production.yml`
**Lens:** CI/CD | **Subsystem:** Infra

**What:** Smoke test fails → workflow exits 1 but bad task definition stays running; manual rollback required.
**Recommended fix:** Capture previous task definition ARN before `update-service`; auto-rollback on smoke test failure.

---

### 🟡 Medium — `deploy-staging.yml` manual dispatch bypasses CI gate

**File:** `.github/workflows/deploy-staging.yml`
**Lens:** CI/CD | **Subsystem:** Infra

**Recommended fix:** Document as intentional emergency hotfix path or add CI status check on manual dispatch.

---

### 🟡 Medium — `deploy-staging.yml` pushes mutable `latest` tag alongside SHA tag

**File:** `.github/workflows/deploy-staging.yml`
**Lens:** CI/CD | **Subsystem:** Infra

**Recommended fix:** Stop pushing `latest` or document it as a convenience alias only.

---

### 🟡 Medium — Production role ARN hardcoded with `staging` name prefix

**File:** `.github/workflows/deploy-production.yml`
**Lens:** CI/CD | **Subsystem:** Infra

**Recommended fix:** Expose as Terraform output → GitHub Actions secret `GHA_PRODUCTION_ROLE_ARN`.

---

### 🟢 Low — `traffic-snapshot.yml` pushes directly to `master` bypassing branch protection

**File:** `.github/workflows/traffic-snapshot.yml`
**Lens:** CI/CD | **Subsystem:** Infra

**Recommended fix:** Allow `github-actions[bot]` bypass in branch protection for `.github/traffic/` paths.

---

### ℹ️ Info — Trivy scan correctly configured with `ignore-unfixed: true` ✅

---

### ℹ️ Info — ECR repo name and ECS task definition are consistent ✅

---

### ℹ️ Info — RDS correctly sized for staging ✅

---

---

## Watch Findings

*(Full findings in `docs/audit/2026-05-12-watch-findings.md`)*

### Security

### 🟡 Medium — `WatchControlListener` accepts start/stop from any paired-device app without auth

**File:** `watch/sensor-capture/app/src/main/AndroidManifest.xml:58` / `WatchControlListener.kt:10`
**Lens:** Security | **Subsystem:** Watch

**What:** Any app on paired phone holding `WEARABLE` permission can start/stop a capture session.
**Recommended fix:** Add shared secret in message payload or restrict via custom permission.

---

### 🟡 Medium — No runtime permission re-check before opening trackers

**File:** `watch/sensor-capture/.../CaptureActivity.kt:116`
**Lens:** Security | **Subsystem:** Watch

**What:** `startCapture` proceeds regardless of dialog result; Samsung SDK returns null data silently.
**Recommended fix:** Check `checkSelfPermission` inside `CaptureSession` before calling `getHealthTracker()`.

---

### 🟢 Low — `isMinifyEnabled = false` in release build; class names/paths fully visible in APK

**File:** `watch/sensor-capture/app/build.gradle.kts:23`
**Lens:** Security | **Subsystem:** Watch

**Recommended fix:** Enable R8/ProGuard with Samsung Health SDK keep rules.

---

### 🟢 Low — `WAKE_LOCK` permission declared but never acquired

**File:** `watch/sensor-capture/app/src/main/AndroidManifest.xml:22`
**Lens:** Security | **Subsystem:** Watch

**Recommended fix:** Remove declaration.

---

### 🟢 Low — `HIGH_SAMPLING_RATE_SENSORS` declared but accelerometer runs at ≤50 Hz (threshold is >200 Hz)

**File:** `watch/sensor-capture/app/src/main/AndroidManifest.xml:14`
**Lens:** Security | **Subsystem:** Watch

**Recommended fix:** Remove declaration.

---

### ℹ️ Info — `Timber.DebugTree` planted unconditionally in production

**File:** `watch/sensor-capture/.../CaptureActivity.kt:100`
**Lens:** Security | **Subsystem:** Watch

**Recommended fix:** Gate behind `BuildConfig.DEBUG`.

---

### Reliability

### 🔴 Critical — Dropped samples on phone unreachability: `drain()` called before confirming send

**File:** `watch/sensor-capture/.../PhoneSenderConsumer.kt:59`
**Lens:** Reliability | **Subsystem:** Watch

**What:** `batch.drain()` clears samples atomically, then `sender.send()` is called; if `send()` returns `false`, drained samples are permanently discarded with no retry.
**Why it matters:** Any Bluetooth gap during sleep recording silently loses minutes of biometric data — unrecoverable.
**Recommended fix:** (a) Hold the drain and retry with back-off, or (b) write to local ring-buffer and replay when connectivity resumes.

---

### 🔴 Critical — `SampleBatch` has no maximum size; overnight sessions can exhaust watch heap

**File:** `watch/sensor-capture/.../SampleBatch.kt:17`
**Lens:** Reliability | **Subsystem:** Watch

**What:** Four unbounded `mutableListOf` lists; PPG at 25 Hz overnight → ~720k samples if phone unreachable → OOM crash.
**Recommended fix:** Add `MAX_SAMPLES_PER_CHANNEL = 500` constant; drop or flush-early when exceeded.

---

### 🟠 High — `RemoteCaptureService` uses `START_NOT_STICKY`; OS kill produces silent session end

**File:** `watch/sensor-capture/.../RemoteCaptureService.kt:43`
**Lens:** Reliability | **Subsystem:** Watch

**What:** If Wear OS kills the service under memory pressure, no `/biosignals/end` is sent; phone waits indefinitely.
**Recommended fix:** Return `START_REDELIVER_INTENT` or send `reason = "service_killed"` in `onDestroy`.

---

### 🟠 High — No reconnect logic if Wearable Data Layer channel drops mid-session

**File:** `watch/sensor-capture/.../WearPhoneSender.kt:20`
**Lens:** Reliability | **Subsystem:** Watch

**What:** Returns `false` immediately if no node connected; no retry, no queue.
**Recommended fix:** 3-attempt retry loop with 500ms gap; buffer last N failed batches in `ConcurrentLinkedQueue`.

---

### 🟠 High — `CaptureActivity` does not stop session when backgrounded or destroyed

**File:** `watch/sensor-capture/.../CaptureActivity.kt:87`
**Lens:** Reliability | **Subsystem:** Watch

**What:** No `onDestroy()` override; pressing home cancels Compose scope coroutine but leaves Health tracker listeners attached; CSV writer may be left open.
**Recommended fix:** Override `onDestroy()`, cancel capture coroutine explicitly, ensure `finally` runs.

---

### 🟠 High — `CaptureActivity.kt` is a 680-line god-class (6 screens + 9 UI atoms + lifecycle)

**File:** `watch/sensor-capture/.../CaptureActivity.kt:1`
**Lens:** Cost | **Subsystem:** Watch

**Recommended fix:** Split into `CaptureActivity.kt` (lifecycle), `CaptureScreens.kt` (screens), `CaptureComponents.kt` (atoms).

---

### 🟡 Medium — `ChannelRecorder` singletons (`object`) leak state between capture sessions

**File:** `watch/sensor-capture/.../ChannelRecorder.kt:116`
**Lens:** Reliability | **Subsystem:** Watch

**What:** `sampleCount`, timestamps, `writer` never reset; second session's `metadata.json` has contaminated values.
**Recommended fix:** Convert `HeartRate`, `PpgGreen`, `Eda`, `Accelerometer` from `object` to `class`.

---

### 🟡 Medium — `connectService()` copy-pasted between `CaptureSession` and `RemoteCaptureSession`

**File:** `watch/sensor-capture/.../CaptureSession.kt:79` / `RemoteCaptureSession.kt:66`
**Lens:** Reliability | **Subsystem:** Watch

**Recommended fix:** Extract `connectHealthTrackingService(ctx)` into shared `HealthTrackerUtils.kt`.

---

### 🟡 Medium — Sensor `onError` only logs; user sees no indication of missing data

**File:** `watch/sensor-capture/.../ChannelRecorder.kt:91`
**Lens:** Reliability | **Subsystem:** Watch

**Recommended fix:** Surface errors via `Channel<TrackerError>` or `MutableStateFlow<String?>`.

---

### 🟢 Low — `FLAG_KEEP_SCREEN_ON` never cleared; problematic for sessions >15 min

**File:** `watch/sensor-capture/.../CaptureActivity.kt:105`
**Lens:** Reliability | **Subsystem:** Watch

**Recommended fix:** Clear flag in `onDestroy()`; add comment about session length limit.

---

### Cost & Architecture

### 🟡 Medium — EDA sampling rate documented as ~25 Hz in README; actual rate is ~1 Hz

**File:** `watch/sensor-capture/README.md:12` / `ChannelRecorder.kt:24`
**Lens:** Cost | **Subsystem:** Watch

**What:** Incorrect README causes wrong resampling expectations for ML analysis.
**Recommended fix:** Correct README to `~1 Hz`; update row count sanity check.

---

### 🟡 Medium — Capture duration hardcoded; changing requires code edit + reinstall

**File:** `watch/sensor-capture/.../CaptureActivity.kt:75`
**Lens:** Cost | **Subsystem:** Watch

**Recommended fix:** Accept `durationSec` extra in launch intent (like `RemoteCaptureService`).

---

### 🟢 Low — `BuildInfo.VERSION_NAME` manual duplicate of Gradle `versionName`

**File:** `watch/sensor-capture/.../BuildInfo.kt:5`
**Lens:** Cost | **Subsystem:** Watch

**Recommended fix:** Use `BuildConfig.VERSION_NAME` with `buildConfig = true`.

---

### 🟢 Low — `serializeBatchPayload` creates new `JSONObject` per sample; GC pressure on 8h sessions

**File:** `watch/sensor-capture/.../SampleBatch.kt:53`
**Lens:** Cost | **Subsystem:** Watch

**Recommended fix:** Consider streaming JSON writer or compact binary format for long sessions.

---

### Correctness & Data Integrity

### 🟠 High — `tStartMs` is wall-clock flush time, not earliest sample timestamp

**File:** `watch/sensor-capture/.../PhoneSenderConsumer.kt:62`
**Lens:** Correctness | **Subsystem:** Watch

**What:** `tStartMs = nowMs()` — the batch anchor is when the flush coroutine ran, not when the first sample was collected. Clock skew corrupts relative timestamps.
**Recommended fix:** `tStartMs = drain.hr.minOfOrNull { it.timestampMs } ?: nowMs()`.

---

### 🟡 Medium — Samsung SDK timestamp units not verified; boot-relative ms would corrupt all sessions

**File:** `watch/sensor-capture/README.md:33` / `ChannelRecorder.kt:77`
**Lens:** Correctness | **Subsystem:** Watch

**Recommended fix:** Assert at session start: `require(ts > 1_600_000_000_000L)`.

---

### 🟡 Medium — No schema version in batch JSON payload; field additions break phone parser silently

**File:** `watch/sensor-capture/.../SampleBatch.kt:49`
**Lens:** Correctness | **Subsystem:** Watch

**Recommended fix:** Add `"schemaVersion": 1` to root JSON; increment on every breaking change.

---

### 🟡 Medium — No batch sequence number; dropped/reordered batches undetectable

**File:** `watch/sensor-capture/.../PhoneSenderConsumer.kt:38`
**Lens:** Correctness | **Subsystem:** Watch

**Recommended fix:** Add monotonic `batchSeq: Int` field; phone logs gaps as data quality events.

---

### 🟡 Medium — `isoUtc()` writes `HH-mm-ss` (hyphens) into `metadata.json`; not valid ISO 8601

**File:** `watch/sensor-capture/.../CaptureSession.kt:173`
**Lens:** Correctness | **Subsystem:** Watch

**Recommended fix:** Separate formatter for JSON metadata using `HH:mm:ss`; keep hyphens only for directory names.

---

### 🟡 Medium — `ChannelRecorder` singleton fields accessed from multiple threads without synchronization

**File:** `watch/sensor-capture/.../ChannelRecorder.kt:31`
**Lens:** Correctness | **Subsystem:** Watch

**What:** `writer`, `tracker`, `sampleCount` mutated from both SDK callback thread and caller thread without `@Volatile` or locks.
**Recommended fix:** `@Volatile` on `writer`/`tracker`; `AtomicLong` for `sampleCount`; `synchronized` for timestamp fields.

---

### 🟢 Low — Tests don't cover concurrent-write correctness of `SampleBatch`

**File:** `watch/sensor-capture/.../SampleBatchTest.kt`
**Lens:** Correctness | **Subsystem:** Watch

**Recommended fix:** Add multi-threaded test: 4 threads × 1000 samples each; assert total drain = 4000.

---

### 🟢 Low — `PhoneSenderConsumerTest` never tests `sender.send() = false`

**File:** `watch/sensor-capture/.../PhoneSenderConsumerTest.kt`
**Lens:** Correctness | **Subsystem:** Watch

**Recommended fix:** Add `FakeSender` variant returning `false` for first N calls; verify samples gone and subsequent batches flush.

---

### Quality

### 🟢 Low — `ChannelRecorder` `object` + mutable instance state is contradictory Kotlin design

**File:** `watch/sensor-capture/.../ChannelRecorder.kt:27`
**Lens:** Quality | **Subsystem:** Watch

**Recommended fix:** Convert to `class` (root cause of the state-leak finding above).

---

### 🟢 Low — Service notification strings hardcoded Korean, not in `strings.xml`

**File:** `watch/sensor-capture/.../RemoteCaptureService.kt:79`
**Lens:** Quality | **Subsystem:** Watch

**Recommended fix:** Move to `res/values/strings.xml`.

---

### ℹ️ Info — EDA CSV header `skin_conductance` vs README `resistance_kohm` (different physical units)

**File:** `watch/sensor-capture/.../ChannelRecorder.kt:166` / `README.md:28`
**Lens:** Quality | **Subsystem:** Watch

**What:** Conductance and resistance are reciprocals; incorrect unit in docs would corrupt EDA feature extraction.
**Recommended fix:** Align README to say `skin_conductance` (µS) matching SDK and code.

---

---

## Cross-cutting Findings

*(Full details in `docs/audit/2026-05-12-cross-cutting-findings.md`)*

### 🔴 Critical — `send_morning_tips` and `send_sleep_nudges` have no EventBridge schedule rule; never fire

**File:** `backend/infra/scheduler.tf` ↔ `backend/app/jobs/send_morning_tips.py` + `send_sleep_nudges.py`
**Lens:** Reliability | **Subsystem:** Cross-cutting

**What:** Scheduler.tf defines 3 rules (purge_accounts, purge_biosignals, weekly_reports). Two job files (`send_morning_tips.py`, `send_sleep_nudges.py`) have no corresponding rule — these features have never been triggered.
**Why it matters:** Morning tips and sleep nudges are user-facing features that silently don't work.
**Recommended fix:** Add EventBridge schedule rules for both jobs (with DLQ + retry); or delete the job files if features are deferred.

---

### 🟠 High — No idempotency key on biosignal upload; retries silently duplicate data

**File:** `watch/.../PhoneSenderConsumer.kt` ↔ `backend/app/sync/router.py:144`
**Lens:** Correctness | **Subsystem:** Cross-cutting

**What:** `POST /sync/biosignals` has no idempotency key; phone retry after network failure creates a new `RawBiosignalUpload` row each time — downstream analytics will double-count.
**Recommended fix:** Add `idempotency_key UUID` to `BiosignalUploadRequest`; unique constraint + return existing `upload_id` on collision.

---

### 🟠 High — Cron task definition missing `FIREBASE_CREDENTIALS_JSON` and `SENTRY_DSN` secrets

**File:** `backend/infra/scheduler.tf` (cron task def) ↔ `backend/app/config.py:78`
**Lens:** Reliability | **Subsystem:** Cross-cutting

**What:** Cron tasks won't send FCM notifications (silently no-op); cron exceptions won't appear in Sentry.
**Recommended fix:** Add same `secrets` block entries from `ecs.tf:179–184` to the cron task definition.

---

### 🟡 Medium — Cron task missing `ENVIRONMENT` and `OTEL_EXPORTER_OTLP_ENDPOINT` env vars

**File:** `backend/infra/scheduler.tf` (cron task def) ↔ `backend/app/config.py:60`
**Lens:** Reliability | **Subsystem:** Cross-cutting

**What:** Cron tasks report as `environment = "local"` to Sentry/OTel; tracing data unroutable.
**Recommended fix:** Copy `ENVIRONMENT` and `OTEL_EXPORTER_OTLP_ENDPOINT` from backend task env block into cron task env block.

---

### 🟡 Medium — Batch biosignal endpoint has no upper bound on item count

**File:** `backend/app/sync/router.py:192` ↔ `watch/.../SampleBatch.kt`
**Lens:** Security / Reliability | **Subsystem:** Cross-cutting

**What:** No limit on `payload.items`; 1,000+ items blocks executor thread pool and can OOM the ECS task.
**Recommended fix:** Add `max_items = 50` validator to `BiosignalBatchUploadRequest`.

---

### ℹ️ Info — Phone-side translation layer (watch → backend HTTP) is unaudited

**File:** `watch/.../WearPhoneSender.kt` ↔ `backend/app/sync/router.py`
**Lens:** Correctness | **Subsystem:** Cross-cutting

**What:** `frontend/` companion app translation is out of scope; auth header, retry behavior, and path mapping are unknown.
**Recommended fix:** Include phone companion app in a follow-up audit; add server-side request logging to `/sync/biosignals` to detect upload gaps.

---

### ℹ️ Info — `weekly_reports` schedule injects `AI_FEATURES_ENABLED=true` via shell export (fragile)

**File:** `backend/infra/scheduler.tf:287` ↔ `backend/app/config.py:99`
**Lens:** Correctness | **Subsystem:** Cross-cutting

**Recommended fix:** Move to `containerOverrides.environment` array instead of shell export in command string.

---

### ℹ️ Info — `AI/serve/` and `backend/services/ai/` are completely separate; no integration exists

**File:** `AI/serve/router.py` ↔ `backend/app/services/ai/bedrock_client.py`
**Lens:** Architecture | **Subsystem:** Cross-cutting

**What:** Backend uses Bedrock directly; `AI/serve/` + ml_demo is a separate research artifact with no HTTP client wired in the backend.
**Recommended fix:** Decide architecture. If research artifact, shut down ml_demo to eliminate ~$10/month idle cost. If intended production path, build the HTTP client in `backend/app/services/ai/`.

---

---

## Triage Table

Sorted: 🔴 → 🟠 → 🟡 → 🟢 → ℹ️. Within severity: Backend → Infra → Watch → Cross-cutting.
**Note:** 🟢 low and ℹ️ info items are summarized briefly; full details in per-subsystem files.

| # | Sev | Subsystem | Title | Lens | Est. fix |
|---|---|---|---|---|---|
| 1 | 🔴 | Backend | Double-commit in `GET /reports/range` → 500 on every success | Reliability | 15 min |
| 2 | 🔴 | Backend | Weekly reports job commits partial state on per-user failure | Reliability | 30 min |
| 3 | 🔴 | Backend | `SleepLog.rating` no Python enum; relies solely on DB constraint | Correctness | 30 min |
| 4 | 🔴 | Watch | `drain()` before send confirmed → permanent data loss on BT gap | Reliability | 1 hr |
| 5 | 🔴 | Watch | `SampleBatch` unbounded → OOM on overnight session | Reliability | 30 min |
| 6 | 🔴 | Cross | `send_morning_tips` + `send_sleep_nudges` have no schedule rule — never fire | Reliability | 1 hr |
| 7 | 🟠 | Backend | JWT bearer token in WebSocket query param (in access logs + OTel spans) | Security | 1 hr |
| 8 | 🟠 | Backend | No rate limiting on auth endpoints | Security | 2 hr |
| 9 | 🟠 | Backend | Firebase init failure → all FCM sends silently no-op | Reliability | 30 min |
| 10 | 🟠 | Backend | `_sweep_loop` swallows exceptions; no metric, no back-off | Reliability | 30 min |
| 11 | 🟠 | Backend | Naive `datetime` in `recorded_at` → wrong `expires_at` (consent compliance) | Correctness | 15 min |
| 12 | 🟠 | Backend | `weekly_reports_job` user_id typed as `Any` | Correctness | 15 min |
| 13 | 🟠 | Infra | ECS service no autoscaling + `desired_count = 1` (SPOF) | Reliability | 1 hr |
| 14 | 🟠 | Infra | ECS no deployment circuit breaker | Reliability | 15 min |
| 15 | 🟠 | Infra | Production deploy: ECS networking fails if prod service not yet created | CI/CD | 30 min |
| 16 | 🟠 | Infra | Production deploy: no auto-rollback after smoke test failure | CI/CD | 1 hr |
| 17 | 🟠 | Watch | `RemoteCaptureService` `START_NOT_STICKY` → silent session end on OS kill | Reliability | 30 min |
| 18 | 🟠 | Watch | No reconnect on Data Layer drop mid-session | Reliability | 1 hr |
| 19 | 🟠 | Watch | `CaptureActivity` no `onDestroy` stop → dangling tracker + open CSV writer | Reliability | 30 min |
| 20 | 🟠 | Watch | `CaptureActivity.kt` 680-line god-class | Architecture | half day |
| 21 | 🟠 | Watch | `tStartMs` is flush wall-clock, not earliest sample timestamp | Correctness | 30 min |
| 22 | 🟠 | Cross | No idempotency key on biosignal upload → retries silently duplicate data | Correctness | 2 hr |
| 23 | 🟠 | Cross | Cron task missing `FIREBASE_CREDENTIALS_JSON` + `SENTRY_DSN` secrets | Reliability | 15 min |
| 24 | 🟡 | Backend | `/docs` + `/openapi.json` exposed unconditionally in production | Security | 15 min |
| 25 | 🟡 | Backend | `supabase_jwt_secret` required but never used | Security | 30 min |
| 26 | 🟡 | Backend | Google JWKS cache never expires (stale key risk) | Security | 30 min |
| 27 | 🟡 | Backend | 500 detail exposes internal exception message | Security | 15 min |
| 28 | 🟡 | Backend | Sleep log unique constraint not in ORM model → autogenerate drift | Reliability | 15 min |
| 29 | 🟡 | Backend | `ensure_user_settings` TOCTOU race on new users | Reliability | 30 min |
| 30 | 🟡 | Backend | `purge_expired_accounts` single long transaction (row lock) | Reliability | 1 hr |
| 31 | 🟡 | Backend | `alembic/env.py` missing 7 of 14 models → autogenerate incorrect | Architecture | 15 min |
| 32 | 🟡 | Backend | Morning tips pollute `pattern_tips` with no expiry | Architecture | 1 hr |
| 33 | 🟡 | Backend | `compute_patterns` called multiple times per request (no memoization) | Cost | 30 min |
| 34 | 🟡 | Backend | `RangeReport`/`WeeklyReport.takeaways` missing `server_default` | Correctness | 15 min |
| 35 | 🟡 | Backend | `avg_rating` O(n²) and non-deterministic on tie | Correctness | 15 min |
| 36 | 🟡 | Backend | `SleepLog` missing index on `user_id` | Correctness | 15 min |
| 37 | 🟡 | Backend | LLM response JSON fence parsing fragile (`strip("\`")`) | Quality | 15 min |
| 38 | 🟡 | Infra | OIDC staging trust allows `pull_request` sub (PR contributor = staging deploy role) | Security | 15 min |
| 39 | 🟡 | Infra | OTel collector sidecar pinned to `latest` | Security | 15 min |
| 40 | 🟡 | Infra | ml_demo `hello-world:latest` runs with backend IAM permissions | Security | 30 min |
| 41 | 🟡 | Infra | ECS task role X-Ray/logs policy uses `resources = ["*"]` | Security | 30 min |
| 42 | 🟡 | Infra | RDS single-AZ | Reliability | needs design |
| 43 | 🟡 | Infra | RDS `deletion_protection = false` + no final snapshot | Reliability | 15 min |
| 44 | 🟡 | Infra | No CloudWatch alarm for RDS CPU | Reliability | 30 min |
| 45 | 🟡 | Infra | Single NAT Gateway (AZ-failure = ECS internet outage) | Reliability | needs design |
| 46 | 🟡 | Infra | ml_demo permanently running (cycling placeholder, ~$10/month) | Cost | 15 min |
| 47 | 🟡 | Infra | `common_tags.Sprint` stale at "2" | Cost | 5 min |
| 48 | 🟡 | Infra | `staging.tfvars` no `ml_demo_image` → service deploys `hello-world` | Correctness | 15 min |
| 49 | 🟡 | Infra | `container_image` is bootstrap placeholder in committed `staging.tfvars` | Correctness | document |
| 50 | 🟡 | Infra | OIDC single legacy SHA1 thumbprint | Correctness | 15 min |
| 51 | 🟡 | Infra | `deploy-staging.yml` manual dispatch bypasses CI gate | CI/CD | document |
| 52 | 🟡 | Infra | `deploy-staging.yml` pushes mutable `latest` tag | CI/CD | 15 min |
| 53 | 🟡 | Infra | Production role ARN hardcoded with `staging` name prefix | CI/CD | 30 min |
| 54 | 🟡 | Watch | `WatchControlListener` accepts commands from any paired app | Security | 1 hr |
| 55 | 🟡 | Watch | No runtime permission re-check before opening trackers | Security | 30 min |
| 56 | 🟡 | Watch | `ChannelRecorder` singletons leak state between sessions | Reliability | 30 min |
| 57 | 🟡 | Watch | `connectService()` copy-pasted between two classes | Reliability | 30 min |
| 58 | 🟡 | Watch | Sensor `onError` only logs; user sees no indication of failed tracker | Reliability | 1 hr |
| 59 | 🟡 | Watch | EDA rate documented as 25 Hz in README; actual is ~1 Hz | Cost | 15 min |
| 60 | 🟡 | Watch | Capture duration hardcoded; requires code edit to change | Cost | 30 min |
| 61 | 🟡 | Watch | Samsung SDK timestamp units not verified; boot-relative ms corrupts all sessions | Correctness | 30 min |
| 62 | 🟡 | Watch | No schema version in batch JSON payload | Correctness | 15 min |
| 63 | 🟡 | Watch | No batch sequence number; dropped/reordered batches undetectable | Correctness | 1 hr |
| 64 | 🟡 | Watch | `isoUtc()` writes `HH-mm-ss` into `metadata.json`; not valid ISO 8601 | Correctness | 15 min |
| 65 | 🟡 | Watch | `ChannelRecorder` singleton fields accessed from multiple threads without sync | Correctness | 30 min |
| 66 | 🟡 | Cross | Cron task missing `ENVIRONMENT` + `OTEL` env vars (reports as `local`) | Reliability | 15 min |
| 67 | 🟡 | Cross | Batch biosignal endpoint no item count limit | Security/Reliability | 30 min |
| 68 | 🟢 | Backend | `role` column no DB check constraint | Security | 15 min |
| 69 | 🟢 | Backend | AI serve `/ml-demo/run` no authentication | Security | 1 hr |
| 70 | 🟢 | Backend | `touch_heartbeat` non-atomic read-modify-write | Reliability | 15 min |
| 71 | 🟢 | Backend | `require_admin` dead code | Architecture | 15 min |
| 72 | 🟢 | Backend | `AuditLog` no index on `target_user_id` / `occurred_at` | Correctness | 15 min |
| 73 | 🟢 | Backend | `_EVENTS_CAP` naming + comment inconsistency | Quality | 5 min |
| 74 | 🟢 | Backend | Sleep log filter uses `fell_asleep_at` vs `ended_on` (semantic mismatch) | Quality | 30 min |
| 75 | 🟢 | Infra | ECR repos use `MUTABLE` image tags | Security | 5 min |
| 76 | 🟢 | Infra | ALB access logging not enabled | Security | 30 min |
| 77 | 🟢 | Infra | `alert_email` personal address committed to `staging.tfvars` | Security | 15 min |
| 78 | 🟢 | Infra | ECS cluster no Container Insights | Reliability | 15 min |
| 79 | 🟢 | Infra | ECS task sizing undocumented for production planning | Cost | document |
| 80 | 🟢 | Infra | `traffic-snapshot.yml` pushes to `master` bypassing branch protection | CI/CD | 30 min |
| 81 | 🟢 | Watch | `isMinifyEnabled = false` in release build | Security | 30 min |
| 82 | 🟢 | Watch | `WAKE_LOCK` permission declared but never acquired | Security | 5 min |
| 83 | 🟢 | Watch | `HIGH_SAMPLING_RATE_SENSORS` declared but not needed at ≤50 Hz | Security | 5 min |
| 84 | 🟢 | Watch | `FLAG_KEEP_SCREEN_ON` never cleared in `onDestroy` | Reliability | 15 min |
| 85 | 🟢 | Watch | `BuildInfo.VERSION_NAME` manual duplicate of Gradle `versionName` | Cost | 15 min |
| 86 | 🟢 | Watch | `serializeBatchPayload` allocates `JSONObject` per sample | Cost | needs design |
| 87 | 🟢 | Watch | Tests don't cover concurrent-write correctness of `SampleBatch` | Correctness | 1 hr |
| 88 | 🟢 | Watch | `PhoneSenderConsumerTest` never tests `sender.send() = false` | Correctness | 30 min |
| 89 | 🟢 | Watch | `ChannelRecorder` object+mutable-state is contradictory Kotlin design | Quality | 30 min |
| 90 | 🟢 | Watch | Service notification strings hardcoded Korean (not in `strings.xml`) | Quality | 15 min |

---

## What's Good

These things are done well and should not be accidentally broken during fixes:

- **No public RDS, no public S3, no hardcoded secrets.** The infra baseline is correctly locked down for staging — all secrets are in Secrets Manager, injected via ECS task secrets.
- **OIDC trust for production is correctly locked.** The production OIDC role uses `StringEquals` + `environment:production` only — no branch or PR wildcards.
- **Trivy scan gates every CI build** on HIGH/CRITICAL with `ignore-unfixed: true` — healthy security gate that blocks real risks without false-positive noise.
- **`get_db` session lifecycle is correct.** The `AsyncSession` dependency commits on success and rolls back on exception — no session leaks in the normal request path.
- **DLQ and retry are configured on the scheduler.** The EventBridge Scheduler targets all have `dead_letter_config` (SQS) and `retry_policy` (3 retries, 1hr window) — the infrastructure is sound; the missing schedule rules are a configuration gap, not a design flaw.
- **Structlog + OTel + Sentry are all wired.** The observability stack is present and integrated; the gaps are metric counters in specific failure paths, not a missing foundation.
- **`SampleBatch` correctly uses `@Synchronized` for thread safety on its add/drain operations.** The existing synchronization approach is sound; the issue is that `ChannelRecorder` singletons don't use it.
- **Migration files are well-ordered, non-destructive, and include appropriate downgrades.** No migrations drop columns or tables without a reversible downgrade path.
- **Alembic env correctly uses `include_schemas=False`** and a typed async runner — the migration infra is correct; it just needs its model import list completed.
- **CI correctly gates deploy-staging on CI success** (`workflow_run: conclusion == 'success'`) — automatic deploys only happen after tests pass.
