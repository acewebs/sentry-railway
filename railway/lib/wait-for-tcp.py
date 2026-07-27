#!/usr/bin/env python3
"""Block until each host:port TCP endpoint accepts a connection (or time out).

Used by the pre-deploy bootstrap scripts (railway/sentry/bootstrap.sh,
railway/snuba-api/bootstrap.sh) so migrations don't run before the data plane is
reachable. On a fresh Railway deploy every service boots in parallel, so `web`'s
pre-deploy can start before Postgres/Kafka finish initialising; without this wait
that first deploy would fail and Railway would have to retry it.

Handles IPv6 targets: Railway's private DNS (`<svc>.railway.internal`) resolves to
AAAA records, and socket.create_connection() goes through getaddrinfo so it works
for both families. Usage: wait-for-tcp.py host1:port1 host2:port2 ...
Timeout (seconds) is BOOTSTRAP_WAIT_TIMEOUT (default 300).
"""
import os
import socket
import sys
import time

timeout = int(os.environ.get("BOOTSTRAP_WAIT_TIMEOUT", "300"))
targets = sys.argv[1:]
if not targets:
    print("[wait-for-tcp] no targets given; nothing to wait for")
    sys.exit(0)

deadline = time.monotonic() + timeout
for target in targets:
    host, _, port = target.rpartition(":")
    if not host or not port:
        print(f"[wait-for-tcp] skipping malformed target {target!r}", file=sys.stderr)
        continue
    port = int(port)
    while True:
        try:
            with socket.create_connection((host, port), timeout=5):
                print(f"[wait-for-tcp] {host}:{port} is reachable")
                break
        except OSError as exc:
            if time.monotonic() > deadline:
                print(
                    f"[wait-for-tcp] timed out after {timeout}s waiting for "
                    f"{host}:{port}: {exc}",
                    file=sys.stderr,
                )
                sys.exit(1)
            print(f"[wait-for-tcp] waiting for {host}:{port} ...")
            time.sleep(3)
