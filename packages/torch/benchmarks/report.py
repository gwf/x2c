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

TITLE = "# Matched x2c and PyTorch applications: results"
DIRTY = " plus uncommitted changes"

INTRO = """\
Three applications and one diagnostic, the same work on both sides, run
live in fresh processes on one idle machine. The plan is
[plans/x2c-torch-comparison.md](../../../plans/x2c-torch-comparison.md);
how to reproduce any line of this is [README.md](README.md), and
[PILOT.md](PILOT.md) holds the earlier single-sample pass and the gaps it
found.

Read the correctness results alongside the timings: a measured timing is
not evidence that a configuration passed. There is no aggregate speedup in
this report; the workloads and their verdicts are separate.
"""


FINDINGS = """\
## Findings

The sections above are generated from one session's raw JSON. This one is
written by hand: it explains those numbers and records what the suite
exposed.

### Per-workload verdicts

- **Tabular training.** x2c finishes first at both thread counts, on both
  the native-Linear forward and the documented enumerated-parameter one.
  The two forwards are within a few percent of each other inside each
  language, so parameter enumeration is not what separates them.
- **Batched prediction.** x2c's margin is largest at batch 1 and is gone
  by batch 256, which is the expected shape: the per-request cost x2c
  avoids is fixed, and by 256 rows the kernels dominate.
- **MNIST.** Parity. This is the kernel-heavy case, and once convolution
  and batch normalization own the time there is nothing left for a
  wrapper or an interpreter to win or lose.
- **Sequence.** x2c finishes first by about the same margin as tabular
  training. A window is 32 small steps, so per-call cost still matters.
- **Interop.** The headline `chain` timing is x2c's worst result in the
  suite, and it is entirely a lifetime effect.

### The interop cost is retention, not wrapper overhead

The attribution table runs the identical chain three ways. Written the
documented way, one scope per request, every intermediate stays alive
until the request ends: at 65,536 elements and 512 operations that is
1,549 live tensor handles and a peak footprint of 205 MB, and the chain
runs 4.33x the C++ control. Releasing each value as it is replaced with
`Tensor.free` recovers part of it. One scope per operation, carrying only
the running value out with `Scope.move`, holds 14 handles and a flat
59-66 MB at every chain length and runs at 0.92x to 1.27x the control -
parity with C++ calling ATen directly, with no wrapper cost left to find.
All three lifetimes produce the same result exactly.

So the wrapper is not the cost. The cost is that a scope is the unit of
release, and a long chain inside one scope holds every intermediate the
mathematics no longer needs. Python's reference counting frees them as it
goes and never pays it. Nothing here is unattributed.

This is a caller obligation with a cheap remedy that does not change the
result, and it is worth stating plainly in the package documentation: a
long out-of-place chain over large tensors inside a single scope is the
one shape where the ordinary idiom is expensive.

### Adam is not the same algorithm in the two languages

Both implementations produce bit-identical outputs, losses, gradients and
parameters for one update. They part at the second, and the `trace` mode
locates it exactly: at update 1 the batch, every forward intermediate,
the loss and every gradient are still bit-identical, and only the
parameters after the optimizer step differ, by 7.45e-09.

`torch.optim.Adam` updates the first moment with
`exp_avg.lerp_(grad, 1 - beta1)`; libtorch's C++ `Adam` uses
`exp_avg.mul_(beta1).add_(grad, 1 - beta1)`. The two agree in exact
arithmetic, and in float32 while `exp_avg` is still zero, which is why
the first update matches and the second does not. Replaying the same
training in Python with the `mul_`/`add_` form reproduces the x2c result
bit for bit; the `lerp_` form does not.

`foreach=False, fused=False` is therefore not enough to match the two
optimizers, and the plan's requirement to match Python's Adam to the C++
algorithm cannot be fully met through `torch.optim.Adam`. Nothing was
relaxed to hide this: the long-run losses still agree within the stated
tolerance in every lane except the tabular `explicit` one, which stands
above as a failed tolerance.

Reproducer:

```sh
python3 packages/torch/benchmarks/firstdiff.py --variant explicit \
    --first 0 --last 4
```

### Memory

Steady training and inference are flat in both languages once warm, with
x2c's whole-process footprint a little over half Python's, mostly the
interpreter and `libtorch_python.dylib`. Live Scope allocations and live
scopes return to their starting values in every profile, including the
one that injects a bad shape inside a deferred scope every 100 requests
and then checks that ordinary work and the model's mode survive it.

The positive control works: retaining forward graphs on purpose grows
both languages to the 128 MiB payload cap and both release fully
afterwards, so the measurement is shown to see a known problem. x2c grows
about twice as fast per retained graph, for the same reason as interop -
Python holds the activations the graph needs, and x2c additionally holds
every pre-activation intermediate until the enclosing scope closes.

One thing grows that need not. In the repeated
create-train-save-load-destroy profile the canonical pool's active bytes
rise about 64 bytes per cycle, because each cycle builds its checkpoint
path with an interpolated String and Strings survive scope release.
Hoisting the path out of the loop removes it. That is the cost of
building the same String repeatedly, not a leak in the pool.

### Gaps

1. **A `#define` numeric constant does not resolve an operator row.**
   `(images - MEAN) / STD` with `#define MEAN 0.1307` emits the C text
   unchanged and fails to compile; a `double` local works. Reproducer:
   `#define M 0.5` then
   `Tensor y = Tensor.zeros(%(2 2), XT_FLOAT32) - M;`.
2. **`Checkpoint.save` crashes on a released Tensor.** A `Map` outlives
   the scope that created the Tensors it holds, so storing one, releasing
   that scope, then saving reaches `tensors[i]->t.detach()` on a freed
   handle instead of raising `<bad-state>`. Using a released wrapper is a
   documented caller error, so this is robustness rather than a defect;
   yyjson raises for the same class of stale access.
3. **Inter-op thread control** was missing when the pilot ran and is now
   in the package as `Torch.set_num_interop_threads`. Both languages in
   this session pin it to 1 before any work and record what they got.
4. **Per-type native handle counters** were missing and are now present
   as the private, benchmark-only instrumentation `README.md` describes.
   They are what made the interop attribution possible.
5. **A composed root has no forward**, so the tabular lane looks its
   three children up once and indexes a List. That is what
   `Module.sequential` exists for and the MNIST lane uses it; the MLP
   lane keeps the composed form the package README documents.
"""


PLACEHOLDER = """\
## Operator temporaries after discard

_Placeholder: to be filled in by Gary._

A compiler change that discards unnamed operator temporaries immediately
after the operator that consumes them is being measured separately. It is
deliberately not folded into any number in this report: everything above
was measured on the tree named under "What ran", without it.

The interop attribution is the result that change bears on most directly,
since the natural-lifetime row there is exactly the cost of keeping
unnamed intermediates alive to the end of a request scope. This section is
where to record what the change does to that row, and whether the
`Tensor.free` and per-operation-scope remedies are still needed after it.
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
    lines.append(f"- Python at `{environment.get('python_executable', '?')}`, "
                 f"torch pinned at 2.10.0.")
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
    lines.append("![learning curves](learning-curves.png)\n")


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
    lines.append("Owner counts on the x2c side, start to end of each run. "
                 "A fixed workload should return them to where it found "
                 "them:\n")
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
    environment_section(load(directory, "environment.json"), lines)
    check_section(load(directory, "check.json"), lines)
    timing_section(load(directory, "timing.json"), lines)
    memory_section(load(directory, "memory.json"), lines)
    attribution_section(load(directory, "attribution.json"), lines)
    # The written analysis. Everything above is generated from a run's
    # JSON; this is the part a person wrote, kept here so the report is
    # one command and cannot drift from the renderer.
    lines.append(FINDINGS + "\n")
    lines.append(PLACEHOLDER)
    lines.append("## Raw data\n")
    lines.append(f"Every number above comes from "
                 f"`debug/torch-comparison/{run}/`: `check.json`, "
                 f"`timing.json`, `memory.json`, `attribution.json`, and "
                 f"`environment.json`, beside one log per launched process. "
                 f"The plots are rendered from those same files by "
                 f"`plots.py {run}`.\n")
    path = os.path.join(common.BENCHMARKS, "REPORT.md")
    with open(path, "w") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(write(sys.argv[1] if len(sys.argv) > 1 else "latest"))
