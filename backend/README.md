# Backend

Supabase project (Postgres + PostGIS, Auth, Storage, Edge Functions). See `docs/CONCEPT.md` §11.

- [`supabase/`](supabase): database migrations, access rules and Edge Functions.
- [`refdata-pipeline/`](refdata-pipeline/README.md): builds the on-device reference database.
- [`api-tests/`](api-tests): checks real API responses against `contracts/openapi.yaml`.

## Local development

Requires Docker, Node.js and the [Supabase CLI](https://supabase.com/docs/guides/local-development). Nothing here touches a hosted project.

```bash
supabase start --workdir backend
```

After changing a migration, rebuild the database and run both test suites:

```bash
supabase db reset --workdir backend
supabase test db --workdir backend
cd backend/api-tests && npm ci && npm test
```

Stop the stack when you're done:

```bash
supabase stop --workdir backend
```

## Access rules

[`20261104100100_access.sql`](supabase/migrations/20261104100100_access.sql) denies everything by default, then grants specific columns and rows. New tables get no client access, and every new function in `public` must revoke `PUBLIC` execute, or the database tests fail.

Implemented endpoints: `/v1/checkins` (upload only), `/v1/config`, `/v1/devices`, `/v1/me/entitlements` and `/v1/refdata/manifest`.

## Before going live

- Set up custom SMTP. Supabase's built-in email only delivers to project team members, so nobody else can sign up without it.
- Add the Apple and Google credentials and enable both providers in [`config.toml`](supabase/config.toml). Only email sign-in is enabled for now.
- Add `https://wingspot.site/auth/callback` to the allowed redirect URLs once the domain is registered and serves Universal Links.
- Move the Edge Functions off the legacy anon key before the end of 2026.

Email confirmation is on in the hosted project and off for local development. Never run `supabase config push`: it would copy local auth settings to the hosted project.
