#!/usr/bin/env python3
"""Compare one measured implementation between two frozen benchmark binaries.

Defaults to the production Var Map. `--implementation x2c-typed` and the other
typed lanes compare the same way, so a candidate for the typed maps can be
told from run-to-run drift rather than read off a single unpaired run.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import platform
import shlex
import shutil
import statistics
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[4]
DEFAULT_RESULTS = (
    ROOT / "unittest/build/benchmarks/hash-table/direct/comparisons"
)


class ComparisonError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_binary(
    binary: Path,
    count: int,
    probe_multiplier: int,
    iteration_repeats: int,
    sample: int,
    order: str,
    command_log: Path,
) -> str:
    command = [
        str(binary), str(count), str(probe_multiplier),
        str(iteration_repeats), str(sample), order,
    ]
    with command_log.open("a", encoding="utf-8") as log:
        log.write(f"$ {shlex.join(command)}\n")
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode:
        sys.stderr.write(completed.stderr)
        raise ComparisonError(
            f"benchmark failed ({completed.returncode}): "
            f"{shlex.join(command)}"
        )
    return completed.stdout


def parse_output(
    text: str, variant: str, raw: csv.writer,
    values: dict[tuple[str, str, int, str], dict[int, float]],
    checksums: dict[tuple[str, str, int, str, int], str],
) -> None:
    reader = csv.reader(text.splitlines())
    for row in reader:
        if len(row) != 8 or row[0] == "sample":
            continue
        sample = int(row[0])
        implementation = row[1]
        count = int(row[2])
        operation = row[4]
        ns = float(row[6])
        checksum = row[7]
        raw.writerow([variant, *row])
        key = (variant, implementation, count, operation)
        values.setdefault(key, {})[sample] = ns
        checksums[
            (variant, implementation, count, operation, sample)
        ] = checksum


def validate(
    variants: list[str], counts: list[int], samples: int,
    checksums: dict[tuple[str, str, int, str, int], str],
    implementation: str, reference: str,
) -> list[str]:
    operations = sorted({
        key[3] for key in checksums if key[1] == implementation
    })
    if not operations:
        available = sorted({key[1] for key in checksums})
        raise ComparisonError(
            f"no results for implementation '{implementation}'; "
            f"the binaries measured {', '.join(available)}"
        )
    for variant in variants:
        for count in counts:
            for operation in operations:
                for sample in range(1, samples + 1):
                    measured = checksums.get(
                        (variant, implementation, count, operation, sample)
                    )
                    expected = checksums.get(
                        (variant, reference, count, operation, sample)
                    )
                    if measured is None or expected is None:
                        raise ComparisonError(
                            "missing result: "
                            f"{variant} {count} {operation} sample {sample}"
                        )
                    if measured != expected:
                        raise ComparisonError(
                            "checksum mismatch: "
                            f"{variant} {count} {operation} sample {sample}"
                        )
    baseline, candidate = variants
    for count in counts:
        for operation in operations:
            for sample in range(1, samples + 1):
                before = checksums[
                    (baseline, implementation, count, operation, sample)
                ]
                after = checksums[
                    (candidate, implementation, count, operation, sample)
                ]
                if before != after:
                    raise ComparisonError(
                        "variant checksum mismatch: "
                        f"{count} {operation} sample {sample}"
                    )
    return operations


def write_summary(
    path: Path, variants: list[str], counts: list[int],
    operations: list[str], samples: int,
    values: dict[tuple[str, str, int, str], dict[int, float]],
    implementation: str,
) -> None:
    baseline, candidate = variants
    with path.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output, delimiter="\t", lineterminator="\n")
        writer.writerow([
            "count", "operation", f"{baseline}_median_ns",
            f"{candidate}_median_ns", "paired_median_delta_pct",
            "candidate_faster_samples", "samples",
        ])
        for count in counts:
            for operation in operations:
                before = values[(baseline, implementation, count, operation)]
                after = values[(candidate, implementation, count, operation)]
                deltas = [
                    (after[sample] - before[sample]) / before[sample] * 100
                    for sample in range(1, samples + 1)
                ]
                faster = sum(
                    after[sample] < before[sample]
                    for sample in range(1, samples + 1)
                )
                writer.writerow([
                    count, operation,
                    f"{statistics.median(before.values()):.6f}",
                    f"{statistics.median(after.values()):.6f}",
                    f"{statistics.median(deltas):.3f}",
                    faster, samples,
                ])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-binary", type=Path, required=True)
    parser.add_argument("--candidate-binary", type=Path, required=True)
    parser.add_argument("--baseline-source", type=Path, required=True)
    parser.add_argument("--candidate-source", type=Path, required=True)
    parser.add_argument("--baseline-label", default="baseline")
    parser.add_argument("--candidate-label", default="candidate")
    parser.add_argument("--baseline-build", default="")
    parser.add_argument("--candidate-build", default="")
    parser.add_argument("--baseline-commit", default="")
    parser.add_argument("--candidate-commit", default="")
    parser.add_argument(
        "--implementation", default="x2c",
        help="which measured implementation to compare between the two "
             "binaries; the typed lanes are x2c-typed, x2c-flat, x2c-wide, "
             "and x2c-meta",
    )
    parser.add_argument(
        "--reference", default="",
        help="the implementation whose checksums must agree with it in "
             "every sample; defaults to khashl for x2c and khashl-typed "
             "for the typed lanes",
    )
    parser.add_argument("--samples", type=int, default=14)
    parser.add_argument(
        "--counts", type=int, nargs="+", default=[32768, 1048576]
    )
    parser.add_argument("--probe-multiplier", type=int, default=4)
    parser.add_argument("--iteration-repeats", type=int, default=8)
    parser.add_argument("--results-root", type=Path, default=DEFAULT_RESULTS)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.samples < 1 or any(count < 1 for count in args.counts):
        raise ComparisonError("samples and counts must be positive")
    inputs = [
        args.baseline_binary, args.candidate_binary,
        args.baseline_source, args.candidate_source,
    ]
    for path in inputs:
        if not path.is_file():
            raise ComparisonError(f"input does not exist: {path}")
    variants = [args.baseline_label, args.candidate_label]
    if variants[0] == variants[1]:
        raise ComparisonError("variant labels must differ")
    # The Var lanes are checksum-matched against khashl and the native ones
    # against khashl-typed, so the default follows the implementation.
    reference = args.reference or (
        "khashl" if args.implementation in ("x2c", "x2c-khashl")
        else "khashl-typed"
    )
    if reference == args.implementation:
        raise ComparisonError("implementation and reference must differ")

    timestamp = dt.datetime.now(dt.timezone.utc).strftime(
        "%Y%m%dT%H%M%S.%fZ"
    )
    result = args.results_root / timestamp
    result.mkdir(parents=True, exist_ok=False)
    copied: dict[str, dict[str, str]] = {}
    for label, binary, source in zip(
        variants,
        [args.baseline_binary, args.candidate_binary],
        [args.baseline_source, args.candidate_source],
    ):
        copied_binary = result / f"{label}-map-comparison"
        copied_source = result / f"{label}-map.x"
        shutil.copy2(binary, copied_binary)
        shutil.copy2(source, copied_source)
        copied[label] = {
            "binary": copied_binary.name,
            "binary_sha256": sha256(copied_binary),
            "source": copied_source.name,
            "source_sha256": sha256(copied_source),
        }

    command_log = result / "commands.log"
    values: dict[tuple[str, str, int, str], dict[int, float]] = {}
    checksums: dict[tuple[str, str, int, str, int], str] = {}
    with (result / "raw.csv").open(
        "w", encoding="utf-8", newline=""
    ) as raw_output:
        raw = csv.writer(raw_output, lineterminator="\n")
        raw.writerow([
            "variant", "sample", "implementation", "count", "capacity",
            "operation", "operations", "ns_per_operation", "checksum",
        ])
        binaries = [args.baseline_binary, args.candidate_binary]
        for sample in range(1, args.samples + 1):
            variant_order = [0, 1] if sample % 2 else [1, 0]
            for count in args.counts:
                for index in variant_order:
                    order = (
                        "x2c-first" if (sample + index) % 2 else
                        "khashl-first"
                    )
                    print(
                        f"sample={sample} count={count} "
                        f"variant={variants[index]} order={order}",
                        flush=True,
                    )
                    output = run_binary(
                        binaries[index], count, args.probe_multiplier,
                        args.iteration_repeats, sample, order, command_log,
                    )
                    parse_output(
                        output, variants[index], raw, values, checksums
                    )

    operations = validate(
        variants, args.counts, args.samples, checksums,
        args.implementation, reference,
    )
    write_summary(
        result / "summary.tsv", variants, args.counts, operations,
        args.samples, values, args.implementation,
    )
    metadata = {
        "completed_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "host": platform.platform(),
        "machine": platform.machine(),
        "samples": args.samples,
        "counts": args.counts,
        "probe_multiplier": args.probe_multiplier,
        "iteration_repeats": args.iteration_repeats,
        "implementation": args.implementation,
        "reference": reference,
        "baseline_label": args.baseline_label,
        "candidate_label": args.candidate_label,
        "baseline_commit": args.baseline_commit,
        "candidate_commit": args.candidate_commit,
        "baseline_build": args.baseline_build,
        "candidate_build": args.candidate_build,
        "inputs": copied,
    }
    (result / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print((result / "summary.tsv").read_text(encoding="utf-8"), end="")
    print(f"results={result}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ComparisonError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
