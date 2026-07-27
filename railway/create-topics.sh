#!/usr/bin/env bash
# Create every Kafka topic the errors-only Sentry pipeline needs.
#
# NOTE: this is the MANUAL / DEBUG fallback. In the template these topics are
# created automatically by the web service's pre-deploy bootstrap — the same list
# lives in railway/sentry/ensure-topics.py (run via railway/sentry/bootstrap.sh).
# Keep the two topic lists in sync. Use this script only to re-create topics by hand.
#
# WHY THIS EXISTS: librdkafka *consumers* default `allow.auto.create.topics=false`,
# so a consumer subscribing to a missing topic CRASHES ("UnknownTopicOrPartition")
# instead of creating it — even with the broker's KAFKA_AUTO_CREATE_TOPICS_ENABLE=true.
# So topics must be created explicitly, once, before/after first boot. taskbroker in
# particular exits (state "Completed") on the first missing topic.
#
# HOW TO RUN (from your machine, after `railway ssh config -s kafka --alias rw-kafka`):
#   ssh rw-kafka 'bash -s' < railway/create-topics.sh
# or paste it into a shell on the kafka service. It is idempotent (--if-not-exists).
#
# Snuba's own topics (events, outcomes, snuba-commit-log, subscription topics, …) are
# created separately by `snuba bootstrap --force --no-migrate` — run that too
# (ssh rw-snuba 'snuba bootstrap --force --no-migrate'). This script covers the
# Sentry ingest topics and the taskbroker topics that snuba bootstrap does NOT create.

set -euo pipefail
BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"

TOPICS=(
  # Sentry ingest topics (produced by relay / consumed by sentry-workers)
  ingest-events
  ingest-attachments
  ingest-monitors
  ingest-occurrences
  # taskbroker topics (all keys under kafka_topics in taskbroker/config.yml)
  taskworker
  taskworker-dlq
  events-subscription-results
  transactions-subscription-results
  metrics-subscription-results
  generic-metrics-subscription-results
  subscription-results-eap-items
  profiles
)

for t in "${TOPICS[@]}"; do
  kafka-topics --create --if-not-exists \
    --topic "$t" --partitions 1 --replication-factor 1 \
    --bootstrap-server "$BOOTSTRAP"
done

echo "All Sentry/taskbroker topics ensured on $BOOTSTRAP."
