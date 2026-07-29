# Railway build wrapper: Snuba errors consumer (errors-only).
#
# Same Snuba image as snuba-api, different command. A wrapper entrypoint waits for the
# data plane AND snuba-api (whose pre-deploy `snuba bootstrap --force` creates the
# ClickHouse errors tables this consumer writes into) before starting the consumer, so
# a fresh/cold deploy converges instead of crash-looping on missing tables. The wrapper
# then hands off to the image's own ./docker_entrypoint.sh so the consumer runs exactly
# as upstream.
#
# DO NOT set a Railway custom start command — it would bypass this entrypoint. Change
# the consumer args in railway/snuba-errors/entrypoint.sh instead.

ARG SNUBA_IMAGE=ghcr.io/getsentry/snuba:26.7.0
FROM ${SNUBA_IMAGE}

COPY railway/lib/wait-for-tcp.py /usr/src/snuba/wait-for-tcp.py
COPY railway/snuba-errors/entrypoint.sh /usr/src/snuba/snuba-errors-entrypoint.sh

ENTRYPOINT ["sh", "/usr/src/snuba/snuba-errors-entrypoint.sh"]
