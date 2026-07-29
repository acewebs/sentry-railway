#!/bin/sh
# Gate the grouped worker/consumer processes on their bootstrap providers.
#
# These processes (ingest-events, post-process-forwarder-errors, taskworker,
# taskworker-scheduler) need the Postgres schema and the Kafka topics that
# sentry-web's pre-deploy creates (`sentry upgrade --create-kafka-topics` + ensure
# topics), and post-processing queries Snuba. A librdkafka consumer that subscribes
# to a not-yet-created topic CRASHES, so on a fresh Railway deploy the workers must
# not start until those exist. sentry-web / snuba-api only listen after their
# pre-deploy bootstrap completes, so waiting for them here is a reliable "ready"
# signal.
set -e

SENTRY_WEB="${SENTRY_WEB_WAIT:-sentry-web.railway.internal:9000}"
SNUBA_API="${SNUBA_API_WAIT:-snuba-api.railway.internal:1218}"

echo "[sentry-workers] waiting for sentry-web (schema + topics) and snuba-api ..."
python3 /wait-for-tcp.py "${SENTRY_WEB}" "${SNUBA_API}"

exec honcho start -f /etc/sentry-workers/Procfile
