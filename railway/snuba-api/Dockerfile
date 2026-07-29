# Railway build wrapper: snuba-api (the Snuba HTTP query API on :1218).
#
# Same Snuba image the compose stack uses; this wrapper exists only to bake the
# pre-deploy bootstrap script (Railway has no host bind mounts) so the snuba-api
# service can run `snuba bootstrap --force` as its preDeployCommand — ClickHouse
# migrations + Snuba's Kafka topics — before it starts serving. See
# railway/snuba-api/bootstrap.sh and railway/snuba-api.json.
#
# ENTRYPOINT/CMD are inherited from the base image (./docker_entrypoint.sh + `api`),
# so DO NOT set a Railway start command — a custom start command bypasses the
# entrypoint and fails "executable `api` not found". Leaving it unset runs
# `./docker_entrypoint.sh api` (same as Compose's `command: api`). Context = repo root.

ARG SNUBA_IMAGE=ghcr.io/getsentry/snuba:26.7.0
FROM ${SNUBA_IMAGE}

COPY railway/lib/wait-for-tcp.py /wait-for-tcp.py
COPY railway/snuba-api/bootstrap.sh /bootstrap.sh
