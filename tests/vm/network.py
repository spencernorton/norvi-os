"""HTTPS-only allowlist proxy and QEMU guestfwd transport for acceptance."""
from __future__ import annotations
import ipaddress
import json
import os
import select
import socket
import socketserver
import sys
import threading

ALLOWED = {"archive.ubuntu.com", "security.ubuntu.com", "ports.ubuntu.com",
           "apt.norvitech.com", "apt.globalentry.systems", "github.com",
           "release-assets.githubusercontent.com", "objects.githubusercontent.com"}


def relay(left, right):
    readers = {left, right}
    while readers:
        ready, _, _ = select.select(list(readers), [], [], 90)
        if not ready:
            return
        for source in ready:
            data = source.recv(65536)
            if not data:
                readers.remove(source)
                try:
                    (right if source is left else left).shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                continue
            (right if source is left else left).sendall(data)


class Proxy(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self):
        self.requests = []
        super().__init__(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    def close(self, path):
        self.shutdown()
        self.server_close()
        self.thread.join(5)
        path.write_text(json.dumps(self.requests, indent=2) + "\n")


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(90)
        header = b""
        established = False
        try:
            while b"\r\n\r\n" not in header and len(header) < 8192:
                data = self.request.recv(1)
                if not data:
                    return
                header += data
            method, target, _ = header.split(b"\r\n", 1)[0].decode("ascii").split(" ")
            host, _, port = target.rpartition(":")
            allowed = method == "CONNECT" and port == "443" and host in ALLOWED
            self.server.requests.append({"host": host, "allowed": allowed})
            if not allowed:
                self.request.sendall(b"HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
                return
            addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
            if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
                raise ValueError("Approved hostname did not resolve exclusively to public addresses")
            # Connect to the already validated address; do not resolve twice.
            family, kind, proto, _, address = next((a for a in addresses if a[0] == socket.AF_INET), addresses[0])
            with socket.socket(family, kind, proto) as remote:
                remote.settimeout(30)
                remote.connect(address)
                self.request.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
                established = True
                relay(self.request, remote)
        except (OSError, ValueError, UnicodeError):
            # A tunnel carries TLS bytes after CONNECT, never another HTTP
            # response. On transport failure just close the established stream.
            if established:
                return
            try:
                self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
            except OSError:
                pass


def forward(port):
    # QEMU starts one process per guest connection. stdin/stdout are the
    # virtual socket; the only real socket is this localhost proxy endpoint.
    with socket.create_connection(("127.0.0.1", port), timeout=30) as peer:
        readers = [0, peer]
        while True:
            ready, _, _ = select.select(readers, [], [], 90)
            if not ready:
                return
            for source in ready:
                if source == 0:
                    data = os.read(0, 65536)
                    if not data:
                        readers.remove(0)
                        peer.shutdown(socket.SHUT_WR)
                        continue
                    peer.sendall(data)
                else:
                    data = peer.recv(65536)
                    if not data:
                        return
                    view = memoryview(data)
                    while view:
                        written = os.write(1, view)
                        view = view[written:]


if __name__ == "__main__":
    forward(int(sys.argv[1]))
