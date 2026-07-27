#!/usr/bin/env bash
# Pre-deploy bootstrap for the `snuba-api` service (Railway preDeployCommand:
# `bash /bootstrap.sh`). Runs once per deploy in a one-off container, BEFORE
# snuba-api serves, and gates the rollout. Idempotent — safe to re-run every deploy.
#
# This is the Snuba half of self-hosted's install (install/bootstrap-snuba.sh):
# `snuba bootstrap --force` runs the ClickHouse migrations AND creates Snuba's own
# Kafka topics (events, outcomes, snuba-commit-log, the subscription topics, …).
#
# The Sentry half (Postgres migrations + ingest/taskbroker topics + admin) is the
# web service's own pre-deploy: railway/sentry/bootstrap.sh.
set -euo pipefail

CH_HOST="${CLICKHOUSE_HOST:-clickhouse.railway.internal}"
CH_PORT="${CLICKHOUSE_PORT:-9000}"
# DEFAULT_BROKERS may be a comma-separated list; wait on the first broker.
KAFKA="${DEFAULT_BROKERS:-kafka.railway.internal:9092}"
KAFKA="${KAFKA%%,*}"

echo "[bootstrap] Waiting for ClickHouse ${CH_HOST}:${CH_PORT} and Kafka ${KAFKA}"
python3 /wait-for-tcp.py "${CH_HOST}:${CH_PORT}" "${KAFKA}"

echo "[bootstrap] Snuba: migrating ClickHouse + creating Snuba Kafka topics ..."
snuba bootstrap --force

echo "[bootstrap] Snuba bootstrap complete."
