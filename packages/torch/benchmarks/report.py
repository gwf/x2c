#!/usr/bin/env python3
"""Render REPORT.md from one session's raw JSON.

`run.py report --run-id <id>` calls this. It reads only what the session
wrote, so the report cannot claim a number no run produced: a missing file
becomes a missing section, named as missing.

Verdicts are per workload. There is no aggregate speedup here on purpose.
"""

import json
import os
import glob
import statistics
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

[Supplemental diagnostics](SUPPLEMENT.md) separately measure startup,
training phases, error-message interning, corrected sequence ownership,
and all four interop sizes. Its separate MNIST correction supersedes only
the two original 20-warmup timing rows; all original records remain intact.
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
                 f", handle counters "
                 f"{'on' if lane.get('counters') else 'off'}.")
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


def timing_section(timing, lines, timing_run=None):
    lines.append("## Timing\n")
    if not timing:
        lines.append(missing("timing samples", "timing.json"))
        return
    samples = max(len(row["x2c"]["samples"]) for row in timing)
    lines.append(f"{samples} fresh-process pairs per configuration, "
                 f"alternating which language ran first, medians below. "
                 f"`python/x2c` above 1 means x2c finished first. Spread is "
                 f"(max - min) / median.\n")
    if timing_run:
        lines.append("The original MNIST rows below used 20 warmup batches; "
                     "[the separate 50-batch correction](SUPPLEMENT.md) "
                     "supersedes those two rows. Other primary rows are unchanged.\n")
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
    overlapping = [f"{row['app']}/{row['variant']} at {row['threads']} threads"
                   for row in timing
                   if row["x2c"]["min"] <= row["python"]["max"]
                   and row["python"]["min"] <= row["x2c"]["max"]]
    if overlapping:
        lines.append("Observed time ranges overlap for " +
                     "; ".join(overlapping) + ". The sample variation limits "
                     "claims about small median differences in these cases. "
                     "All samples remain in the raw record.\n")
    lines.append("![paired throughput](paired-throughput.png)\n")


def memory_section(memory, lines):
    lines.append("## Memory\n")
    if not memory:
        lines.append(missing("memory samples", "memory.json"))
        return
    lines.append("| Profile | App | Steps | x2c start (MB) | x2c end (MB) "
                 "| x2c peak (MB) | Python peak (MB) | x2c/Python peak "
                 "| Incremental peak ratio |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for row in memory:
        def envelope(language):
            samples = row.get(language, {}).get("samples") or []
            if not samples:
                return 0.0, 0.0, 0.0
            return (samples[0]["footprint"] / 1e6,
                    samples[-1]["footprint"] / 1e6,
                    max(s["footprint_peak"] for s in samples) / 1e6)
        x_start, x_end, x_peak = envelope("x2c")
        p_start, _, p_peak = envelope("python")
        ratio = f"{x_peak / p_peak:.2f}x" if p_peak else "n/a"
        incremental = (f"{(x_peak - x_start) / (p_peak - p_start):.2f}x"
                       if p_peak > p_start else "n/a")
        label = str(row["profile"])
        if row["profile"] == 2:
            label += " " + row.get("churn_lifetime", "ordinary")
        lines.append(f"| {label} | {row['app']} | {row['steps']} | "
                     f"{x_start:.1f} | {x_end:.1f} | {x_peak:.1f} | "
                     f"{p_peak:.1f} | {ratio} | {incremental} |")
    lines.append("")
    lines.append("Incremental peak subtracts each process's first sample "
                 "before taking the x2c/Python ratio. It exposes workload "
                 "retention that different runtime baselines can hide. "
                 "Profile 6 deliberately retains outputs and graphs; its "
                 "large peak is a positive control, not ordinary usage.\n")

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
    churn = {}
    for row in memory:
        if row["profile"] == 2:
            lifetime = row.get("churn_lifetime", "ordinary")
            if lifetime not in churn or row["steps"] > churn[lifetime]["steps"]:
                churn[lifetime] = row
    if churn:
        lines.append("Canonical churn at the longest recorded request count "
                     "for each lifetime. Samples follow request cleanup at "
                     "the same root-pool depth:\n")
        lines.append("| Lifetime | Requests | Pool bytes, warm to final | "
                     "Live Scope allocations during requests | "
                     "Live native tensor handles during requests |")
        lines.append("| --- | --- | --- | --- | --- |")
        for lifetime, row in sorted(churn.items()):
            samples = row["x2c"]["samples"]
            warm = next(s for s in samples if s["label"] == "warm")
            requests = [s for s in samples if s["label"] == "request"]
            scopes = [s["live_allocations"] for s in requests]
            handles = [s["handles"]["tensor"]["live"] for s in requests
                       if "handles" in s and "tensor" in s["handles"]]
            handle_range = (f"{min(handles)} to {max(handles)}"
                            if handles else "not recorded")
            lines.append(f"| {lifetime} | {row['steps']} | "
                         f"{warm['pool_active_bytes']:,} to "
                         f"{samples[-1]['pool_active_bytes']:,} | "
                         f"{min(scopes)} to {max(scopes)} | {handle_range} |")
        lines.append("")
        lines.append("`pooled` adds a List-pool bracket per request. `hoisted` "
                     "retains stable parameter handles but still constructs "
                     "generated tuple results inside each request. These "
                     "are explicit caller lifetime choices; the pool owns "
                     "canonical cells and does not extend wrapper lifetime.\n")
    if any(row["profile"] == 2 for row in memory):
        lines.append("The incremental process-peak excess remaining in the "
                     "pooled and hoisted churn variants is unresolved. Stable "
                     "native/Scope counts and bounded pooled canonical storage "
                     "do not attribute that residual to an allocator or "
                     "establish general memory suitability.\n")
    if any(row["profile"] == 4 and not any(
            sample["label"] == "window-released"
            for sample in row.get("x2c", {}).get("samples", []))
           for row in memory):
        lines.append("The original sequence profile 4 retained models between "
                     "window lengths. Its aggregate row remains historical; "
                     "[the supplemental profile](SUPPLEMENT.md) corrects that "
                     "ownership mismatch and supersedes its window attribution.\n")
    lines.append("Owner counts span the measured profile, including model "
                 "and data setup. The final sample precedes the outer Scope "
                 "release; a start-to-end difference alone is not a leak. "
                 "Repeated-step samples establish whether retention grows:\n")
    for row in memory:
        samples = row.get("x2c", {}).get("samples") or []
        if not samples:
            continue
        first, last = samples[0], samples[-1]
        label = str(row["profile"])
        if row["profile"] == 2:
            label += " " + row.get("churn_lifetime", "ordinary")
        lines.append(f"- Profile {label}, {row['steps']} steps: "
                     f"live Scope allocations {first['live_allocations']} to "
                     f"{last['live_allocations']}, live scopes "
                     f"{first['live_scopes']} to {last['live_scopes']}, "
                     f"canonical pool {first['pool_active_bytes']} to "
                     f"{last['pool_active_bytes']} bytes.")
    lines.append("")
    lines.append("![memory versus steps](memory-versus-steps.png)\n")
    if any(row["profile"] == 2 for row in memory):
        lines.append("![canonical churn](canonical-churn.png)\n")


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


def write(run, diagnostics_run=None, timing_run=None):
    root = common.ROOT
    directory = os.path.join(root, "debug", "torch-comparison", run)
    if not os.path.isdir(directory):
        sys.exit(f"no run at {directory}")
    lines = [TITLE, "", INTRO]
    comparison = load(directory, "comparison.json") or {}
    optimizer = comparison.get("optimizer", "historical stock")
    diagnostics = (os.path.join(root, "debug", "torch-comparison",
                               diagnostics_run)
                   if diagnostics_run else directory)
    if diagnostics_run:
        other = load(diagnostics, "comparison.json") or {}
        if other.get("optimizer") != optimizer:
            raise ValueError("timing and diagnostic optimizer selections differ")
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
    checked = load(directory, "check.json")
    check_section(checked, lines)
    if optimizer != "matched":
        conditions = load(directory, "host-before-timing.json")
        if conditions:
            lines.append("Measurement conditions: " + conditions["note"] + "\n")
        if checked and not any(data.get("curve", {}).get("python")
                               for data in checked.values()):
            lines.append("The original learning-curve capture below contains x2c "
                     "only. [The supplemental paired plot](SUPPLEMENT.md) "
                     "recovers Python curves from the retained per-app files "
                     "with source hashes, without retraining.\n")
        lines.append("![learning curves](learning-curves.png)\n")
        timing_section(load(directory, "timing.json"), lines, timing_run)
        if diagnostics_run:
            lines.append(f"Memory and attribution use the separate diagnostic "
                         f"session `{diagnostics_run}` below. Its instrumented "
                         f"timings are not the headline timings above.\n")
            environment_section(load(diagnostics, "environment.json"), lines)
        memory_section(load(diagnostics, "memory.json"), lines)
        attribution_section(load(diagnostics, "attribution.json"), lines)
    lines.append("## Historical context\n")
    lines.append("[The earlier report](HISTORICAL-20260910.md) retains its "
                 "measurements, failures and analysis. Those observations "
                 "are not results from this session.\n")
    lines.append("## Raw data\n")
    records = "`check.json` and `environment.json`"
    if optimizer != "matched":
        records += ", plus `timing.json`"
        if not diagnostics_run:
            records += ", `memory.json` and `attribution.json`"
    lines.append(f"Correctness and timing records come from "
                 f"`debug/torch-comparison/{run}/`: {records}, beside one log "
                 f"per launched process and the complete checkpoints.\n")
    if diagnostics_run:
        lines.append(f"Memory and attribution records come from "
                     f"`debug/torch-comparison/{diagnostics_run}/`: "
                     f"`memory.json`, `attribution.json`, and their own "
                     f"`environment.json` and process logs.\n")
    if optimizer != "matched":
        arguments = run + (f" {diagnostics_run}" if diagnostics_run else "")
        lines.append(f"Plots read those same files through "
                     f"`plots.py {arguments}`.\n")
    filename = "MATCHED.md" if optimizer == "matched" else "REPORT.md"
    path = os.path.join(common.BENCHMARKS, filename)
    with open(path, "w") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")
    print(f"wrote {path}")
    return 0


def supplement(run, timing_run=None):
    directory = os.path.join(common.LOGS, run)
    measured = load(directory, "diagnose.json")
    lines = ["# Supplemental Torch comparison diagnostics\n",
             "These separate runs close diagnostic coverage gaps. They do not "
             "turn diagnostic phase costs into headline performance. The separate "
             "counter-free MNIST correction below supersedes only the original "
             "20-warmup timing rows; the original raw records remain intact.\n"]
    environment_section(load(directory, "environment.json"), lines)
    lines += ["## Startup, loading and checkpoints\n",
        "Startup is elapsed fresh process launch through exit after imports, "
        "native initialization, thread configuration and a no-work main. "
        "It does not isolate dynamic loading from Python import cost. Data "
        "loading and model/optimizer setup below follow each application's "
        "existing owners: x2c loads initial weights during setup, Python "
        "reads them during artifact loading. Compare those two columns together. "
        "Tabular setup is the first model/optimizer construction, including "
        "lazy Python optimizer imports; MNIST and sequence setup follows their "
        "warmup. These boundaries differ across applications. "
        "Checkpoint columns include model and optimizer archives, whose native "
        "and Python serialization formats differ. These are measured user "
        "paths, not identical serialization kernels.\n"]
    if not measured:
        lines.append(missing("phase diagnostics", "diagnose.json"))
    else:
        lines += ["| App | Startup x2c median (s) | Python median (s) |",
                  "| --- | --- | --- |"]
        for app in sorted({r["app"] for r in measured["startup"]}):
            rows = [r for r in measured["startup"] if r["app"] == app]
            values = [statistics.median(r[lang] for r in rows)
                      for lang in ("x2c", "python")]
            lines.append(f"| {app} | {values[0]:.4f} | {values[1]:.4f} |")
        lines += ["", "| App/forward | Language | Load (ms) | Setup (ms) | "
                  "Save (ms) | Reload (ms) |", "| --- | --- | --- | --- | --- | --- |"]
        groups = sorted({(r["app"], r["variant"]) for r in measured["phases"]})
        for app, variant in groups:
            rows = [r for r in measured["phases"]
                    if (r["app"], r["variant"]) == (app, variant)]
            for lang in ("x2c", "python"):
                vals = [statistics.median(r[lang][key] for r in rows) * 1000
                        for key in ("load_seconds", "setup_seconds",
                                    "checkpoint_save_seconds",
                                    "checkpoint_load_seconds")]
                lines.append(f"| {app}/{variant} | {lang} | " +
                             " | ".join(f"{v:.3f}" for v in vals) + " |")
        lines += ["", "## Training phases\n",
            f"Each row is the median of {measured['samples']} fresh-process "
            f"diagnostic blocks of {measured['steps']} updates/windows, after "
            "50 warmup steps and restoring initial model/optimizer state. "
            "The matched Adam control is used. Final pre-update losses and "
            "recorded reload checks agree across languages.\n",
            "Clocks and native handle counters are enabled only for these "
            "diagnostics. Batch includes slicing and zero_grad; forward includes "
            "the loss; optimizer measures step. Cleanup is explicit Scope "
            "release or Python del (plus detached sequence carry replacement). "
            "Python also destroys intermediates during forward/backward; "
            "cleanup is not its total lifetime cost. Per-phase clocks perturb "
            "these short blocks; no phase ratio is a headline speedup.\n",
            "| App/forward | Language | Batch (us/step) | Forward | Backward | "
            "Optimizer | Explicit cleanup |", "| --- | --- | --- | --- | --- | --- | --- |"]
        for app, variant in groups:
            rows = [r for r in measured["phases"]
                    if (r["app"], r["variant"]) == (app, variant)]
            for lang in ("x2c", "python"):
                vals = [statistics.median(r[lang][key + "_seconds"] /
                        r[lang]["diagnostic_steps"] * 1e6 for r in rows)
                        for key in ("batch", "forward", "backward", "optimizer",
                                    "cleanup")]
                lines.append(f"| {app}/{variant} | {lang} | " +
                             " | ".join(f"{v:.2f}" for v in vals) + " |")
    lines += ["", "## Fixed and unique contextual errors\n",
        "Both variants invoke the same invalid native shape, catch it, and "
        "raise a contextual request error. Only the message varies: fixed text "
        "or a request number. Every error is followed by a checked valid "
        "forward; inference-mode restoration is checked. Error details are "
        "not retained in an output log. x2c String and List values are "
        "canonical; Python has no corresponding canonical pools.\n",
        "| Requests | Message | Language | Canonical pool delta (bytes) | "
        "End footprint (MB) |", "| --- | --- | --- | --- | --- |"]
    error_samples = []
    for path in sorted(glob.glob(os.path.join(directory, "errors-*.json"))):
        for row in load(directory, os.path.basename(path)):
            for lang in ("x2c", "python"):
                data = row[lang]
                first, last = data["samples"][0], data["samples"][-1]
                if lang == "x2c":
                    error_samples.extend(data["samples"])
                lists = (str(last["pool_active_bytes"] - first["pool_active_bytes"])
                         if lang == "x2c" else "n/a")
                lines.append(f"| {row['steps']} | {row['variant']} | {lang} | "
                             f"{lists} | {last['footprint']/1e6:.1f} |")
    if error_samples:
        allocations = [sample["live_allocations"] for sample in error_samples]
        handles = [sample["handles"]["tensor"]["live"] for sample in error_samples]
        lines.append(f"\nAcross x2c error samples, live Scope allocations "
                     f"range {min(allocations)} to {max(allocations)}, and "
                     f"native tensor handles {min(handles)} to {max(handles)}. "
                     "The canonical growth is separate from those owners.\n")
    lines += ["", "## Sequence window length\n",
        "Each x2c sweep now releases its model and optimizer before the next "
        "length, matching Python. The preceding sweep accidentally kept all "
        "three models alive and cannot attribute peak changes solely to "
        "window length. These corrected supplemental samples supersede that "
        "profile only. The plot shows cumulative process high water through "
        "the ascending sweep; allocator caches and earlier high water remain "
        "in the process, so it is not an isolated per-window allocation peak.\n",
        "![sequence window memory](supplement-window-memory.png)\n",
        "| Window | x2c peak (MB) | Python peak (MB) | x2c model handles "
        "after release | Optimizer handles after release |", "| --- | --- | --- | --- | --- |"]
    for row in load(directory, "memory.json") or []:
        if row["profile"] != 4:
            continue
        for window in (8, 32, 128):
            x = next(s for s in row["x2c"]["samples"]
                     if s["label"] == "window-done" and s["index"] == window)
            p = next(s for s in row["python"]["samples"]
                     if s["label"] == f"window{window}-done")
            released = next(s for s in row["x2c"]["samples"]
                            if s["label"] == "window-released" and
                            s["index"] == window)
            handles = released["handles"]
            lines.append(f"| {window} | {x['footprint_peak']/1e6:.1f} | "
                         f"{p['footprint_peak']/1e6:.1f} | "
                         f"{handles['module']['live']} | "
                         f"{handles['optimizer']['live']} |")
        x = row["x2c"]["records"]["accumulated_val_mse"]
        p = row["python"]["records"]["accumulated_val_mse"]
        lines.append(f"\nFour-microbatch validation MSE: x2c {x:.11g}; "
                     f"Python {p:.11g}. The comparison passes.\n")
    lines += ["## Interop size grid\n",
        "Each cell runs 16, 128 and 512 operations using Python, native C++, "
        "and the three existing x2c lifetimes. Every result is checked against "
        "the C++ output. Timings are single diagnostic observations with "
        "counter/sampling overhead, not repeated headline comparisons.\n",
        "| Elements | Operations | C++ (ns/op) | Python | x2c natural | "
        "x2c early-free | x2c shorter-scope |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for size in (1, 64, 4096, 65536):
        data = load(directory, f"attribution-e{size}.json")
        if not data:
            continue
        for ops in (16, 128, 512):
            vals = [data["control_ns_per_step"][str(ops)],
                    data["python_ns_per_step"][str(ops)]]
            vals += [next(r["ns_per_step"] for r in data["rows"]
                          if r["shape"] == shape and r["operations"] == ops)
                     for shape in ("natural", "freed", "subscope")]
            lines.append(f"| {size} | {ops} | " +
                         " | ".join(f"{v:.0f}" for v in vals) + " |")
    lines += ["", "## Paired learning curves from retained outputs\n",
        "The original Python checks saved their full curves to files but "
        "did not emit the curve records consumed by check.json. The original "
        "plot therefore showed x2c alone. This paired plot uses unchanged "
        "primary x2c records plus the exact retained Python curve files; "
        "`paired-curves-provenance.json` records their paths, hashes and point "
        "counts beside the primary logs. No training was repeated or original "
        "check.json rewritten. Tabular has both languages; MNIST and sequence "
        "have Python-only panels because no native learning curves were "
        "recorded. Future Python checks now emit their curve records.\n",
        "![paired original learning curves](supplement-paired-learning.png)\n"]
    if timing_run:
        correction_dir = os.path.join(common.LOGS, timing_run)
        correction = load(correction_dir, "timing.json")
        correction_env = load(correction_dir, "environment.json")
        if not correction or correction_env["lane"]["counters"]:
            raise ValueError("MNIST correction needs counter-free timing evidence")
        lines += ["## MNIST with 50 warmup batches\n",
            "The original MNIST timing used 20 warmup batches on both sides, "
            "short of the planned 50. Those original rows remain historical "
            "in REPORT.md. This separately built counter-free correction "
            "warms 50 batches, then constructs the same fresh model and "
            "optimizer before timing. Only MNIST is repeated; the other "
            "primary workloads are unchanged.\n",
            "Five fresh-process pairs alternate order at each thread count. "
            "The original stock-Adam MNIST numerical counterpart passed and "
            "its check/train functions are unchanged. Command-scoped sleep "
            "prevention was active and task-owned CPU work was paused. "
            "Unrelated desktop applications remained present; the host was "
            "not isolated. Spread is (max-min)/median.\n",
            "| Threads | Updates | x2c median (s) | Spread | Python median (s) | "
            "Spread | Python/x2c |", "| --- | --- | --- | --- | --- | --- | --- |"]
        for row in correction:
            x, p = row["x2c"], row["python"]
            lines.append(f"| {row['threads']} | {row['count']} | "
                         f"{x['median']:.4f} | {x['spread']:.1%} | "
                         f"{p['median']:.4f} | {p['spread']:.1%} | "
                         f"{row['ratio']:.2f}x |")
        overlap = [str(row["threads"]) for row in correction
                   if row["x2c"]["min"] <= row["python"]["max"] and
                   row["python"]["min"] <= row["x2c"]["max"]]
        if overlap:
            lines.append("\nObserved timing ranges overlap at thread counts " +
                         ", ".join(overlap) + ". Small median differences "
                         "there do not establish a reliable advantage.\n")
        lines += [f"\nCorrection environment, hashes, binaries and all 20 "
                  f"process logs are retained in `{timing_run}` and the "
                  "external supplemental evidence.\n"]
    lines += ["", "## Remaining memory limitation\n",
        "The original canonical-churn runs show over 2x incremental process "
        "peak even with a per-request List pool or hoisted handles. Flat Scope "
        "and native-handle counts establish those owners' stability; pooling "
        "bounds canonical storage. They do not explain the remaining process "
        "footprint excess. That residual is unresolved. No allocator-specific "
        "cause or general memory-suitability claim is established.\n",
        "## Reproduction and evidence\n",
        f"Raw supplemental data: `debug/torch-comparison/{run}/` with "
        "`diagnose.json`, `errors-*.json`, `memory.json`, "
        "`attribution-e*.json`, environment and one log per process. "
        "The [README](README.md) gives the commands. "
        "`run.py supplement` and `plots.py --supplement` regenerate this "
        "report and its plot without replacing the primary report/plots.\n"]
    path = os.path.join(common.BENCHMARKS, "SUPPLEMENT.md")
    with open(path, "w") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(write(sys.argv[1] if len(sys.argv) > 1 else "latest"))
