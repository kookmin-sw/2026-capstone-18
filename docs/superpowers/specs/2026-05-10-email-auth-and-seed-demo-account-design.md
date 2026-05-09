# Email Auth + Seed Demo Account

**Date:** 2026-05-10
**Status:** Approved, pending implementation

## Goal

Enable a demo/test account with realistic 6-month history that can be logged into via email + password, alongside the existing Google sign-in flow.

The frontend's email login/signup UI already exists, but the auth code path throws "not supported" errors. This spec adds real backend endpoints and frontend wiring, then seeds one demo account with full historical data so the app can be demoed without requiring real device usage over time.

## Scope

### In scope

- Backend: two new endpoints `POST /auth/email/signup` and `POST /auth/email/login` that wrap Supabase email/password auth.
- Frontend: replace the `throw` stubs in `AuthApi.emailLogin` / `AuthApi.emailSignUp` with real HTTP calls.
- One-shot seed script that creates a single demo user and 6 months of synthetic data.
- A simple kill-switch env var so signup can be disabled in prod.

### Out of scope

- Email verification flows (auto-confirm via Supabase admin API).
- Password reset (the existing `email_forgot_password_screen.dart` continues to be a stub).
- Multi-account seeding (only one demo user).
- Real biosignal payloads (S3 metadata rows only — no actual encrypted blobs).

## Architecture

### Auth flow (new endpoints mirror the Google pattern)

```
Frontend                    Backend                       Supabase
   │                          │                              │
   │ POST /auth/email/signup  │                              │
   │   {email, password, name}│                              │
   ├─────────────────────────>│                              │
   │                          │ admin.create_user            │
   │                          │   (email_confirm=True)       │
   │                          ├─────────────────────────────>│
   │                          │<─────────────────────────────┤
   │                          │ INSERT users(supabase_user_id│
   │                          │   display_name, ...)         │
   │                          │ (idempotent _ensure_user_row)│
   │                          │ sign_in_with_password        │
   │                          ├─────────────────────────────>│
   │                          │<─────────────────────────────┤
   │  TokenResponse           │                              │
   │<─────────────────────────┤                              │
```

`/auth/email/login` is the same minus the `admin.create_user` step.

### Components touched

| Layer | File | Change |
|---|---|---|
| Backend | `backend/app/auth/router.py` | Add `sign_in_with_email_password`, `sign_up_with_email_password` route handlers + Pydantic request bodies |
| Backend | `backend/app/auth/router.py` | Reuse existing `_ensure_user_row` helper (factor out from `sign_in_with_google` if not already shared) |
| Backend | `backend/app/config.py` | Add `email_signup_enabled: bool = True` |
| Backend | `backend/app/tests/test_auth_router.py` | Add tests for happy path + duplicate email + bad password + signup-disabled |
| Frontend | `frontend/lib/features/auth/data/auth_api.dart` | Implement `emailLogin` and `emailSignUp` HTTP calls |
| Backend | `backend/scripts/seed-demo-user.py` | New one-shot script |

## Data flow & generation rules

Time range: **2025-11-10 → 2026-05-10** (last 6 months from today).

### `trigger_categories` (6 rows)

Standard set, all owned by the demo user:
- 업무 (Work)
- 가족 (Family)
- 수면 부족 (Sleep deprivation)
- 운동 (Exercise)
- 사회적 관계 (Social relationships)
- 기타 (Other)

### `cycles` (~6 rows)

Generated with 28-day average length, ±2 day random variation. Period duration 4-6 days. Each cycle has `started_on` and `ended_on` (derived from start + period length). All `phase` calculations rely on these dates — the frontend should render expected phases automatically.

### `sleep_logs` (~180 rows, one per day)

- `slept_at`: 22:30-01:30 (skewed toward midnight)
- `woke_at`: derived (sleep duration 6-9 hours)
- `quality_score`: 60-90 with mild weekly cycle (worse Mon-Tue)
- Source: `manual` for half, `watch` for half (mix is more realistic)

### `stress_events` (~80 rows)

- 2-4 events per week, randomly distributed
- `valence` ∈ [-2, 2], `arousal` ∈ [0, 4]
- Each linked to a random `trigger_category_id` from the 6 above
- `occurred_at` clusters in evenings + work hours

### `raw_biosignal_uploads` (~180 rows)

One per day metadata row with synthetic `s3_object_key`:
- Format: `users/{user_id}/biosignals/{YYYY-MM-DD}/seed-{uuid}.bin`
- `signal_type`: rotates between `hrv`, `heart_rate`
- Marks `consent_raw_biosignals=true` on the user
- **Note:** the S3 objects don't actually exist — these are pure DB rows for completeness. The app's existing UI doesn't directly render these, so no visible breakage.

### `user_settings` (1 row)

- All defaults from spec §6.3
- `sleep_nudge_enabled=true`
- Locale `ko_KR`, timezone `Asia/Seoul`

## Error handling

### Backend endpoints

| Condition | Status | Body |
|---|---|---|
| Email already in use (signup) | 409 | `{"status":"error","reason":"email_in_use"}` |
| Invalid credentials (login) | 401 | `{"status":"error","reason":"invalid_email_credentials"}` |
| Signup disabled (env flag false) | 403 | `{"status":"error","reason":"signup_disabled"}` |
| Malformed body | 422 | FastAPI default |
| Supabase upstream error | 502 | `{"status":"error","reason":"upstream_unavailable"}` |

### Frontend mapping

`auth_api.dart` translates these reasons into Korean user-facing messages mirroring the existing Google flow patterns:

- `email_in_use` → "이미 사용 중인 이메일이에요."
- `invalid_email_credentials` → "이메일이나 비밀번호를 확인해 주세요."
- `signup_disabled` → "지금은 새 계정을 만들 수 없어요."
- network/other → "잠시 후 다시 시도해 주세요."

## Security

- Auto-confirm email (`email_confirm=True`) skips the verification email — acceptable for staging/demo. **For prod**, this should change to `email_confirm=False` so users have to verify ownership.
- `email_signup_enabled` env flag (default `True` in staging, can flip to `False` in prod via Terraform variable).
- Existing FastAPI rate limiting (if any) applies. No additional rate limit added in this spec — out of scope.
- The seed user's password is in this spec doc / chat history. After demo, rotate or delete the seed user.

## Testing

### Backend (`pytest`)

- `test_email_signup_creates_user_and_returns_tokens`
- `test_email_signup_duplicate_returns_409`
- `test_email_signup_disabled_returns_403`
- `test_email_login_success`
- `test_email_login_bad_password_returns_401`

Mock Supabase admin client the same way `test_auth_router.py` already mocks the Google flow.

### Frontend

Add a unit test in `frontend/test/` for `AuthApi.emailLogin` and `emailSignUp` happy paths against a mocked `ApiClient`. Existing test pattern for `googleLogin` (already in `app_regression_smoke_test.dart`) is the template.

### Manual verification

1. Run seed script → confirm Supabase Console shows the user, RDS shows ~180 sleep_logs etc.
2. On Z Flip 5: open app → tap "이미 계정이 있으신가요?" → enter `anu.bn@yahoo.com` / `Password123!` → app navigates to home.
3. Verify cycles screen shows 6 months of cycles, sleep tab shows daily logs, stress events show on home.

## Rollout

Incremental, no migration needed (no schema changes — `email_signup_enabled` is just a config field):

1. Land backend endpoints + tests, deploy to staging via existing CI.
2. Land frontend wiring, build APK locally for verification.
3. Run seed script against staging RDS.
4. Manually test on phone.
5. Document credentials in team's secure notes (1Password / Notion private).

If anything breaks in production after this lands (unlikely — endpoints are net-new), the kill switch is `EMAIL_SIGNUP_ENABLED=false` set via Terraform var → ECS task restart.

## Open decisions deferred to implementation plan

- Exact Pydantic model location (probably `backend/app/auth/schemas.py` if it exists, otherwise inline in router).
- Whether to factor out `_ensure_user_row` from `sign_in_with_google` — depends on what's already shared.
- Random seed deterministic vs. time-based — script will use a fixed seed (e.g., `42`) so reseeding produces identical data.
