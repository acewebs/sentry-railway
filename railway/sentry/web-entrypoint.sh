#!/bin/sh
# Run the one-time (idempotent) bootstrap before starting web.
#
# Railway does not run the config-as-code preDeployCommand for a published template
# (there's no way to declare the config-file path in the template), so the setup is
# baked into the entrypoint here instead. bootstrap.sh waits for the data plane, runs
# the Postgres migrations, creates the Sentry Kafka topics (`sentry upgrade
# --create-kafka-topics`), ensures the taskbroker/subscription topics, and optionally
# creates the admin. Only after it completes do we start web — so the moment web's
# port opens is a reliable "schema + topics ready" signal for the services that gate
# on sentry-web (sentry-workers).
set -e
bash /etc/sentry/bootstrap.sh
exec /etc/sentry/entrypoint.sh run web
