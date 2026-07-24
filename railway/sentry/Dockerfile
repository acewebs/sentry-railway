# Railway build wrapper for the Sentry app image.
#
# Bakes the /etc/sentry config into the image, because Railway has no host bind
# mounts (upstream Compose bind-mounts ./sentry:/etc/sentry at runtime instead).
#
# One image, many Railway services: web / worker / cron / consumers / taskworker
# all use this image and differ only by their start command (set per-service in
# Railway, e.g. `run web`, `run worker`, `run cron`, `run consumer ...`).
#
# Build context = repo root (so both sentry/ config and enhance-image.sh are in
# scope). On Railway set this file as the service Dockerfile and the root dir to
# the repo root.
#
# STATUS: starter artifact from the locally-verified stack; not yet deployed on
# Railway. See ../README.md.

ARG SENTRY_IMAGE=ghcr.io/getsentry/sentry:nightly
FROM ${SENTRY_IMAGE}

# Optional pip enhancements (kept in step with upstream sentry/Dockerfile).
RUN pip install https://github.com/getsentry/sentry-nodestore-s3/archive/main.zip

# Enhance-image hook (extra packages) — same as upstream.
COPY sentry/ /usr/src/sentry
RUN if [ -s /usr/src/sentry/enhance-image.sh ]; then /usr/src/sentry/enhance-image.sh; fi

# The Railway-specific bit: bake the whole /etc/sentry dir that Compose would
# bind-mount at runtime — includes entrypoint.sh, sentry.conf.py and config.yml.
COPY sentry/ /etc/sentry/
ENV SENTRY_CONF=/etc/sentry

ENTRYPOINT ["/etc/sentry/entrypoint.sh"]
CMD ["run", "web"]
