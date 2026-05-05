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

## ADR-4: JWT verification uses JWKS-based ES256/RS256

**Decision:** Use `python-jose` with the project's JWKS endpoint (`<supabase_url>/auth/v1/.well-known/jwks.json`). The verifier matches the token's `kid` header against the JWK set, retries the fetch once if the key isn't found (cache-rotation safety), and decodes with the algorithm declared by the JWK (`ES256` or `RS256`).

**Why:** Sprint 3 originally planned HS256 + the project JWT secret on the assumption that Supabase issued HS256 by default. In practice, Supabase projects now sign with asymmetric keys (ES256 in particular) and the legacy "JWT secret" exposed in the dashboard is no longer what tokens are signed with. JWKS-based verification matches what Supabase actually issues, supports key rotation without code changes, and follows the same pattern already used by `app.auth.google` for Google ID tokens.

**Trade-offs:** Adds a network round trip on the first JWT verification per process (subsequent verifications hit the in-memory cache). Test fixtures generate an ES256 keypair at module load and prime the verifier's `_jwks_cache` directly, so unit tests don't hit the network.

## ADR-5: 30-day account-deletion grace is enforced lazily

**Decision:** `DELETE /account` sets `users.deleted_at`. `get_current_user` rejects deleted users with 403. `POST /account/restore` clears the flag if `now - deleted_at < 30 days`, otherwise returns 410.

**Why:** Avoids needing a cron job in Sprint 3. The hard-delete cron is a future sprint that walks the table and deletes rows where `deleted_at < now - 30 days`.

## ADR-6: Apple Sign-In is deferred

Out of scope this sprint. The runbook stub references Apple under "Configure Supabase Auth" so a future sprint can flip the provider on without rediscovering the path.
