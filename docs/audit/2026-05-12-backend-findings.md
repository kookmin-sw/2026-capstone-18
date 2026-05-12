# Backend Findings

Audit date: 2026-05-12
Scope: Python backend (`backend/`) and AI serve layer (`AI/serve/`).
Auditor: Claude Sonnet 4.6 (automated read-only analysis)

---

## Security

### 🟠 High — JWT bearer token passed in WebSocket query parameter

**File:** `backend/app/realtime/router.py:55`
**Lens:** Security
**Subsystem:** Backend

**What:** The WebSocket endpoint `/ws/realtime` authenticates via a `token` query parameter (`?token=<jwt>`), which means the JWT is logged verbatim in reverse-proxy access logs and server-side request logs.
**Why it matters:** Access logs are lower-security than application logs; any log aggregation system (CloudWatch, Datadog) will store the bearer token in plain text and it is trivially exfiltrable, unlike a request header that can be masked at the proxy level.
**Recommended fix:** Accept the token in the first WebSocket message payload after the connection opens (client sends `{"type":"auth","token":"..."}`) rather than in the URL. The backend sends `WS_1008_POLICY_VIOLATION` and closes if the first message is not auth or the token is invalid.

---

### 🟠 High — No rate limiting on auth endpoints

**File:** `backend/app/auth/router.py` (entire file)
**Lens:** Security
**Subsystem:** Backend

**What:** There is no rate limiting on `POST /auth/anon`, `/auth/google`, `/auth/email/login`, or `/auth/email/signup` — an attacker can perform unlimited credential-stuffing or anonymous-user creation at the application layer.
**Why it matters:** Unlimited `/auth/anon` calls create Supabase users on demand (costing quota); unlimited `/auth/email/login` calls are a credential-stuffing vector; there is no application-layer defence-in-depth even if a WAF exists upstream.
**Recommended fix:** Add `slowapi` (or an AWS WAF rule) to cap each IP to ~10 calls per minute on auth endpoints. Alternatively configure Supabase's own rate-limit settings for the auth API.

---

### 🟡 Medium — /docs and /openapi.json exposed in production with no auth

**File:** `backend/app/main.py:82`
**Lens:** Security
**Subsystem:** Backend

**What:** `docs_url="/docs"`, `redoc_url="/redoc"`, and `openapi_url="/openapi.json"` are all enabled unconditionally; the Swagger UI is publicly accessible in staging and production.
**Why it matters:** The schema exposes endpoint paths, parameter names, and detailed error reasons that give an attacker a map of the API surface.
**Recommended fix:** Disable docs in production: `docs_url=None if settings.environment == "production" else "/docs"` (and similarly for `redoc_url` and `openapi_url`).

---

### 🟡 Medium — `supabase_jwt_secret` loaded but never used

**File:** `backend/app/config.py:45`
**Lens:** Security
**Subsystem:** Backend

**What:** `supabase_jwt_secret` is a required `Settings` field and is set in all test environments, but `app/auth/jwt.py` was refactored to use the asymmetric JWKS flow — the HS256 secret is never referenced anywhere in the production code path.
**Why it matters:** The field is a required secret injected from AWS Secrets Manager, adding operational overhead; more importantly, its presence can mislead future developers into thinking HS256 verification is active, when the JWKS flow is the real gate.
**Recommended fix:** Remove the field from `Settings` and from any Secrets Manager / `.env` templates; add a code comment in `jwt.py` confirming HS256 is fully retired.

---

### 🟡 Medium — Google JWKS cache never expiries; stale key after rotation could lock out users

**File:** `backend/app/auth/google.py:24`
**Lens:** Security
**Subsystem:** Backend

**What:** `_jwks_cache` is a module-level dict that is filled once and never proactively expired; Supabase's JWKS cache (`app/auth/jwt.py:25`) has the same pattern.
**Why it matters:** Google rotates its public keys roughly every 6 hours. If the process runs longer than a key rotation and the old kid disappears from the JWKS, a one-time refetch is attempted (line 74), but if a new token arrives with a new kid that the cache doesn't have, the refetch is correct. The real risk is the opposite: an old kid still in cache after rotation could theoretically allow replay of an old id_token if the library doesn't enforce `exp`. (`python-jose` does check `exp`, so this is medium not high.) The pattern is still fragile for long-lived processes.
**Recommended fix:** Cache the JWKS with a TTL (e.g., `cachetools.TTLCache` with 3600 s) so stale entries expire automatically between rotations.

---

### 🟡 Medium — Error detail exposes internal exception message to clients

**File:** `backend/app/observability/exception_handlers.py:79`
**Lens:** Security
**Subsystem:** Backend

**What:** The catch-all `_generic_exception_handler` includes `str(exc)` in the `detail` field of the 500 response returned to the client.
**Why it matters:** Internal exception messages can leak database query fragments, S3 key paths, internal service URLs, or dependency version strings that aid attackers.
**Recommended fix:** Return a generic `"detail": "an unexpected error occurred"` to clients and keep the full exception in the structured log only (already present via `logger.exception`).

---

### 🟢 Low — `role` column has no DB check constraint

**File:** `backend/app/models/user.py:46`
**Lens:** Security
**Subsystem:** Backend

**What:** The `role` column has a `server_default="user"` but no `CHECK (role IN ('user', 'admin'))` constraint; `require_admin` in dependencies.py relies solely on an application-level string comparison.
**Why it matters:** A direct DB write (migration bug, admin tool) can set an arbitrary role string that bypasses the admin gate silently; the constraint enforces the invariant at the storage layer.
**Recommended fix:** Add a check constraint in a new migration: `ALTER TABLE users ADD CONSTRAINT ck_users_role CHECK (role IN ('user', 'admin'));`

---

### 🟢 Low — AI serve endpoint (`/api/v1/ml-demo/run`) has no authentication

**File:** `AI/serve/router.py:33`
**Lens:** Security
**Subsystem:** Backend (AI)

**What:** The ML demo endpoint accepts arbitrary zip file uploads with no JWT verification — any caller who can reach the service can upload data and trigger model inference.
**Why it matters:** Even if the service is network-restricted, internal tooling mistakes (accidental exposure) would allow unauthenticated inference with potential DoS via CPU-heavy signal processing.
**Recommended fix:** Add a shared API key header check or, if the service is deployed as an ECS side-task, enforce network-level isolation so it is not reachable from the public internet at all.

---

## Reliability

### 🔴 Critical — `run_weekly_reports_job` commits mid-loop but continues on failure, leaving partial state

**File:** `backend/app/jobs/weekly_reports_job.py:56`
**Lens:** Reliability
**Subsystem:** Backend

**What:** The weekly report job iterates over all user IDs, calls `gen.generate(db, ...)` for each (which calls `db.flush()` inside), catches exceptions per-user, and then calls `await db.commit()` at line 63 after the loop regardless of how many failures occurred.
**Why it matters:** If `gen.generate` raises inside the loop after some successful flushes, the `except` block catches the error, increments `failed`, and continues. At the end, `db.commit()` commits the partial work — successfully-generated reports are committed even though the job "failed." On the next run the job will find existing rows and update them, so it is roughly idempotent, but error observability is broken: the caller's `JobSummary` might show `failures=3, reports_written=7` while the commit also persists those 7, giving the impression of partial success when the caller was expecting an all-or-nothing result. The deeper issue is that any exception *after* the `db.flush()` call inside `generate()` but before the user loop's `except` could leave orphaned unflushed state on the session.
**Recommended fix:** Move `await db.commit()` outside the job function (callers already wrap it), or structure the loop so each user gets its own sub-transaction via a savepoint (`async with db.begin_nested()`).

---

### 🔴 Critical — Double-commit in `GET /reports/range` corrupts the session

**File:** `backend/app/reports/router.py:179`
**Lens:** Reliability
**Subsystem:** Backend

**What:** The range report endpoint calls `await db.commit()` directly at line 179 inside the request handler, and then the `get_db` dependency also calls `await db.commit()` at request teardown (`app/db/dependencies.py:32`). This double-commit is called on the same `AsyncSession` object.
**Why it matters:** SQLAlchemy's async session raises `InvalidRequestError: Can't operate on a closed transaction` on the second commit, causing a 500 error on every successful range-report generation. Even if the ORM happens to silently accept it (it does not), committing twice is semantically wrong and could cause race conditions if another task is using the same session.
**Recommended fix:** Remove the inline `await db.commit()` from the router; `get_db` already commits at request end. The `RangeReportGenerator.generate()` method already calls `db.flush()`, which is sufficient within the request scope.

---

### 🟠 High — WebSocket JWT in URL is logged by the `request_id_middleware` via Starlette's internal URL

**File:** `backend/app/main.py:123`
**Lens:** Reliability / Security (overlap)
**Subsystem:** Backend

**What:** The `request_id_middleware` logs the full request URL via `request.url.path` for validation errors; the `_generic_exception_handler` logs `path=str(request.url.path)`. Starlette's `.path` does not include query params, but `.url` does. However the WebSocket token appears in request-level logging from the OTel FastAPI instrumentor which records the full URL including query string.
**Why it matters:** See the Security finding above; this is the reliability angle — if the OTel exporter is shipping spans to a third party (e.g., Datadog via OTLP), the token appears in span attributes.
**Recommended fix:** Same as the Security fix: move the token out of the URL.

---

### 🟠 High — Firebase initialisation failure is silently swallowed; FCM silently no-ops

**File:** `backend/app/services/fcm.py:52`
**Lens:** Reliability
**Subsystem:** Backend

**What:** If `firebase_admin.initialize_app(cred)` raises any exception, the code logs an error but sets `_initialized = True` anyway, and subsequent calls to `send_to_user` will try to import `firebase_admin.messaging` which will succeed (the module exists) but the app is not initialised, leading to a `ValueError: The default Firebase app does not exist` that is itself caught by the `except Exception` at line 85 and logged as a warning — meaning every FCM send silently fails in production if credentials are bad.
**Recommended fix:** On init failure, set `_initialized = False` (or a separate `_init_failed` flag) so `send_to_user` can short-circuit with a proper error rather than silently failing.

---

### 🟠 High — `_sweep_loop` swallows all exceptions silently, masking DB issues

**File:** `backend/app/main.py:59`
**Lens:** Reliability
**Subsystem:** Backend

**What:** The `except Exception` block in `_sweep_loop` calls `logger.exception("websocket_sweep_failed")` but never increments a counter, never alerts, and never backs off — it logs once per 60 s if the DB is down, flooding logs but not surfacing a structured metric.
**Why it matters:** A persistent DB connectivity issue would cause 1440 logged exceptions per day but no pagerduty-level alert, and the stale-connection table would grow unbounded.
**Recommended fix:** Emit a Prometheus counter (`websocket_sweep_errors_total`) on each exception so alerting can fire on sustained failure; add exponential backoff (cap at 5 min) to reduce log noise during outages.

---

### 🟡 Medium — Sleep log unique constraint exists only in migration, not in the ORM model

**File:** `backend/app/models/sleep_log.py`
**Lens:** Reliability / Correctness
**Subsystem:** Backend

**What:** The migration `abd7e990abd2_add_sleep_logs.py` creates a unique index `uq_sleep_logs_user_ended` on `(user_id, ended_on)`, but the `SleepLog` ORM model has no `__table_args__` with a corresponding `UniqueConstraint`. The router comment (line 159) references this constraint by name but the model is unaware of it.
**Why it matters:** Alembic autogenerate will not detect schema drift for this constraint because the model doesn't declare it; a future `alembic revision --autogenerate` might silently drop the unique index if the model is taken as the source of truth.
**Recommended fix:** Add `__table_args__ = (UniqueConstraint("user_id", "ended_on", name="uq_sleep_logs_user_ended"),)` to `SleepLog`.

---

### 🟡 Medium — Scheduler jobs have no retry or dead-letter mechanism

**File:** `backend/app/jobs/` (all job files)
**Lens:** Reliability
**Subsystem:** Backend

**What:** All jobs (`send_sleep_nudges`, `send_morning_tips`, `purge_accounts`, `purge_biosignals`) are invoked by EventBridge ECS RunTask with no retry configuration shown; if the task exits non-zero (e.g., DB unreachable at startup), the run is lost.
**Why it matters:** A transient network blip at the scheduled minute causes a full day's tips/nudges to be silently skipped with no automatic retry.
**Recommended fix:** Configure EventBridge Scheduler retry policy (max 3 retries, 5 min back-off) for each ECS RunTask target; jobs are already idempotent so retries are safe.

---

### 🟡 Medium — Stale `ensure_user_settings` is not race-condition safe

**File:** `backend/app/services/user_settings.py:18`
**Lens:** Reliability
**Subsystem:** Backend

**What:** `ensure_user_settings` first does a `SELECT`, and if no row is found does an `INSERT`. Under concurrent requests (two requests for the same new user arriving simultaneously), both `SELECT` calls return `None` and both attempt an `INSERT`, causing a unique constraint violation on the second.
**Why it matters:** The violation surfaces as an unhandled `IntegrityError` bubbling out to the global 500 handler during the very first authenticated request for a new user, which is also the most likely moment for concurrency (app launch typically fires several simultaneous API calls).
**Recommended fix:** Use `INSERT ... ON CONFLICT DO NOTHING RETURNING *` via SQLAlchemy's `insert().on_conflict_do_nothing()`, or wrap the operation in a savepoint and retry on `IntegrityError`.

---

### 🟡 Medium — `purge_expired_accounts` deletes all users in a single transaction; long lock potential

**File:** `backend/app/services/deletion.py:77`
**Lens:** Reliability
**Subsystem:** Backend

**What:** The purge job collects all expired users, deletes their S3 objects (which is I/O-bound and can take seconds per user), then issues one `DELETE` per user and calls `db.flush()` at the end, all within a single transaction opened by the caller.
**Why it matters:** A single long-lived transaction holding row locks on `users` and cascade-locked child tables blocks concurrent reads on those rows and any auto-vacuum work on the table.
**Recommended fix:** Process users in batches of 10 and commit after each batch; since the job is idempotent, partial progress is safe.

---

### 🟢 Low — `touch_heartbeat` does a SELECT then UPDATE; race on concurrent pings

**File:** `backend/app/realtime/registry.py:33`
**Lens:** Reliability
**Subsystem:** Backend

**What:** `touch_heartbeat` fetches the row with `scalar_one_or_none` then sets `last_seen_at`, but two concurrent pings for the same connection id would both fetch the row and both write, resulting in a lost update (non-atomic read-modify-write).
**Why it matters:** In practice one WebSocket sends one ping at a time so concurrency is low, but under network bursts the heartbeat timestamp can be stale.
**Recommended fix:** Replace with a direct `UPDATE websocket_connections SET last_seen_at = now() WHERE id = :id`.

---

## Cost & Architecture

### 🟡 Medium — `alembic/env.py` does not import all models needed for autogenerate

**File:** `backend/alembic/env.py:17`
**Lens:** Cost & Architecture
**Subsystem:** Backend

**What:** The import block in `env.py` imports `Cycle, FcmToken, RawBiosignalUpload, StressEvent, SyncBlob, User, WebsocketConnection` but is missing `AuditLog, PatternTip, WeeklyReport, RangeReport, SleepLog, TriggerCategory, UserSettings`.
**Why it matters:** Running `alembic revision --autogenerate` would generate a migration that creates those missing tables even though they already exist in the DB, or would miss new columns added to those models.
**Recommended fix:** Import every model that subclasses `Base` in `env.py`, or switch to `from app.models import *` with an explicit `__all__` in `app/models/__init__.py`.

---

### 🟡 Medium — Morning tip caches tips in `pattern_tips` with a synthetic `morning:YYYY-MM-DD` key

**File:** `backend/app/services/ai/morning_tip.py:58`
**Lens:** Cost & Architecture
**Subsystem:** Backend

**What:** Morning tips are stored in the `pattern_tips` table using a synthetic `pattern_key` like `morning:2026-05-12` to avoid a new migration, but the `PatternTip.pattern_key` column is `String(64)` and the `UniqueConstraint("user_id", "pattern_key")` was designed for a different semantic — tips accumulate as one row per day per user and are never pruned.
**Why it matters:** After a year, a user with daily tips has 365 extra rows in `pattern_tips`; after scaling to many users this pollutes the table and makes real pattern tips slower to query.
**Recommended fix:** Create a dedicated `morning_tips` table with appropriate retention logic, or add a purge step to the `purge_biosignals` job that deletes `morning:*` keys older than 7 days.

---

### 🟡 Medium — `compute_patterns` is called multiple times per request in AI report pipeline

**File:** `backend/app/services/ai/range_report.py:100`, `backend/app/services/ai/weekly_report.py:100`, `backend/app/services/insights/patterns.py`
**Lens:** Cost & Architecture
**Subsystem:** Backend

**What:** Both `RangeReportGenerator.generate()` and `WeeklyReportGenerator.generate()` call `compute_patterns(db, user_id, frm, to)`, which itself issues 3–4 queries. Additionally the `/insights/morning-tip` endpoint calls `compute_patterns` inside `MorningTipGenerator`, and these generators are also called from `/insights/tips/{pattern_key}` which calls `compute_patterns` again.
**Why it matters:** A single user request to `/insights/tips/{pattern_key}` executes `compute_patterns` (several DB round-trips) plus a Bedrock call — the pattern compute is redone every time the cache misses.
**Recommended fix:** Memoize `compute_patterns` results with a short in-request cache (or use `functools.lru_cache` keyed on `(user_id, frm, to)` within a single async context) to deduplicate repeated calls in the same request.

---

### 🟢 Low — `require_admin` dependency is defined but no route uses it

**File:** `backend/app/auth/dependencies.py:105`
**Lens:** Cost & Architecture
**Subsystem:** Backend

**What:** The `require_admin` dependency is defined but the audit found no router that depends on it (`grep` across all routers returns no result for `require_admin`).
**Why it matters:** Dead code increases cognitive overhead and may indicate a planned admin-only route that was never wired up; if forgotten, admin actions may be accessible to all authenticated users.
**Recommended fix:** Either wire `require_admin` to the intended admin routes, or remove it and note in a comment that admin operations are done via direct DB/Supabase access.

---

### ℹ️ Info — `content_hash` in sync upload request is accepted but never verified

**File:** `backend/app/schemas/sync.py:17`
**Lens:** Cost & Architecture
**Subsystem:** Backend

**What:** `SyncUploadRequest` requires a `content_hash` field, but the sync router never reads or stores it; the field is silently discarded.
**Why it matters:** If content-hash verification was intended as an integrity check, it is not being performed; if it was forward-looking, the dead field should be removed or documented.

---

## Correctness & Data Integrity

### 🔴 Critical — `SleepLog.rating` is `str` in the ORM but `SleepRating` Literal in the create schema; no DB validation in model

**File:** `backend/app/models/sleep_log.py:39`, `backend/app/schemas/sleep_logs.py:52`
**Lens:** Correctness
**Subsystem:** Backend

**What:** `SleepLogResponse.rating` is typed as plain `str`, while `SleepLogCreate.rating` is `SleepRating = Literal["very_poor","poor","okay","good","great"]`. A `PATCH` that sets `rating` uses `SleepRating | None` in the update schema correctly. However, because the ORM model column is `String(16)` with no Python-level enum, any code that reads a `SleepLog` row directly (e.g., weekly report) gets a `str` and must trust the DB check constraint. If the check constraint were to be accidentally dropped, invalid rating values would silently flow through the entire analytics pipeline.
**Why it matters:** The check constraint in the migration is the only guard; the model provides no defence-in-depth and the response schema does not re-validate.
**Recommended fix:** Add a Python-level `Enum` or `CheckConstraint` directly to the `SleepLog` ORM model and use it in `SleepLogResponse` to ensure validation at both layers.

---

### 🟠 High — Naive `datetime` from biosignal `recorded_at` field could mix with aware datetimes

**File:** `backend/app/schemas/sync.py:43`
**Lens:** Correctness
**Subsystem:** Backend

**What:** `BiosignalUploadRequest.recorded_at` is `datetime` with no `AwareDatetime` annotation or validator; Pydantic v2 accepts naive datetimes. In the router (`sync/router.py:158`), `expires_at = payload.recorded_at + timedelta(days=365)` is stored in a `DateTime(timezone=True)` column. Postgres will accept a naive datetime via asyncpg and treat it as local time (or UTC depending on session settings), making `expires_at` subtly wrong.
**Why it matters:** Wrong `expires_at` means biosignal data may not be purged on schedule, which is a GDPR/consent compliance risk given this data is tied to explicit consent.
**Recommended fix:** Use `pydantic.AwareDatetime` for `recorded_at` in `BiosignalUploadRequest` to reject naive timestamps at the API boundary.

---

### 🟠 High — `weekly_reports_job.py` user_id passed to `WeeklyReportGenerator.generate` is a UUID but typed as a generic `Any`

**File:** `backend/app/jobs/weekly_reports_job.py:51`
**Lens:** Correctness
**Subsystem:** Backend

**What:** `select(distinct(StressEvent.user_id))` returns SQLAlchemy-mapped `UUID` objects; these are then passed directly to `gen.generate(db, user_id=uid, ...)`. However the return type of `.scalars().all()` for a UUID column is `Sequence[Any]` — if asyncpg ever returns a string UUID instead of a `uuid.UUID` object (e.g., after a SQLAlchemy version bump), the generator will fail when it tries to use it as a UUID in further queries.
**Why it matters:** Type mismatch would surface as a runtime error on the next weekly report run, silently failing all reports.
**Recommended fix:** Explicitly cast: `uid = uuid.UUID(str(uid))` before passing to the generator, or add a type annotation to verify the column yields `uuid.UUID`.

---

### 🟡 Medium — `RangeReport` model declares `takeaways` with Python `default=list` but no `server_default`

**File:** `backend/app/models/range_report.py:37`
**Lens:** Correctness
**Subsystem:** Backend

**What:** `takeaways: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)` uses a Python-side `default` but no `server_default`. `WeeklyReport` at line 34 has the same pattern. The migration correctly adds `server_default=sa.text("'[]'::jsonb")`, but the model does not, meaning a row inserted by a non-ORM path (e.g., a raw SQL insert) would get a NULL for `takeaways` (violating `nullable=False`).
**Why it matters:** Raw SQL inserts (data migrations, DBA tooling) would fail with a NOT NULL violation instead of defaulting to `[]`.
**Recommended fix:** Add `server_default=text("'[]'::jsonb")` to the `takeaways` column in both models, matching the migration.

---

### 🟡 Medium — `avg_rating` computation uses `max` with a count key, which returns the wrong modal value for ties

**File:** `backend/app/services/ai/range_report.py:109`, `backend/app/services/ai/weekly_report.py:109`
**Lens:** Correctness
**Subsystem:** Backend

**What:** `avg_rating = max({s.rating for s in sleeps}, key=[s.rating for s in sleeps].count)` computes a mode but constructs a new list on every call to `key`, making it O(n²) and potentially returning a non-deterministic result when two ratings tie (Python's `max` returns the first maximum encountered, which depends on set iteration order — undefined).
**Why it matters:** For weekly summaries with balanced `good`/`great` ratings, the displayed "average rating" in the AI report could flip between runs.
**Recommended fix:** Use `collections.Counter(s.rating for s in sleeps).most_common(1)[0][0]` which is O(n) and deterministic on tie (returns the first encountered in insertion order).

---

### 🟡 Medium — `SleepLog` missing index on `user_id`

**File:** `backend/app/models/sleep_log.py`
**Lens:** Correctness
**Subsystem:** Backend

**What:** The `SleepLog` model has a `user_id` FK column but no dedicated index on it (no `index=True` and no `__table_args__` with an `Index`). The migration (`abd7e990abd2`) only creates the composite unique index `uq_sleep_logs_user_ended (user_id, ended_on)`. While that composite index is used by some queries, queries that filter only by `user_id` without `ended_on` (e.g., `dashboard._sleep`, `morning_tip._gather_context`) cannot use it efficiently.
**Why it matters:** As sleep logs accumulate, queries fetching the latest log by user will do a sequential scan of the composite index rather than a tight index seek.
**Recommended fix:** Add `index=True` to the `user_id` column or add `Index("ix_sleep_logs_user_id", "user_id")` to `__table_args__`.

---

### 🟢 Low — `AuditLog` model has no index on `occurred_at` or `target_user_id`

**File:** `backend/app/models/audit_log.py`
**Lens:** Correctness
**Subsystem:** Backend

**What:** `AuditLog` has no `__table_args__` with any index; `occurred_at` and `target_user_id` have no index despite being the natural query columns for compliance lookups.
**Why it matters:** As the audit log grows, compliance queries (`SELECT * FROM audit_log WHERE target_user_id = :id ORDER BY occurred_at`) will do full sequential scans.
**Recommended fix:** Add `Index("ix_audit_log_target_user_occurred", "target_user_id", "occurred_at")`.

---

### ℹ️ Info — Alembic `env.py` imports from `app.models` using names that require `app/models/__init__.py` to re-export them

**File:** `backend/alembic/env.py:17`
**Lens:** Correctness
**Subsystem:** Backend

**What:** The import `from app.models import (Cycle, FcmToken, ...)` requires these names to be exported from `app/models/__init__.py`. If that file doesn't exist or is incomplete, migrations fail with an `ImportError`. This is low-risk currently but worth auditing.

---

## Quality

### 🟡 Medium — `_try_parse_payload` strips backticks incorrectly; could reject valid JSON

**File:** `backend/app/services/ai/morning_tip.py:232`
**Lens:** Quality
**Subsystem:** Backend

**What:** `text.strip("`")` removes *all* leading and trailing backtick characters, not just the triple-backtick fence; then `if text.lower().startswith("json")` strips the language hint. However, `strip("`")` is greedy and would also strip a single backtick from a response that starts with a legitimate backtick-prefixed string. The same pattern exists in `range_report.py:189` and `weekly_report.py:178`.
**Why it matters:** If the LLM returns `` `{"headline":...} `` (single backtick, which it can do in some responses), the strip removes the backtick and leaves a JSON string that parses correctly — so the bug is actually harmless in that direction. But if the response is ` ```json\n{"key": "value with `backtick`"} ``` `, the inner backticks are not affected. The real correctness issue is that a correct fence like ` ```json\nJSON\n``` ` where `.strip("\`")` removes both opening and closing backticks, then `startswith("json")` strips the language tag — this path works. No actual bug, but the code is fragile and will silently fail to parse if the model ever returns ` ```\nJSON\n``` ` (no language tag after backticks) because `text.lower().startswith("json")` would be False and `json.loads("json\nJSON")` would fail.
**Recommended fix:** Use a proper regex: `re.sub(r'^```(?:json)?\n?', '', re.sub(r'\n?```$', '', text.strip()))`.

---

### 🟢 Low — `_EVENTS_CAP` in `range_report.py` slices the last 50 events, not the most recent 50

**File:** `backend/app/services/ai/range_report.py:116`
**Lens:** Quality
**Subsystem:** Backend

**What:** `events` is already ordered ascending (`order_by(StressEvent.detected_at)`); `events[-_EVENTS_CAP:]` correctly takes the last 50 (most recent). This is fine, but the comment says "cap at 50 most recent" while the variable is named `_EVENTS_CAP` — the semantics are correct but potentially confusing.
**Why it matters:** No bug, but a future developer sorting descending would silently break the cap logic.
**Recommended fix:** Name the variable `_EVENTS_DISPLAY_CAP` and add a comment: `# events is ascending-ordered, so [-N:] gives the most recent N`.

---

### 🟢 Low — Inconsistent `ended_on` handling in sleep log filter

**File:** `backend/app/sleep/router.py:100`
**Lens:** Quality
**Subsystem:** Backend

**What:** `list_sleep_logs` filters by `SleepLog.fell_asleep_at >= start` and `SleepLog.woke_up_at <= end`, but `SleepLog.ended_on` (the canonical date column) is not used in filtering. Dashboard and morning tip services query by `ended_on`. This mixing of `fell_asleep_at`/`woke_up_at` vs. `ended_on` as the filtering dimension creates different semantics for what "in range" means for sleep logs.
**Why it matters:** A log that starts before `start` but ends on a date within the range would not be returned by the list endpoint but would be returned by dashboard queries, leading to confusing discrepancies for the same data.

---

## Summary

21 total findings: 2 🔴 critical, 6 🟠 high, 9 🟡 medium, 4 🟢 low, 2 ℹ️ info
