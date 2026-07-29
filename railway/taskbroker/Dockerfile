# Railway build wrapper: taskbroker (the task queue broker for taskworker).
#
# Bakes ./taskbroker config (Railway has no bind mounts). Needs a volume at
# /opt/sqlite for its activations DB, and env pointing at kafka.railway.internal.
# gRPC serves on :50051; taskworker connects via taskbroker.railway.internal:50051.
#
# Build context = repo root.

ARG TASKBROKER_IMAGE=ghcr.io/getsentry/taskbroker:26.7.0
FROM ${TASKBROKER_IMAGE}

COPY taskbroker/ /etc/taskbroker/
COPY railway/taskbroker/entrypoint.sh /entrypoint.sh

# Retry loop so a cold start tolerates the subscription-result topics not existing
# yet (they're created by sentry-web's bootstrap); taskbroker exits cleanly on a
# missing topic and Railway's On-Failure policy won't restart a clean exit.
ENTRYPOINT ["sh", "/entrypoint.sh"]
