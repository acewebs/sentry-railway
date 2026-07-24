# Railway build wrapper for ClickHouse.
#
# Bakes Sentry's ClickHouse config into the image, because Railway has no host
# bind mounts (upstream Compose bind-mounts ./clickhouse/*.xml at runtime).
#
# Build context = repo root. On Railway set this file as the service Dockerfile,
# attach a volume at /var/lib/clickhouse, and the service must run on a CPU with
# SSE4.2 (ClickHouse requirement).
#
# STATUS: starter artifact from the locally-verified stack; not yet Railway-deployed.

ARG BASE_IMAGE=altinity/clickhouse-server:25.3.6.10034.altinitystable
FROM ${BASE_IMAGE}

# Same two mounts upstream Compose provides at runtime:
#   ./clickhouse/config.xml           -> /etc/clickhouse-server/config.d/sentry.xml
#   ./clickhouse/default-password.xml -> /etc/clickhouse-server/users.d/default-password.xml
COPY clickhouse/config.xml           /etc/clickhouse-server/config.d/sentry.xml
COPY clickhouse/default-password.xml /etc/clickhouse-server/users.d/default-password.xml
