#!/usr/bin/env python3
"""Serve Partition locally; graph data stays separate from shipped web assets."""
import argparse
import json
from analysis import Analyses
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, graph, analyses, **kwargs):
        self.graph = graph
        self.analyses = analyses
        super().__init__(*args, directory=str(HERE / 'web'), **kwargs)

    def reply(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/api/analyses':
            self.reply(200, self.analyses.jobs)
            return
        if path.startswith('/api/analysis/'):
            job = self.analyses.jobs.get(path.rsplit('/', 1)[-1])
            self.reply(200 if job else 404, job or {'message': 'Analysis not found.'})
            return
        super().do_GET()

    def do_POST(self):
        if urlsplit(self.path).path != '/api/analysis':
            self.reply(404, {'message': 'Unknown action.'})
            return
        origin = self.headers.get('Origin')
        expected = 'http://' + self.headers.get('Host', '')
        if (origin and origin != expected) or self.headers.get('Content-Type') != 'application/json':
            self.reply(403, {'message': 'Analysis must be requested from this application.'})
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 1000000:
                raise ValueError('Invalid analysis request size.')
            request = json.loads(self.rfile.read(length))
            job = self.analyses.start(request['scope'], request['revision'])
            self.reply(202, {'id': job})
        except (ValueError, KeyError, TypeError) as error:
            self.reply(400, {'message': str(error)})

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
    graph = args.graph.resolve()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, graph=graph, analyses=Analyses(graph)))
    print(f'Partition: http://127.0.0.1:{args.port}/', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
