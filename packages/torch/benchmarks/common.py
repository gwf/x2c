"""Shared configuration, artifact handling, and comparison for the suite.

This module owns no model logic. It owns the one fixed profile both
languages read, where artifacts and outputs live, how a checkpoint is
compared to its counterpart, and how a benchmark process's printed records
are collected. `prepare.py` writes the artifacts, `run.py` launches the
programs, and the paired `.x`/`.py` applications do the machine learning.

Every application is also runnable on its own; see README.md.
"""

import hashlib
import json
import math
import os
import platform
import subprocess
import sys

PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCHMARKS = os.path.join(PACKAGE, "benchmarks")
ROOT = os.path.dirname(os.path.dirname(PACKAGE))
WORK = os.path.join(ROOT, "unittest", "build", "torch-comparison")
ARTIFACTS = os.path.join(WORK, "artifacts")
BINARIES = os.path.join(WORK, "bin")
OUTPUTS = os.environ.get("X2C_TORCH_OUTPUTS", os.path.join(WORK, "out"))
LOGS = os.path.join(ROOT, "debug", "torch-comparison")

DEFAULT_PYTHON = "/Users/gary/Git/Bonsai-demo/.venv/bin/python"

# The artifact layout. A program that reads an artifact checks this number
# and refuses a mismatch, so a stale dataset cannot be compared silently.
ARTIFACT_VERSION = 1

# One fixed profile for both languages. `prepare.py` copies it into
# config.json beside the artifacts; each program records the constants it
# was compiled with and `run.py` refuses a disagreement.
PROFILE = {
    "artifact_version": ARTIFACT_VERSION,
    "dtype": "float32",
    "tabular": {
        "train_rows": 32768,
        "val_rows": 8192,
        "features": 128,
        "targets": 8,
        "hidden1": 256,
        "hidden2": 128,
        "teacher_hidden": 64,
        "noise": 0.05,
        "seed": 20260909,
        "batch": 128,
        "updates": 1024,
        "lr": 1e-3,
        "predict_batches": [1, 32, 256],
        "predict_requests": 256,
    },
    "sequence": {
        "observed": 8,
        "latent": 16,
        "drivers": 4,
        "hidden": 64,
        "train_streams": 32,
        "train_steps": 4096,
        "val_streams": 8,
        "val_steps": 1024,
        "spectral_norm": 0.8,
        "noise": 0.02,
        "seed": 20260910,
        "window": 32,
        "batch": 32,
        "windows": 512,
        "lr": 1e-3,
        "window_sweep": [8, 32, 128],
    },
    "interop": {
        "elements": [1, 64, 4096, 65536],
        "operations": [16, 128, 512],
        "requests": 64,
        "seed": 20260911,
    },
    "mnist": {
        # The plan's architecture, as one Sequential on both sides. The
        # child names are positions, which is what libtorch and nn.Module
        # both produce, so one checkpoint fits both.
        "channels1": 16,
        "channels2": 32,
        "kernel": 3,
        "padding": 1,
        "pool": 2,
        "flat": 1568,
        "hidden": 128,
        "classes": 10,
        "batch": 64,
        "epochs": 2,
        "batches_per_epoch": 938,
        "lr": 1e-3,
        "mean": 0.1307,
        "std": 0.3081,
        "seed": 20260912,
        "accuracy_target": 0.95,
        "accuracy_gap": 0.005,
    },
}

# The published IDX files. They are read in place by both languages; the
# hashes go into config.json so a comparison names its actual input.
MNIST_DEFAULT_ROOT = "/tmp/mnist-real"
MNIST_FILES = ["train-images-idx3-ubyte", "train-labels-idx1-ubyte",
               "t10k-images-idx3-ubyte", "t10k-labels-idx1-ubyte"]


# Float32 starting tolerances from the plan. A relaxation is recorded in
# the report with its numerical explanation, never chosen to pass a run.
ATOL = 1e-6
RTOL = 1e-4
LOSS_RTOL = 1e-3

# Resource caps. A stopped case is incomplete, never a passing result.
FOOTPRINT_LIMIT = 2 * 1024 * 1024 * 1024
TIMEOUT = 600


def mnist_root():
    return os.environ.get("TORCH_MNIST", MNIST_DEFAULT_ROOT)


def torch_python():
    return os.environ.get("TORCH_PYTHON", DEFAULT_PYTHON)


def ensure_directories():
    for path in (WORK, ARTIFACTS, BINARIES, OUTPUTS):
        os.makedirs(path, exist_ok=True)


def artifact(name):
    return os.path.join(ARTIFACTS, name)


def output(name):
    return os.path.join(OUTPUTS, name)


def config_path():
    return artifact("config.json")


def load_config():
    with open(config_path()) as handle:
        return json.load(handle)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def reexec_with_torch(script):
    """Re-runs `script` under the pinned wheel when torch is missing here."""
    interpreter = torch_python()
    if os.environ.get("X2C_TORCH_REEXEC") or not os.path.exists(interpreter):
        sys.exit("no interpreter with torch; set TORCH_PYTHON")
    os.environ["X2C_TORCH_REEXEC"] = "1"
    os.execv(interpreter,
             [interpreter, os.path.abspath(script), *sys.argv[1:]])


def save_tensors(mapping, path):
    """Writes the plain dict form the C++ unpickler reads."""
    import torch

    os.makedirs(os.path.dirname(path), exist_ok=True)
    torch.save({str(k): v for k, v in mapping.items()}, path)


def load_tensors(path):
    """Reads a checkpoint written by either language.

    weights_only=False is required: the C++ pickler tags its dict with
    torch.jit._pickle.restore_type_tag, which the safe loader rejects.
    """
    import torch

    return torch.load(path, weights_only=False)


def check_artifact_version(mapping, path):
    import torch

    version = mapping.get("meta.version")
    if version is None:
        sys.exit(f"{path}: no meta.version; rerun prepare.py")
    if int(version.item()) != ARTIFACT_VERSION:
        sys.exit(f"{path}: artifact version {int(version.item())} "
                 f"but this suite wants {ARTIFACT_VERSION}; rerun prepare.py")


def compare_tensors(left, right, atol=ATOL, rtol=RTOL):
    """Returns per-name (max absolute, max normalized) differences.

    Normalized differences summarize scale; acceptance uses elementwise
    atol + rtol * abs(right), with exact integer and metadata comparisons.
    """
    import torch

    findings = []
    names = sorted(set(left) | set(right))
    if not names:
        return [("checkpoint", float("inf"), float("inf"), "empty")]
    for name in names:
        if name not in left or name not in right:
            findings.append((name, float("inf"), float("inf"), "missing"))
            continue
        a, b = left[name], right[name]
        if not (torch.is_tensor(a) and torch.is_tensor(b)):
            findings.append((name, float("inf"), float("inf"), "not tensor"))
            continue
        if a.dtype != b.dtype:
            findings.append((name, float("inf"), float("inf"), "dtype"))
            continue
        if a.shape != b.shape:
            findings.append((name, float("inf"), float("inf"), "shape"))
            continue
        if not (torch.isfinite(a).all() and torch.isfinite(b).all()):
            findings.append((name, float("inf"), float("inf"), "non-finite"))
            continue
        exact = (name.startswith("meta.") or
                 not (a.is_floating_point() or a.is_complex()))
        equal = torch.equal(a, b)
        dtype = torch.complex128 if a.is_complex() else torch.float64
        a, b = a.to(dtype), b.to(dtype)
        absolute = (a - b).abs()
        scale = torch.maximum(a.abs(), b.abs()).clamp_min(1e-30)
        worst_abs = float(absolute.max()) if a.numel() else 0.0
        worst_rel = float((absolute / scale).max()) if a.numel() else 0.0
        within = equal if exact else bool(
            (absolute <= atol + rtol * b.abs()).all())
        verdict = "ok" if within else "different" if exact else "over"
        findings.append((name, worst_abs, worst_rel, verdict))
    return findings


def agree(what, left, right, tolerance=LOSS_RTOL):
    if not (math.isfinite(left) and math.isfinite(right)):
        return float("inf"), False
    scale = max(abs(left), abs(right), 1e-12)
    relative = abs(left - right) / scale
    return relative, relative <= tolerance


class Result:
    """What one benchmark process printed."""

    def __init__(self, records, texts, samples, dropped, stdout, seconds,
                 handles=None, counters=False, curve=None):
        self.records = records
        self.texts = texts
        self.samples = samples
        self.dropped = dropped
        self.stdout = stdout
        self.seconds = seconds
        # Native handle totals by kind, and whether this build counted at
        # all. Python leaves both empty: it has no such layer.
        self.handles = handles or {}
        self.counters = counters
        # (update, loss) pairs a check run printed, for the learning curve.
        self.curve = curve or []

    def number(self, name):
        if name not in self.records:
            raise KeyError(f"no record {name!r} in output:\n{self.stdout}")
        return self.records[name]


SAMPLE_FIELDS = [
    "label", "index", "seconds", "footprint", "footprint_peak", "resident",
    "resident_peak", "live_allocations", "live_scopes", "allocation_calls",
    "free_calls", "requested_bytes", "pool_interned", "pool_active_bytes",
    "pool_backing_bytes", "pool_depot_bytes",
]


HANDLE_KINDS = ["tensor", "module", "optimizer", "scheduler", "pickle",
                "jit", "array"]


def parse_output(text):
    records, texts, samples, dropped = {}, {}, [], 0
    handles, summary, enabled, curve = {}, {}, False, []
    for line in text.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "record" and len(parts) == 3:
            records[parts[1]] = float(parts[2])
        elif parts[0] == "text" and len(parts) >= 3:
            texts[parts[1]] = " ".join(parts[2:])
        elif parts[0] == "sample" and len(parts) == len(SAMPLE_FIELDS) + 1:
            values = parts[1:]
            sample = {"label": values[0], "index": int(values[1]),
                      "seconds": float(values[2])}
            for name, value in zip(SAMPLE_FIELDS[3:], values[3:]):
                sample[name] = int(value)
            samples.append(sample)
        elif parts[0] == "curve" and len(parts) == 3:
            curve.append((int(parts[1]), float(parts[2])))
        elif parts[0] == "handles" and len(parts) >= 3:
            values = [int(v) for v in parts[3:]]
            handles[(parts[1], int(parts[2]))] = {
                name: {"live": values[2 * i], "peak": values[2 * i + 1]}
                for i, name in enumerate(HANDLE_KINDS)
                if 2 * i + 1 < len(values)}
        elif parts[0] == "handlesum" and len(parts) == 6:
            summary[HANDLE_KINDS[int(parts[1])]] = {
                "created": int(parts[2]), "destroyed": int(parts[3]),
                "live": int(parts[4]), "peak": int(parts[5])}
        elif parts[0] == "counters" and len(parts) == 2:
            enabled = parts[1] == "1"
        elif parts[0] == "dropped" and len(parts) == 2:
            dropped = int(parts[1])
    for sample in samples:
        found = handles.get((sample["label"], sample["index"]))
        if found:
            sample["handles"] = found
    return records, texts, samples, dropped, summary, enabled, curve


def launch(command, environment=None, log=None, timeout=TIMEOUT):
    """Runs one benchmark process to completion and collects its records."""
    import time

    env = dict(os.environ)
    if environment:
        env.update(environment)
    start = time.monotonic()
    finished = subprocess.run(command, capture_output=True, text=True,
                              env=env, timeout=timeout, cwd=ROOT)
    seconds = time.monotonic() - start
    if log:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "w") as handle:
            handle.write("$ " + " ".join(command) + "\n")
            handle.write(finished.stdout)
            handle.write(finished.stderr)
    if finished.returncode != 0:
        raise RuntimeError(
            f"{' '.join(command)} exited {finished.returncode}\n"
            f"{finished.stdout}\n{finished.stderr}")
    parsed = parse_output(finished.stdout)
    records, texts, samples, dropped, summary, enabled, curve = parsed
    return Result(records, texts, samples, dropped,
                  finished.stdout + finished.stderr, seconds,
                  summary, enabled, curve)


def environment_record():
    """Machine, toolchain, and library facts a measurement is only valid
    against. Torch and library paths are filled in by the caller that has
    torch imported."""
    return {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": subprocess.run(
            ["sysctl", "-n", "machdep.cpu.brand_string"],
            capture_output=True, text=True).stdout.strip(),
        "physical_cores": subprocess.run(
            ["sysctl", "-n", "hw.physicalcpu"],
            capture_output=True, text=True).stdout.strip(),
        "logical_cores": subprocess.run(
            ["sysctl", "-n", "hw.logicalcpu"],
            capture_output=True, text=True).stdout.strip(),
        "python": sys.version.split()[0],
        "python_executable": sys.executable,
        "source_head": subprocess.run(
            ["git", "-C", ROOT, "rev-parse", "HEAD"],
            capture_output=True, text=True).stdout.strip(),
        "source_dirty": bool(subprocess.run(
            ["git", "-C", ROOT, "status", "--porcelain"],
            capture_output=True, text=True).stdout.strip()),
    }
