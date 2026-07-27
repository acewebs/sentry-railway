# `railway/` — Railway-specific build wrappers

Railway has **no host bind mounts**, but upstream Compose delivers the Sentry,
ClickHouse and Relay *configuration* by bind-mounting repo dirs at runtime
(`./sentry:/etc/sentry`, `./clickhouse/...`, `./relay:/work/.relay`). So for Railway
the config has to be **baked into each image at build time**. That is what the
wrappers here do.

> **Status:** live-validated on the `sentry` Railway project (bootstrap, ingestion,
> UI, env-driven secrets). Remaining before publish: connect each service's source
> (below), then a fresh empty-volume deploy (see [../docs/RAILWAY.md](../docs/RAILWAY.md)
> and [../dev/docs/PUBLISH-PLAN.md](../dev/docs/PUBLISH-PLAN.md) T9).

## Service → source map

Each service is one of two kinds. Stock services need no repo file; the config-baking
ones build from a Dockerfile here. Every service has a `railway/<service>.json`
config-as-code file — point the service's "Railway config file" at it.

| Service | Source | Config file | Notes |
|---|---|---|---|
| postgres | image `postgres:14.23-bookworm` | — | env only (`PGDATA` subdir) |
| redis | image `redis:6.2.20-alpine` | — | default |
| memcached | image `memcached:1.6.45-alpine` | — | start arg `memcached -I 1M` |
| snuba-errors | image `ghcr.io/getsentry/snuba` | `snuba-errors.json` | stock image + start command (no Dockerfile) |
| clickhouse | `clickhouse/Dockerfile` | `clickhouse.json` | bakes Snuba's ClickHouse XML config |
| kafka | `kafka/Dockerfile` | `kafka.json` | `USER root` (Railway volume perms) |
| gateway | `nginx/Dockerfile` | `gateway.json` | nginx-based public reverse proxy; the one public service |
| sentry-relay | `relay/Dockerfile` | `sentry-relay.json` | Sentry ingestion gateway; bakes config + busybox entrypoint (creds from env) |
| sentry-web | `sentry/Dockerfile` | `sentry-web.json` | Sentry's Django app (`/etc/sentry` + bootstrap; `preDeployCommand`) |
| sentry-workers | `sentry-workers/Dockerfile` | `sentry-workers.json` | honcho-grouped consumers |
| snuba-api | `snuba-api/Dockerfile` | `snuba-api.json` | thin wrapper for the pre-deploy script; `preDeployCommand` |
| sentry-taskbroker | `taskbroker/Dockerfile` | `sentry-taskbroker.json` | Sentry task-queue broker; bakes `taskbroker/config.yml` |

Only `sentry-web` and `snuba-api` set a `preDeployCommand` (the bootstrap); the rest
are build + start config. `snuba-errors` shows the pattern for command-only services:
the stock image plus a start command, no Dockerfile.

Service names double as private DNS (`<name>.railway.internal`): `gateway` is the
public nginx proxy; `sentry-web` is the Django app (referenced by `gateway`,
`sentry-relay`, `sentry/config.yml`); `sentry-relay` is referenced by `gateway`;
`sentry-taskbroker` by `sentry-workers`; and the infra/snuba names are addressed by
peers too — rename with care (update the matching `*.railway.internal` refs).

## Contents

- `sentry/Dockerfile` — wraps `ghcr.io/getsentry/sentry`, bakes `/etc/sentry`
  config in. Shared by `sentry-web` and `sentry-workers` (same image, different start
  command). Also bakes the pre-deploy bootstrap (`sentry/bootstrap.sh`,
  `sentry/ensure-topics.py`, `lib/wait-for-tcp.py`).
- `snuba-api/Dockerfile` — thin wrapper over `ghcr.io/getsentry/snuba` that bakes the
  `snuba-api/bootstrap.sh` pre-deploy script in (Railway has no bind mounts). Start
  command stays `api`.
- `relay/{Dockerfile,entrypoint.sh}` — bakes non-secret `relay/config.yml` + a static
  busybox; the entrypoint writes `credentials.json` from `RELAY_CREDENTIALS_JSON` at
  start (no secret baked, so a fresh clone builds).
- `lib/wait-for-tcp.py` — shared helper: block until host:port endpoints accept a
  connection (IPv6-aware), so a pre-deploy doesn't migrate before the data plane is up.
- `<service>.json` — one Railway config-as-code file per service (build + start +
  any `preDeployCommand`). See the source map above.
- `create-topics.sh` — manual/debug fallback for Kafka topic creation (the automated
  path is `sentry/ensure-topics.py`; keep the two topic lists in sync).

## Why upstream's own Dockerfiles aren't enough

`../sentry/Dockerfile` copies the repo into `/usr/src/sentry` (the "enhance image"
hook for extra pip packages) — it does **not** put `sentry.conf.py` / `config.yml`
at `/etc/sentry`, because Compose bind-mounts those at runtime. On Railway there is
no runtime mount, so we add a layer that copies the config to `/etc/sentry`.

Likewise `../clickhouse/Dockerfile` is just `FROM $BASE_IMAGE`; the ClickHouse
config arrives via bind mount upstream and must be `COPY`d in for Railway.

## Contents

- `sentry/Dockerfile` — wraps `ghcr.io/getsentry/sentry`, bakes `/etc/sentry`
  config in. Used by every Sentry-image Railway service (`web`, `sentry-consumers`,
  `sentry-tasks`) — they share this image and differ only by start command, set
  per-service in Railway. Also bakes the pre-deploy bootstrap (`sentry/bootstrap.sh`,
  `sentry/ensure-topics.py`, `lib/wait-for-tcp.py`).
- `snuba-api/Dockerfile` — thin wrapper over `ghcr.io/getsentry/snuba` that bakes the
  `snuba-api/bootstrap.sh` pre-deploy script in (Railway has no bind mounts). Start
  command stays `api`.
- `lib/wait-for-tcp.py` — shared helper: block until host:port endpoints accept a
  connection (IPv6-aware), so a pre-deploy doesn't migrate before the data plane is up.
- `web.json` / `snuba-api.json` — Railway config files that pin each service's build,
  start command and `preDeployCommand` (the bootstrap). Set each service's "Railway
  config file" to point at these.
- `create-topics.sh` — manual/debug fallback for Kafka topic creation (the automated
  path is `sentry/ensure-topics.py`; keep the two topic lists in sync).

## Bootstrap (one-click)

Migrations, Kafka topics and the optional admin run automatically as pre-deploy
commands — deployers never open a shell. Details:
[../docs/RAILWAY.md § Bootstrap](../docs/RAILWAY.md#bootstrap-pre-deploy).

## Still to do before publish

- Connect each service's source in the Railway project (repo + config file for the
  Dockerfile services; image + `railway/<svc>.json` start command for the stock ones),
  so the graph is reproducible and "publish as template" captures it.
- Fresh empty-volume deploy to validate the cold path + that `preDeployCommand`
  actually runs and gates the rollout, per
  [../dev/docs/PUBLISH-PLAN.md](../dev/docs/PUBLISH-PLAN.md) T9.
- Service polish for the marketplace: per-service icons and canvas grouping
  (Data / Sentry / Snuba / Edge) — dashboard-only.
