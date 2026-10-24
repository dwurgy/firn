#!/usr/bin/env python3
"""Serves docs/ over https on localhost only, for docs/password-test.html.

Firn saves and fills passwords only on https pages, so the test page needs
a real certificate the Mac trusts. Steps are at the top of the test page.
Uses only Python's own modules; listens on this Mac only (never the network).
"""
import http.server
import pathlib
import ssl
import sys

PORT = 8443
FOLDER = pathlib.Path.home() / "Library/Caches/firn-password-test"
DOCS = pathlib.Path(__file__).resolve().parent

cert, key = FOLDER / "cert.pem", FOLDER / "key.pem"
if not cert.exists() or not key.exists():
    sys.exit(f"No certificate in {FOLDER}. Make one first (see the top of password-test.html).")

handler = lambda *args: http.server.SimpleHTTPRequestHandler(*args, directory=str(DOCS))
server = http.server.HTTPServer(("127.0.0.1", PORT), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
print(f"Open https://localhost:{PORT}/password-test.html in Firn. Ctrl-C stops.")
server.serve_forever()
