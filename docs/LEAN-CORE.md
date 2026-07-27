# Lean-core deploy blueprint

The service set for the **lean-core** Railway template: error tracking + basic
performance, with the `feature-complete` profile services dropped (profiling/Vroom,
replays, uptime, feedback, spans, EAP, launchpad, generic-metrics beyond basic).
This is the cheapest footprint that still satisfies the bounty.

All start commands below are the **exact** upstream commands, pulled from the
locally-verified compose.

## Grouping strategy

A Railway service runs **one** start command = one process. Sentry has many small
consumer processes. To keep the service count (and cost) down, the consumers are
**grouped** behind a process manager (`honcho`, already present in the Sentry
image) driven by a Procfile — one Railway service runs several consumer commands.
Stateful stores and the web tier stay as their own services.

Result: ~11 Railway services instead of 40+.

## Services

### Data plane (stateful — attach a Railway Volume)

| Service | Image / build | Volume | Start cmd |
|---|---|---|---|
| `postgres` | `postgres:14.23-bookworm` | `/var/lib/postgresql/data` | default |
| `pgbouncer` | `edoburu/pgbouncer:v1.25.2-p0` | — | default |
| `redis` | `redis:6.2.20-alpine` | `/data` (optional) | default |
| `clickhouse` | build `railway/clickhouse/Dockerfile` | `/var/lib/clickhouse` | default (needs SSE4.2 CPU) |
| `kafka` | `confluentinc/cp-kafka:7.6.6` | `/var/lib/kafka/data` | single-node KRaft |
| `memcached` | `memcached:1.6.45-alpine` | — | `-I 1M` |

### App + support

| Service | Image / build | Public? | Start cmd |
|---|---|---|---|
| `gateway` | build `railway/nginx/Dockerfile` | **public** | nginx-based; routes ingest→relay, rest→sentry-web |
| `relay` | build `railway/relay/Dockerfile` | private | default |
| `sentry-web` | build `railway/sentry/Dockerfile` | private | `run web` |
| `snuba-api` | `ghcr.io/getsentry/snuba:nightly` | private | default (API on :1218) |
| `taskbroker` | `ghcr.io/getsentry/taskbroker:nightly` | private | `/opt/taskbroker -c /etc/taskbroker/config.yml` |

### Grouped process-manager services (Sentry image = `railway/sentry/Dockerfile`)

**`sentry-tasks`** (taskworker + scheduler):
```
run taskworker --concurrency=4 --rpc-host=taskbroker:50051 --health-check-file-path=/tmp/health.txt --max-child-task-count=10000
run taskworker-scheduler
```

**`sentry-consumers`** (ingest + post-process), Procfile lines:
```
run consumer ingest-events        --consumer-group ingest-consumer --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer ingest-transactions  --consumer-group ingest-consumer --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer ingest-attachments   --consumer-group ingest-consumer --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer ingest-occurrences   --consumer-group ingest-occurrences --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer ingest-monitors      --consumer-group ingest-monitors --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer ingest-metrics       --consumer-group metrics-consumer --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer billing-metrics-consumer --consumer-group billing-metrics-consumer --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer --no-strict-offset-reset post-process-forwarder-errors --consumer-group post-process-forwarder --synchronize-commit-log-topic=snuba-commit-log --synchronize-commit-group=snuba-consumers --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
run consumer --no-strict-offset-reset post-process-forwarder-transactions --consumer-group post-process-forwarder --synchronize-commit-log-topic=snuba-transactions-commit-log --synchronize-commit-group transactions_group --max-poll-interval-ms 300000 --healthcheck-file-path /tmp/health.txt
```

### Grouped Snuba consumers (Snuba image = `ghcr.io/getsentry/snuba:nightly`)

**`snuba-consumers`**, Procfile lines:
```
rust-consumer --storage errors       --consumer-group snuba-consumers --auto-offset-reset=latest   --max-batch-time-ms 750 --no-strict-offset-reset --health-check-file /tmp/health.txt --max-poll-interval-ms 300000
rust-consumer --storage transactions --consumer-group transactions_group --auto-offset-reset=latest --max-batch-time-ms 750 --no-strict-offset-reset --health-check-file /tmp/health.txt --max-poll-interval-ms 300000
rust-consumer --storage outcomes_raw --consumer-group snuba-consumers --auto-offset-reset=earliest --max-batch-time-ms 750 --no-strict-offset-reset --health-check-file /tmp/health.txt --max-poll-interval-ms 300000
replacer --storage errors --auto-offset-reset=latest --no-strict-offset-reset --health-check-file /tmp/health.txt --max-poll-interval-ms 300000
subscriptions-scheduler-executor --dataset events       --entity events       --auto-offset-reset=latest --no-strict-offset-reset --consumer-group=snuba-events-subscriptions-consumers       --followed-consumer-group=snuba-consumers    --schedule-ttl=60 --stale-threshold-seconds=900 --health-check-file /tmp/health.txt
subscriptions-scheduler-executor --dataset transactions --entity transactions --auto-offset-reset=latest --no-strict-offset-reset --consumer-group=snuba-transactions-subscriptions-consumers --followed-consumer-group=transactions_group --schedule-ttl=60 --stale-threshold-seconds=900 --health-check-file /tmp/health.txt
```

## Dropped for lean (add back for a feature-complete variant)

Vroom (profiling) + its consumers, symbolicator (native symbolication),
uptime-checker/uptime-results, ingest-feedback-events, ingest-replay-recordings +
snuba-replays-consumer, process-spans/process-segments, EAP consumers, launchpad,
seaweedfs (use external S3), smtp (use external SMTP), generic-metrics gauges/sets/
counters/distributions consumers, profiling consumers.

## Private-network naming

Name the services (or aliases) so these hostnames resolve on Railway's private
network: `postgres`/`pgbouncer`, `redis`, `clickhouse`, `kafka`, `memcached`,
`relay`, `sentry-web`, `snuba-api`, `taskbroker`. Where a name can't match, override the
matching env (`CLICKHOUSE_HOST`, `SNUBA`, `DEFAULT_BROKERS`, `REDIS_HOST`, the
taskbroker `--rpc-host`) to the `*.railway.internal` name.

> STATUS: blueprint derived from the locally-verified stack. The process-manager
> grouping and single-node Kafka config get finalized during the first Railway
> deploy.
