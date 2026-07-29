# Railway build wrapper for Relay (Sentry's ingestion gateway).
#
# Bakes only Relay's NON-secret config (config.yml) into the image. The per-deploy
# Relay keypair is a SECRET and is provided at runtime via the RELAY_CREDENTIALS_JSON
# Railway variable, not baked in — so a fresh clone builds with no secret files and
# the template stays safe to publish. See railway/relay/entrypoint.sh.
#
# The upstream relay image is distroless (no shell), so we copy a static busybox in
# to run the entrypoint that assembles the config folder and materialises the
# credentials from the env var. Build context = repo root.

ARG RELAY_IMAGE=ghcr.io/getsentry/relay:26.7.0

FROM busybox:musl AS busybox

FROM ${RELAY_IMAGE}
# Static (musl) shell for the entrypoint; the base image has none.
COPY --from=busybox /bin/busybox /bin/busybox
# Non-secret config only (upstream Compose bind-mounts ./relay -> /work/.relay).
COPY relay/config.yml /work/.relay/config.yml
COPY railway/relay/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/busybox", "sh", "/entrypoint.sh"]
