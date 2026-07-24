# Railway build wrapper: Snuba errors consumer (errors-only).
#
# Same Snuba image as snuba-api, different command. Keeps the image's
# ./docker_entrypoint.sh (which takes the command as args) and just overrides CMD.
# Reads ClickHouse/Kafka/Redis hosts from env (set on the service to
# *.railway.internal). STATUS: being validated on the live deploy.

ARG SNUBA_IMAGE=ghcr.io/getsentry/snuba:nightly
FROM ${SNUBA_IMAGE}

CMD ["rust-consumer", "--storage", "errors", "--consumer-group", "snuba-consumers", \
     "--auto-offset-reset=latest", "--max-batch-time-ms", "750", \
     "--no-strict-offset-reset", "--max-poll-interval-ms", "300000"]
