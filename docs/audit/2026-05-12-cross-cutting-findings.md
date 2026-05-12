# Cross-cutting Findings
## Six boundary pairs traced after reading all three subsystem reports

---

## Boundary 1 — Watch → Backend (biosignal data path)

The watch sends data to the paired phone via WearPhoneSender (Wearable Data Layer
MessageClient). The phone companion app (frontend/, not audited) then calls the backend
at `/api/v1/sync/biosignals` or `/api/v1/sync/biosignals/batch`. The backend responds
with presigned S3 URLs; the phone uploads binary directly to S3.

### 🟠 High — No idempotency on biosignal upload; retries silently duplicate data

**File:** watch/sensor-capture/.../PhoneSenderConsumer.kt ↔ backend/app/sync/router.py:144
**Lens:** Correctness
**Subsystem:** Cross-cutting

**What:** `POST /sync/biosignals` has no idempotency key; if the phone retries after a network failure (e.g., channel drop mid-upload), the backend creates a new `RawBiosignalUpload` row and a new S3 object each time — there is no dedup check.
**Why it matters:** The watch agent already flagged that `flushIfNonEmpty` discards data before confirming the send; retry is the intended recovery path, but each retry produces a duplicate DB row and S3 object that downstream processing will double-count.
**Recommended fix:** Add an `idempotency_key` UUID field to `BiosignalUploadRequest`; store it in `RawBiosignalUpload` with a unique constraint; return the existing `upload_id` if the key is already seen instead of creating a new row.

---

### 🟡 Medium — Batch biosignal endpoint has no upper bound on item count

**File:** backend/app/sync/router.py:192  ↔  watch/sensor-capture/.../SampleBatch.kt
**Lens:** Security / Reliability
**Subsystem:** Cross-cutting

**What:** `POST /sync/biosignals/batch` loops over `payload.items` with no limit; a client (or malformed watch batch) can send thousands of items, generating thousands of S3 `presign_put` calls and DB inserts in one request.
**Why it matters:** S3 presign calls are sync-in-executor; a 1,000-item batch blocks the event loop thread pool and can OOM the ECS task.
**Recommended fix:** Add `max_items: int = 50` to `BiosignalBatchUploadRequest` and validate with `@field_validator`; return HTTP 422 if exceeded.

---

### ℹ️ Info — Phone-side translation layer is unaudited

**File:** watch/sensor-capture/.../WearPhoneSender.kt ↔ backend/app/sync/router.py
**Lens:** Correctness
**Subsystem:** Cross-cutting

**What:** The actual mapping from the watch's `(path: String, body: String)` Wear Data Layer message to the backend HTTP POST lives entirely in `frontend/` (not in scope). It is unknown whether the phone correctly maps watch message paths to backend endpoints, whether it adds the `Authorization` header, or whether it retries on failure.
**Why it matters:** The entire data pipeline depends on this translation layer; bugs there would cause silent data loss with no server-side trace.
**Recommended fix:** Scope the phone-side companion app into a follow-up audit, or add server-side request logging to `/sync/biosignals` to detect upload gaps.

---

## Boundary 2 — Backend secrets ↔ Infra Secrets Manager

### 🟠 High — Cron task definition missing FIREBASE_CREDENTIALS_JSON and SENTRY_DSN secrets

**File:** backend/infra/scheduler.tf — resource "aws_ecs_task_definition" "cron" ↔ backend/app/config.py:78
**Lens:** Reliability / Security
**Subsystem:** Cross-cutting

**What:** The cron task definition (`scheduler.tf:61–126`) does not inject `FIREBASE_CREDENTIALS_JSON` or `SENTRY_DSN` from Secrets Manager; the backend task definition (`ecs.tf:152–184`) does both. If any cron job triggers FCM notifications, `firebase_credentials_json` will be `None`, and the FCM service silently no-ops (backend agent already flagged this bug). Cron exceptions also won't be reported to Sentry.
**Why it matters:** The weekly reports job (`send_morning_tips` path) and any future cron job that sends push notifications will silently fail to deliver; errors disappear with no alerting.
**Recommended fix:** Add the same `secrets` block entries for `FIREBASE_CREDENTIALS_JSON` and `SENTRY_DSN` to the cron task definition in `scheduler.tf`, mirroring `ecs.tf:179–184`.

---

### 🟡 Medium — Cron task missing ENVIRONMENT, OTEL_EXPORTER_OTLP_ENDPOINT env vars

**File:** backend/infra/scheduler.tf — resource "aws_ecs_task_definition" "cron" ↔ backend/app/config.py:60
**Lens:** Reliability
**Subsystem:** Cross-cutting

**What:** The cron task definition omits `ENVIRONMENT` and `OTEL_EXPORTER_OTLP_ENDPOINT` from its environment block. `Settings.environment` defaults to `"local"`, so Sentry tags and OTel resource attributes will report all cron spans as coming from `local`, not `staging` or `production`. Tracing data from cron jobs will be unroutable or missing.
**Why it matters:** Cron job traces and Sentry errors will appear as `local` environment, causing them to be filtered out from staging/production dashboards.
**Recommended fix:** Copy the `ENVIRONMENT` and `OTEL_EXPORTER_OTLP_ENDPOINT` entries from the backend task env block into the cron task env block in `scheduler.tf`.

---

## Boundary 3 — ECS task definition ↔ Dockerfile

### 🟡 Medium — OTel collector sidecar pinned to `latest` tag

**File:** backend/infra/ecs.tf:204
**Lens:** Reliability
**Subsystem:** Cross-cutting

**What:** The OTel collector sidecar container uses `public.ecr.aws/aws-observability/aws-otel-collector:latest`. The backend container uses a SHA-pinned ECR image, but the sidecar floats on `latest`.
**Why it matters:** A breaking change to the collector image format will silently deploy on the next ECS task launch, potentially breaking all traces and metrics with no code change in the repo.
**Recommended fix:** Pin to a specific version tag (e.g., `v0.43.1`) and update intentionally. Set a Renovate/Dependabot rule or a manual review cadence.

---

### ℹ️ Info — ECS healthcheck, port, and command alignment is correct

**File:** backend/infra/ecs.tf:128 ↔ backend/Dockerfile
**Lens:** Correctness
**Subsystem:** Cross-cutting

**What:** The ECS task runs `uvicorn app.main:app --host 0.0.0.0 --port 8000`; port 8000 is mapped; the healthcheck curls `http://localhost:8000/health`. The backend has a `/health` endpoint. The image tag is always a full SHA (not `latest`) — this is correct.
**Why it matters:** No mismatch found.
**Recommended fix:** No action required.

---

## Boundary 4 — Scheduler jobs ↔ Infra scheduler rules

### 🔴 Critical — Two job files have no scheduler rule; they never fire

**File:** backend/infra/scheduler.tf ↔ backend/app/jobs/send_morning_tips.py + backend/app/jobs/send_sleep_nudges.py
**Lens:** Reliability / Correctness
**Subsystem:** Cross-cutting

**What:** `scheduler.tf` defines three EventBridge rules: `purge_accounts`, `purge_biosignals`, `weekly_reports`. But the jobs directory has five files — `send_morning_tips.py` and `send_sleep_nudges.py` have no corresponding schedule. These jobs are dead: they are never triggered.
**Why it matters:** Morning tips and sleep nudges are user-facing features. If they exist as code but have no trigger, users never receive them — a silent feature failure invisible to operators.
**Recommended fix:** Either add EventBridge schedule rules for `send_morning_tips` and `send_sleep_nudges` (with appropriate cadences and DLQ), or delete the job files and remove associated code if the features are intentionally deferred.

---

### ℹ️ Info — weekly_reports schedule injects AI_FEATURES_ENABLED=true via command override

**File:** backend/infra/scheduler.tf:287 ↔ backend/app/config.py:99
**Lens:** Correctness
**Subsystem:** Cross-cutting

**What:** The `weekly_reports` schedule overrides `AI_FEATURES_ENABLED=true` via command-level `export`, while `ai_features_enabled` in the cron task def inherits the env-level value (which may be `false` in staging). The command override works because the shell export takes precedence over the task-level env — but the mechanism is fragile and non-obvious.
**Why it matters:** If the cron task definition is updated to add an env-level `AI_FEATURES_ENABLED=false`, it won't override the command-level export; but if someone changes the shell command to remove the export, AI features silently disable without a Terraform change.
**Recommended fix:** Move `AI_FEATURES_ENABLED` for the weekly_reports schedule into the ECS `containerOverrides.environment` array (proper override path) rather than a shell `export` in the command string.

---

## Boundary 5 — CI/CD ↔ OIDC trust

### 🟠 High — OIDC staging trust allows `pull_request` sub; any contributor PR can assume staging deploy role during CI

**File:** backend/infra/oidc.tf:33 ↔ .github/workflows/ci.yml
**Lens:** Security
**Subsystem:** Cross-cutting

**What:** The staging OIDC trust policy uses `StringLike` and includes `repo:...:pull_request` as an allowed sub claim. Any contributor who opens a PR triggers CI, and if `ci.yml` calls `configure-aws-credentials` with this role, their workflow gets full ECR push + ECS RunTask permissions on the staging account.
**Why it matters:** A malicious or compromised PR can push a poisoned image to the staging ECR repo or run arbitrary ECS tasks in the staging cluster — without needing write access to the repo.
**Recommended fix:** Remove `pull_request` from the OIDC trust. If CI needs AWS access for tests (e.g., ECR pull), create a separate read-only CI role. The deploy role should only be assumable from `environment:staging` and `ref:refs/heads/master`.

---

### ✅ Good — Production OIDC role is correctly locked to `environment:production`

**File:** backend/infra/oidc.tf:128
**Lens:** Security
**Subsystem:** Cross-cutting

**What:** The production OIDC role uses `StringEquals` (not `StringLike`) and `environment:production` only — no `pull_request` or branch refs.
**Why it matters:** No finding — this is done correctly.
**Recommended fix:** No action required. Apply the same `StringEquals` + `environment:staging`-only approach to the staging role.

---

## Boundary 6 — AI/serve ↔ Backend AI services

### ℹ️ Info — AI/serve/ and backend/services/ai/ are completely separate; no integration exists

**File:** AI/serve/router.py ↔ backend/app/services/ai/bedrock_client.py
**Lens:** Architecture
**Subsystem:** Cross-cutting

**What:** The backend's `services/ai/` uses `BedrockClient` (boto3 → AWS Bedrock directly) for tip generation and weekly reports. `AI/serve/` is a completely separate FastAPI model-serving service (with its own schemas, runner, and Dockerfile) deployed in the `ml_demo` Terraform stack. The backend has zero calls to `AI/serve/` — they share no code, no client, and no HTTP calls.
**Why it matters:** Not a bug per se, but a significant architectural gap: the ml_demo stack runs a separate inference container at real AWS cost, but the production feature path (Bedrock) doesn't use it at all. If the intent was to replace Bedrock with a fine-tuned local model, the integration was never built.
**Recommended fix:** Decide the intended architecture. If `AI/serve/` + ml_demo is a research artifact, shut it down to eliminate the idle cost. If it is the intended production AI path, build the HTTP client in `backend/app/services/ai/` to call it instead of (or alongside) Bedrock.

---

## Cross-cutting Summary

7 findings: 1 🔴 critical, 3 🟠 high, 3 🟡 medium, 0 🟢 low, 4 ℹ️ info
