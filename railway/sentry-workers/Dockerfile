# Railway build wrapper: grouped Sentry worker processes (errors-only).
#
# One Railway service runs several Sentry consumer/worker processes via honcho
# (bundled in the Sentry image at /.venv/bin/honcho), instead of one Railway
# service per process — fewer services, lower cost. Each Procfile line goes
# through the normal Sentry entrypoint so setup is preserved per process.
#
# Processes (errors-only): ingest-events, post-process-forwarder-errors,
# taskworker, taskworker-scheduler. See railway/sentry-workers/Procfile.
#
# Build context = repo root.

ARG SENTRY_IMAGE=ghcr.io/getsentry/sentry:26.7.0
FROM ${SENTRY_IMAGE}

RUN pip install https://github.com/getsentry/sentry-nodestore-s3/archive/main.zip

COPY sentry/ /usr/src/sentry
RUN if [ -s /usr/src/sentry/enhance-image.sh ]; then /usr/src/sentry/enhance-image.sh; fi

# Bake the runtime config (Railway has no bind mounts) + the Procfile.
COPY sentry/ /etc/sentry/
COPY railway/sentry-workers/Procfile /etc/sentry-workers/Procfile
COPY railway/lib/wait-for-tcp.py /wait-for-tcp.py
COPY railway/sentry-workers/entrypoint.sh /etc/sentry-workers/entrypoint.sh
ENV SENTRY_CONF=/etc/sentry

# Wait for sentry-web (Postgres schema + Kafka topics) and snuba-api before starting
# the consumers — a Kafka consumer subscribing to a not-yet-created topic crashes, so
# on a cold deploy the workers must not start before sentry-web's bootstrap has run.
ENTRYPOINT []
CMD ["sh", "/etc/sentry-workers/entrypoint.sh"]
