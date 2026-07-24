# Railway build wrapper for Relay (Sentry's ingestion gateway).
#
# Bakes Relay's config + credentials into the image, because Railway has no host
# bind mounts (upstream Compose bind-mounts ./relay -> /work/.relay at runtime).
#
# Build context = repo root. On Railway set this file as the service Dockerfile.
#
# SECURITY NOTE: relay/credentials.json contains this deployment's Relay keypair.
# For a published template, DO NOT ship real credentials — generate them per deploy
# (install/ensure-relay-credentials.sh) and inject via a Railway variable/secret,
# or run the generation as a one-off deploy step. This wrapper is for a concrete
# instance; strip credentials.json before publishing the template.
#
# STATUS: starter artifact from the locally-verified stack; not yet Railway-deployed.

ARG RELAY_IMAGE=ghcr.io/getsentry/relay:nightly
FROM ${RELAY_IMAGE}

# ./relay -> /work/.relay (config.yml + credentials.json)
# NOTE: relay/credentials.json is gitignored (contains a private key). Before
# building from a fresh clone, generate it:
#   docker compose run --rm relay credentials generate --stdout > relay/credentials.json
# then copy its public_key into SENTRY_RELAY_WHITELIST_PK in sentry/sentry.conf.py.
COPY relay/config.yml /work/.relay/config.yml
COPY relay/credentials.json /work/.relay/credentials.json
