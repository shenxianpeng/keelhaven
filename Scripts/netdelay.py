#!/usr/bin/env python3
"""TCP proxy that injects propagation delay in both directions.

Used by bench-remote-ls.sh to put a realistic round-trip between restic and a
backend that is actually running on loopback. Protocol-agnostic on purpose:
the same proxy fronts MinIO (HTTP) and sshd (SSH), so the two backends are
measured under identical conditions.

Every chunk is stamped with `arrival + RTT/2` and held by a sender thread
until that deadline. That is deliberately not the same as sleeping once per
request: chunks stay in flight concurrently, so a protocol's own pipelining
still pays off instead of being flattened into a serial round-trip count —
which is exactly the difference this benchmark is trying to measure.

Nothing is parsed or rewritten. S3 request signing covers the Host header, so
a proxy that touched the bytes would be rejected by MinIO; staying at the TCP
layer also means SSH's encrypted stream needs no special handling.

Usage: netdelay.py <listen-port> <upstream-port> <rtt-ms>
"""
import socket
import sys
import threading
import time
import queue

LISTEN, UPSTREAM, RTT_MS = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
ONE_WAY = RTT_MS / 2000.0  # seconds, half the round trip per direction


def pump(src, dst):
    """Forward src → dst, holding each chunk for one-way delay."""
    q = queue.Queue()

    def sender():
        while True:
            item = q.get()
            if item is None:
                break
            deadline, data = item
            gap = deadline - time.time()
            if gap > 0:
                time.sleep(gap)
            try:
                dst.sendall(data)
            except OSError:
                break
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass

    thread = threading.Thread(target=sender, daemon=True)
    thread.start()
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            q.put((time.time() + ONE_WAY, data))
    except OSError:
        pass
    q.put(None)
    thread.join()


def handle(client):
    try:
        upstream = socket.create_connection(("127.0.0.1", UPSTREAM))
    except OSError:
        client.close()
        return
    up = threading.Thread(target=pump, args=(client, upstream), daemon=True)
    down = threading.Thread(target=pump, args=(upstream, client), daemon=True)
    up.start()
    down.start()
    up.join()
    down.join()
    client.close()
    upstream.close()


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", LISTEN))
    server.listen(128)
    print(f"netdelay :{LISTEN} -> :{UPSTREAM}  rtt={RTT_MS}ms", flush=True)
    while True:
        conn, _ = server.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
