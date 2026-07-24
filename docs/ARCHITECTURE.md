# How this works — Sentry on Railway, end to end

This explains what the template deploys, how the pieces fit together, and how an
error event travels from a client SDK all the way into ClickHouse and the UI. It's
the conceptual companion to [RAILWAY.md](RAILWAY.md) (deploy mechanics),
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) (the exact fixes/gotchas), and
[LEAN-CORE.md](LEAN-CORE.md) (the service list + commands).

## What it is

Self-hosted **Sentry** (error tracking) running as a **grouped, private-network
Railway project**. This is the **lean / errors-only** footprint: exception capture,
issue grouping, and alerting — the classic Sentry. It deliberately drops the
observability-platform features (performance/tracing, profiling, replays, uptime,
feedback, native symbolication) to stay cheap and deployable. See
[ARCHITECTURE.md#errors-only-vs-full](#errors-only-vs-full) for the difference.

It is based on upstream [`getsentry/self-hosted`](https://github.com/getsentry/self-hosted)
(a ~65-service Docker Compose stack) collapsed to **~14 Railway services**, because
almost all of those 65 are the *same image* running different commands.

## The services (and why each exists)

**Data plane (stateful, on Railway Volumes):**
- **postgres** — primary relational DB: orgs, projects, users, issues, and (in this
  lean build) the **event bodies** (nodestore, see below).
- **clickhouse** — columnar analytics store: the searchable/aggregatable copy of
  every event. All "search issues / view event" queries ultimately hit this.
- **kafka** — the bus that decouples ingestion from processing. Every stage hands
  off to the next via a Kafka topic.
- **redis** — caches, rate limits, buffers, and Sentry's internal queues.
- **memcached** — a plain cache.

**Ingestion + query:**
- **relay** — the ingestion gateway. The only thing SDKs talk to. Authenticates the
  project (DSN), applies quotas/normalization, and puts accepted events on Kafka.
- **snuba-api** — the query service in front of ClickHouse. Sentry never queries
  ClickHouse directly; it asks Snuba.
- **snuba-errors** — the consumer that reads processed events off Kafka and writes
  the rows into ClickHouse.

**Application:**
- **web** — the Django app: UI, REST API, and the relay-facing endpoints
  (`/api/0/relays/*`). Serves the dashboard.
- **sentry-workers** — one Railway service running four processes via **honcho**
  (bundled in the Sentry image):
  - `ingest-events` — consumes relay's output, runs event processing, hands the
    event to the task system to be saved.
  - `post-process-forwarder-errors` — post-processing: grouping into issues,
    firing alert rules.
  - `taskworker` — executes async tasks (including `save_event`).
  - `taskworker-scheduler` — schedules periodic tasks (cleanup, digests, …).
- **taskbroker** — the broker for the task system; taskworker pulls work from it
  over gRPC (`:50051`). If it's down, event processing stalls.

**Edge:**
- **nginx** — the single public service. Routes ingestion paths to relay and
  everything else to web. Holds the Railway domain + TLS.

## How an error flows (the whole pipeline)

```
  SDK / curl
     │  POST https://<domain>/api/<project>/store/   (DSN in X-Sentry-Auth)
     ▼
  nginx  ──(/api/*/store, /api/N/*, /api/0/relays/*)──►  relay
     │  (everything else)                                  │
     └──────────────────────────────────────────►  web    │ relay authenticates the
                                                           │ DSN, normalizes, quotas
                                                           ▼
                                              Kafka topic: ingest-events
                                                           │
                                                           ▼
                                   sentry-workers: ingest-events consumer
                                                           │  dispatches save_event
                                                           ▼
                                   taskbroker ◄──gRPC──► taskworker  runs save_event:
                                                           │   • writes event BODY to
                                                           │     nodestore (Postgres)
                                                           │   • produces to Kafka `events`
                                                           ▼
                                              Kafka topic: events
                                                           │
                                                           ▼
                                        snuba-errors consumer ──► ClickHouse (errors_local)
                                                           │
                          post-process-forwarder-errors ◄──┘  (grouping into issues,
                                                               alert rules)

  Reading in the UI:  web ──► snuba-api ──► ClickHouse   (search, issue/event views)
```

Two independent "sinks" for every event: the **body** goes to the **nodestore
(Postgres)**, and a **searchable/aggregatable row** goes to **ClickHouse** via
Snuba. The UI stitches them back together.

## Key design decisions (and the Railway-specific reasons)

- **Postgres nodestore, not S3/SeaweedFS.** Event bodies are stored in Postgres
  (`sentry.nodestore.django.backend.DjangoNodeStorage`) instead of an S3-compatible
  object store. This removes an entire service (SeaweedFS) for the lean build. It's
  the single most important choice: upstream defaults to S3, and pointing at a
  non-existent SeaweedFS silently breaks `save_event` so no event ever reaches
  ClickHouse. (Replays/profiles in the full build *require* real object storage, so
  the full variant cannot make this choice.)
- **Consumers grouped with honcho.** The ~48 Sentry/Snuba processes are the same
  two images with different commands. Grouping the errors-only workers into one
  `sentry-workers` service keeps the Railway service count (and cost) down.
- **Config baked into images.** Railway has no host bind mounts, so each service's
  config (`/etc/sentry`, ClickHouse XML, relay yaml, nginx.conf) is `COPY`d into a
  thin wrapper image under [`../railway/`](../railway/).
- **Private network by hostname.** Services address each other at
  `<name>.railway.internal`; the baked configs point at those names. nginx uses a
  `resolver` so it re-resolves upstreams (Railway rotates private IPs on redeploy).
- **Internal relay trusted by public-key whitelist.** On Railway the relay's source
  IP isn't in Sentry's internal-network set, so it's trusted via
  `SENTRY_RELAY_WHITELIST_PK` instead (see TROUBLESHOOTING.md).
- **Kafka topics created explicitly.** Consumers don't auto-create topics on
  subscribe; [`../railway/create-topics.sh`](../railway/create-topics.sh) +
  `snuba bootstrap` create them once.

## Bootstrapping (what turns an empty stack into a working one)

1. Migrate schemas: `snuba migrations migrate` (ClickHouse) + `sentry upgrade`
   (Postgres, creates the internal project).
2. Create Kafka topics: `snuba bootstrap --force --no-migrate` +
   `railway/create-topics.sh`.
3. Create an admin user: `sentry createuser --superuser`.
4. Generate + trust relay credentials (whitelist the public key).

Run these as one-off commands against the live services (via `railway ssh`) —
Railway has no host to run upstream's `install.sh`. Exact commands:
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## errors-only vs full

The lean build sets `SENTRY_SELF_HOSTED_ERRORS_ONLY` (via `COMPOSE_PROFILES` !=
`feature-complete`). Everything in it works; the full build only *adds* surfaces:

| Feature | Lean | Full (adds) |
|---|---|---|
| Errors, grouping, alerts | ✅ | ✅ |
| Performance/tracing (transactions, spans, EAP) | — | consumers + storage |
| Profiling | — | **vroom** service + storage |
| Session Replay | — | consumers + **object storage** |
| Uptime/cron monitors | — | **uptime-checker** |
| Feedback, custom metrics | — | consumers |
| Native symbolication | — | **symbolicator** |

The one hard structural difference: Replays/Profiles need real **object storage**,
so the full variant must re-introduce SeaweedFS (or external S3) and switch the
nodestore/filestore back off Postgres.
