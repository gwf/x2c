"""Render existing shootout measurements; never rerun a benchmark."""

import argparse
import csv
import hashlib
import json
from pathlib import Path
from statistics import fmean, geometric_mean, median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import FixedLocator, FuncFormatter, NullFormatter
import numpy as np


SERIES = [
    ("c", "C", "#39434d", "o"),
    ("idiomatic", "Idiomatic x2c", "#007e87", "^"),
    ("tuned", "Tuned x2c", "#7655aa", "D"),
    ("python", "Python", "#b47712", "s"),
    ("rust", "Rust", "#bd5038", "P"),
    ("cpp", "C++", "#346caf", "X"),
]
TICKS = [1, 1.25, 1.5, 2, 3, 5, 10, 20, 30, 50, 100, 200]


def read_rows(path):
    report = json.loads(path.read_text())
    rows = []
    for problem in report["benchmark_order"]:
        entry = report["benchmarks"][problem]
        programs = {
            key: entry[key] if key in entry else entry["references"][key]
            for key, *_ in SERIES
            if key in entry or key in entry["references"]
        }
        best_time = min(p["statistics"]["median_elapsed_ns"]
                        for p in programs.values())
        shortest = min(p["source"]["source_lines"] for p in programs.values())
        smallest = min(p["source"]["game_style_gzip_bytes"]
                       for p in programs.values())
        for key, label, *_ in SERIES:
            if key not in programs:
                continue
            program = programs[key]
            rows.append({
                "problem": problem, "implementation": key, "label": label,
                "available_columns": len(programs),
                "seconds": program["statistics"]["median_elapsed_ns"] / 1e9,
                "source_lines": program["source"]["source_lines"],
                "gzip_bytes": program["source"]["game_style_gzip_bytes"],
                "time_ratio": program["statistics"]["median_elapsed_ns"]
                              / best_time,
                "loc_ratio": program["source"]["source_lines"] / shortest,
                "gzip_ratio": program["source"]["game_style_gzip_bytes"]
                              / smallest,
            })
    return report, rows


def ticks(ax, axis, limits, dense=False):
    selected = [x for x in TICKS if limits[0] <= x <= limits[1]
                and (dense or x not in [1.25, 1.5, 30])]
    target = ax.xaxis if axis == "x" else ax.yaxis
    target.set_major_locator(FixedLocator(selected))
    target.set_major_formatter(FuncFormatter(lambda value, _: f"{value:g}x"))
    target.set_minor_formatter(NullFormatter())


def base_axes(ax):
    ax.set_axisbelow(True)
    ax.grid(True, which="major", color="#e4e8ec", linewidth=.7)
    ax.tick_params(which="both", length=0, pad=7)
    for spine in ax.spines.values():
        spine.set_color("#bec6cd")
        spine.set_linewidth(.8)


def heading(fig, title, subtitle):
    fig.text(.07, .98, title, ha="left", va="top", fontsize=21)
    fig.text(.07, .91, subtitle, ha="left", va="top", fontsize=12,
             color="#53606b")


def footer(fig, report, detail):
    fig.text(.07, .022,
             f"{report['machine'].get('cpu_model') or report['machine']['machine']} | "
             f"{report['profile']} inputs | "
             f"{report['samples']}-sample wall-time medians | run {report['run_id']}\n"
             + detail, fontsize=10.5, color="#53606b", va="bottom")


def save(fig, output, name):
    for extension in ["png", "svg", "pdf"]:
        fig.savefig(output / f"{name}.{extension}", dpi=180,
                    facecolor="white", metadata={"Creator": "matplotlib"})
    plt.close(fig)


def summary(report, rows, output):
    fig, axes = plt.subplots(1, 2, figsize=(12, 6.5))
    heading(fig, "Runtime and source size",
            "Six implementations | geometric means across nine shared problems")
    for ax, metric, title, xlabel in zip(
        axes, ["loc_ratio", "gzip_ratio"],
        ["Source lines (LOC)", "Compressed source (Benchmarks Game metric)"],
        ["LOC / shortest program", "Gzip bytes / smallest program"],
    ):
        means = []
        for key, label, color, marker in SERIES:
            group = [r for r in rows if r["implementation"] == key]
            x = geometric_mean(r[metric] for r in group)
            y = geometric_mean(r["time_ratio"] for r in group)
            means.append((x, y))
            ax.scatter(x, y, color=color, marker=marker, s=100, zorder=4)
            offsets = {"tuned": (-10, 16), "cpp": (10, 14), "c": (-10, -14)}
            offset = offsets.get(key, (10, 8))
            ax.annotate(label, (x, y), xytext=offset,
                        ha="right" if offset[0] < 0 else "left",
                        textcoords="offset points", fontsize=11.5, color=color)
        ax.set(xscale="log", yscale="log", xlim=(.91, max(x for x, _ in means)*1.6),
               ylim=(.78, max(y for _, y in means)*1.6))
        ticks(ax, "x", ax.get_xlim(), dense=True)
        ticks(ax, "y", ax.get_ylim())
        ax.set_title(title, fontsize=12.5, pad=16)
        ax.set_xlabel(xlabel, labelpad=12)
        ax.set_ylabel("Elapsed time / fastest program", labelpad=12)
        base_axes(ax)
    footer(fig, report, "Normalize each problem against the best of these six; "
           "these are local results, not the website's measurements.")
    fig.subplots_adjust(left=.075, right=.975, bottom=.19, top=.80, wspace=.30)
    save(fig, output, "runtime-source-size")


def profiles(report, rows, output):
    fig, axes = plt.subplots(3, 2, figsize=(11.2, 12.5), sharex=True, sharey=True)
    heading(fig, "Where each implementation varies",
            "Marceau-style star plots | nine shared outcomes per panel | identical log scales")
    xlim = (.86, max(r["time_ratio"] for r in rows)*1.32)
    ylim = (.86, max(r["loc_ratio"] for r in rows)*1.3)
    for ax, (key, label, color, marker) in zip(axes.flat, SERIES):
        group = [r for r in rows if r["implementation"] == key]
        centre = (fmean(r["time_ratio"] for r in group),
                  fmean(r["loc_ratio"] for r in group))
        ax.scatter([r["time_ratio"] for r in rows], [r["loc_ratio"] for r in rows],
                   s=23, color="#d8dde1", alpha=.8, zorder=2)
        for row in group:
            x, y = row["time_ratio"], row["loc_ratio"]
            ax.plot([centre[0], x], [centre[1], y], color=color, lw=1, alpha=.6)
            ax.scatter(x, y, color=color, marker=marker, s=47, zorder=4)
        ax.scatter(*centre, marker="+", color=color, s=155, linewidths=2, zorder=5)
        farthest = max(group, key=lambda r: r["time_ratio"])
        if farthest["time_ratio"] > 3:
            ax.annotate(farthest["problem"],
                        (farthest["time_ratio"], farthest["loc_ratio"]),
                        xytext=(-8, 13), textcoords="offset points",
                        ha="right", fontsize=10, color=color)
        ax.set(xscale="log", yscale="log", xlim=xlim, ylim=ylim)
        ticks(ax, "x", xlim)
        ticks(ax, "y", ylim)
        base_axes(ax)
        ax.set_title(label, color=color, fontsize=14, loc="left", pad=11)
    fig.supxlabel("Elapsed time / fastest program  (faster to the left)", y=.075,
                  fontsize=12)
    fig.supylabel("LOC / shortest program  (shorter toward the bottom)", x=.018,
                  fontsize=12)
    footer(fig, report, "One mark = one problem. Spokes meet at the arithmetic "
           "centre (+); grey marks show all 54 shared programs. No outcomes are clipped.")
    fig.subplots_adjust(left=.09, right=.98, bottom=.14, top=.85, hspace=.35,
                        wspace=.13)
    save(fig, output, "implementation-profiles")


def percentiles(values):
    # The upstream PHP uses medians of halves, then caps 1.5-IQR whiskers
    # at min/max. These numeric whiskers need not coincide with observations.
    ordered = sorted(values)
    middle = len(ordered)//2
    lower = median(ordered[:middle + len(ordered) % 2])
    upper = median(ordered[middle:])
    spread = 1.5*(upper-lower)
    return dict(q1=lower, med=median(ordered), q3=upper,
                whislo=max(ordered[0], lower-spread),
                whishi=min(ordered[-1], upper+spread), fliers=[])


def distributions(report, rows, output):
    fig, axes = plt.subplots(1, 2, figsize=(12, 6.5))
    heading(fig, "Runtime and LOC across nine shared problems",
            "Benchmarks Game-style box plots | points retain individual problem outcomes")
    for ax, metric, title, ylabel in zip(
        axes, ["time_ratio", "loc_ratio"],
        ["How many times slower?", "How many times longer?"],
        ["Elapsed time / fastest program", "LOC / shortest program"],
    ):
        for position, (key, label, color, marker) in enumerate(SERIES, 1):
            group = [r[metric] for r in rows if r["implementation"] == key]
            stats = percentiles(group)
            ax.bxp([stats], positions=[position], widths=.48,
                   showfliers=False, patch_artist=True,
                   boxprops=dict(facecolor=color+"20", edgecolor=color, linewidth=1.4),
                   whiskerprops=dict(color=color), capprops=dict(color=color),
                   medianprops=dict(color=color, linewidth=2.2))
            jitter = np.linspace(-.13, .13, len(group))
            ax.scatter(position+jitter, group, marker=marker, s=32, color=color,
                       alpha=.9, zorder=4)
            offset = (-17, 5) if position == len(SERIES) else (17, 5)
            align = "right" if position == len(SERIES) else "left"
            ax.annotate(f"{stats['med']:.2f}x", (position, stats["med"]),
                        xytext=offset, textcoords="offset points", ha=align,
                        color=color, fontsize=11)
        ax.set_yscale("log")
        ax.set_ylim(.85, max(r[metric] for r in rows)*1.55)
        ticks(ax, "y", ax.get_ylim())
        ax.set_xticks(range(1, 7), ["C", "Idiomatic\nx2c", "Tuned\nx2c", "Python", "Rust", "C++"])
        ax.set_xlim(.45, 6.55)
        ax.set_title(title+"  (labels = medians)", fontsize=12.5, pad=17)
        ax.set_ylabel(ylabel, labelpad=12)
        base_axes(ax)
        ax.xaxis.grid(False)
    footer(fig, report, "Boxes: middle 50% of problem ratios; centre line: median; "
           "whiskers: capped 1.5 IQR. K-nucleotide is excluded from every column.")
    fig.subplots_adjust(left=.075, right=.975, bottom=.20, top=.80, wspace=.30)
    save(fig, output, "runtime-loc-distributions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report, rows = read_rows(args.results)
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 12,
        "axes.labelcolor": "#303b45", "text.color": "#303b45",
        "xtick.color": "#53606b", "ytick.color": "#53606b",
        "svg.fonttype": "none", "axes.titleweight": "normal",
    })
    with (args.output/"measurements.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    provenance = {
        "report_path": str(args.results.resolve()),
        "report_sha256": hashlib.sha256(args.results.read_bytes()).hexdigest(),
        "run_id": report["run_id"], "profile": report["profile"],
        "samples": report["samples"], "baseline_sha256": report["baseline_sha256"],
        "normalization": "Per-problem minima among available columns; all six for shared problems",
        "summary": "Geometric mean of the nine shared normalized problem values",
        "profile_centres": "Arithmetic means, following the historical star-plot form",
        "runtime": "Median wall-clock elapsed time from the existing report",
        "loc": "Nonblank source lines after language-aware comment removal",
        "gzip": "Existing harness game_style_gzip_bytes, not LOC",
        "benchmark_count": len(report["benchmark_order"]),
        "summary_benchmarks": report["summary_benchmarks"],
        "unavailable": {name: entry["unavailable"] for name, entry
                        in report["benchmarks"].items() if entry["unavailable"]},
    }
    (args.output/"provenance.json").write_text(json.dumps(provenance, indent=2)+"\n")
    shared = set(report["summary_benchmarks"])
    plotted = [row for row in rows if row["problem"] in shared]
    summary_rows = []
    for key, label, *_ in SERIES:
        group = [row for row in plotted if row["implementation"] == key]
        summary_rows.append({"implementation": label, **{
            metric: geometric_mean(row[metric] for row in group)
            for metric in ["time_ratio", "loc_ratio", "gzip_ratio"]
        }})
    with (args.output/"summaries.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=summary_rows[0].keys())
        writer.writeheader()
        writer.writerows(summary_rows)
    for plot in [summary, profiles, distributions]:
        plot(report, plotted, args.output)
    print(f"Rendered six columns: {len(rows)} measured outcomes, {len(plotted)} shared.")


if __name__ == "__main__":
    main()
