#!/usr/bin/env python3
"""Port-state check for the staging host.

REFUSED  — security group open, nothing listening yet (expected pre-deploy)
OPEN     — a service is listening (expected post-deploy)
FILTERED — packets dropped: security group still closed
"""
import socket
import sys
import time

host = sys.argv[1]
for p in (80, 443):
    s = socket.socket()
    s.settimeout(5)
    t = time.time()
    try:
        s.connect((host, p))
        state = "OPEN"
    except ConnectionRefusedError:
        state = "REFUSED (SG open, nothing listening)" if time.time() - t < 2 \
            else "closed (slow RST?)"
    except (socket.timeout, OSError):
        state = "FILTERED (SG closed)"
    finally:
        s.close()
    print(f"port {p}: {state}")
