# Sprint 3 Supabase + Google OAuth Runbook

This runbook walks through the one-time external setup Sprint 3 depends on. Steps 1-3 happen outside the codebase (Supabase + Google + AWS dashboards). The remaining sprint code assumes everything here is in place.

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
2. **Anonymous Sign-Ins**: **enable**. (`Authentication → Providers → Email → Allow anonymous sign-ins`.) The backend uses native anonymous sign-in.
3. **Google**:
   - Enable.
   - `Client ID for OAuth` and `Client Secret` come from step 3 below.
   - Authorized client IDs (skip OS-specific lists for now; Android client comes in a later sprint).

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

Plan should show: one new `aws_secretsmanager_secret`, IAM policy diff, ECS task definition diff. Apply.

## 6. Run the Sprint 3 Migration Against Staging RDS

```bash
cd backend
AWS_PROFILE=little-signals-staging ./scripts/run-staging-migration.sh
```

Expected: migration applies, exit code 0. Confirm by inspecting the alembic_version table or the ECS task logs in CloudWatch.

## 7. Smoke-Test Auth End-to-End

```bash
# Get an anonymous JWT.
ANON_TOKEN=$(curl -fsS -X POST https://api-staging.littlesignals.app/api/v1/auth/anon | jq -r '.access_token')

# Hit /me with it.
curl -fsS -H "Authorization: Bearer $ANON_TOKEN" https://api-staging.littlesignals.app/api/v1/me
```

Expected: the second curl returns `{"id":"...","supabase_user_id":"...","anon_id":"...",...}`.
