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

**~13 services**, all private except the public `gateway`: postgres, redis,
memcached, kafka, clickhouse, snuba-api, snuba-errors, sentry-web, sentry-workers
(honcho-grouped: ingest + post-process + taskworker + scheduler), taskbroker,
relay, gateway (nginx). Full roles: [ARCHITECTURE.md](ARCHITECTURE.md).

## Before you deploy

- **Budget / resources.** Sentry is heavy: ClickHouse, Kafka, Postgres, and several
  worker processes. Expect a **meaningful monthly bill** and budget ClickHouse +
  Kafka + the Sentry group the most RAM. This lean build avoids object storage
  (event bodies live in Postgres) to keep it smaller, but it is not "cheap."
- **No third-party accounts required** for the lean build (unlike the full build,
  which wants object storage). You provide a few per-deploy variables (below) — all
  Railway variables, no repo files to edit.
- **Volumes** are attached to postgres, clickhouse, kafka, and taskbroker.

## Required inputs (Railway variables — no file editing)

All per-deploy secrets are **Railway variables**; you never edit repo files. See
[`.env.railway.example`](../.env.railway.example) for the full list.

1. **`SENTRY_SYSTEM_SECRET_KEY`** (web) — Django secret. Make it a generated
   variable: `${{ secret(50) }}`.
2. **`SENTRY_URL_PREFIX`** (web) — the public https URL, needed for links and (since
   Django 4) for browser login to pass CSRF. Point it at nginx's domain:
   `https://${{gateway.RAILWAY_PUBLIC_DOMAIN}}`.
3. **Relay credentials** — generate one keypair
   (`docker run --rm ghcr.io/getsentry/relay:nightly credentials generate --stdout`),
   then set the whole JSON as **`RELAY_CREDENTIALS_JSON`** (relay) and its
   `public_key` as **`SENTRY_RELAY_WHITELIST_PK`** (sentry-web) so it trusts the relay.
   Why: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) (relay 403 note).
4. **Admin user (optional)** — set `SENTRY_ADMIN_EMAIL` + `SENTRY_ADMIN_PASSWORD`
   and the bootstrap creates the superuser for you; leave them unset to create the
   first admin on the web setup screen instead.

## Deploy + bootstrap (automated)

Sentry needs a one-time schema/topic bootstrap that Railway does not do on its own.
This template runs it **automatically** as **pre-deploy commands** — no shell steps:

- The **`sentry-web`** service runs [`railway/sentry/bootstrap.sh`](../railway/sentry/bootstrap.sh)
  before it starts: waits for the data plane, then `sentry upgrade --create-kafka-topics`
  (Postgres migrations + internal project + Sentry's Kafka topics), ensures the
  taskbroker / subscription-result topics, and (if you set `SENTRY_ADMIN_EMAIL` +
  `SENTRY_ADMIN_PASSWORD`) creates the admin superuser.
- The **`snuba-api`** service runs [`railway/snuba-api/bootstrap.sh`](../railway/snuba-api/bootstrap.sh)
  before it starts: waits for ClickHouse + Kafka, then `snuba bootstrap --force`
  (ClickHouse migrations + Snuba's Kafka topics).

Both are idempotent (they re-run safely on every deploy) and **gate the rollout** —
the service only goes live once its bootstrap succeeds, and Railway retries a failed
pre-deploy. The wait step means a fresh, all-at-once deploy converges without manual
ordering. Wiring is [`railway/web.json`](../railway/web.json) and
[`railway/snuba-api.json`](../railway/snuba-api.json) (each service's Railway config
file points at these). All you do is:

1. Deploy the template (data plane volumes are pre-attached).
2. **Attach the public domain** to `gateway` (port 80).
3. Open it and sign in — with the admin you set via env, or create the first admin on
   the setup screen if you left those unset.

[`railway/create-topics.sh`](../railway/create-topics.sh) remains as a manual
fallback for debugging topic issues. Exact commands and every gotcha:
[TROUBLESHOOTING.md](TROUBLESHOOTING.md). Deploy order + wiring: [RAILWAY.md](RAILWAY.md).

## First login + first event

- Open the `gateway` domain → sign in with your admin user.
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
