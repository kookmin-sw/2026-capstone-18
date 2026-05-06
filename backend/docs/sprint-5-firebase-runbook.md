# Sprint 5 Firebase + FCM Runbook

This runbook is the one-time external setup Sprint 5 depends on. Steps 1–3 happen
outside the codebase (Firebase + AWS dashboards). The Sprint 5 application code
assumes everything here is in place.

## 1. Create the Firebase project

1. Sign in at <https://console.firebase.google.com> with the project's shared
   Google account.
2. Click **Add project**. Project name: `little-signals` (or `little-signals-prod`
   when prod is created later). Disable Google Analytics for this project — no
   analytics on a privacy-first product.
3. Once the project is created, go to **Project settings → General** and confirm
   the project ID; copy it into `backend/docs/sprint-5-deploy-runbook.md` later.

## 2. Add the Android app

1. In the Firebase console, **Add app → Android**.
2. Package name: `com.littlesignals.phone` (must match the Flutter app's
   `applicationId`).
3. App nickname: `little-signals-phone`.
4. SHA-1 (debug): obtain from the Flutter team (or skip — only required for
   Google Sign-In which we route through Supabase, not Firebase).
5. Download `google-services.json`. Hand it to the Flutter team — it is a phone
   side artifact, not a backend one.

## 3. Generate the service account credentials

The backend uses a **service account** (not the Android API key) to send
messages via Firebase Admin SDK.

1. In the Firebase console, go to **Project settings → Service accounts**.
2. Click **Generate new private key**. Download the JSON.
3. Open the JSON and confirm it contains `"type": "service_account"`,
   `"project_id"`, `"private_key"`, `"client_email"`. **Do not edit the file.**

## 4. Populate AWS Secrets Manager

The Sprint 5 Terraform creates an empty secret named `firebase`. Populate it
with the JSON from the previous step.

```bash
AWS_PROFILE=little-signals-staging aws secretsmanager put-secret-value \
  --region ap-northeast-2 \
  --secret-id "$(terraform -chdir=backend/infra output -raw firebase_secret_arn)" \
  --secret-string file://path/to/service-account.json
```

After this, **shred the local file**:

```bash
shred -u path/to/service-account.json   # or `srm` on macOS
```

The local copy must not survive on the operator's laptop — the secret lives in
Secrets Manager from now on.

## 5. Verify the secret is readable

```bash
AWS_PROFILE=little-signals-staging aws secretsmanager get-secret-value \
  --region ap-northeast-2 \
  --secret-id "$(terraform -chdir=backend/infra output -raw firebase_secret_arn)" \
  --query 'SecretString' --output text | jq -r .project_id
```

Expected: prints the Firebase project ID. Anything else means the secret is
malformed; re-run step 4 with a fresh JSON.

## 6. Add the Android app's FCM token endpoint to the integration build

This step is for the Flutter team. The phone app registers its FCM token with
the backend at `POST /api/v1/devices/fcm-token` after sign-in. The contract is
documented in `backend/app/schemas/devices.py` and exposed in the OpenAPI doc
at `/docs`.
