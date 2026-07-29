# Railway build wrapper for Kafka.
#
# confluentinc/cp-kafka runs as uid 1000 (appuser) and its preflight fails with
# "/var/lib/kafka/data is writable ... FAILED" because Railway mounts the volume
# owned by root. Running as root lets the preflight pass and Kafka own its data
# dir. (Single-node, low-volume self-host — running the broker as root is
# acceptable here.)
#
# Railway-specific fix.

FROM confluentinc/cp-kafka:7.6.6
USER root
