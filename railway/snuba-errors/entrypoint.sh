#!/bin/sh
# Gate the errors consumer on its dependencies before starting it.
#
# The rust-consumer writes into ClickHouse tables that are created by snuba-api's
# pre-deploy (`snuba bootstrap --force`). On a fresh Railway deploy every service
# boots in parallel, so without this wait the consumer starts before those tables
# exist and crash-loops. snuba-api only begins listening on :1218 AFTER its
# pre-deploy bootstrap completes, so waiting for it here is a reliable "tables ready"
# signal. We also wait on ClickHouse and Kafka directly, since the consumer connects
# to both.
set -e

CH_HOST="${CLICKHOUSE_HOST:-clickhouse.railway.internal}"
KAFKA="${DEFAULT_BROKERS:-kafka.railway.internal:9092}"
KAFKA="${KAFKA%%,*}"   # DEFAULT_BROKERS may be a list; wait on the first broker
SNUBA_API="${SNUBA_API_WAIT:-snuba-api.railway.internal:1218}"

echo "[snuba-errors] waiting for ClickHouse, Kafka, and snuba-api (errors tables) ..."
python3 /usr/src/snuba/wait-for-tcp.py "${CH_HOST}:9000" "${KAFKA}" "${SNUBA_API}"

# Hand off to the image's own entrypoint so the consumer runs exactly as upstream.
exec /usr/src/snuba/docker_entrypoint.sh rust-consumer --storage errors --consumer-group snuba-consumers --auto-offset-reset=latest --max-batch-time-ms 750 --no-strict-offset-reset --max-poll-interval-ms 300000
