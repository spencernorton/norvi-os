"""Real socket/pipe boundaries: half-close must not truncate the response."""
import socket
import subprocess
import sys
import threading
import unittest
from pathlib import Path
from network import Proxy, relay


class NetworkTest(unittest.TestCase):
    def test_tunnel_drains_response_after_client_half_close(self):
        client, incoming = socket.socketpair()
        outgoing, server = socket.socketpair()
        for sock in (client, incoming, outgoing, server):
            sock.settimeout(3)
        worker = threading.Thread(target=relay, args=(incoming, outgoing), daemon=True)
        worker.start()
        try:
            client.sendall(b'request')
            client.shutdown(socket.SHUT_WR)
            request = b''
            while chunk := server.recv(65536):
                request += chunk
            self.assertEqual(request, b'request')
            server.sendall(b'response after EOF')
            server.shutdown(socket.SHUT_WR)
            response = b''
            while chunk := client.recv(65536):
                response += chunk
            self.assertEqual(response, b'response after EOF')
            worker.join(3)
            self.assertFalse(worker.is_alive())
        finally:
            for sock in (client, incoming, outgoing, server):
                sock.close()

    def test_guestfwd_drains_response_after_stdin_eof(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            def respond():
                with listener.accept()[0] as peer:
                    peer.settimeout(3)
                    request = b''
                    while chunk := peer.recv(65536):
                        request += chunk
                    peer.sendall(b'reply:' + request)
            worker = threading.Thread(target=respond, daemon=True)
            worker.start()
            child = subprocess.Popen([sys.executable, str(Path(__file__).with_name('network.py')),
                                      str(listener.getsockname()[1])],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                child.stdin.write(b'request')
                child.stdin.close()
                child.stdin = None
                stdout, stderr = child.communicate(timeout=5)
                self.assertEqual(child.returncode, 0, stderr)
                self.assertEqual(stdout, b'reply:request')
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
            worker.join(3)
            self.assertFalse(worker.is_alive())

    def test_unlisted_origin_is_refused_before_any_upstream_connection(self):
        proxy = Proxy()
        try:
            with socket.create_connection(proxy.server_address, timeout=3) as client:
                client.sendall(b'CONNECT unlisted.invalid:443 HTTP/1.1\r\n\r\n')
                self.assertTrue(client.recv(1024).startswith(b'HTTP/1.1 403 Forbidden'))
            self.assertEqual(proxy.requests, [{'host': 'unlisted.invalid', 'allowed': False}])
        finally:
            proxy.shutdown()
            proxy.server_close()
            proxy.thread.join(3)
