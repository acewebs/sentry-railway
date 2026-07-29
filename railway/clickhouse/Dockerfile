# Railway build wrapper for ClickHouse.
#
# Bakes Sentry's ClickHouse config into the image, because Railway has no host
# bind mounts (upstream Compose bind-mounts ./clickhouse/*.xml at runtime).
#
# Build context = repo root. On Railway set this file as the service Dockerfile,
# attach a volume at /var/lib/clickhouse, and the service must run on a CPU with
# SSE4.2 (ClickHouse requirement).
#
# The default-user config is written here (not COPYed from a file) so the password
# comes from the CLICKHOUSE_PASSWORD env var at runtime instead of being baked
# empty into the image. Set CLICKHOUSE_PASSWORD (auto-generate with ${{ secret(32) }})
# and give the same value to the Snuba services that connect to ClickHouse.

ARG BASE_IMAGE=altinity/clickhouse-server:25.3.6.10034.altinitystable
FROM ${BASE_IMAGE}

# Server config (memory ratio, log trimming, merge-tree tuning). Same file upstream
# Compose bind-mounts to /etc/clickhouse-server/config.d/sentry.xml at runtime.
COPY clickhouse/config.xml /etc/clickhouse-server/config.d/sentry.xml

# Default user: password read from CLICKHOUSE_PASSWORD at runtime, reachable only on
# Railway's private network. Written inline (printf) so there is no separate
# context file to COPY.
RUN printf '<clickhouse>\n  <users>\n    <default>\n      <password from_env="CLICKHOUSE_PASSWORD"/>\n      <networks>\n        <ip>::/0</ip>\n      </networks>\n    </default>\n  </users>\n</clickhouse>\n' \
    > /etc/clickhouse-server/users.d/default-password.xml
