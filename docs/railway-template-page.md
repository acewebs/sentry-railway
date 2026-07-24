# Self-Hosted Sentry on Railway — template guide

Everything you need to deploy and run this template. It deploys **your own Sentry**
for error tracking as a grouped, private-network Railway project.

> **Community / unofficial template — not affiliated with or endorsed by Sentry.**
> Sentry is under the Functional Source License; self-hosting for your own use is
> permitted. Do not resell it as a hosted service. See
> [FSL.md](FSL.md).

---

## Marketplace listing (for publishing)

- **Name:** Self-Hosted Sentry — Error Tracking (Lean)
- **Description:** Run your own Sentry for error tracking on Railway — private
  network, ~13 services, Postgres-backed (no object storage required). The lean,
  budget-friendly build; a full/APM variant is separate. Community template, not
  affiliated with Sentry.
- **Tags:** sentry, error-tracking, monitoring, observability, self-hosted, apm
- **Icon:** Sentry glyph (community use; label unofficial).

---

## What you get

Classic Sentry **error tracking**: exception capture, issue grouping, search,
and alerting — the product most people mean by "Sentry." This is the **lean /
errors-only** build. It does **not** include performance/tracing, profiling,
session replay, uptime/cron monitors, feedback, or native symbolication (a
separate "Full / APM" template covers those). See
[ARCHITECTURE.md](ARCHITECTURE.md#errors-only-vs-full).

**~13 services**, all private except the public `nginx`: postgres, redis,
memcached, kafka, clickhouse, snuba-api, snuba-errors, web, sentry-workers
(honcho-grouped: ingest + post-process + taskworker + scheduler), taskbroker,
relay, nginx. Full roles: [ARCHITECTURE.md](ARCHITECTURE.md).

## Before you deploy

- **Budget / resources.** Sentry is heavy: ClickHouse, Kafka, Postgres, and several
  worker processes. Expect a **meaningful monthly bill** and budget ClickHouse +
  Kafka + the Sentry group the most RAM. This lean build avoids object storage
  (event bodies live in Postgres) to keep it smaller, but it is not "cheap."
- **No third-party accounts required** for the lean build (unlike the full build,
  which wants object storage). You will generate two secrets (below).
- **Volumes** are attached to postgres, clickhouse, kafka, and taskbroker.

## Required inputs (secrets — generate per deployment)

1. **`system.secret-key`** — Sentry's Django secret. Generate:
   `sentry config generate-secret-key`. Set it (env `SENTRY_SYSTEM_SECRET_KEY` or in
   `sentry/config.yml`). The repo ships a placeholder.
2. **Relay credentials** — generate `relay/credentials.json`
   (`relay credentials generate`), then copy its `public_key` into
   `SENTRY_RELAY_WHITELIST_PK` in `sentry/sentry.conf.py` so the internal relay is
   trusted. Why: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) (relay 403 note).
3. **Admin user** — email + password you'll create during bootstrap.

## Deploy + bootstrap (the important part)

Railway spins up the **services**, but Sentry needs a **one-time bootstrap** that
does not happen automatically. Order:

1. **Deploy the data plane first** (postgres, redis, memcached, clickhouse, kafka)
   and let them go healthy.
2. **Migrate schemas:**
   - `sentry upgrade --noinput` (Postgres + creates the internal project)
   - `snuba migrations migrate --force` (ClickHouse)
3. **Create Kafka topics** (consumers do NOT auto-create them):
   - `snuba bootstrap --force --no-migrate`
   - run [`../railway/create-topics.sh`](../railway/create-topics.sh)
4. **Create your admin user:** `sentry createuser --superuser`.
5. **Bring up** snuba-errors, web, sentry-workers, taskbroker, relay, nginx.
6. **Attach the public domain** to `nginx` (port 80).

Exact commands, the `railway ssh` patterns, and every gotcha:
[TROUBLESHOOTING.md](TROUBLESHOOTING.md). Deploy order + wiring:
[RAILWAY.md](RAILWAY.md).

> A one-shot bootstrap job that runs steps 2–4 for you is on the roadmap so this
> becomes truly one-click.

## First login + first event

- Open the `nginx` domain → sign in with your admin user.
- Send a test event to `https://<your-app>.up.railway.app/api/<project-id>/store/`
  with `X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<dsn-public-key>`; it
  should appear as an issue. (Verified end-to-end: event → relay → Kafka → ingest →
  save_event → Snuba → ClickHouse.)

## Limits (lean build)

Errors only. No performance/tracing, profiling, replays, uptime, feedback, or
native symbolication — those need more services and **object storage**, and ship in
the separate **Full / APM** template. Difference table:
[ARCHITECTURE.md](ARCHITECTURE.md#errors-only-vs-full).

## Troubleshooting

Almost every first-deploy issue is covered in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md): Postgres `lost+found`, Kafka
permission/topic crashes, relay 403 (public-key whitelist), the nodestore/object-
storage trap, nginx stale upstream IPs, and the `railway ssh` quirks.

## Referral

Railway pays template publishers ~30% of the usage of deployments made from the
template. Publish under the account that should receive it. Sentry is heavy, so
per-deployment usage — and the kickback — is meaningful.

## How to publish (maintainers)

Build a working project from `andrei-aceweb/sentry-railway` @ `railway-template`
(each build service → its `RAILWAY_DOCKERFILE_PATH`; image services → pinned
images; volumes attached), run the bootstrap, then Railway dashboard → **publish as
a template**. Mark the required variables; set name/description/icon above. Group
the services (Data / Sentry / Snuba / Support) in the project so the template shows
grouped. Internal roadmap: `dev/docs/PUBLISH-PLAN.md`.
