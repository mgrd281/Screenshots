"""Serves the built website on localhost with the Content Security Policy from vercel.json, as Vercel does."""
import functools
import http.server
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
port = int(sys.argv[1]) if len(sys.argv) > 1 else 4173
config = json.loads((root / "vercel.json").read_text())
policy = next(h["value"] for rule in config["headers"] for h in rule["headers"] if h["key"] == "Content-Security-Policy")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Content-Security-Policy", policy)
        super().end_headers()

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=root / "website" / "_site")).serve_forever()
