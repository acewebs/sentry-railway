# Troubleshooting self-hosted Sentry on Railway

Sentry self-hosting is finicky, and Railway adds a few platform-specific twists
(IPv6 private network, no host bind mounts, per-redeploy IPs). This is the concise
"symptom → cause → fix" reference; the wiring/architecture is in
[ARCHITECTURE.md](ARCHITECTURE.md) and [RAILWAY.md](RAILWAY.md).

## Data plane

**Postgres won't init — `directory "…/data" exists but is not empty … lost+found`.**
Railway volumes contain a `lost+found`, and Postgres refuses to init into a
non-empty dir. → Set `PGDATA=/var/lib/postgresql/data/pgdata` (a subdirectory of
the mount).

**Kafka — `/var/lib/kafka/data is writable … FAILED`.** `cp-kafka` runs as a
non-root user but Railway mounts the volume as root. → Build Kafka from a thin
wrapper that runs as root (`FROM confluentinc/cp-kafka … USER root`), as this
template does (`railway/kafka/Dockerfile`).

**Kafka — `Error starting LogManager`.** Again the volume's `lost+found`. → Point
logs at a subdir: `KAFKA_LOG_DIRS=/var/lib/kafka/data/logs`.

**Kafka clients can't reach the broker.** Advertise the internal DNS name, not
`localhost`: `KAFKA_ADVERTISED_LISTENERS=…kafka.railway.internal:9092/9093`.

**ClickHouse — `CANNOT_PARSE_NUMBER … max_server_memory_usage_to_ram_ratio`.** The
config reads it from an env var that isn't set. → Set `MAX_MEMORY_USAGE_RATIO=0.3`.
(The `Address already in use 0.0.0.0:*` lines are **warnings** — ClickHouse binds
`::` first, which is what Railway's private net uses; harmless.)

## Private networking (IPv6)

Railway's private network is IPv6, DNS is `<service>.railway.internal`, and each
redeploy can change a service's private IP.

- **Every Sentry command crashes: `ValueError: '()' does not appear to be an IPv4 or
  IPv6 network`.** `sentry.conf.py` computes `INTERNAL_SYSTEM_IPS` from an `eth0`
  IPv4 lookup that fails on Railway → returns `()`. → Guard it:
  `INTERNAL_SYSTEM_IPS = (net,) if net else ("fd00::/8",)`.
- **A service can't be reached by another over the private net.** Bind to `::`
  (dual-stack), not `0.0.0.0` — e.g. `SENTRY_WEB_HOST = "::"`, relay `host: "::"`.
- **Peer hostnames.** The baked config points at `*.railway.internal`
  (postgres/redis/memcached/kafka/clickhouse/snuba-api/web). Name services to match.

## Kafka topics (the #1 gotcha)

**Consumers crash with `UnknownTopicOrPartition … Subscribed topic not available`.**
librdkafka *consumers* default `allow.auto.create.topics=false`, so a consumer
subscribing to a missing topic **crashes** — even with the broker's
`KAFKA_AUTO_CREATE_TOPICS_ENABLE=true`. Topics must be created explicitly:
- `snuba bootstrap --force --no-migrate` (snuba's topics: `events`, `outcomes`, …)
- run [`../railway/create-topics.sh`](../railway/create-topics.sh) (Sentry ingest +
  taskbroker topics).

**taskbroker shows state "Completed" and taskworker can't reach `:50051`.**
taskbroker **exits** on the first missing Kafka topic (and Railway won't auto-restart
a Completed service), so the task system dies and event processing stalls. → Create
all taskbroker topics (`create-topics.sh` covers them), then `railway up -s taskbroker`.

## Relay

**Relay logs `failed to fetch global config … 403 Forbidden`; web logs
`Forbidden: /api/0/relays/projectconfigs/`.** The relay isn't treated as "internal."
On Railway its source IP isn't in Sentry's internal-network set, so the IP-based
trust path fails. → **Whitelist the relay's public key**:
`SENTRY_RELAY_WHITELIST_PK = ["<relay public_key>"]` in `sentry.conf.py` (must match
`relay/credentials.json`). Then **restart relay** — it backs off after repeated
403s and only re-authenticates on a fresh start.

**Relay crashloops: `could not parse yaml config file … ${RELAY_STATSD_ADDR}`.** The
stock `relay/config.yml` has an active `metrics:` block referencing an unset env. →
Comment out the `metrics:` block (no statsd server in this build).

**Relay crashloops: `could not load the Geoip Db … /geoip/GeoLite2-City.mmdb`.** No
GeoIP DB is baked. → Comment out `geoip_path` in `relay/config.yml` (it's fatal for
relay; for web/workers the same missing DB is only a warning).

## Ingestion (events accepted but never appear)

**`POST /api/N/store/` returns 200, but nothing reaches ClickHouse.** The event is
accepted by relay but silently dropped during `save_event`. The usual cause is the
**nodestore**: upstream defaults to S3/SeaweedFS, and if that store isn't present,
`save_event` fails with `Could not connect to endpoint http://seaweedfs:8333/…` and
never produces to the `events` topic. → This lean build uses the **Postgres
nodestore** (`SENTRY_NODESTORE = "sentry.nodestore.django.backend.DjangoNodeStorage"`,
`SENTRY_NODESTORE_OPTIONS = {}`) — no object storage needed. To confirm the failure,
replay it: `EventManager({...}).save(project_id)` in `sentry django shell` prints the
real exception.

## nginx (the public edge)

**`POST /api/*/store/` hangs, nginx logs 499.** nginx resolves upstream hostnames
once at startup, so after relay/web get new private IPs (any redeploy) it routes to
a stale IP. → This template uses a `resolver` + variable `proxy_pass`
(`railway/nginx/Dockerfile` / `nginx.conf`) so nginx re-resolves per request. If you
hit this on an older config, redeploy nginx.

**nginx dies at boot: `host not found in upstream`.** Same root cause — static
`upstream` blocks resolve at startup and fail if relay/web aren't up yet. The
resolver + variable approach avoids it.

## Running one-off commands (migrations, topics, shell)

Railway's private network isn't reachable from your laptop, and `railway run` only
injects env locally — so migrations/bootstrap must run **inside** a service.

- **`railway ssh -s <svc> <cmd>` swallows stdout or splits quoted args.** Use a
  native OpenSSH alias instead:
  `railway ssh config -s <svc> --alias rw-<svc> -i <your-key>`, then
  `ssh rw-<svc> "<cmd>"`. Pipe queries over stdin:
  `echo "SELECT count() FROM errors_local" | ssh rw-clickhouse clickhouse-client`.
- **Make sure your SSH key is registered to the *right* Railway account**
  (`railway ssh keys add`) — a key registered to a different account authenticates
  as that account and can't see this project.

## Redeploys

**A build service reverts to the base image after `railway redeploy`.** `redeploy`
can drop a service off its Dockerfile build. → Use `railway up -s <svc>` to redeploy
build (Dockerfile) services.
