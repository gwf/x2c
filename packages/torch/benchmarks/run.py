#!/usr/bin/env python3
"""Build, run, and summarize the matched x2c/PyTorch comparison suite.

The runner launches the applications and compares their printed numbers.
It owns no model logic, no tensor semantics, and no training engine; each
application runs on its own with the same arguments this passes.

    python3 packages/torch/benchmarks/run.py prepare
    python3 packages/torch/benchmarks/run.py build [--lane primary|shipped]
    python3 packages/torch/benchmarks/run.py check [--app <name>]
    python3 packages/torch/benchmarks/run.py time  [--samples 5] [--updates N]
    python3 packages/torch/benchmarks/run.py memory [--profiles 1,3,4,5,6]
    python3 packages/torch/benchmarks/run.py attribute [--elements 65536]
    python3 packages/torch/benchmarks/run.py report
    python3 packages/torch/benchmarks/run.py env

`--lane primary` builds the x2c benchmark objects against the libtorch
dylibs inside the pinned Python wheel, so both languages call the same
backend binary; `--lane shipped` uses the package's own prepared prefix.
A comparison across the two prefixes is a comparison of distributions and
is labelled that way.

Timing collects paired fresh processes, alternating which language runs
first, and reports medians, spread, every raw sample, and the paired
ratio. `--samples 1` is the pilot that proves the harness.
"""

import argparse
import hashlib
import json
import os
import statistics
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

X2C = os.path.join(common.ROOT, "builds", "0", "x2c")
PACKAGE = common.PACKAGE
BENCH = common.BENCHMARKS

X_APPS = ["tabular", "mnist", "sequence", "interop"]
PENDING = {}


def run_id():
    return os.environ.get("X2C_RUN_ID",
                          time.strftime("%Y%m%dT%H%M%S", time.localtime()))


def log_dir(run):
    path = os.path.join(common.LOGS, run)
    os.makedirs(path, exist_ok=True)
    return path


# ---- build ----------------------------------------------------------------

def wheel_prefix():
    """The pinned wheel's own include/ and lib/, which is a libtorch prefix
    in the same shape as the package's prepared one."""
    finished = subprocess.run(
        [common.torch_python(), "-c",
         "import torch, os; print(os.path.dirname(torch.__file__))"],
        capture_output=True, text=True, check=True)
    return finished.stdout.strip()


def package_prefix():
    finished = subprocess.run(["make", "-s", "dependency-path"], cwd=PACKAGE,
                              capture_output=True, text=True, check=True)
    return finished.stdout.strip().splitlines()[-1]


def library_record(prefix):
    """Path, size, and hash of every dylib a benchmark binary will load.
    A timing result is only valid against these."""
    libraries = {}
    lib = os.path.join(prefix, "lib")
    for name in sorted(os.listdir(lib)):
        if not name.endswith(".dylib"):
            continue
        path = os.path.join(lib, name)
        if not os.path.isfile(path):
            continue
        libraries[name] = {"path": path, "bytes": os.path.getsize(path),
                           "sha256": common.sha256(path)}
    return libraries


def build(lane, counters=False):
    common.ensure_directories()
    prefix = wheel_prefix() if lane == "primary" else package_prefix()
    include = os.path.join(prefix, "include")
    lib = os.path.join(prefix, "lib")
    for path in (include, lib):
        if not os.path.isdir(path):
            sys.exit(f"{lane} lane: {path} is not a libtorch prefix")

    # The package's own targets, rebuilt against the chosen prefix through
    # the documented override. The shim object, the generated operator
    # object, and the link line record no prefix in their prerequisites,
    # so a lane switch drops them; otherwise make would keep the previous
    # lane's objects and the comparison would name the wrong backend.
    # A counters build is a different package build, so the marker
    # carries the flag as well as the prefix.
    wanted = prefix + (" +counters" if counters else "")
    marker = os.path.join(PACKAGE, "builds", "benchmark-lane")
    recorded = None
    if os.path.exists(marker):
        with open(marker) as handle:
            recorded = handle.read().strip()
    if recorded != wanted:
        for name in ("torch.link", "torch-shim.o", "xt_ops.o"):
            path = os.path.join(PACKAGE, "builds", name)
            if os.path.exists(path):
                os.remove(path)
    diagnostic = "-DXT_HANDLE_COUNTERS" if counters else ""
    subprocess.run(["make", f"TORCH_PREFIX={prefix}",
                    f"PACKAGE_DIAGNOSTIC={diagnostic}", "build"],
                   cwd=PACKAGE, check=True)
    os.makedirs(os.path.dirname(marker), exist_ok=True)
    with open(marker, "w") as handle:
        handle.write(wanted + "\n")

    membytes = os.path.join(common.BINARIES, "libmembytes.dylib")
    subprocess.run(["clang", "-O2", "-dynamiclib",
                    os.path.join(BENCH, "membytes.c"), "-o", membytes],
                   check=True)
    # The C++ control links the same helper as C; clang++ would give it C++
    # linkage and the extern "C" declaration would not find it.
    membytes_object = os.path.join(common.BINARIES, "membytes.o")
    subprocess.run(["clang", "-O2", "-c", os.path.join(BENCH, "membytes.c"),
                    "-o", membytes_object], check=True)

    for app in X_APPS:
        source = os.path.join(BENCH, f"{app}.x")
        if not os.path.exists(source):
            print(f"{app}: no source yet, skipped")
            continue
        output = os.path.join(common.BINARIES, app)
        subprocess.run([
            X2C, "build", "--output", output, "-O2",
            "--build-dir", os.path.join(common.BINARIES, f"{app}-build"),
            "--x-include-dir", os.path.join(PACKAGE, "src"),
            "--x-include-dir", os.path.join(PACKAGE, "generated"),
            "--x-include-dir", BENCH,
            "--c-include-dir", os.path.join(PACKAGE, "src"),
            "--c-include-dir", os.path.join(PACKAGE, "generated"),
            "-I", BENCH,
            "--package-dir", os.path.join(common.ROOT, "packages"),
            source, os.path.join(BENCH, "bench.x"),
            os.path.join(BENCH, "membytes.c"),
            os.path.join(BENCH, "handles.c"),
            *(["-D", "XT_HANDLE_COUNTERS"] if counters else []),
        ], check=True, cwd=common.ROOT)
        print(f"built {output}")

    # The C++ control for the interop diagnostic: it bounds host and
    # wrapper cost and is not another application framework.
    control = os.path.join(BENCH, "interop.cpp")
    if os.path.exists(control):
        output = os.path.join(common.BINARIES, "interop-cpp")
        subprocess.run([
            "clang++", "-std=c++17", "-O2",
            f"-I{include}",
            f"-I{os.path.join(include, 'torch/csrc/api/include')}",
            f"-I{BENCH}", f"-I{os.path.join(PACKAGE, 'src')}",
            control, membytes_object,
            "-o", output, f"-L{lib}", "-ltorch", "-ltorch_cpu", "-lc10",
            f"-Wl,-rpath,{lib}"], check=True)
        print(f"built {output}")

    record = {"lane": lane, "prefix": prefix, "counters": counters,
              "libraries": library_record(prefix)}
    with open(os.path.join(common.BINARIES, "lane.json"), "w") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"lane {lane} prefix {prefix}")
    for name, entry in record["libraries"].items():
        print(f"  {name:<28} {entry['bytes']:>12}  {entry['sha256'][:16]}")
    for name, reason in PENDING.items():
        print(f"{name}: pending, {reason}")


# ---- launching ------------------------------------------------------------

def x2c_command(app, mode, *arguments):
    return [os.path.join(common.BINARIES, app), mode, common.ARTIFACTS,
            common.OUTPUTS, *[str(a) for a in arguments]]


def python_command(app, mode, *arguments):
    return [common.torch_python(), os.path.join(BENCH, f"{app}.py"), mode,
            common.ARTIFACTS, common.OUTPUTS, *[str(a) for a in arguments]]


def environment(threads):
    return {"X2C_TORCH_THREADS": str(threads),
            "OMP_NUM_THREADS": str(threads)}


def both(app, mode, arguments, threads, run, tag, x2c_first=True):
    """One paired launch, in the requested order, in fresh processes."""
    logs = log_dir(run)
    calls = [("x2c", x2c_command(app, mode, *arguments)),
             ("python", python_command(app, mode, *arguments))]
    if not x2c_first:
        calls.reverse()
    results = {}
    for language, command in calls:
        results[language] = common.launch(
            command, environment(threads),
            os.path.join(logs, f"{tag}-{language}.log"))
    return results


# ---- check ----------------------------------------------------------------

def report_comparison(name, path_a, path_b, atol=common.ATOL,
                      rtol=common.RTOL):
    left = common.load_tensors(path_a)
    right = common.load_tensors(path_b)
    findings = common.compare_tensors(left, right, atol, rtol)
    worst = max((f[1] for f in findings), default=0.0)
    failed = [f for f in findings if f[3] != "ok"]
    print(f"  {name}: {len(findings)} tensors, worst absolute {worst:.3e}, "
          f"{len(failed)} over tolerance")
    for entry in failed[:8]:
        print(f"    {entry[0]:<24} abs {entry[1]:.3e}  rel {entry[2]:.3e}  "
              f"{entry[3]}")
    return worst, failed


def check(apps, threads, run):
    import torch  # noqa: F401  (only for the comparison, not the run)

    ok = True
    collected = {}
    for app in apps:
        if not os.path.exists(os.path.join(common.BINARIES, app)):
            print(f"{app}: not built, skipped")
            continue
        print(f"== {app} check")
        results = both(app, "check", (), threads, run, f"check-{app}")
        x, p = results["x2c"], results["python"]
        collected[app] = {
            "records": {"x2c": x.records, "python": p.records},
            "curve": {"x2c": x.curve, "python": p.curve},
            "agreement": [],
        }

        for name in sorted(set(x.records) & set(p.records)):
            if name.startswith("cfg_"):
                continue
            relative, agreed = common.agree(name, x.number(name),
                                            p.number(name))
            collected[app]["agreement"].append(
                {"name": name, "x2c": x.number(name),
                 "python": p.number(name), "relative": relative,
                 "ok": agreed})
            mark = "ok" if agreed else "OVER"
            print(f"  {name:<24} x2c {x.number(name):.8g}  "
                  f"python {p.number(name):.8g}  rel {relative:.2e}  {mark}")
            ok = ok and agreed

        step1 = (common.output(f"{app}-x2c-step1.pt"),
                 common.output(f"{app}-python-step1.pt"))
        if all(os.path.exists(path) for path in step1):
            worst, failed = report_comparison("one update, full values",
                                              *step1)
            collected[app]["step1_worst_absolute"] = worst
            collected[app]["step1_tensors"] = len(
                common.compare_tensors(common.load_tensors(step1[0]),
                                       common.load_tensors(step1[1])))
            ok = ok and not failed
        final = (common.output(f"{app}-x2c-final.pt"),
                 common.output(f"{app}-python-final.pt"))
        if all(os.path.exists(path) for path in final):
            # Long-run acceptance is task quality plus loss agreement; the
            # per-weight numbers are reported, not required to match.
            worst, failed = report_comparison(
                "after the full profile (reported, not required)", *final)
            collected[app]["final_worst_absolute"] = worst
        step1_worst = collected[app].get("step1_worst_absolute")
        if step1_worst is not None:
            collected[app]["step1_exact"] = step1_worst == 0.0
    path = os.path.join(log_dir(run), "check.json")
    with open(path, "w") as handle:
        json.dump(collected, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"results {path}")
    return 0 if ok else 1


# ---- timing ---------------------------------------------------------------

TIMING = [
    ("tabular", "native", "updates"),
    ("tabular", "explicit", "updates"),
    ("tabular", "predict1", "requests"),
    ("tabular", "predict32", "requests"),
    ("tabular", "predict256", "requests"),
    ("mnist", "epoch", "batches"),
    ("sequence", "window32", "windows"),
    ("interop", "chain", "requests"),
]


def summarize(samples):
    return {
        "median": statistics.median(samples),
        "min": min(samples),
        "max": max(samples),
        "spread": (max(samples) - min(samples)) / statistics.median(samples)
        if statistics.median(samples) else 0.0,
        "samples": samples,
    }


def time_lane(app, variant, count, samples, threads, run):
    if not os.path.exists(os.path.join(common.BINARIES, app)):
        print(f"{app}: not built, skipped")
        return None
    x_seconds, p_seconds = [], []
    for index in range(samples):
        tag = f"time-{app}-{variant}-t{threads}-{index}"
        results = both(app, "time", (variant, count), threads, run, tag,
                       x2c_first=(index % 2 == 0))
        x_seconds.append(results["x2c"].number("steady_seconds"))
        p_seconds.append(results["python"].number("steady_seconds"))
        peak = max(results["x2c"].records.get("footprint_peak", 0),
                   results["python"].records.get("footprint_peak", 0))
        if peak > common.FOOTPRINT_LIMIT:
            print(f"  {tag}: footprint {peak} over the 2 GiB stop limit; "
                  f"this case is incomplete")
    x, p = summarize(x_seconds), summarize(p_seconds)
    ratio = p["median"] / x["median"] if x["median"] else float("nan")
    print(f"  {app}/{variant} threads={threads} count={count}: "
          f"x2c {x['median']:.4f}s (spread {x['spread']:.1%})  "
          f"python {p['median']:.4f}s (spread {p['spread']:.1%})  "
          f"python/x2c {ratio:.2f}x")
    return {"app": app, "variant": variant, "count": count,
            "threads": threads, "x2c": x, "python": p, "ratio": ratio}


def time_all(samples, counts, thread_counts, run, apps=None):
    print(f"== paired timing, {samples} sample(s) per configuration")
    rows = []
    for app, variant, _unit in TIMING:
        if apps and app not in apps:
            continue
        for threads in thread_counts:
            count = counts.get(f"{app}.{variant}", counts.get(app, 1000))
            row = time_lane(app, variant, count, samples, threads, run)
            if row:
                rows.append(row)
    path = os.path.join(log_dir(run), "timing.json")
    with open(path, "w") as handle:
        json.dump(rows, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"raw samples {path}")
    return 0


# ---- memory ---------------------------------------------------------------

MEMORY = {
    1: ("tabular", "steady training and inference"),
    3: ("tabular", "useful survivor"),
    4: ("sequence", "graph and scope granularity"),
    5: ("tabular", "repeated lifetime and error recovery"),
    6: ("tabular", "positive control"),
}


def envelope(samples, label=None):
    chosen = [s for s in samples if label is None or s["label"] == label]
    if not chosen:
        return None
    return {
        "footprint_min": min(s["footprint"] for s in chosen),
        "footprint_max": max(s["footprint"] for s in chosen),
        "footprint_peak": max(s["footprint_peak"] for s in chosen),
        "live_allocations_last": chosen[-1]["live_allocations"],
        "live_scopes_last": chosen[-1]["live_scopes"],
        "pool_active_last": chosen[-1]["pool_active_bytes"],
    }


def memory(profiles, steps, threads, run):
    rows = []
    for profile in profiles:
        app, description = MEMORY[profile]
        if not os.path.exists(os.path.join(common.BINARIES, app)):
            print(f"profile {profile} ({app}): not built, skipped")
            continue
        print(f"== memory profile {profile}: {description} ({app})")
        results = both(app, "memory", (profile, steps), threads, run,
                       f"memory-{profile}-{app}")
        row = {"profile": profile, "app": app, "steps": steps}
        for language, result in results.items():
            if result.dropped:
                print(f"  {language}: {result.dropped} samples did not fit "
                      f"the reservation; the tail of this series is invalid")
            row[language] = {
                "envelope": envelope(result.samples),
                "records": result.records,
                "samples": result.samples,
            }
            first = result.samples[0]["footprint"] if result.samples else 0
            last = result.samples[-1]["footprint"] if result.samples else 0
            peak = max((s["footprint_peak"] for s in result.samples),
                       default=0)
            print(f"  {language:<7} baseline {first/1e6:9.1f} MB  "
                  f"final {last/1e6:9.1f} MB  peak {peak/1e6:9.1f} MB")
            if peak > common.FOOTPRINT_LIMIT:
                print(f"  {language}: over the 2 GiB stop limit; this case "
                      f"is incomplete, not a result")
        x_peak = max((s["footprint_peak"] for s in results["x2c"].samples),
                     default=0)
        p_peak = max((s["footprint_peak"] for s in results["python"].samples),
                     default=0)
        if p_peak:
            print(f"  within-run peak footprint x2c/python "
                  f"{x_peak / p_peak:.2f}x")
        rows.append(row)
    # Profiles run at different scales, so a later invocation merges into
    # the same file by profile number instead of replacing it.
    path = os.path.join(log_dir(run), "memory.json")
    def key(row):
        return "%d@%d" % (row["profile"], row["steps"])

    merged = {}
    if os.path.exists(path):
        with open(path) as handle:
            merged = {key(row): row for row in json.load(handle)}
    merged.update({key(row): row for row in rows})
    order = sorted(merged, key=lambda k: (merged[k]["profile"],
                                          merged[k]["steps"]))
    with open(path, "w") as handle:
        json.dump([merged[k] for k in order], handle, indent=2,
                  sort_keys=True)
        handle.write("\n")
    print(f"raw samples {path}")
    return 0


# ---- attribution ----------------------------------------------------------

SHAPES = ["natural", "freed", "subscope"]
CHAIN_LENGTHS = [16, 128, 512]


def attribute(elements, requests, threads, run):
    """The interop chain under three lifetimes against the C++ control.

    One fresh process per lifetime: run in one process, the earlier
    shapes' allocator churn biases the later ones. Needs a counters build
    for the handle numbers, which `run.py build --counters` produces.
    """
    binary = os.path.join(common.BINARIES, "interop")
    control = os.path.join(common.BINARIES, "interop-cpp")
    if not os.path.exists(binary):
        print("interop: not built, skipped")
        return 1
    logs = log_dir(run)
    rows, counted = {}, None
    for shape in SHAPES:
        result = common.launch(
            [binary, "attribute", common.ARTIFACTS, common.OUTPUTS,
             str(elements), str(requests), shape], environment(threads),
            os.path.join(logs, f"attribute-{shape}.log"))
        counted = bool(result.records.get("counters_enabled"))
        for ops in CHAIN_LENGTHS:
            rows[(shape, ops)] = {
                "ns_per_step": result.number(
                    f"attr_{shape}_o{ops}_ns_per_step"),
                "peak_handles": int(
                    result.number(f"attr_{shape}_o{ops}_peak_handles")),
                "peak_bytes": result.number(f"attr_{shape}_o{ops}_peak_bytes"),
                "result": result.number(f"attr_{shape}_o{ops}_result"),
            }
    control_ns = {}
    for ops in CHAIN_LENGTHS:
        result = common.launch(
            [control, "time", common.ARTIFACTS, common.OUTPUTS,
             f"e{elements}o{ops}", str(requests)], environment(threads),
            os.path.join(logs, f"attribute-cpp-o{ops}.log"))
        control_ns[ops] = result.number(f"ns_per_op_e{elements}_o{ops}")

    if not counted:
        print("  handle counts are zero: this is not a --counters build")
    print(f"== interop attribution, {elements} elements, {requests} requests, "
          f"{threads} intra-op thread(s)")
    print(f"  {'lifetime':<10} {'ops':>4} {'ns/step':>9} {'vs c++':>7} "
          f"{'live handles':>13} {'peak MB':>8}")
    for shape in SHAPES:
        for ops in CHAIN_LENGTHS:
            row = rows[(shape, ops)]
            row["vs_control"] = row["ns_per_step"] / control_ns[ops]
            print(f"  {shape:<10} {ops:>4} {row['ns_per_step']:>9.0f} "
                  f"{row['vs_control']:>6.2f}x {row['peak_handles']:>13} "
                  f"{row['peak_bytes'] / 1e6:>8.1f}")
    for ops in CHAIN_LENGTHS:
        print(f"  {'c++':<10} {ops:>4} {control_ns[ops]:>9.0f} {1.0:>6.2f}x "
              f"{'n/a':>13} {'n/a':>8}")
    for ops in CHAIN_LENGTHS:
        values = {rows[(shape, ops)]["result"] for shape in SHAPES}
        print(f"  ops {ops:>3}: the three lifetimes agree exactly: "
              f"{len(values) == 1}")

    record = {"elements": elements, "requests": requests,
              "threads": threads, "counters": counted,
              "control_ns_per_step": control_ns,
              "rows": [{"shape": shape, "operations": ops,
                        **rows[(shape, ops)]}
                       for shape in SHAPES for ops in CHAIN_LENGTHS]}
    path = os.path.join(logs, "attribution.json")
    with open(path, "w") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"raw samples {path}")
    return 0


# ---- environment ----------------------------------------------------------

def environment_report(run):
    record = common.environment_record()
    lane = os.path.join(common.BINARIES, "lane.json")
    if os.path.exists(lane):
        with open(lane) as handle:
            record["lane"] = json.load(handle)
    if os.path.exists(common.config_path()):
        record["artifacts"] = common.load_config().get("artifacts", {})
    record["x2c"] = subprocess.run([X2C, "--version"], capture_output=True,
                                   text=True).stdout.strip()
    record["torch_python"] = common.torch_python()
    path = os.path.join(log_dir(run), "environment.json")
    with open(path, "w") as handle:
        json.dump(record, handle, indent=2, sort_keys=True, default=str)
        handle.write("\n")
    print(json.dumps(record, indent=2, sort_keys=True, default=str))
    print(f"written {path}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "build", "check", "time",
                                         "memory", "attribute", "report",
                                         "env"])
    parser.add_argument("--lane", default="primary",
                        choices=["primary", "shipped"])
    parser.add_argument("--counters", action="store_true",
                        help="build the package with the private "
                             "handle counters and link the reader")
    parser.add_argument("--app", action="append")
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--updates", type=int, default=None)
    parser.add_argument("--threads", default="1")
    parser.add_argument("--profiles", default="1,3,4,5,6")
    parser.add_argument("--steps", type=int, default=512)
    parser.add_argument("--run-id", default=None)
    parser.add_argument("--elements", type=int, default=65536)
    parser.add_argument("--requests", type=int, default=60)
    options = parser.parse_args()

    run = options.run_id or run_id()
    threads = [int(value) for value in options.threads.split(",")]
    common.ensure_directories()

    if options.mode == "prepare":
        return subprocess.run([common.torch_python(),
                               os.path.join(BENCH, "prepare.py")]).returncode
    if options.mode == "build":
        return build(options.lane, options.counters) or 0
    if options.mode == "check":
        return check(options.app or X_APPS, threads[0], run)
    if options.mode == "time":
        # Calibrated from the pilot so the slower language takes roughly
        # 15 seconds per sample at one intra-op thread. --updates
        # overrides every lane at once, which is for a quick harness
        # check, not for a reported session.
        counts = {"tabular": options.updates or 60000,
                  "tabular.predict1": options.updates or 900000,
                  "tabular.predict32": options.updates or 520000,
                  "tabular.predict256": options.updates or 210000,
                  "mnist": options.updates or 1150,
                  "sequence": options.updates or 6800,
                  "interop": options.updates or 190}
        return time_all(options.samples, counts, threads, run,
                        options.app)
    if options.mode == "memory":
        profiles = [int(v) for v in options.profiles.split(",")]
        return memory(profiles, options.steps, threads[0], run)
    if options.mode == "attribute":
        return attribute(options.elements, options.requests, threads[0], run)
    if options.mode == "report":
        import report
        return report.write(run)
    return environment_report(run)


if __name__ == "__main__":
    sys.exit(main())
