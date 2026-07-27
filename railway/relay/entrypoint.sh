#!/bin/sh
# Relay entrypoint (run via the busybox shell baked into the wrapper image, since
# the upstream relay image is distroless with no shell). Only the busybox binary is
# copied in (no applet symlinks on PATH), so external commands are invoked as
# `/bin/busybox <applet>`; echo / [ / exec / set are busybox-sh builtins.
#
# Relay's keypair is a per-deploy SECRET, so it must NOT be baked into the image.
# The deployer provides it as the RELAY_CREDENTIALS_JSON Railway variable (the full
# output of `relay credentials generate --stdout`), and the matching public_key goes
# in SENTRY_RELAY_WHITELIST_PK on the web service so web trusts this relay.
#
# The upstream image runs as uid 65532 and /work/.relay is root-owned (read-only to
# us), so assemble the config folder in a writable /tmp dir: copy the baked config
# and write credentials.json from the env var, then run relay against it.
set -eu

CONF=/tmp/.relay
/bin/busybox mkdir -p "$CONF"
/bin/busybox cp /work/.relay/config.yml "$CONF/config.yml"

if [ -n "${RELAY_CREDENTIALS_JSON:-}" ]; then
  echo "$RELAY_CREDENTIALS_JSON" > "$CONF/credentials.json"
  echo "[relay-entrypoint] wrote credentials.json from RELAY_CREDENTIALS_JSON"
else
  echo "[relay-entrypoint] ERROR: RELAY_CREDENTIALS_JSON is not set." >&2
  echo "[relay-entrypoint] Generate once and set it as a Railway variable:" >&2
  echo "[relay-entrypoint]   docker run --rm ghcr.io/getsentry/relay:nightly credentials generate --stdout" >&2
  echo "[relay-entrypoint] Put its \"public_key\" in SENTRY_RELAY_WHITELIST_PK on web." >&2
  exit 1
fi

exec /bin/relay run -c "$CONF"
