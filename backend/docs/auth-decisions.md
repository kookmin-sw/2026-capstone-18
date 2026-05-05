# Auth Decisions — Sprint 3

This file records architectural decisions made during Sprint 3 so future sprints don't relitigate them.

## ADR-1: Anonymous identity uses Supabase native anonymous sign-in

**Decision:** Backend calls Supabase's `POST /auth/v1/signup` with `{}` (anonymous sign-in must be enabled in the project) to mint anonymous Supabase JWTs. We do not self-sign anonymous JWTs.

**Why:** Single source of truth for identity. Eliminates a Supabase-specific signing key in our code, keeps the JWKS/JWT secret story uniform across anon and registered users, and means the anon→Google upgrade is a normal Supabase admin update rather than a token-format migration.

**Trade-offs:** Hard dependency on Supabase availability for anon bootstrap. Supabase free tier rate limits apply.

## ADR-2: `users.supabase_user_id` is set for both anonymous and registered users

**Decision:** Diverge from spec §6.3's comment ("NULL for anonymous users"). With Supabase native anonymous sign-in, every Supabase user has a stable `id`; we mirror that into `supabase_user_id` from creation. `anon_id` is set at creation iff the user originated as anonymous, and survives the upgrade as audit metadata.

**Why:** Avoids an artificial NULL→UUID transition during upgrade and lets `get_current_user` look up by `supabase_user_id` uniformly.

## ADR-3: Existing-Google-account collision logs into the existing account

**Decision:** When an anonymous user signs in with a Google ID token whose email/sub is already attached to a different Supabase user, abandon the anon `users` row (set `deleted_at`) and return tokens for the pre-existing account.

**Why:** Sprint 3 has no per-user data yet, so a "merge" would have nothing to merge. Logging into the existing account preserves the long-tenured user's history once stress_events lands. Revisit when the data model has rows worth merging.

## ADR-4: JWT verification uses HS256 + project JWT secret

**Decision:** Use `python-jose` HS256 with `Settings.supabase_jwt_secret`. Do not implement JWKS-based RS256 verification yet.

**Why:** Supabase issues HS256 tokens by default with the project JWT secret across all current projects. Asymmetric signing keys are an opt-in beta. HS256 keeps test mocking simple — tests just inject a known secret and re-sign tokens with it.

**Trade-offs:** When Supabase rotates the JWT secret (rare, opt-in), every running container needs the new secret in its env via the Sprint 3 `aws_secretsmanager_secret.supabase` secret update + ECS rolling deploy.

## ADR-5: 30-day account-deletion grace is enforced lazily

**Decision:** `DELETE /account` sets `users.deleted_at`. `get_current_user` rejects deleted users with 403. `POST /account/restore` clears the flag if `now - deleted_at < 30 days`, otherwise returns 410.

**Why:** Avoids needing a cron job in Sprint 3. The hard-delete cron is a future sprint that walks the table and deletes rows where `deleted_at < now - 30 days`.

## ADR-6: Apple Sign-In is deferred

Out of scope this sprint. The runbook stub references Apple under "Configure Supabase Auth" so a future sprint can flip the provider on without rediscovering the path.
