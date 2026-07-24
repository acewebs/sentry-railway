# Sentry on Railway (self-hosted)

A Railway-ready packaging of [self-hosted Sentry](https://github.com/getsentry/self-hosted),
the open-source error-tracking platform. It deploys Sentry as a **grouped,
private-network Railway project** — the backing stores (Postgres, Redis, ClickHouse,
Kafka, memcached), the Sentry app processes (web + honcho-grouped workers), and the
supporting services (Snuba, Relay, taskbroker, nginx) as separate Railway services.

This is the **lean / errors-only** build: exception capture, issue grouping, and
alerting — the classic Sentry — at ~14 services. It's **verified end-to-end on
Railway**: a public event ingests all the way through to ClickHouse. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it all works, and
[docs/ARCHITECTURE.md#errors-only-vs-full](docs/ARCHITECTURE.md#errors-only-vs-full)
for what the (heavier) full/APM build would add.

> This packaging exists to make Sentry deployable on Railway. For what Sentry is and
> its product docs, see the [upstream repo](https://github.com/getsentry/self-hosted)
> and [develop.sentry.dev/self-hosted](https://develop.sentry.dev/self-hosted/). The
> upstream README is preserved at [docs/sentry-upstream-readme.md](docs/sentry-upstream-readme.md).

## Is this allowed? (FSL)

Yes. Sentry is under the Functional Source License (`FSL-1.1-Apache-2.0`).
Self-hosting for your own use is a **Permitted Purpose**, and a deploy template for
others to self-host **is not** a Competing Use. Full reasoning + primary sources:
**[docs/FSL.md](docs/FSL.md)**.

## Secrets

Deployment secrets are **not** committed — generate them per deploy:
- `sentry/config.yml` `system.secret-key` is a placeholder → `sentry config generate-secret-key`.
- `relay/credentials.json` is gitignored → generate with `relay credentials generate`
  and copy its `public_key` into `SENTRY_RELAY_WHITELIST_PK` in `sentry/sentry.conf.py`.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Docs

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how it works: services, the
  end-to-end event pipeline, key design decisions, errors-only vs full.
- [docs/RAILWAY.md](docs/RAILWAY.md) — deploy mechanics: service decomposition,
  private networking, config baking, env, deploy order.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — the exact
  Railway-specific fixes/gotchas found while getting it working (the hard-won part).
- [docs/LEAN-CORE.md](docs/LEAN-CORE.md) — the lean service list + exact start commands.
- [docs/FSL.md](docs/FSL.md) — licensing analysis.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — symptom → cause → fix for the
  Railway-specific issues (topics, relay 403, nodestore, nginx, …).
- [docs/railway-template-page.md](docs/railway-template-page.md) — publishing as a
  Railway template + marketplace copy.
- [railway/](railway/) — the Railway build wrappers (config baked per service) +
  `create-topics.sh`.

## License

Same as upstream Sentry: [`FSL-1.1-Apache-2.0`](LICENSE.md).
