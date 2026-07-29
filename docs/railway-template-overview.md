# Deploy and Host Self-Hosted Sentry: Error Tracking (Lean) on Railway

Self-Hosted Sentry: Error Tracking (Lean) gives you a private Sentry installation for monitoring application errors across web, mobile, and backend services.

This errors-only deployment includes exception capture, issue grouping, event search, project management, and alert rules. It runs as 12 services connected through Railway's private network, backed by PostgreSQL and ClickHouse, without requiring external object storage.

> This is an unofficial community template and is not affiliated with or endorsed by Sentry. Review Sentry's current license terms before using it commercially. This template is intended for operating Sentry for your own applications, not for offering Sentry as a hosted service to third parties.

## About Hosting Self-Hosted Sentry: Error Tracking (Lean)

Self-hosted Sentry is a distributed application rather than a single container. It requires separate services for event ingestion, background processing, querying, storage, caching, and application management.

This template deploys the required components on Railway's private network:

* PostgreSQL for Sentry application data and event payloads
* ClickHouse for searchable event data and analytics
* Kafka for the event-processing pipeline
* Redis and Memcached for queues and caching
* Relay for receiving and validating events
* Snuba for querying ClickHouse
* Sentry web, worker, and task-processing services
* nginx as the only publicly accessible gateway

The gateway routes SDK ingestion requests to Relay and browser traffic to the Sentry web application. All remaining services communicate internally through Railway's private network.

The template also automates the initial Sentry, Snuba, ClickHouse, Kafka, and Relay setup. Stateful services use Railway Volumes so their data persists between deployments.

## Common Use Cases

* Run private error tracking for web, mobile, API, worker, and backend applications
* Keep application exceptions, stack traces, and diagnostic event data within infrastructure you control
* Support teams with internal data-governance, security, or infrastructure-ownership requirements
* Provide a dedicated Sentry environment for internal applications, staging systems, or isolated projects
* Avoid sending application errors to an externally managed error-tracking platform
* Explore and evaluate Sentry's ingestion, processing, storage, and issue-management architecture

Self-hosting alone does not provide regulatory compliance. Teams with legal or regulatory requirements should separately evaluate Railway, Sentry, access controls, backups, data retention, encryption, and their own operational procedures.

## Dependencies for Self-Hosted Sentry: Error Tracking (Lean) Hosting

This template uses:

* Official Sentry container images from `ghcr.io/getsentry` (sentry, snuba, relay, taskbroker), pinned to release 26.7.0
* PostgreSQL
* Redis
* Memcached
* Kafka running in single-node KRaft mode
* ClickHouse
* nginx
* Railway private networking
* Railway Volumes for PostgreSQL, ClickHouse, Kafka, and Taskbroker state

### Deployment Dependencies

* Sentry self-hosted repository: https://github.com/getsentry/self-hosted
* Sentry self-hosted documentation: https://develop.sentry.dev/self-hosted/
* Sentry Relay documentation: https://docs.sentry.io/product/relay/
* Template repository: https://github.com/acewebs/sentry-railway
* Architecture and event-flow documentation: https://github.com/acewebs/sentry-railway/blob/railway-template/docs/ARCHITECTURE.md
* Troubleshooting and known deployment considerations: https://github.com/acewebs/sentry-railway/blob/railway-template/docs/TROUBLESHOOTING.md

### Implementation Details

#### What Gets Deployed

Upstream self-hosted Sentry uses a large Docker Compose stack containing many process-specific containers. Several of those containers use the same Sentry or Snuba images with different startup commands.

This Railway template groups related processes together to reduce the deployment to 12 Railway services.

The `sentry-workers` service uses Honcho to run the required background processes: event ingestion consumers, post-process forwarders, task workers, and scheduled tasks. As noted above, only the `gateway` service is public; every other service communicates over Railway's private network.

#### Preconfigured Deployment

The required service connections are configured through Railway variables. No repository files need to be edited after deploying the template.

The template includes:

* An automatically generated `SENTRY_SYSTEM_SECRET_KEY`, shared between Sentry services
* An automatically generated `CLICKHOUSE_PASSWORD`, shared with Snuba
* A `SENTRY_URL_PREFIX` referencing the gateway's Railway public domain
* Preconfigured private-network addresses for all supporting services
* Preconfigured Relay credentials and trust settings
* Persistent Railway Volumes for stateful services

The stack deploys without additional configuration. You can optionally provide credentials for the first administrator:

```env
SENTRY_ADMIN_EMAIL=admin@example.com
SENTRY_ADMIN_PASSWORD=replace-with-a-secure-password
```

If set, the administrator is created automatically on first deploy; otherwise, complete setup through the Sentry web interface.

You can also change event retention (the default is 90 days):

```env
SENTRY_EVENT_RETENTION_DAYS=30
```

Email notifications require an external SMTP provider. Set `SENTRY_SMTP_HOST` (and optionally `SENTRY_SMTP_PORT`, `SENTRY_SMTP_USERNAME`, `SENTRY_SMTP_PASSWORD`) to enable invitation and alert emails. Without an SMTP host, email delivery is disabled cleanly and issue alert rules still evaluate inside the Sentry UI.

#### Automatic First-Deploy Bootstrap

A normal container deployment does not automatically perform all the initialization Sentry requires. This template runs it through Railway pre-deploy commands.

The `sentry-web` service:

1. Waits for its required data services
2. Runs Sentry database migrations
3. Creates the required internal Sentry project
4. Creates the required Kafka topics
5. Creates the first administrator when credentials are provided

The `snuba-api` service:

1. Waits for ClickHouse and Kafka
2. Runs the Snuba bootstrap process
3. Applies the required ClickHouse migrations
4. Creates the required Snuba Kafka topics

These bootstrap operations are idempotent, and each application service is deployed only after its initialization command succeeds. Because the commands wait for their dependencies, the complete template can be deployed together without manually controlling the startup order.

#### First Login and First Event

1. Deploy the template and wait for all services to become healthy.
2. Open the public domain assigned to the `gateway` service.
3. Sign in with the administrator configured through Railway variables, or complete the initial setup through the web interface.
4. Create a Sentry project for your application.
5. Copy the generated DSN into your Sentry SDK configuration.
6. Trigger a test exception from your application.

The event flows through Relay, Kafka, and the ingestion workers, is stored in PostgreSQL and ClickHouse, and appears as an issue in the UI. For direct testing, send events to `https://<your-domain>/api/<project-id>/store/` with a valid `X-Sentry-Auth` header carrying your project DSN public key.

#### Relay Credentials (rotate for production)

The template ships a preconfigured Relay keypair so the stack can complete its initial deployment without manual setup. This keypair is the same for every deployment created from the template.

> Rotate the Relay keypair before using the deployment for production traffic. A shared default private key should not be trusted for a real installation.

Generate a new credential pair with:

```bash
docker run --rm ghcr.io/getsentry/relay credentials generate --stdout
```

Then update both values together so Sentry continues to trust the Relay instance:

* `RELAY_CREDENTIALS_JSON` on the `sentry-relay` service with the complete generated JSON
* `SENTRY_RELAY_WHITELIST_PK` on the `sentry-web` service with the generated `public_key`

#### Resources and Infrastructure Usage

Sentry is not a lightweight application. It runs an event-streaming pipeline, background workers, and both relational and analytical storage, so ClickHouse, Kafka, and the Sentry workers dominate memory and compute. This lean build reduces the number of processes and stores event payloads in PostgreSQL instead of adding object storage, but it is still a substantial deployment rather than a single container. Actual usage depends on event volume, payload size, retention, worker concurrency, and query activity. Review Railway usage after deploying and tune service limits and retention for your workload.

#### What Is Not Included

This is an errors-only Sentry deployment. It does not include performance monitoring and distributed tracing, profiling, session replay, uptime monitoring, cron monitoring, user feedback, native crash symbolication, or other object-storage-backed features. Those capabilities require more Sentry processes and additional infrastructure. A separate Full or APM-oriented template can provide them.

The detailed architecture and feature scope are documented here: https://github.com/acewebs/sentry-railway/blob/railway-template/docs/ARCHITECTURE.md

## Why Deploy Self-Hosted Sentry: Error Tracking (Lean) on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Self-Hosted Sentry: Error Tracking (Lean) on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
