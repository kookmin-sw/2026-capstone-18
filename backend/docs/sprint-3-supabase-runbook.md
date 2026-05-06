# Sprint 3 Supabase + Google OAuth Runbook

This runbook walks through the one-time external setup Sprint 3 depends on. Steps 1-3 happen outside the codebase (Supabase + Google + AWS dashboards). The remaining sprint code assumes everything here is in place.

## Before You Start

- AWS CLI v2 installed and authenticated. The local profile `little-signals-staging` must be configured with permissions to read/write Secrets Manager and run Terraform against the staging account (set up in Sprint 2).
- `terraform` >= 1.7.0 (matches the version pinned by Sprint 2's `infra/main.tf`).
- `jq` available on PATH (used by `scripts/run-staging-migration.sh` and the smoke test).
- Sprint 2 already merged and applied — the staging RDS, ECS cluster, and Route 53 zone for `friendlykr.com` exist. The smoke test in section 7 depends on `api-staging.friendlykr.com` resolving to the Sprint 2 ALB.
- Access to the team's shared Supabase account and Google Cloud Console.

## 1. Create Supabase Project

1. Sign in at <https://supabase.com> with the project's shared account.
2. Create a new project named `little-signals-staging`.
3. Region: `ap-northeast-1` (Tokyo). Free tier.
4. Save the database password to the team password manager (we will not use this directly — Supabase manages its own DB; the staging RDS is unrelated).
5. After provisioning completes, capture the following values from `Project Settings`:
   - **Project URL** (`https://<project-ref>.supabase.co`) — `Project Settings → API → Project URL`.
   - **anon public key** — `Project Settings → API → Project API keys → anon public`.
   - **service_role secret key** — `Project Settings → API → Project API keys → service_role secret`.
   - **JWT secret** — `Project Settings → API → JWT Settings → JWT secret`.

## 2. Configure Supabase Auth

In `Authentication → Providers`:

1. **Email**: enable but do not configure SMTP for Sprint 3 (we do not use email login this sprint).
2. **Anonymous Sign-Ins**: **enable**. The toggle has moved between sub-pages over time — search the `Authentication` section for "anonymous" if it isn't where you expect (recent locations include `Authentication → Sign In / Providers`, `Authentication → Settings → User Signups`, and `Authentication → Providers → Email`). The backend uses native anonymous sign-in.
3. **Google**:
   - Enable.
   - `Client ID for OAuth` and `Client Secret` come from step 3 below.
   - Leave the **Authorized Client IDs** field blank. The Android-specific client ID will be added in a later mobile sprint.

## 3. Configure Google OAuth Client

In <https://console.cloud.google.com>:

1. Create a new project named `little-signals` (or reuse if one exists).
2. Configure the OAuth consent screen. User type: External. App name: `little-signals`. Support email: the team account. Scopes: `openid`, `email`, `profile`.
3. Create OAuth 2.0 credentials, type **Web application** (Android client comes later in the mobile sprint):
   - Authorized JavaScript origins: `https://<project-ref>.supabase.co`.
   - Authorized redirect URIs: `https://<project-ref>.supabase.co/auth/v1/callback`.
4. Capture the **Client ID** and **Client Secret**.
5. Paste both into Supabase `Authentication → Providers → Google`. Save.

## 4. Populate AWS Secrets Manager

After Sprint 3 PR is merged and `terraform apply` has created the empty `little-signals-staging/supabase` secret, populate it:

```bash
AWS_PROFILE=little-signals-staging aws secretsmanager put-secret-value \
  --secret-id little-signals-staging/supabase \
  --secret-string '{
    "url": "https://<project-ref>.supabase.co",
    "anon_key": "<anon public key>",
    "service_role_key": "<service_role secret>",
    "jwt_secret": "<JWT secret>",
    "google_oauth_client_id": "<google client id>.apps.googleusercontent.com"
  }'
```

The Google Client ID lives in the same secret JSON because the backend reads it for `aud` claim verification when directly verifying Google ID tokens.

## 5. Apply Sprint 3 Terraform Changes

```bash
cd backend/infra
AWS_PROFILE=little-signals-staging terraform plan -var-file=staging.tfvars
AWS_PROFILE=little-signals-staging terraform apply -var-file=staging.tfvars
```

Plan should show: one new `aws_secretsmanager_secret`, IAM policy diff, ECS task definition diff, and a new `supabase_secret_arn` output. Apply.

## 6. Run the Sprint 3 Migration Against Staging RDS

```bash
cd backend
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
```

Expected: migration applies, exit code 0. Confirm by inspecting the alembic_version table or the ECS task logs in CloudWatch.

## 7. Smoke-Test Auth End-to-End

```bash
# Get an anonymous JWT.
ANON_TOKEN=$(curl -fsS -X POST https://api-staging.friendlykr.com/api/v1/auth/anon | jq -r '.access_token')

# Hit /me with it.
curl -fsS -H "Authorization: Bearer $ANON_TOKEN" https://api-staging.friendlykr.com/api/v1/me
```

Expected: the second curl returns `{"id":"...","supabase_user_id":"...","anon_id":"...",...}`.
