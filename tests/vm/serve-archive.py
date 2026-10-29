#!/usr/bin/env python3
"""Serve only the acceptance guest's signed archive, with normal TLS checks."""
import http.server
import os
import ssl
import sys

os.chdir(sys.argv[1])


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"


server = http.server.ThreadingHTTPServer(("127.0.0.1", 443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("/tmp/accept/fixture-ca.crt", "/tmp/accept/fixture-private.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
