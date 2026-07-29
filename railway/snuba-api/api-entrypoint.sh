#!/bin/sh
# Run the idempotent Snuba bootstrap before serving the API.
#
# Railway does not run the config-as-code preDeployCommand for a published template
# (there's no way to declare the config-file path in the template), so the setup is
# baked into the entrypoint here instead. bootstrap.sh waits for ClickHouse + Kafka,
# then `snuba bootstrap --force` runs the ClickHouse migrations and creates Snuba's
# Kafka topics (including `events`). Only after it completes do we start the API — so
# the moment snuba-api's port opens is a reliable "tables + topics ready" signal for
# the consumers that gate on snuba-api (snuba-errors, sentry-workers).
set -e
bash /bootstrap.sh
exec /usr/src/snuba/docker_entrypoint.sh api
