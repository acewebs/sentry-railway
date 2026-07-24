# Railway build wrapper for nginx (the one public-facing service).
#
# Bakes the Sentry nginx routing config into the image, because Railway has no
# host bind mounts (upstream Compose bind-mounts ./nginx.conf -> /etc/nginx/nginx.conf).
#
# nginx is the ONLY service that gets a public Railway domain. It routes ingestion
# paths (/api/*/store/, /api/*/envelope/, ...) to `relay` and everything else to
# `web`. Both upstreams are addressed by hostname, so the Railway service names (or
# aliases) must resolve to `relay` and `web` on the private network — otherwise
# edit nginx.conf to point at the *.railway.internal names.
#
# STATUS: starter artifact from the locally-verified stack; not yet Railway-deployed.

FROM nginx:1.31.3-alpine

COPY nginx.conf /etc/nginx/nginx.conf
