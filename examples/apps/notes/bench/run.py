#!/usr/bin/env python3
"""Measure the notes lookup route over persistent loopback connections."""
import argparse
import contextlib
import datetime
import hashlib
import http.client
import json
import pathlib
import platform
import socket
import statistics
import subprocess
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@contextlib.contextmanager
def server(program, port, connections, scratch):
    with (scratch / "server.log").open("w") as output:
        process = subprocess.Popen([
            str(program), "--host", "127.0.0.1", "--port", str(port),
            "--workers", str(connections), "--store", str(scratch / "notes.db"),
        ], cwd=ROOT, stdout=output, stderr=output)
        try:
            for _ in range(500):
                if process.poll() is not None:
                    raise RuntimeError(f"server exited; see {scratch / 'server.log'}")
                try:
                    with socket.create_connection(("127.0.0.1", port), .1):
                        break
                except OSError:
                    time.sleep(.02)
            else:
                raise RuntimeError("server did not listen within 10 seconds")
            yield
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connections", type=int, default=64)
    parser.add_argument("--seconds", type=float, default=10)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--output", type=pathlib.Path, default=HERE / "results")
    args = parser.parse_args()
    if not 1 <= args.connections <= 1024 or args.seconds <= 0 or args.runs < 1:
        parser.error("connections must be 1..1024; seconds/runs must be positive")
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="x2c-notes-bench-", dir="/tmp"))
    subprocess.run(["make", "-C", str(HERE.parent), "build"], check=True)
    subprocess.run([str(ROOT / "builds/0/x2c"), "build", "-o",
                    str(scratch / "load"), str(HERE / "load.x")],
                   cwd=ROOT, check=True)
    port = free_port()
    with server(HERE.parent / "builds/notes", port, args.connections, scratch):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        connection.request("POST", "/api/notes", json.dumps({
            "title": "benchmark", "body": "hello", "tags": []}),
            {"Content-Type": "application/json"})
        response = connection.getresponse()
        body = response.read()
        connection.close()
        if response.status != 201 or json.loads(body)["id"] != "1":
            raise RuntimeError(f"seed failed: {response.status} {body!r}")
        samples = []
        for _ in range(args.runs):
            result = subprocess.run([str(scratch / "load"), str(port),
                str(args.connections), str(args.seconds)], cwd=ROOT, check=True,
                text=True, capture_output=True, timeout=args.seconds + 30)
            samples.append(json.loads(result.stdout))
    sources = (HERE.parent / "notes.x", HERE / "load.x")
    result = {
        "date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "machine": platform.platform(), "processor": platform.processor(),
        "connections": args.connections, "seconds": args.seconds,
        "runs": args.runs, "samples": samples,
        "median": {key: statistics.median(row[key] for row in samples)
                   for key in ("requests_per_s", "p50_us", "p99_us")},
        "source_sha256": {str(path.relative_to(ROOT)):
            hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
        "sqlite": json.loads((ROOT / "packages/sqlite/dependency.json").read_text())["version"],
        "scratch": str(scratch),
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "current.json").write_text(json.dumps(result, indent=2) + "\n")
    median = result["median"]
    report = (f"# Notes lookup load\n\n{result['date']}\n\n"
        f"{result['machine']}; SQLite {result['sqlite']}.\n"
        f"{args.connections} keep-alive clients, {args.seconds:g} s, "
        f"median of {args.runs} samples.\n\n"
        "| Requests/s | p50 us | p99 us |\n| ---: | ---: | ---: |\n"
        f"| {median['requests_per_s']:.1f} | {median['p50_us']:.1f} | "
        f"{median['p99_us']:.1f} |\n\n"
        "Each request selects one note from SQLite and encodes its JSON response.\n"
        "Access logging is enabled. This measures the x2c application only.\n")
    (args.output / "current.md").write_text(report)
    print(report)


if __name__ == "__main__":
    main()
