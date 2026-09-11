#!/usr/bin/env python3
"""Render REPORT.md from one session's raw JSON.

`run.py report --run-id <id>` calls this. It reads only what the session
wrote, so the report cannot claim a number no run produced: a missing file
becomes a missing section, named as missing.

Verdicts are per workload. There is no aggregate speedup here on purpose.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

TITLE = "# x2c and PyTorch applications: results"
DIRTY = " plus uncommitted changes"

INTRO = """\
Three applications and one diagnostic, the same work on both sides, run
live in fresh processes on one machine. [README.md](README.md) gives the
method, plan, and reproduction commands;
[PILOT.md](PILOT.md) holds the earlier single-sample pass and the gaps it
found.

Read the correctness results alongside the timings: a measured timing is
not evidence that a configuration passed. There is no aggregate speedup in
this report; the workloads and their verdicts are separate.
"""



def load(directory, name):
    path = os.path.join(directory, name)
    if not os.path.exists(path):
        return None
    with open(path) as handle:
        return json.load(handle)


def missing(what, name):
    return (f"_No {what} in this run: `{name}` was not written. "
            f"Rerun that mode and regenerate._\n")


def environment_section(environment, lines):
    lines.append("## What ran\n")
    if not environment:
        lines.append(missing("environment record", "environment.json"))
        return
    lane = environment.get("lane", {})
    libraries = lane.get("libraries", {})
    cpu = environment.get("processor", "unknown")
    lines.append(f"- Tree `{environment.get('source_head', 'unknown')}`"
                 f"{DIRTY if environment.get('source_dirty') else ''}"
                 f", `{environment.get('x2c', 'x2c')}`.")
    lines.append(f"- {environment.get('platform', 'unknown')}, {cpu}, "
                 f"{environment.get('physical_cores', '?')} physical and "
                 f"{environment.get('logical_cores', '?')} logical cores.")
    lines.append(f"- Build lane `{lane.get('lane', 'unknown')}`, prefix "
                 f"`{lane.get('prefix', 'unknown')}`"
                 f"{', handle counters on' if lane.get('counters') else ''}.")
    for name in ("libtorch_cpu.dylib", "libtorch.dylib", "libc10.dylib"):
        entry = libraries.get(name)
        if entry:
            lines.append(f"  - `{name}` {entry['bytes']} bytes, SHA-256 "
                         f"`{entry['sha256'][:16]}`")
    runtime = environment.get("python_runtime", {})
    lines.append(f"- Python at `{runtime.get('executable', '?')}`, "
                 f"torch `{runtime.get('torch', '?')}`.")
    artifacts = environment.get("artifacts", {})
    if artifacts:
        lines.append("- Artifacts, SHA-256 prefixes: " + ", ".join(
            f"`{name} {entry['sha256'][:12]}`"
            for name, entry in sorted(artifacts.items())) + ".")
    lines.append("")


def check_section(check, lines):
    lines.append("## Correctness\n")
    if not check:
        lines.append(missing("correctness results", "check.json"))
        return
    lines.append("One update with every value kept is the decisive check: "
                 "outputs, loss, every gradient, every parameter and buffer "
                 "afterwards, against `atol=1e-6, rtol=1e-4`.\n")
    lines.append("| Lane | Tensors compared after one update | "
                 "Worst absolute | Verdict |")
    lines.append("| --- | --- | --- | --- |")
    for app, data in sorted(check.items()):
        worst = data.get("step1_worst_absolute")
        if worst is None:
            continue
        count = data.get("step1_tensors", "?")
        accepted = data.get("step1_ok")
        verdict = ("not revalidated" if accepted is None else
                   "**failed**" if not accepted else
                   "bit-identical" if worst == 0.0 else "within tolerance")
        lines.append(f"| {app} | {count} | {worst:.3e} | {verdict} |")
    lines.append("")
    for app, data in sorted(check.items()):
        for error in data.get("errors", []):
            lines.append(f"- **{app} failed:** {error}")
    lines.append("")
    lines.append("Task quality and the plan's `1e-3` relative loss "
                 "tolerance:\n")
    lines.append("| Lane | Measure | x2c | Python | Relative | Verdict |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    failures = []
    for app, data in sorted(check.items()):
        for entry in data.get("agreement", []):
            verdict = "ok" if entry["ok"] else "**over tolerance**"
            if not entry["ok"]:
                failures.append((app, entry))
            lines.append(f"| {app} | {entry['name']} | {entry['x2c']:.8g} | "
                         f"{entry['python']:.8g} | {entry['relative']:.2e} | "
                         f"{verdict} |")
    lines.append("")
    if failures:
        lines.append("Failed tolerances, kept as failures rather than "
                     "relaxed:\n")
        for app, entry in failures:
            lines.append(f"- `{app}` `{entry['name']}`: relative "
                         f"{entry['relative']:.2e} against a 1e-3 limit.")
        lines.append("")
    worst_final = {app: data.get("final_worst_absolute")
                   for app, data in check.items()
                   if data.get("final_worst_absolute") is not None}
    if worst_final:
        lines.append("Per-weight equality after the full profile is "
                     "reported, not required; float32 training separates "
                     "from a one-ulp difference. Worst absolute difference "
                     "at the end: " + ", ".join(
                         f"`{app}` {value:.2e}"
                         for app, value in sorted(worst_final.items())) + ".")
        lines.append("")


def timing_section(timing, lines):
    lines.append("## Timing\n")
    if not timing:
        lines.append(missing("timing samples", "timing.json"))
        return
    samples = max(len(row["x2c"]["samples"]) for row in timing)
    lines.append(f"{samples} fresh-process pairs per configuration, "
                 f"alternating which language ran first, medians below. "
                 f"`python/x2c` above 1 means x2c finished first. Spread is "
                 f"(max - min) / median.\n")
    lines.append("| Lane | Threads | Count | x2c median (s) | spread | "
                 "Python median (s) | spread | python/x2c |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for row in timing:
        lines.append(
            f"| {row['app']} {row['variant']} | {row['threads']} | "
            f"{row['count']} | {row['x2c']['median']:.4f} | "
            f"{row['x2c']['spread']:.1%} | {row['python']['median']:.4f} | "
            f"{row['python']['spread']:.1%} | {row['ratio']:.2f}x |")
    lines.append("")
    lines.append("![paired throughput](paired-throughput.png)\n")


def memory_section(memory, lines):
    lines.append("## Memory\n")
    if not memory:
        lines.append(missing("memory samples", "memory.json"))
        return
    lines.append("| Profile | App | Steps | x2c start (MB) | x2c end (MB) "
                 "| x2c peak (MB) | Python peak (MB) | x2c/Python peak |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for row in memory:
        def envelope(language):
            samples = row.get(language, {}).get("samples") or []
            if not samples:
                return 0.0, 0.0, 0.0
            return (samples[0]["footprint"] / 1e6,
                    samples[-1]["footprint"] / 1e6,
                    max(s["footprint_peak"] for s in samples) / 1e6)
        x_start, x_end, x_peak = envelope("x2c")
        _, _, p_peak = envelope("python")
        ratio = f"{x_peak / p_peak:.2f}x" if p_peak else "n/a"
        lines.append(f"| {row['profile']} | {row['app']} | {row['steps']} | "
                     f"{x_start:.1f} | {x_end:.1f} | {x_peak:.1f} | "
                     f"{p_peak:.1f} | {ratio} |")
    lines.append("")

    slope = [row for row in memory
             if row["profile"] == 1 and row["steps"] >= 10000]
    if len(slope) > 1:
        lines.append("Profile 1 at N, 2N, and 4N steps in fresh processes, "
                     "which is the plan's bounded-memory test. The rate is "
                     "measured over the second half of each run, after "
                     "warmup:\n")
        lines.append("| Steps | x2c end (MB) | x2c bytes/1,000 steps | "
                     "Python end (MB) | Python bytes/1,000 steps |")
        lines.append("| --- | --- | --- | --- | --- |")
        for row in slope:
            cells = []
            for language in ("x2c", "python"):
                samples = row.get(language, {}).get("samples") or []
                steps = [s for s in samples if s["label"] == "step"]
                end = samples[-1]["footprint"] / 1e6 if samples else 0.0
                rate = "n/a"
                if len(steps) >= 8:
                    a, b = steps[len(steps) // 2], steps[-1]
                    span = (b["index"] - a["index"]) / 1000.0
                    if span:
                        moved = b["footprint"] - a["footprint"]
                        rate = f"{moved / span:,.0f}"
                cells += [f"{end:.1f}", rate]
            lines.append(f"| {row['steps']} | " + " | ".join(cells) + " |")
        lines.append("")
    lines.append("Owner counts span the measured profile, including model "
                 "and data setup. The final sample precedes the outer Scope "
                 "release; a start-to-end difference alone is not a leak. "
                 "Repeated-step samples establish whether retention grows:\n")
    for row in memory:
        samples = row.get("x2c", {}).get("samples") or []
        if not samples:
            continue
        first, last = samples[0], samples[-1]
        lines.append(f"- Profile {row['profile']}, {row['steps']} steps: "
                     f"live Scope allocations {first['live_allocations']} to "
                     f"{last['live_allocations']}, live scopes "
                     f"{first['live_scopes']} to {last['live_scopes']}, "
                     f"canonical pool {first['pool_active_bytes']} to "
                     f"{last['pool_active_bytes']} bytes.")
    lines.append("")
    lines.append("![memory versus steps](memory-versus-steps.png)\n")


def attribution_section(attribution, lines):
    lines.append("## What the interop cost is made of\n")
    if not attribution:
        lines.append(missing("attribution run", "attribution.json"))
        return
    if not attribution.get("counters"):
        lines.append("_Handle counts are zero: this was not a `--counters` "
                     "build._\n")
    lines.append(
        f"The same chain at {attribution['elements']} elements under three "
        f"lifetimes, one fresh process each, against a C++ control running "
        f"the identical ATen sequence with no wrapper. `natural` is one "
        f"scope per request, `freed` releases each value it replaces, "
        f"`subscope` is one scope per operation carrying only the running "
        f"value. All three produce the same result exactly.\n")
    lines.append("| Lifetime | Ops per request | ns per step | vs C++ | "
                 "Live tensor handles | Peak footprint (MB) |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for row in attribution["rows"]:
        lines.append(f"| {row['shape']} | {row['operations']} | "
                     f"{row['ns_per_step']:.0f} | {row['vs_control']:.2f}x | "
                     f"{row['peak_handles']} | "
                     f"{row['peak_bytes'] / 1e6:.1f} |")
    control = attribution["control_ns_per_step"]
    for ops in sorted(control, key=int):
        lines.append(f"| c++ control | {ops} | {control[ops]:.0f} | 1.00x | "
                     f"n/a | n/a |")
    lines.append("")
    lines.append("![peak against chain length](peak-versus-length.png)\n")


def write(run):
    root = common.ROOT
    directory = os.path.join(root, "debug", "torch-comparison", run)
    if not os.path.isdir(directory):
        sys.exit(f"no run at {directory}")
    lines = [TITLE, "", INTRO]
    comparison = load(directory, "comparison.json") or {}
    optimizer = comparison.get("optimizer", "historical stock")
    lines.append(f"Optimizer comparison: **{optimizer}**.\n")
    if optimizer == "matched":
        lines.append("Python uses an operation-order control for libtorch Adam. "
                     "This session records correctness only.\n")
    else:
        lines.append("Python uses stock PyTorch Adam. Its numerical divergence "
                     "is reported below; failed tolerances remain failures.\n")
        lines.append("[The matched control](MATCHED.md) reports the separate "
                     "libtorch operation-order correctness comparison.\n")
    environment_section(load(directory, "environment.json"), lines)
    check_section(load(directory, "check.json"), lines)
    if optimizer != "matched":
        conditions = load(directory, "host-before-timing.json")
        if conditions:
            lines.append("Measurement conditions: " + conditions["note"] + "\n")
        lines.append("![learning curves](learning-curves.png)\n")
        timing_section(load(directory, "timing.json"), lines)
        memory_section(load(directory, "memory.json"), lines)
        attribution_section(load(directory, "attribution.json"), lines)
    lines.append("## Historical context\n")
    lines.append("[The earlier report](HISTORICAL-20260910.md) retains its "
                 "measurements, failures and analysis. Those observations "
                 "are not results from this session.\n")
    lines.append("## Raw data\n")
    records = "`check.json` and `environment.json`"
    if optimizer != "matched":
        records += ", plus `timing.json`, `memory.json` and `attribution.json`"
    lines.append(f"Every number above comes from "
                 f"`debug/torch-comparison/{run}/`: {records}, beside one log "
                 f"per launched process and the complete checkpoints.\n")
    if optimizer != "matched":
        lines.append(f"Plots read those same files through `plots.py {run}`.\n")
    filename = "MATCHED.md" if optimizer == "matched" else "REPORT.md"
    path = os.path.join(common.BENCHMARKS, filename)
    with open(path, "w") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(write(sys.argv[1] if len(sys.argv) > 1 else "latest"))
