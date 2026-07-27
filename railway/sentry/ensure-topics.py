#!/usr/bin/env python3
"""Ensure every Kafka topic the errors-only pipeline needs exists (idempotent).

`sentry upgrade --create-kafka-topics` creates Sentry's own ingest topics and
`snuba bootstrap` creates Snuba's, but neither creates the taskbroker retry/DLQ
and query-subscription-result topics (see taskbroker/config.yml `kafka_topics`).
A librdkafka *consumer* subscribing to a missing topic CRASHES rather than
auto-creating it (taskbroker exits on the first missing one), so these must be
created explicitly before the consumers start.

Runs from the Sentry image (confluent_kafka is bundled), so it needs no
`kafka-topics` CLI. This is the automated equivalent of railway/create-topics.sh.
Existing topics are left untouched.
"""
import os
import sys

from confluent_kafka.admin import AdminClient, NewTopic

bootstrap = os.environ.get("KAFKA_BOOTSTRAP", "kafka.railway.internal:9092")

# Keep this list in sync with railway/create-topics.sh (the manual fallback).
TOPICS = [
    # Sentry ingest topics (produced by relay / consumed by sentry-consumers).
    "ingest-events",
    "ingest-attachments",
    "ingest-monitors",
    "ingest-occurrences",
    # taskbroker topics (every key under kafka_topics in taskbroker/config.yml).
    "taskworker",
    "taskworker-dlq",
    "events-subscription-results",
    "transactions-subscription-results",
    "metrics-subscription-results",
    "generic-metrics-subscription-results",
    "subscription-results-eap-items",
    "profiles",
]

admin = AdminClient({"bootstrap.servers": bootstrap})
existing = set(admin.list_topics(timeout=30).topics)
todo = [t for t in TOPICS if t not in existing]

if not todo:
    print(f"[ensure-topics] all {len(TOPICS)} topics already exist on {bootstrap}")
    sys.exit(0)

futures = admin.create_topics(
    [NewTopic(t, num_partitions=1, replication_factor=1) for t in todo]
)

rc = 0
for topic, future in futures.items():
    try:
        future.result()
        print(f"[ensure-topics] created {topic}")
    except Exception as exc:  # noqa: BLE001 - report and keep going
        # A concurrent create (TopicAlreadyExists) is fine; anything else is real.
        if "already exists" in str(exc).lower():
            print(f"[ensure-topics] {topic} already exists")
        else:
            print(f"[ensure-topics] FAILED {topic}: {exc}", file=sys.stderr)
            rc = 1

print(f"[ensure-topics] ensured {len(TOPICS)} topics on {bootstrap}")
sys.exit(rc)
