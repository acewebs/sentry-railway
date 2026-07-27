#!/usr/bin/env bash
# Pre-deploy bootstrap for the Sentry `web` service (Railway preDeployCommand:
# `bash /etc/sentry/bootstrap.sh`). Runs once per deploy in a one-off container,
# BEFORE web serves, and gates the rollout. Idempotent — safe to re-run every deploy.
#
# This is the Sentry half of self-hosted's install (install/set-up-and-migrate-database.sh):
#   1. wait for the data plane (Postgres/Kafka/Redis) to be reachable — services
#      boot in parallel on a fresh deploy, so don't migrate before deps are up.
#   2. `sentry upgrade --create-kafka-topics` — Postgres migrations + internal
#      project + Sentry's own ingest Kafka topics.
#   3. ensure the taskbroker / subscription-result topics `--create-kafka-topics`
#      does NOT create (a consumer on a missing topic crashes; taskbroker exits).
#   4. optional superuser, if SENTRY_ADMIN_EMAIL / SENTRY_ADMIN_PASSWORD are set;
#      otherwise create the first admin via Sentry's web setup screen.
#
# The Snuba half (ClickHouse migrations + Snuba's own topics) is the snuba-api
# service's own pre-deploy: railway/snuba-api/bootstrap.sh (`snuba bootstrap --force`).
set -euo pipefail

WAIT_FOR="${BOOTSTRAP_WAIT_FOR:-postgres.railway.internal:5432 kafka.railway.internal:9092 redis.railway.internal:6379}"
echo "[bootstrap] Waiting for data plane: ${WAIT_FOR}"
# shellcheck disable=SC2086 - intentional word-splitting into host:port args.
python3 /etc/sentry/wait-for-tcp.py ${WAIT_FOR}

echo "[bootstrap] Running Sentry migrations + creating Sentry Kafka topics ..."
/etc/sentry/entrypoint.sh upgrade --noinput --create-kafka-topics

echo "[bootstrap] Ensuring taskbroker / subscription-result topics ..."
python3 /etc/sentry/ensure-topics.py

if [[ -n "${SENTRY_ADMIN_EMAIL:-}" && -n "${SENTRY_ADMIN_PASSWORD:-}" ]]; then
  echo "[bootstrap] Ensuring admin superuser ${SENTRY_ADMIN_EMAIL} ..."
  /etc/sentry/entrypoint.sh createuser \
    --email "${SENTRY_ADMIN_EMAIL}" --password "${SENTRY_ADMIN_PASSWORD}" \
    --superuser --no-input --force-update
else
  echo "[bootstrap] SENTRY_ADMIN_EMAIL/PASSWORD not set — create the first admin"
  echo "[bootstrap] via the web setup screen on first visit."
fi

echo "[bootstrap] Sentry bootstrap complete."
