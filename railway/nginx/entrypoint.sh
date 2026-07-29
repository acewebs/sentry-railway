#!/bin/sh
# Railway assigns the port the service must listen on via $PORT (injected at runtime;
# it does not appear in the variables list). Its healthcheck and public proxy target
# that port, so nginx MUST listen on it — a hardcoded 'listen 80' gets "service
# unavailable" on every probe. nginx can't read env vars in its config, so substitute
# $PORT into nginx.conf here (default 80 for local/other use), then run nginx.
#
# The allowlist form `envsubst '${PORT}'` replaces ONLY ${PORT}; nginx's own runtime
# variables ($relay_upstream, $sentry_upstream, $uri, ...) are left untouched.
set -e
export PORT="${PORT:-80}"
envsubst '${PORT}' < /etc/nginx/nginx.conf > /tmp/nginx.conf.rendered
cp /tmp/nginx.conf.rendered /etc/nginx/nginx.conf
exec nginx -g 'daemon off;'
