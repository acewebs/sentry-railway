# Railway build wrapper: taskbroker (the task queue broker for taskworker).
#
# Bakes ./taskbroker config (Railway has no bind mounts). Needs a volume at
# /opt/sqlite for its activations DB, and env pointing at kafka.railway.internal.
# gRPC serves on :50051; taskworker connects via taskbroker.railway.internal:50051.
#
# Build context = repo root. STATUS: being validated on the live deploy.

ARG TASKBROKER_IMAGE=ghcr.io/getsentry/taskbroker:nightly
FROM ${TASKBROKER_IMAGE}

COPY taskbroker/ /etc/taskbroker/

CMD ["/opt/taskbroker", "-c", "/etc/taskbroker/config.yml"]
