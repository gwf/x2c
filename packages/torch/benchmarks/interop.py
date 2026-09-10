#!/usr/bin/env python3
"""The Python half of the interop diagnostic. Same chain, same sizes."""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
import membytes

try:
    import torch
except ImportError:
    common.reexec_with_torch(__file__)

ELEMENTS = common.PROFILE["interop"]["elements"]
OPERATIONS = common.PROFILE["interop"]["operations"]


def record(name, value):
    print(f"record {name} {value:.12g}")


def text(name, value):
    print(f"text {name} {value}")


SAMPLES = []
START = time.monotonic()


def sample(label, index):
    SAMPLES.append((label, index, time.monotonic() - START,
                    membytes.footprint(), membytes.footprint_peak(),
                    membytes.resident(), membytes.resident_peak()))


def flush():
    for row in SAMPLES:
        print("sample {} {} {:.6f} {} {} {} {} 0 0 0 0 0 0 0 0 0".format(*row))
    print("dropped 0")


def chain(x, a, b, operations):
    with torch.inference_mode():
        y = x
        for _ in range(operations):
            y = torch.relu(y * a + b)
        return float(y.sum())


def load(artifacts):
    values = common.load_tensors(os.path.join(artifacts, "interop-init.pt"))
    common.check_artifact_version(values, "interop-init.pt")
    return values


def triple(values, count):
    return (values[f"x.{count}"], values[f"a.{count}"], values[f"b.{count}"])


def mode_check(artifacts, out):
    values = load(artifacts)
    for count in ELEMENTS:
        for operations in OPERATIONS:
            record(f"chain_e{count}_o{operations}",
                   chain(*triple(values, count), operations))
    return 0


def mode_time(artifacts, out, variant, requests):
    values = load(artifacts)
    text("variant", variant)
    record("threads", torch.get_num_threads())
    only = None
    if variant != "chain":
        head, _, tail = variant[1:].partition("o")
        only = (int(head), int(tail))

    total = 0.0
    for count in ELEMENTS:
        for operations in OPERATIONS:
            if only and (count, operations) != only:
                continue
            x, a, b = triple(values, count)
            for _ in range(8):
                chain(x, a, b, operations)
            result = 0.0
            start = time.monotonic()
            for _ in range(requests):
                result += chain(x, a, b, operations)
            seconds = time.monotonic() - start
            total += seconds
            record(f"seconds_e{count}_o{operations}", seconds)
            record(f"ns_per_op_e{count}_o{operations}",
                   seconds * 1e9 / (requests * operations))
            record(f"result_e{count}_o{operations}", result)
    record("requests", requests)
    record("steady_seconds", total)
    return 0


def mode_memory(artifacts, out, profile, requests):
    if profile != 4:
        sys.exit(f"interop.py: no memory profile {profile}")
    sample("baseline", 0)
    values = load(artifacts)
    sample("loaded", 0)
    x, a, b = triple(values, 65536)
    for operations in OPERATIONS:
        sample("chain-start", operations)
        for _ in range(requests):
            chain(x, a, b, operations)
        sample("chain-done", operations)
    # Python has no scope to shorten; the reference is the same total work
    # in one loop, which is what the blocks above already measure.
    sample("final", 0)
    flush()
    return 0


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    mode, artifacts, out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    torch.set_num_threads(int(os.environ.get("X2C_TORCH_THREADS", "1")))
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError:
        text("interop_threads_note", "already-set")
    text("language", "python")
    text("torch_version", torch.__version__)
    if mode == "check":
        return mode_check(artifacts, out)
    if mode == "time":
        return mode_time(artifacts, out, sys.argv[4], int(sys.argv[5]))
    if mode == "memory":
        return mode_memory(artifacts, out, int(sys.argv[4]), int(sys.argv[5]))
    sys.exit(f"interop.py: no mode {mode}")


if __name__ == "__main__":
    sys.exit(main())
