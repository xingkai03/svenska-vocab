#!/usr/bin/env python3
"""Serve the web version locally without browser caching, so changes show up on a normal reload.

    python3 scripts/serve_web.py          # http://localhost:8000
    python3 scripts/serve_web.py 8080     # another port

Runs scripts/build_web.py first if web/data is missing.
"""
import functools
import http.server
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "web"


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    if not (WEB / "data" / "decks.json").exists():
        subprocess.run([sys.executable, str(ROOT / "scripts" / "build_web.py")], check=True)
    handler = functools.partial(NoCacheHandler, directory=str(WEB))
    with http.server.ThreadingHTTPServer(("localhost", port), handler) as server:
        print(f"Serving the web version at http://localhost:{port} (Ctrl+C to stop)")
        server.serve_forever()


if __name__ == "__main__":
    main()
