#!/usr/bin/env python3
"""Render the report's standalone plots from the recorded raw JSON.

Needs matplotlib, which the pinned torch wheel's interpreter does not
have; run it under an interpreter that does. It reads only the JSON the
runner wrote, never a benchmark process, so it can run any time after a
session.

    python3 packages/torch/benchmarks/plots.py <run-id> [diagnostics-run-id]

Writes learning-curves.png, paired-throughput.png, memory-versus-steps.png,
canonical-churn.png and peak-versus-length.png beside REPORT.md.
"""

import json
import hashlib
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator, StrMethodFormatter

X2C = "#1f5c8b"
PYTHON = "#c2571a"
CONTROL = "#4a4a4a"


def load(directory, name):
    path = os.path.join(directory, name)
    if not os.path.exists(path):
        return None
    with open(path) as handle:
        return json.load(handle)


def finish(figure, axes, path, title, xlabel, ylabel):
    axes.set_title(title, loc="left", fontsize=11)
    axes.set_xlabel(xlabel, fontsize=9)
    axes.set_ylabel(ylabel, fontsize=9)
    axes.spines["top"].set_visible(False)
    axes.spines["right"].set_visible(False)
    axes.grid(axis="y", color="#dddddd", linewidth=0.6)
    axes.set_axisbelow(True)
    figure.tight_layout()
    figure.savefig(path, dpi=144)
    plt.close(figure)
    print(f"wrote {path}")


def learning_curves(directory, check, filename="learning-curves.png"):
    curves = {app: data["curve"] for app, data in check.items()
              if any(data.get("curve", {}).values())}
    if not curves:
        return
    figure, axes = plt.subplots(1, len(curves), figsize=(5 * len(curves), 3.4),
                                squeeze=False)
    for column, (app, pair) in enumerate(sorted(curves.items())):
        cell = axes[0][column]
        for language, colour in (("x2c", X2C), ("python", PYTHON)):
            points = pair.get(language) or []
            if not points:
                continue
            cell.plot([p[0] for p in points], [p[1] for p in points],
                      color=colour, linewidth=1.6, label=language)
        cell.set_yscale("log")
        present = [name for name, points in pair.items() if points]
        title = app if len(present) > 1 else f"{app} ({present[0]} only)"
        cell.set_title(title, loc="left", fontsize=11)
        cell.set_xlabel("update", fontsize=9)
        cell.set_ylabel("training loss", fontsize=9)
        cell.spines["top"].set_visible(False)
        cell.spines["right"].set_visible(False)
        cell.grid(axis="y", color="#dddddd", linewidth=0.6)
        cell.set_axisbelow(True)
        cell.legend(frameon=False, fontsize=9)
    figure.tight_layout()
    path = os.path.join(directory, filename)
    figure.savefig(path, dpi=144)
    plt.close(figure)
    print(f"wrote {path}")


def paired_throughput(directory, timing):
    if not timing:
        return
    rows = [r for r in timing if r["threads"] == 1]
    if not rows:
        rows = timing
    labels = [f"{r['app']}\n{r['variant']}" for r in rows]
    ratios = [r["ratio"] for r in rows]
    low = [r["ratio"] - r["python"]["min"] / r["x2c"]["max"] for r in rows]
    high = [r["python"]["max"] / r["x2c"]["min"] - r["ratio"] for r in rows]
    spread = [low, high]
    figure, axes = plt.subplots(figsize=(1.15 * len(rows) + 2, 3.8))
    positions = range(len(rows))
    axes.bar(positions, ratios, color=[X2C if v >= 1 else PYTHON
                                       for v in ratios], width=0.62)
    axes.errorbar(positions, ratios, yerr=spread, fmt="none",
                  ecolor=CONTROL, elinewidth=1, capsize=3)
    axes.axhline(1.0, color=CONTROL, linewidth=1)
    axes.set_xticks(list(positions))
    axes.set_xticklabels(labels, fontsize=8)
    for position, value in zip(positions, ratios):
        axes.text(position, value, f"{value:.2f}x", ha="center",
                  va="bottom", fontsize=8)
    finish(figure, axes, os.path.join(directory, "paired-throughput.png"),
           "Python time over x2c time, one intra-op thread "
           "(above 1.0 means x2c finished first)",
           "", "python / x2c")


def memory_versus_steps(directory, memory):
    candidates = [r for r in (memory or []) if r["profile"] in (1, 5, 6)]
    if not candidates:
        return
    # Profile 1 is run at N, 2N, and 4N; the longest one carries the slope.
    rows, seen = [], {}
    for row in candidates:
        keep = seen.get(row["profile"])
        if keep is None or row["steps"] > keep["steps"]:
            seen[row["profile"]] = row
    rows = [seen[key] for key in sorted(seen)]
    figure, axes = plt.subplots(1, len(rows), figsize=(4.6 * len(rows), 3.4),
                                squeeze=False)
    for column, row in enumerate(rows):
        cell = axes[0][column]
        for language, colour in (("x2c", X2C), ("python", PYTHON)):
            samples = row.get(language, {}).get("samples") or []
            counted = [s for s in samples
                       if s["label"] in ("step", "request", "cycle",
                                         "retained")]
            if not counted:
                continue
            positions = [s["index"] + (row["steps"] if row["profile"] == 1
                                      and s["label"] == "request" else 0)
                         for s in counted]
            cell.plot(positions,
                      [s["footprint"] / 1e6 for s in counted],
                      color=colour, linewidth=1.6, marker="o",
                      markersize=2.5, label=language)
        cell.set_title(f"profile {row['profile']} ({row['app']}), "
                       f"{row['steps']} steps", loc="left", fontsize=11)
        cell.set_xlabel("training steps + requests" if row["profile"] == 1
                        else "steps completed", fontsize=9)
        cell.xaxis.set_major_locator(MaxNLocator(4, integer=True))
        cell.xaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}"))
        cell.set_ylabel("process footprint (MB)", fontsize=9)
        cell.set_ylim(bottom=0)
        cell.spines["top"].set_visible(False)
        cell.spines["right"].set_visible(False)
        cell.grid(axis="y", color="#dddddd", linewidth=0.6)
        cell.set_axisbelow(True)
        cell.legend(frameon=False, fontsize=9)
    figure.tight_layout()
    path = os.path.join(directory, "memory-versus-steps.png")
    figure.savefig(path, dpi=144)
    plt.close(figure)
    print(f"wrote {path}")


def canonical_churn(directory, memory):
    rows = {}
    for row in memory or []:
        if row["profile"] != 2:
            continue
        lifetime = row.get("churn_lifetime", "ordinary")
        if lifetime not in rows or row["steps"] > rows[lifetime]["steps"]:
            rows[lifetime] = row
    if not rows:
        return
    figure, axes = plt.subplots(1, 2, figsize=(10.5, 3.6))
    colours = {"ordinary": PYTHON, "pooled": X2C, "hoisted": "#8a7a12"}
    for lifetime, row in sorted(rows.items()):
        samples = [s for s in row["x2c"]["samples"]
                   if s["label"] == "request"]
        for cell, key in zip(axes, ("pool_active_bytes", "footprint")):
            cell.plot([s["index"] for s in samples],
                      [s[key] / 1e6 for s in samples],
                      color=colours.get(lifetime, CONTROL), label=lifetime)
    for cell, title, ylabel in (
            (axes[0], "Canonical storage after request cleanup", "pool MB"),
            (axes[1], "x2c process footprint", "process MB")):
        cell.set_title(title, loc="left", fontsize=11)
        cell.set_xlabel("requests completed", fontsize=9)
        cell.xaxis.set_major_locator(MaxNLocator(4, integer=True))
        cell.xaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}"))
        cell.set_ylabel(ylabel, fontsize=9)
        cell.spines["top"].set_visible(False)
        cell.spines["right"].set_visible(False)
        cell.grid(axis="y", color="#dddddd", linewidth=0.6)
        cell.legend(frameon=False, fontsize=9)
    figure.tight_layout()
    path = os.path.join(directory, "canonical-churn.png")
    figure.savefig(path, dpi=144)
    plt.close(figure)
    print(f"wrote {path}")


def peak_versus_length(directory, attribution, memory):
    if not attribution:
        return
    shapes = {}
    for row in attribution["rows"]:
        shapes.setdefault(row["shape"], []).append(row)
    figure, axes = plt.subplots(1, 2, figsize=(10.5, 3.6))
    colours = {"natural": PYTHON, "freed": "#8a7a12", "subscope": X2C}
    for shape, rows in sorted(shapes.items()):
        rows.sort(key=lambda r: r["operations"])
        axes[0].plot([r["operations"] for r in rows],
                     [r["peak_bytes"] / 1e6 for r in rows],
                     marker="o", markersize=4, linewidth=1.6,
                     color=colours.get(shape, CONTROL), label=shape)
        axes[1].plot([r["operations"] for r in rows],
                     [r["vs_control"] for r in rows],
                     marker="o", markersize=4, linewidth=1.6,
                     color=colours.get(shape, CONTROL), label=shape)
    axes[1].axhline(1.0, color=CONTROL, linewidth=1)
    for cell, title, ylabel in (
            (axes[0], f"peak footprint against chain length "
                      f"({attribution['elements']} elements)",
             "peak footprint (MB)"),
            (axes[1], "time against the C++ control", "x2c / c++")):
        cell.set_title(title, loc="left", fontsize=11)
        cell.set_xlabel("operations per request", fontsize=9)
        cell.set_ylabel(ylabel, fontsize=9)
        cell.set_xscale("log", base=2)
        cell.set_xticks([16, 128, 512])
        cell.set_xticklabels(["16", "128", "512"])
        cell.spines["top"].set_visible(False)
        cell.spines["right"].set_visible(False)
        cell.grid(axis="y", color="#dddddd", linewidth=0.6)
        cell.set_axisbelow(True)
        cell.legend(frameon=False, fontsize=9)
    figure.tight_layout()
    path = os.path.join(directory, "peak-versus-length.png")
    figure.savefig(path, dpi=144)
    plt.close(figure)
    print(f"wrote {path}")


def paired_learning_curves(directory, check, curve_directory, evidence):
    provenance = {}
    for app, data in check.items():
        path = os.path.join(curve_directory, f"{app}-python-curve.txt")
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            content = handle.read()
        points = [(int(index), float(value)) for index, value in
                  (line.split() for line in content.decode().splitlines())]
        data.setdefault("curve", {})["python"] = points
        provenance[app] = {"file": os.path.abspath(path),
                           "sha256": hashlib.sha256(content).hexdigest(),
                           "points": len(points)}
    learning_curves(directory, check, "supplement-paired-learning.png")
    with open(os.path.join(evidence, "paired-curves-provenance.json"), "w") as f:
        json.dump({"check": "check.json (unchanged)", "python": provenance},
                  f, indent=2)
        f.write("\n")


def window_memory(directory, memory):
    rows = [r for r in memory or [] if r["profile"] == 4]
    if not rows:
        return
    row = rows[-1]
    figure, axes = plt.subplots(figsize=(7, 4))
    for language, color in (("x2c", X2C), ("python", PYTHON)):
        samples = [s for s in row[language]["samples"]
                   if s["label"] == "window-done" or
                   (s["label"].startswith("window") and
                    s["label"].endswith("-done"))]
        axes.plot([s["index"] for s in samples],
                  [s["footprint_peak"] / 1e6 for s in samples],
                  marker="o", color=color, label=language)
    axes.set_xscale("log", base=2)
    axes.set_xticks([8, 32, 128], ["8", "32", "128"])
    axes.legend(frameon=False)
    finish(figure, axes, os.path.join(directory, "supplement-window-memory.png"),
           "Sequence memory: model released between window lengths",
           "window length (ascending sweep)", "cumulative process peak (MB)")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))))
    directory = os.path.join(root, "debug", "torch-comparison", sys.argv[1])
    if not os.path.isdir(directory):
        sys.exit(f"no run at {directory}")
    if len(sys.argv) > 3 and sys.argv[2] == "--paired-curves":
        paired_learning_curves(os.path.dirname(os.path.abspath(__file__)),
                               load(directory, "check.json"), sys.argv[3],
                               directory)
        return 0
    if len(sys.argv) > 2 and sys.argv[2] == "--supplement":
        window_memory(os.path.dirname(os.path.abspath(__file__)),
                      load(directory, "memory.json"))
        return 0
    diagnostics = (os.path.join(root, "debug", "torch-comparison", sys.argv[2])
                   if len(sys.argv) > 2 else directory)
    # Read the raw samples from the run's log directory; write the plots
    # beside REPORT.md, which is what refers to them.
    out = os.path.dirname(os.path.abspath(__file__))
    check = load(directory, "check.json")
    if check:
        learning_curves(out, check)
    paired_throughput(out, load(directory, "timing.json"))
    memory_versus_steps(out, load(diagnostics, "memory.json"))
    canonical_churn(out, load(diagnostics, "memory.json"))
    peak_versus_length(out, load(diagnostics, "attribution.json"),
                       load(diagnostics, "memory.json"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
