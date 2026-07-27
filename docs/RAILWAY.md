# Deploying Sentry on Railway

How this self-hosted Sentry packaging maps onto Railway: the service grouping, the
private-network wiring, the config-baking that replaces Compose bind mounts, the
volumes, and the environment. It also states plainly what is verified and what is
not.

> **Status of this document.** This mapping has been **deployed and verified
> end-to-end on Railway** — a public event ingests all the way through to ClickHouse.
> See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the fixes it took. Treat the
> per-service table as the build spec, not a "it's live" claim.

## Why this isn't 65 Railway services

Upstream Compose defines ~65 services, but they are not 65 different programs.
Grouped by image:

| Image | # of compose services | What they are |
|---|---:|---|
| `ghcr.io/getsentry/snuba` | **27** | 1 Snuba API + 26 Kafka consumers / subscription consumers / replacer |
| `ghcr.io/getsentry/sentry` (built as `sentry-self-hosted-local`) | **21** | `web` + 20 workers / ingest consumers / post-process-forwarders / taskworker |
| distinct backing + support images | ~17 | Postgres, pgbouncer, Redis, ClickHouse, Kafka, memcached, SMTP, SeaweedFS, Relay, Symbolicator, Vroom, taskbroker, uptime-checker, launchpad, nginx, cleanup |

Almost all of the 48 Sentry/Snuba services are the **same image with a different
`command:`**. Every Kafka consumer is a long-running process, but for a **low-volume
self-hosted install** they do not each need their own Railway service. The template
therefore **groups** them. That is exactly the "separate services + grouping" the
bounty asks for, without a 65-service bill.

## Target Railway architecture (grouped)

One **public** service (nginx), everything else on the **private network**.
Railway gives every service a `<name>.railway.internal` DNS name; Sentry's config
already talks to peers by hostname (`clickhouse`, `kafka:9092`, `redis`,
`http://snuba-api:1218`, `http://vroom:8085`), so **name the Railway services to
match those hostnames** and the internal wiring resolves with minimal changes.

### Data plane (stateful — needs Railway Volumes)

| Railway service | Image | Volume | Notes |
|---|---|---|---|
| `postgres` | `postgres:14.23-bookworm` | `/var/lib/postgresql/data` | Primary DB. Railway's managed Postgres also works; upstream expects PG 14 + the pgbouncer hop. |
| `pgbouncer` | `edoburu/pgbouncer:v1.25.2` | — | Pooler in front of Postgres (upstream default). Can be skipped if you point Sentry straight at Postgres and adjust `sentry.conf.py`. |
| `redis` | `redis:6.2.20-alpine` | `/data` (optional) | Cache + queues + buffers. |
| `clickhouse` | built from [`../clickhouse`](../clickhouse) (`clickhouse-self-hosted-local`) | `/var/lib/clickhouse` | Event/analytics store. Requires SSE4.2 CPU. Build context is this repo's `clickhouse/` dir. |
| `kafka` | `confluentinc/cp-kafka:7.6.6` | `/var/lib/kafka/data` | Event bus. Single-node KRaft; set a stable broker id/advertised listener to the internal DNS name. |
| `memcached` | `memcached:1.6.45-alpine` | — | Stateless cache. |

### Storage & mail

| Railway service | Image | Volume | Notes |
|---|---|---|---|
| `seaweedfs` | `chrislusf/seaweedfs` | `/data` | Object store for attachments/profiles/replays. **Recommended alternative: point Sentry at external S3-compatible storage** (Railway has no managed object store) and drop this service. |
| `smtp` | `registry.gitlab.com/egos-tech/smtp` | — | Outbound mail. Better: set `SENTRY_MAIL_HOST`/SMTP env to an external provider and drop this. |

### Support services

| Railway service | Image | Volume | Notes |
|---|---|---|---|
| `relay` | `ghcr.io/getsentry/relay` | — | Ingestion gateway. Needs generated credentials (see below). |
| `symbolicator` | `ghcr.io/getsentry/symbolicator` | `/data` (cache) | Native/JS symbolication. Optional for pure backend error tracking. |
| `vroom` | `ghcr.io/getsentry/vroom` | `/var/lib/sentry-profiles` | Profiling. Optional. |
| `nginx` | `nginx:1.31.3-alpine` | — | **The one public service.** Routes `/api/…/store/` to Relay and everything else to `web`. Attach the Railway domain here. |

### Snuba (image `ghcr.io/getsentry/snuba`, grouped)

| Railway service | Command role | Notes |
|---|---|---|
| `snuba-api` | `api` | HTTP query API on `:1218`. Sentry's `SNUBA` env points here. |
| `snuba-consumers` | grouped consumers | For low volume, run the essential consumers (errors, transactions, outcomes, replacer, subscriptions) in one grouped service; add more only if you enable those datasets. |

### Sentry app (image `ghcr.io/getsentry/sentry`, grouped)

| Railway service | Command | Role |
|---|---|---|
| `web` | `run web` | Django/UI/API (private; fronted by nginx). |
| `worker` | `run worker` | Celery background tasks. |
| `cron` | `run cron` | Scheduler (beat). |
| `consumers` | `run consumer …` grouped | ingest-consumer(s) + post-process-forwarder(s), grouped for low volume. |
| `taskbroker` + `taskworker` | `taskbroker` image + `run taskworker` | New task system; keep if your nightly requires it (this build does). |

**Optional / drop for a lean install:** `launchpad-taskworker`, `uptime-checker`,
`uptime-results`, `ingest-feedback-events`, `ingest-replay-recordings`,
`snuba-replays-consumer`, `process-spans`, `process-segments`, the EAP/profiling
consumers. These belong to the `feature-complete` profile. Dropping them trims
services and RAM substantially while keeping core error + performance monitoring.

## The three real porting challenges

### 1. No host bind mounts → bake config into images

Compose bind-mounts config from the repo, e.g. `./sentry:/etc/sentry` (holds
`sentry.conf.py`, `config.yml`), plus `./clickhouse`, `./relay`, `./geoip`. **Railway
has no host bind mounts.** So the config must travel with the image:

- Build the Sentry service **from this repo** with a Dockerfile that does
  `COPY sentry/ /etc/sentry/` on top of `ghcr.io/getsentry/sentry:nightly`
  (this is essentially what upstream's `sentry/Dockerfile` +
  `sentry-self-hosted-local` already is — reuse it as the Railway build).
- Same pattern for `clickhouse/` (upstream already builds `clickhouse-self-hosted-local`).
- Provide the small per-service configs (relay, nginx) the same way.

`railway/` in this repo holds the Railway-specific Dockerfiles / configs that wrap
the upstream ones so each grouped service builds with its config baked in.

### 2. Private networking → name services to match hostnames

Sentry's config addresses peers by bare hostname. On Railway, set each service's
name (or a service alias) to the expected hostname so
`clickhouse.railway.internal`, `kafka.railway.internal`, `redis.railway.internal`,
`snuba-api.railway.internal` resolve. Where a name can't match exactly, override the
corresponding env (`CLICKHOUSE_HOST`, `SNUBA`, `VROOM`, broker list) to the Railway
internal DNS name. Bind services to `0.0.0.0`/`::` as Railway expects; only nginx is
exposed publicly.

### 3. One-time secrets → generate then store as Railway variables

Upstream generates these on install; on Railway generate once and paste into
service variables (shared where needed):

- **`SENTRY_SYSTEM_SECRET_KEY`** (and the `system.secret-key` in `config.yml`) —
  Django secret. Generate: `docker compose run --rm web config generate-secret-key`.
- **Relay credentials** — upstream's `install/ensure-relay-credentials.sh` produces
  `relay/credentials.json`. Generate once, then bake/provide to the `relay` service.
- Admin user — set `SENTRY_ADMIN_EMAIL` + `SENTRY_ADMIN_PASSWORD` and the `web`
  pre-deploy bootstrap creates the superuser (idempotent, `--force-update`); or
  leave them unset and create the first admin on the web setup screen.

## Environment

See [`.env.railway.example`](../.env.railway.example) for the variables to set on
Railway (image tags, secret key, retention, mail/SMTP, storage, healthcheck
tuning). Set shared values (`SENTRY_SYSTEM_SECRET_KEY`, broker/host names) as
Railway **shared variables** so every service sees the same value.

## Deploy order

1. Create the project; add **volumes** for `postgres`, `clickhouse`, `kafka`
   (+ `redis`, `seaweedfs`, `symbolicator`, `vroom` if used).
2. Deploy the **data plane** first (postgres, pgbouncer, redis, clickhouse, kafka,
   memcached) and let healthchecks go green.
3. Deploy `snuba-api`, then `relay`, `symbolicator`, `vroom`, `smtp`.
4. Deploy the **Sentry group** (`web`, `worker`, `cron`, `consumers`, `taskbroker`,
   `taskworker`) and the **Snuba consumers** group.
5. Deploy `nginx`, attach the public domain.

The **install/migration** step (Postgres migrations + Snuba bootstrap + Kafka
topics + internal project + optional admin) runs **automatically as pre-deploy
commands** on the `web` and `snuba-api` services — see
[Bootstrap](#bootstrap-pre-deploy) below. A brand-new all-at-once deploy converges
on its own because each pre-deploy waits for its data-plane dependencies first.

## Bootstrap (pre-deploy)

Each of the two migration-owning services runs a one-time, idempotent bootstrap in
a one-off container **before it starts serving** (Railway `preDeployCommand`), which
gates the rollout:

- **`web`** → `bash /etc/sentry/bootstrap.sh` ([`railway/sentry/bootstrap.sh`](../railway/sentry/bootstrap.sh)):
  wait for Postgres/Kafka/Redis, `sentry upgrade --create-kafka-topics`, ensure the
  taskbroker/subscription-result topics ([`railway/sentry/ensure-topics.py`](../railway/sentry/ensure-topics.py)),
  optional `createuser` from `SENTRY_ADMIN_EMAIL`/`SENTRY_ADMIN_PASSWORD`.
- **`snuba-api`** → `bash /bootstrap.sh` ([`railway/snuba-api/bootstrap.sh`](../railway/snuba-api/bootstrap.sh)):
  wait for ClickHouse/Kafka, `snuba bootstrap --force` (ClickHouse migrations +
  Snuba's Kafka topics).

Wired via each service's Railway config file: [`railway/web.json`](../railway/web.json)
and [`railway/snuba-api.json`](../railway/snuba-api.json). This is why `snuba-api`
builds from [`railway/snuba-api/Dockerfile`](../railway/snuba-api/Dockerfile) (a thin
wrapper over the Snuba image) rather than the bare image — the wrapper only bakes the
bootstrap script in, since Railway has no host bind mounts.

## Resource sizing

Upstream enforces a **16 GB host minimum** for the full `feature-complete` profile.
On Railway, budget memory per service (ClickHouse, Kafka, and each Sentry/Snuba
group are the heavy ones). Dropping the optional profile services (see above) is the
main lever to fit a smaller footprint. Document the expected monthly resource cost
on the template page so deployers aren't surprised — Sentry is genuinely heavy, and
that heaviness is also why the template's usage-referral upside is meaningful.

## Verification status

- ✅ **Verified on Railway, end-to-end:** the grouped services deploy from this repo,
  the UI serves publicly, and a public event ingests all the way through to
  ClickHouse (relay → Kafka → Sentry ingest → save_event → Snuba → ClickHouse).
- The exact fixes it took (topics, relay trust, nodestore, nginx resolver, …) are in
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
