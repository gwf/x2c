#!/usr/bin/env python3
"""Serve Partition locally; graph data stays separate from shipped web assets."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, graph, **kwargs):
        self.graph = graph
        super().__init__(*args, directory=str(HERE / 'web'), **kwargs)

    def translate_path(self, path):
        if urlsplit(path).path == '/graph.json':
            return str(self.graph)
        return super().translate_path(path)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8794)
    parser.add_argument('--graph', type=Path, default=HERE / 'data/graph.json')
    args = parser.parse_args()
    if not args.graph.is_file():
        parser.error('No graph snapshot. Run python3 tools/partition/generate.py first.')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, graph=args.graph.resolve()))
    print(f'Partition: http://127.0.0.1:{args.port}/', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
