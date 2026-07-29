#!/bin/sh
# taskbroker exits cleanly when a Kafka subscription topic it consumes hasn't been
# created yet, and Railway's On-Failure restart policy does NOT restart a clean exit.
# On a cold deploy those topics are created by sentry-web's pre-deploy bootstrap
# (ensure-topics.py), which may not have finished when taskbroker first starts, so it
# would otherwise stay down ("Completed"). Retry until the topics exist; once they do,
# /opt/taskbroker runs in the foreground and this loop blocks on it.
#
# (The image has no python/nc, so a wait-for-tcp gate isn't possible here — a retry
# loop is the portable way to let this Rust binary tolerate a cold start.)
while true; do
  /opt/taskbroker -c /etc/taskbroker/config.yml
  echo "[taskbroker] exited (subscription topics not ready yet?); retrying in 10s..." >&2
  sleep 10
done
