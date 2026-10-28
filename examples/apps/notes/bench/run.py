#!/usr/bin/env python3
"""Measure notes on loopback; record reference baselines only on request."""
import argparse
import contextlib
import datetime
import hashlib
import http.client
import json
import pathlib
import platform
import shutil
import socket
import statistics
import sys
import subprocess
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BODY = {"title": "benchmark", "body": "hello", "tags": []}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hardware():
    if sys.platform == "darwin":
        keys = ("machdep.cpu.brand_string", "hw.model", "hw.memsize")
        return dict(zip(keys, (subprocess.check_output(
            ["sysctl", "-n", key], text=True).strip() for key in keys)))
    return {"processor": platform.processor(), "node": platform.node()}


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@contextlib.contextmanager
def server(command, log, port):
    with log.open("w") as output:
        process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=output)
        try:
            for _ in range(500):
                if process.poll() is not None:
                    raise RuntimeError(f"server exited; see {log}")
                try:
                    with socket.create_connection(("127.0.0.1", port), .1):
                        break
                except OSError:
                    time.sleep(.02)
            else:
                raise RuntimeError(f"server did not listen; see {log}")
            yield
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def measure(name, command, port, args, scratch, seed=False):
    with server(command, scratch / f"{name}.log", port):
        if seed:
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            connection.request("POST", "/api/notes", json.dumps(BODY),
                               {"Content-Type": "application/json"})
            response = connection.getresponse()
            body = response.read()
            connection.close()
            if response.status != 201:
                raise RuntimeError(f"seed failed: {response.status} {body!r}")
        samples = []
        for _ in range(args.runs):
            result = subprocess.run([str(scratch / "load"), str(port),
                                     str(args.connections), str(args.seconds)],
                                    cwd=ROOT, check=True, text=True,
                                    capture_output=True, timeout=args.seconds + 30)
            samples.append(json.loads(result.stdout))
        return {"samples": samples, "median": {
            key: statistics.median(sample[key] for sample in samples)
            for key in ("requests_per_s", "p50_us", "p99_us")}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record-baseline", action="store_true")
    parser.add_argument("--connections", type=int, default=64)
    parser.add_argument("--seconds", type=float, default=10)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--output", type=pathlib.Path, default=HERE / "results")
    args = parser.parse_args()
    if not 1 <= args.connections <= 1024 or args.seconds <= 0 or args.runs < 1:
        parser.error("connections must be 1..1024; seconds and runs must be positive")
    args.output.mkdir(parents=True, exist_ok=True)
    pins = {name: digest(HERE / source)
            for name, source in (("c", "server.c"), ("go", "main.go"), ("client", "load.x"))}
    metadata = {"date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "machine": platform.platform(), "processor": platform.machine(),
                "hardware": hardware(),
                "connections": args.connections, "seconds": args.seconds,
                "runs": args.runs, "source_sha256": pins}
    baseline_path = HERE / "baseline.json"
    baseline = json.loads(baseline_path.read_text()) if baseline_path.exists() else {}
    # Keep build products and logs for diagnosis; results name their location.
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="x2c-notes-bench-"))
    compiler = ROOT / "builds/0/x2c"
    subprocess.run([str(compiler), "build", "-o", str(scratch / "load"),
                    str(HERE / "load.x")], cwd=ROOT, check=True)
    if args.record_baseline:
        baseline = {**metadata, "references": {}}
        subprocess.run(["cc", "-O2", "-pthread", str(HERE / "server.c"),
                        "-o", str(scratch / "server-c")], check=True)
        port = free_port()
        baseline["references"]["c"] = measure("c", [str(scratch / "server-c"),
            str(port), str(args.connections)], port, args, scratch)
        if shutil.which("go"):
            subprocess.run(["go", "build", "-o", str(scratch / "server-go"),
                            str(HERE / "main.go")], check=True)
            port = free_port()
            baseline["references"]["go"] = measure("go", [str(scratch / "server-go"),
                str(port)], port, args, scratch)
        else:
            baseline["unavailable"] = {"go": "Go toolchain is not installed"}
        baseline_path.write_text(json.dumps(baseline, indent=2) + "\n")
    subprocess.run([str(compiler), "build", "-o", str(scratch / "notes"),
                    *(str(HERE.parent / name) for name in ("notes.x", "service.x", "store.x", "record.x"))], cwd=ROOT, check=True)
    port = free_port()
    measured = measure("x2c", [str(scratch / "notes"), "--host", "127.0.0.1",
        "--port", str(port), "--workers", str(args.connections),
        "--store", str(scratch / "notes.json")], port, args, scratch, seed=True)
    result = {**metadata, "x2c": measured, "scratch": str(scratch)}
    comparable = all(baseline.get(key) == metadata[key]
                     for key in ("source_sha256", "machine", "hardware", "connections", "seconds", "runs"))
    result["baseline_comparable"] = comparable
    if comparable:
        result["references"] = baseline.get("references", {})
        result["baseline_date"] = baseline.get("date")
    (args.output / "current.json").write_text(json.dumps(result, indent=2) + "\n")
    lines = ["# Notes loopback benchmark", "", f"Machine: {metadata['machine']}",
        f"{args.connections} keep-alive clients, {args.seconds:g} s, median of {args.runs} runs.",
        "", "| Server | Requests/s | p50 us | p99 us | x2c/server |",
        "| --- | ---: | ---: | ---: | ---: |"]
    rate = measured["median"]["requests_per_s"]
    for name, row in [("x2c", measured), *result.get("references", {}).items()]:
        values = row["median"]
        lines.append(f"| {name} | {values['requests_per_s']:.1f} | "
                     f"{values['p50_us']:.1f} | {values['p99_us']:.1f} | "
                     f"{rate / values['requests_per_s']:.3f} |")
    lines += ["", "C and Go return fixed JSON. x2c performs note lookup, copies, and JSON encoding.",
              "The ratios compare these workloads, not equivalent implementations."]
    if not comparable:
        lines += ["", "No matching pinned baseline; reference ratios are omitted."]
    if baseline.get("unavailable"):
        lines += ["", "Go baseline pending: Go toolchain is not installed on the measurement host."]
    (args.output / "current.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
