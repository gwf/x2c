#!/usr/bin/env python3
"""Compare equivalent x2c and Go notes servers using one common load client."""
import argparse
import contextlib
import datetime
import hashlib
import http.client
import json
import os
import pathlib
import platform
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_usage(process, timeout):
    deadline = time.monotonic() + timeout
    while True:
        pid, status, usage = os.wait4(process.pid, os.WNOHANG)
        if pid:
            process.returncode = os.waitstatus_to_exitcode(status)
            return {"user_s": usage.ru_utime, "system_s": usage.ru_stime,
                    "max_rss_bytes": usage.ru_maxrss *
                    (1 if sys.platform == "darwin" else 1024)}
        if time.monotonic() >= deadline:
            os.kill(process.pid, signal.SIGKILL)
            os.wait4(process.pid, 0)
            process.returncode = -signal.SIGKILL
            raise RuntimeError(f"process {process.pid} exceeded {timeout}s")
        time.sleep(.01)


@contextlib.contextmanager
def server(binary, database, clients, prefix):
    port = free_port()
    log_path = prefix.with_suffix(".server.log")
    lifetime = {}
    with log_path.open("w") as log:
        started = time.monotonic()
        process = subprocess.Popen([
            str(binary), "--host", "127.0.0.1", "--port", str(port),
            "--workers", str(clients), "--store", str(database),
            "--public", str(ROOT / "examples/apps/notes/public"),
        ], cwd=ROOT, stdout=log, stderr=log)
        try:
            for _ in range(500):
                if process.poll() is not None:
                    raise RuntimeError(f"server exited; see {log_path}")
                try:
                    with socket.create_connection(("127.0.0.1", port), .1):
                        break
                except OSError:
                    time.sleep(.02)
            else:
                raise RuntimeError(f"startup timeout; see {log_path}")
            yield port, lifetime
        finally:
            if process.returncode is None:
                os.kill(process.pid, signal.SIGTERM)
                lifetime.update(wait_usage(process, 12))
            lifetime["wall_s"] = time.monotonic() - started
            lifetime["log_bytes"] = log_path.stat().st_size
            if process.returncode != 0:
                raise RuntimeError(f"server exited {process.returncode}; see {log_path}")


def request(port, method, target, body=None):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        connection.request(method, target, None if body is None else json.dumps(body),
                           {"Content-Type": "application/json"})
        response = connection.getresponse()
        payload = response.read()
        if response.status not in (200, 201):
            raise RuntimeError(f"{method} {target}: {response.status} {payload!r}")
        return json.loads(payload)
    finally:
        connection.close()


def fixture(binary, path, count, scratch):
    with server(binary, path, 8, scratch / "fixture") as (port, _):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        try:
            for index in range(count):
                body = {"title": "benchmark" if index == 0 else f"Note {index:04d}",
                        "body": "hello" if index == 0 else "x" * 256,
                        "tags": ["work"]}
                connection.request("POST", "/api/notes", json.dumps(body),
                                   {"Content-Type": "application/json"})
                response = connection.getresponse()
                payload = json.loads(response.read())
                if response.status != 201 or payload["id"] != str(index + 1):
                    raise RuntimeError("fixture creation failed")
        finally:
            connection.close()


def load(program, port, clients, seconds, workload, prefix):
    with prefix.with_suffix(".stdout").open("w") as output, \
            prefix.with_suffix(".stderr").open("w") as errors:
        started = time.monotonic()
        process = subprocess.Popen([str(program), str(port), str(clients),
            str(seconds), workload], stdout=output, stderr=errors)
        usage = wait_usage(process, seconds + 20)
        usage["wall_s"] = time.monotonic() - started
    if process.returncode:
        raise RuntimeError(f"load failed; see {prefix.with_suffix('.stderr')}")
    sample = json.loads(prefix.with_suffix(".stdout").read_text())
    return sample, usage


def measure(binary, fixture_path, args, load_binary, workload, clients, prefix):
    database = prefix.with_suffix(".db")
    shutil.copy2(fixture_path, database)
    before = os.getloadavg()
    with server(binary, database, clients, prefix) as (port, lifetime):
        warmup, _ = load(load_binary, port, clients, args.warmup, workload,
                         prefix.with_name(prefix.name + "-warmup"))
        sample, client_usage = load(load_binary, port, clients, args.seconds,
            workload, prefix.with_name(prefix.name + "-timed"))
    return {**sample, "warmup_requests": warmup["requests"],
            "server_lifetime": lifetime, "load_process": client_usage,
            "host_load_before": before, "host_load_after": os.getloadavg()}


def summarize(samples):
    return {
        **{key: statistics.median(row[key] for row in samples)
           for key in ("requests_per_s", "p50_us", "p99_us")},
        "rps_min": min(row["requests_per_s"] for row in samples),
        "rps_max": max(row["requests_per_s"] for row in samples),
        "peak_rss_mib": statistics.median(
            row["server_lifetime"]["max_rss_bytes"] / (1024 * 1024)
            for row in samples),
        "server_cpu_cores": statistics.median(
            (row["server_lifetime"]["user_s"] +
             row["server_lifetime"]["system_s"]) /
            row["server_lifetime"]["wall_s"] for row in samples),
        "client_cpu_cores": statistics.median(
            (row["load_process"]["user_s"] + row["load_process"]["system_s"]) /
            row["load_process"]["wall_s"] for row in samples),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--go-binary", type=pathlib.Path, required=True)
    parser.add_argument("--go-tool", default="go")
    parser.add_argument("--connections", type=int, nargs="+", default=[1, 64])
    parser.add_argument("--seconds", type=float, default=5)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmup", type=float, default=1)
    parser.add_argument("--rows", type=int, default=1000)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if (any(not 1 <= n <= 1024 for n in args.connections) or
        args.seconds <= 0 or args.warmup <= 0 or args.runs < 1 or args.rows < 1):
        parser.error("positive run parameters required; clients must be 1..1024")
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="notes-compare-", dir="/tmp"))
    compiler = ROOT / "builds/0/x2c"
    sqlite_prefix = pathlib.Path(subprocess.check_output([
        sys.executable, str(ROOT / "packages/tools/deps.py"), "path",
        str(ROOT / "packages/sqlite/dependency.json"), "prefix"],
        text=True).strip())
    subprocess.run(["make", "-C", str(ROOT / "packages/sqlite"), "build",
        f"PACKAGE_C_FLAGS=-O2 --c-include-dir src --c-include-dir {sqlite_prefix / 'include'}"],
        check=True)
    x2c_binary = scratch / "notes-x2c"
    build_app = [str(compiler), "build", "-O2", "-o", str(x2c_binary),
        "--build-dir", str(scratch / "build-x2c"), "--package-dir", str(ROOT / "packages"),
        "--c-include-dir", str(ROOT / "packages/sqlite/src"), "--c-include-dir",
        str(sqlite_prefix / "include"), str(HERE.parent / "notes.x")]
    subprocess.run(build_app, cwd=ROOT, check=True)
    load_binary = scratch / "load"
    subprocess.run([str(compiler), "build", "-O2", "-o",
                    str(load_binary), str(HERE / "load.x")], cwd=ROOT, check=True)
    binaries = {"x2c": x2c_binary,
                "go": args.go_binary.resolve()}
    for name, binary in binaries.items():
        subprocess.run([sys.executable, str(HERE.parent / "tests/test_notes.py"),
                        str(binary)], cwd=ROOT, check=True)
    fixture_path = scratch / "fixture.db"
    fixture(binaries["x2c"], fixture_path, args.rows, scratch)
    responses = {}
    sqlite_version = json.loads((ROOT / "packages/sqlite/dependency.json").read_text())["version"]
    for name, binary in binaries.items():
        path = scratch / f"preflight-{name}.db"
        shutil.copy2(fixture_path, path)
        with server(binary, path, 2, scratch / f"preflight-{name}") as (port, _):
            responses[name] = [request(port, "GET", "/api/notes/1"),
                               request(port, "GET", "/api/stats"),
                               request(port, "GET", "/api/notes?tag=work&q=Note")]
            updated = request(port, "PUT", "/api/notes/1", {
                "title": "benchmark-0000-00000000000000000001",
                "body": "hello", "tags": ["work"]})
            if updated["updated"] < updated["created"]:
                raise RuntimeError("invalid updated timestamp")
            updated["updated"] = 0
            responses[name].append(updated)
        if name == "go":
            expected = (f"sqlite version={sqlite_version} journal=delete "
                        "synchronous=2 busy_timeout=0 connections=1")
            log_text = (scratch / "preflight-go.server.log").read_text()
            if expected not in log_text:
                raise RuntimeError("Go native SQLite configuration mismatch")
    if responses["x2c"] != responses["go"]:
        raise RuntimeError("normalized fixture responses differ")
    result = {"date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host": platform.platform(), "cpu_count": os.cpu_count(),
        "build_app_command": build_app,
        "native_cc": subprocess.check_output([os.environ.get("CC", "cc"), "--version"], text=True),
        "hardware": {key: subprocess.check_output(["sysctl", "-n", key], text=True).strip()
                     for key in ("machdep.cpu.brand_string", "hw.model", "hw.memsize")}
                    if sys.platform == "darwin" else {},
        "sqlite": {"version": json.loads((ROOT / "packages/sqlite/dependency.json").read_text())["version"],
                   "archive_sha256": digest(sqlite_prefix / "lib/libsqlite3.a"),
                   "header_sha256": digest(sqlite_prefix / "include/sqlite3.h"),
                   "dependency_sha256": digest(ROOT / "packages/sqlite/dependency.json"),
                   "x2c_adapter_sha256": digest(ROOT / "packages/sqlite/builds/libsqlite.a"),
                   "journal_mode": "delete", "synchronous": 2,
                   "busy_timeout": 0, "cache_size": -2000},
        "go_environment": {key: os.environ.get(key, "default")
                           for key in ("GOMAXPROCS", "GOGC", "GOMEMLIMIT")},
        "fixture_rows": args.rows, "fixture_sha256": digest(fixture_path),
        "seconds": args.seconds, "warmup_s": args.warmup, "runs": args.runs,
        "x2c_version": subprocess.check_output([str(ROOT / "builds/0/x2c"), "--version"], text=True).strip(),
        "go_build": subprocess.check_output([args.go_tool, "version", "-m",
                                             str(binaries["go"])], text=True),
        "binary_sha256": {name: digest(path) for name, path in binaries.items()},
        "source_sha256": {str(path.relative_to(ROOT)): digest(path) for path in
            [HERE.parent / "notes.x", HERE / "load.x", HERE / "go/main.go",
             HERE / "go/go.mod", HERE / "go/go.sum", pathlib.Path(__file__).resolve()]},
        "cases": [], "scratch": str(scratch)}
    case_index = 0
    for workload in ("lookup", "update"):
        for clients in args.connections:
            case = {"workload": workload, "clients": clients,
                    "samples": {"x2c": [], "go": []}, "order": []}
            for index in range(args.runs):
                order = ["x2c", "go"] if (index + case_index) % 2 == 0 else ["go", "x2c"]
                case["order"].append(order)
                for name in order:
                    prefix = scratch / f"{workload}-{clients}-{index}-{name}"
                    print(f"{workload}: {clients} clients, pair {index+1}, {name}",
                          flush=True)
                    case["samples"][name].append(measure(binaries[name], fixture_path,
                        args, load_binary, workload, clients, prefix))
            case["summary"] = {name: summarize(rows)
                               for name, rows in case["samples"].items()}
            case["x2c_over_go"] = (case["summary"]["x2c"]["requests_per_s"] /
                                   case["summary"]["go"]["requests_per_s"])
            result["cases"].append(case)
            case_index += 1
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
    lines = ["# x2c and Go notes servers", "", result["date"], "",
        f"{result['host']}, {result['cpu_count']} logical CPUs; {args.rows} notes.",
        f"Timed samples {args.seconds:g}s, "
        f"warmup {args.warmup:g}s, {args.runs} alternating pairs.", "",
        "| Workload | Clients | Server | Requests/s | p50 us | p99 us | Peak MiB |",
        "| --- | ---: | --- | ---: | ---: | ---: | ---: |"]
    for case in result["cases"]:
        for name, summary in case["summary"].items():
            lines.append(f"| {case['workload']} | {case['clients']} | {name} | "
                f"{summary['requests_per_s']:.1f} | {summary['p50_us']:.1f} | "
                f"{summary['p99_us']:.1f} | {summary['peak_rss_mib']:.1f} |")
    lines += ["", "Rates and latency columns are medians of per-sample results.",
        "Peak RSS covers each server lifetime, including startup and warmup.",
        "Both use one native SQLite connection, the same copied fixture and SQL,",
        "DELETE journaling/FULL synchronization, and per-request access logging.",
        "PUT titles change on every request; these are real database updates.",
        "The common closed-loop client runs on the same shared host. CPU/load",
        "details, lifetime server CPU, load-process CPU, and every sample are in JSON.",
        "This compares these applications and bindings on this host."]
    (args.output / "comparison.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
