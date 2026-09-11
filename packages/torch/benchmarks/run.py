#!/usr/bin/env python3
"""Build, run, and summarize the matched x2c/PyTorch comparison suite.

The runner launches the applications and compares their printed numbers.
It owns no model logic, no tensor semantics, and no training engine; each
application runs on its own with the same arguments this passes.

    python3 packages/torch/benchmarks/run.py prepare
    python3 packages/torch/benchmarks/run.py build [--lane primary|shipped]
    python3 packages/torch/benchmarks/run.py check [--app <name>]
    python3 packages/torch/benchmarks/run.py time  [--samples 5] [--updates N]
    python3 packages/torch/benchmarks/run.py memory [--profiles 1,2,3,4,5,6]
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
import shutil
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


def configure_session(run, optimizer=None):
    """A session never combines different optimizer comparisons."""
    path = os.path.join(log_dir(run), "comparison.json")
    previous = None
    if os.path.exists(path):
        with open(path) as handle:
            previous = json.load(handle)["optimizer"]
    selected = optimizer or previous or "stock"
    if previous and previous != selected:
        raise ValueError(f"session {run} already uses {previous} Adam")
    os.environ["X2C_TORCH_OPTIMIZER"] = selected
    common.OUTPUTS = os.path.join(common.WORK, "out", run)
    os.makedirs(common.OUTPUTS, exist_ok=True)
    if not previous:
        with open(path, "w") as handle:
            json.dump({"optimizer": selected}, handle)
            handle.write("\n")
    return selected


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

    # Reuse the package Makefile in a private directory. Package discovery
    # uses canonical paths, so source files must be actual private copies.
    # Refresh both trees to remove obsolete inputs; copy2 retains timestamps.
    variant = lane + ("-counters" if counters else "")
    packages = os.path.join(common.WORK, "lanes", variant, "packages")
    package = os.path.join(packages, "torch")
    os.makedirs(package, exist_ok=True)
    for name in ("package.mk", "dependency.mk", "tools"):
        target = os.path.join(packages, name)
        if not os.path.lexists(target):
            os.symlink(os.path.join(common.ROOT, "packages", name), target)
    for name in ("src", "generated"):
        target = os.path.join(package, name)
        if os.path.islink(target):
            os.unlink(target)
        elif os.path.isdir(target):
            shutil.rmtree(target)
        shutil.copytree(os.path.join(PACKAGE, name), target)
    for name in ("Makefile", "dependency.json",
                 "dependency-linux.json"):
        target = os.path.join(package, name)
        if not os.path.lexists(target):
            os.symlink(os.path.join(PACKAGE, name), target)

    # Make does not fingerprint the prefix or C++ flags for these three
    # outputs. Discard only private outputs when that configuration changes.
    wanted = prefix + (" +counters" if counters else "")
    marker = os.path.join(package, "builds", "benchmark-lane")
    recorded = None
    if os.path.exists(marker):
        with open(marker) as handle:
            recorded = handle.read().strip()
    if recorded != wanted:
        for name in ("torch.link", "torch-shim.o", "xt_ops.o"):
            path = os.path.join(package, "builds", name)
            if os.path.exists(path):
                os.remove(path)
    diagnostic = "-DXT_HANDLE_COUNTERS" if counters else ""
    subprocess.run(["make", f"ROOT={common.ROOT}", f"X2C={X2C}",
                    f"TORCH_PREFIX={prefix}",
                    f"PACKAGE_DIAGNOSTIC={diagnostic}", "build"],
                   cwd=package, check=True)
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
            "--x-include-dir", os.path.join(package, "src"),
            "--x-include-dir", os.path.join(package, "generated"),
            "--x-include-dir", BENCH,
            "--c-include-dir", os.path.join(package, "src"),
            "--c-include-dir", os.path.join(package, "generated"),
            "-I", BENCH,
            "--package-dir", packages,
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
              "package_build": os.path.join(package, "builds"),
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
            "OMP_NUM_THREADS": str(threads),
            "X2C_TORCH_OPTIMIZER": os.environ.get("X2C_TORCH_OPTIMIZER", "stock"),
            "X2C_TORCH_OUTPUTS": common.OUTPUTS}


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

# Records printed by the four check-mode producers. Generated families use
# the same PROFILE the Python applications and artifact preparation read.
CHECK_RECORDS = {
    "tabular": set("probe_loss untrained_val_mse mean_val_mse trained_val_mse "
                   "explicit_val_mse resumed_val_mse".split()) | {
        f"predict{size}_checksum"
        for size in common.PROFILE["tabular"]["predict_batches"]},
    "mnist": set("data_checksum test_checksum probe_loss untrained_accuracy "
                 "trained_accuracy reloaded_accuracy mode_after_reload".split()),
    "sequence": set("probe_loss untrained_val_mse mean_val_mse "
                    "last_value_val_mse trained_val_mse resumed_val_mse".split())
                | {f"window{size}_val_mse"
                   for size in common.PROFILE["sequence"]["window_sweep"]},
    "interop": {f"chain_e{size}_o{ops}"
                for size in common.PROFILE["interop"]["elements"]
                for ops in common.PROFILE["interop"]["operations"]},
}
CHECK_CONFIG = {
    "tabular": "features hidden1 hidden2 targets batch updates lr",
    "mnist": "channels1 channels2 flat hidden batch epochs batches_per_epoch lr",
    "sequence": "observed hidden window windows lr",
    "interop": "",
}


def check(apps, threads, run):
    collected = {}
    ok = bool(apps)
    for app in apps:
        print(f"== {app} check")
        errors = []
        row = collected[app] = {
            "records": {}, "curve": {}, "agreement": [], "errors": errors,
            "ok": False,
            "optimizer": os.environ.get("X2C_TORCH_OPTIMIZER", "stock"),
        }
        if not os.path.isfile(os.path.join(common.BINARIES, app)):
            errors.append(f"{app}: requested binary is not built")
            print(errors[-1])
            ok = False
            continue

        checkpoints = [] if app == "interop" else [
            common.output(f"{app}-{language}-{stage}.pt")
            for stage in ("step1", "final")
            for language in ("x2c", "python")]
        # A previous run's files cannot satisfy this run's output contract.
        for path in checkpoints:
            if os.path.exists(path):
                os.unlink(path)
        results = both(app, "check", (), threads, run, f"check-{app}")
        x, p = results["x2c"], results["python"]
        row["records"] = {name: value.records for name, value in results.items()}
        row["curve"] = {name: value.curve for name, value in results.items()}
        names = CHECK_RECORDS[app] | {"interop_threads"}
        names |= {name for name in set(x.records) | set(p.records)
                  if not name.startswith("cfg_") and name != "threads"}
        for name in sorted(names):
            missing = [language for language, value in results.items()
                       if name not in value.records]
            if missing:
                errors.append(f"{name}: missing from {', '.join(missing)}")
                continue
            relative, agreed = common.agree(name, x.number(name), p.number(name))
            if name in ("interop_threads", "mode_after_reload"):
                agreed = x.number(name) == p.number(name) == 1
            row["agreement"].append(
                {"name": name, "x2c": x.number(name), "python": p.number(name),
                 "relative": relative, "ok": agreed})
            print(f"  {name:<24} x2c {x.number(name):.8g}  "
                  f"python {p.number(name):.8g}  rel {relative:.2e}  "
                  f"{'ok' if agreed else 'OVER'}")
            if not agreed:
                errors.append(f"{name}: values disagree")

        config = {f"cfg_{key}": common.PROFILE[app][key]
                  for key in CHECK_CONFIG[app].split()}
        config.update(cfg_artifact_version=common.ARTIFACT_VERSION,
                      threads=threads)
        for name, expected in config.items():
            if x.records.get(name) != expected:
                errors.append(f"x2c {name}: expected {expected}")

        for language, result in results.items():
            values = result.records
            if not CHECK_RECORDS[app] <= values.keys():
                continue
            if app in ("tabular", "sequence"):
                baseline = min(values["untrained_val_mse"], values["mean_val_mse"])
                for name in ("trained_val_mse", "resumed_val_mse") + (
                        ("explicit_val_mse",) if app == "tabular" else ()):
                    if not 0 <= values[name] < baseline:
                        errors.append(f"{language} {name}: did not beat baselines")
            elif app == "mnist":
                for name in ("trained_accuracy", "reloaded_accuracy"):
                    if not common.PROFILE[app]["accuracy_target"] <= values[name] <= 1:
                        errors.append(f"{language} {name}: below accuracy target")

        for stage in (() if app == "interop" else ("step1", "final")):
            paths = [common.output(f"{app}-{language}-{stage}.pt")
                     for language in ("x2c", "python")]
            missing = [path for path in paths if not os.path.isfile(path)]
            if missing:
                errors.extend(f"missing checkpoint: {path}" for path in missing)
                continue
            left, right = [common.load_tensors(path) for path in paths]
            retained = os.path.join(log_dir(run), "checkpoints")
            os.makedirs(retained, exist_ok=True)
            for checkpoint in paths:
                shutil.copy2(checkpoint, retained)
            findings = common.compare_tensors(left, right)
            worst = max(item[1] for item in findings)
            failed = [item for item in findings if item[3] != "ok"]
            row[f"{stage}_worst_absolute"] = worst
            print(f"  {stage}: {len(findings)} tensors, worst absolute {worst:.3e}, "
                  f"{len(failed)} differences")
            if stage == "step1":
                row["step1_tensors"] = len(findings)
                row["step1_ok"] = not failed
                row["step1_exact"] = not failed and worst == 0.0
            # Final floating weight drift is reported, not an acceptance
            # failure. Missing/changed structure and integer state still fail.
            for name, absolute, relative, verdict in failed:
                structural = verdict != "over"
                if stage == "step1" or structural:
                    errors.append(f"{stage} {name}: {verdict}")
        for error in errors:
            print(f"  FAIL: {error}")
        row["ok"] = not errors
        ok = ok and not errors
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
    if not os.path.isfile(os.path.join(common.BINARIES, app)):
        raise RuntimeError(f"{app}: requested binary is not built")
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
    2: ("tabular", "canonical churn over bounded batch shapes"),
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


def memory(profiles, steps, threads, run, churn_lifetime="ordinary"):
    rows = []
    for profile in profiles:
        app, description = MEMORY[profile]
        if not os.path.isfile(os.path.join(common.BINARIES, app)):
            raise RuntimeError(f"profile {profile}: {app} is not built")
        variant = churn_lifetime if profile == 2 else None
        label = f"{profile} {variant}" if variant else str(profile)
        print(f"== memory profile {label}: {description} ({app})")
        arguments = (profile, steps, variant) if variant else (profile, steps)
        suffix = f"-{variant}" if variant else ""
        results = both(app, "memory", arguments, threads, run,
                       f"memory-{profile}-{app}-s{steps}{suffix}")
        if profile == 2:
            x, p = results["x2c"], results["python"]
            if x.number("churn_pool_depth") != x.number("churn_final_pool_depth"):
                raise RuntimeError("canonical churn: pool depth changed")
            for name in ("churn_requests", "churn_indices_sum",
                         "churn_named_elements", "churn_name_bytes"):
                if x.number(name) != p.number(name):
                    raise RuntimeError(f"canonical churn: {name} disagrees")
            name = "churn_values_sum"
            _, agreed = common.agree(name, x.number(name), p.number(name),
                                      common.RTOL)
            if not agreed:
                raise RuntimeError("canonical churn: output values disagree")
        if profile == 4:
            _, agreed = common.agree("accumulated_val_mse",
                results["x2c"].number("accumulated_val_mse"),
                results["python"].number("accumulated_val_mse"), common.RTOL)
            if not agreed:
                raise RuntimeError("microbatch accumulation: output disagrees")
        row = {"profile": profile, "app": app, "steps": steps}
        if variant:
            row["churn_lifetime"] = variant
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
    # Preserve each profile, scale and lifetime variant across invocations.
    path = os.path.join(log_dir(run), "memory.json")
    def key(row):
        variant = row.get("churn_lifetime", "ordinary")
        return "%d@%d@%s" % (row["profile"], row["steps"], variant)

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
            os.path.join(logs, f"attribute-e{elements}-{shape}.log"))
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
    control_ns, python_ns, control_values = {}, {}, {}
    for ops in CHAIN_LENGTHS:
        result = common.launch(
            [control, "time", common.ARTIFACTS, common.OUTPUTS,
             f"e{elements}o{ops}", str(requests)], environment(threads),
            os.path.join(logs, f"attribute-e{elements}-cpp-o{ops}.log"))
        control_ns[ops] = result.number(f"ns_per_op_e{elements}_o{ops}")
        control_values[ops] = result.number(f"result_e{elements}_o{ops}")
        python = common.launch(python_command("interop", "time",
                               f"e{elements}o{ops}", requests),
                               environment(threads), os.path.join(logs,
                               f"attribute-e{elements}-python-o{ops}.log"))
        python_ns[ops] = python.number(f"ns_per_op_e{elements}_o{ops}")
        values = [rows[(shape, ops)]["result"] for shape in SHAPES]
        values.append(python.number(f"result_e{elements}_o{ops}"))
        for value in values:
            _, agreed = common.agree("chain_result", value,
                                      control_values[ops], common.RTOL)
            if not agreed:
                raise RuntimeError(f"e{elements}o{ops}: C++ output disagrees")

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
              "python_ns_per_step": python_ns,
              "control_result": control_values,
              "rows": [{"shape": shape, "operations": ops,
                        **rows[(shape, ops)]}
                       for shape in SHAPES for ops in CHAIN_LENGTHS]}
    path = os.path.join(logs, f"attribution-e{elements}.json")
    with open(path, "w") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    shutil.copyfile(path, os.path.join(logs, "attribution.json"))
    print(f"raw samples {path}")
    return 0


# ---- supplemental diagnostics --------------------------------------------


def diagnose(apps, steps, samples, threads, run):
    rows, startup = [], []
    for app in apps:
        for repeat in range(samples):
            results = both(app, "startup", (), threads, run,
                           f"startup-{app}-{repeat}", repeat % 2 == 0)
            startup.append({"app": app, "repeat": repeat,
                            **{lang: value.seconds
                               for lang, value in results.items()}})
        variants = ("native", "explicit") if app == "tabular" else ("native",)
        for variant in variants:
            for repeat in range(samples):
                arguments = (variant, steps) if app == "tabular" else (steps,)
                results = both(app, "diagnose", arguments, threads, run,
                               f"diagnose-{app}-{variant}-{repeat}",
                               repeat % 2 == 0)
                row = {"app": app, "variant": variant, "repeat": repeat}
                for language, result in results.items():
                    row[language] = result.records
                    if result.records.get("diagnostic_reload_difference", 0) != 0:
                        raise RuntimeError(f"{app}: checkpoint reload changed loss")
                names = [name for name in row["x2c"]
                         if name.startswith("diagnostic_")]
                for name in names:
                    _, agreed = common.agree(name, results["x2c"].number(name),
                                              results["python"].number(name),
                                              common.RTOL)
                    if not agreed:
                        raise RuntimeError(f"{app} {variant}: {name} disagrees")
                rows.append(row)
    path = os.path.join(log_dir(run), "diagnose.json")
    with open(path, "w") as handle:
        json.dump({"steps": steps, "samples": samples, "threads": threads,
                   "startup": startup, "phases": rows}, handle, indent=2)
        handle.write("\n")
    print(f"phase and startup diagnostics passed: {path}")
    return 0


def errors(steps, threads, run):
    rows = []
    for variant in ("fixed", "unique"):
        results = both("tabular", "errors", (variant, steps), threads, run,
                       f"errors-{variant}-{steps}")
        row = {"variant": variant, "steps": steps}
        for language, result in results.items():
            if result.number("errors_caught") != steps:
                raise RuntimeError(f"{variant}: missed expected errors")
            if result.number("grad_after_errors") != 1 or result.dropped:
                raise RuntimeError(f"{variant}: invalid recovery or samples")
            row[language] = {"records": result.records,
                             "samples": result.samples}
        _, agreed = common.agree("recovery_checksum",
            results["x2c"].number("recovery_checksum"),
            results["python"].number("recovery_checksum"), common.RTOL)
        if not agreed:
            raise RuntimeError(f"{variant}: recovered output disagrees")
        rows.append(row)
    path = os.path.join(log_dir(run), f"errors-{steps}.json")
    with open(path, "w") as handle:
        json.dump(rows, handle, indent=2)
        handle.write("\n")
    print(f"fixed and unique error recovery passed: {path}")
    return 0


# ---- environment ----------------------------------------------------------

def environment_report(run):
    record = common.environment_record()
    record["optimizer"] = os.environ.get("X2C_TORCH_OPTIMIZER", "stock")
    lane = os.path.join(common.BINARIES, "lane.json")
    if os.path.exists(lane):
        with open(lane) as handle:
            record["lane"] = json.load(handle)
    if os.path.exists(common.config_path()):
        record["artifacts"] = common.load_config().get("artifacts", {})
    record["x2c"] = subprocess.run([X2C, "--version"], capture_output=True,
                                   text=True).stdout.strip()
    record["torch_python"] = common.torch_python()
    record["python_runtime"] = json.loads(subprocess.run(
        [common.torch_python(), "-c",
         "import json, sys, torch; print(json.dumps({"
         "'executable': sys.executable, 'python': sys.version, "
         "'torch': torch.__version__}))"],
        capture_output=True, text=True, check=True).stdout)
    record["binaries"] = {name: common.sha256(path)
                          for name, path in [("compiler", X2C)] + [
                              (app, os.path.join(common.BINARIES, app))
                              for app in X_APPS]
                          if os.path.isfile(path)}
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
                                         "env", "diagnose", "errors", "supplement"])
    parser.add_argument("--lane", default="primary",
                        choices=["primary", "shipped"])
    parser.add_argument("--counters", action="store_true",
                        help="build the package with the private "
                             "handle counters and link the reader")
    parser.add_argument("--app", action="append")
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--updates", type=int, default=None)
    parser.add_argument("--threads", default="1")
    parser.add_argument("--profiles", default="1,2,3,4,5,6")
    parser.add_argument("--steps", type=int, default=512)
    parser.add_argument("--churn-lifetime", default="ordinary",
                        choices=["ordinary", "pooled", "hoisted"],
                        help="profile 2 request pool or stable-handle lifetime")
    parser.add_argument("--run-id", default=None)
    parser.add_argument("--diagnostics-run", default=None,
                        help="report memory and attribution from a separately "
                             "recorded counter build")
    parser.add_argument("--timing-run", default=None,
                        help="supplemental counter-free timing correction")
    parser.add_argument("--optimizer", choices=["stock", "matched"],
                        help="stock PyTorch or libtorch operation-order control; "
                             "fixed for all measurements in one run-id")
    parser.add_argument("--elements", type=int, default=65536)
    parser.add_argument("--requests", type=int, default=60)
    options = parser.parse_args()

    if options.mode == "check":
        try:
            import torch
        except ImportError:
            common.reexec_with_torch(__file__)

    run = options.run_id or run_id()
    threads = [int(value) for value in options.threads.split(",")]
    common.ensure_directories()

    if options.mode not in ("prepare", "build"):
        configure_session(run, options.optimizer)

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
    if options.mode == "diagnose":
        return diagnose(options.app or ["tabular", "mnist", "sequence"],
                        options.steps, options.samples, threads[0], run)
    if options.mode == "errors":
        return errors(options.steps, threads[0], run)
    if options.mode == "supplement":
        import report
        return report.supplement(run, options.timing_run)
    if options.mode == "memory":
        profiles = [int(v) for v in options.profiles.split(",")]
        return memory(profiles, options.steps, threads[0], run,
                      options.churn_lifetime)
    if options.mode == "attribute":
        return attribute(options.elements, options.requests, threads[0], run)
    if options.mode == "report":
        import report
        return report.write(run, options.diagnostics_run, options.timing_run)
    return environment_report(run)


if __name__ == "__main__":
    sys.exit(main())
