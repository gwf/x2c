#!/usr/bin/env python3
"""Find the first update, and the first operation, where the two
implementations stop producing identical float32 values.

Both programs have a `trace` mode that runs one update with every
intermediate kept: the parameters before it, the batch, each matmul, each
bias add, each ReLU, the loss, each gradient, and the parameters after.
This runs that mode at a series of update counts and reports, per update,
which recorded tensor first differs.

    python3 packages/torch/benchmarks/firstdiff.py [--variant explicit]
                                                [--first 0] [--last 40]

`pre.*` at update n is `post.*` at update n-1, so the first update whose
`pre.*` differs names the update that produced the difference, and the
`fwd.*`/`grad.*` keys at that update name the operation.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
import run

# The order the values are produced in, which is the order that matters
# for "first difference". Parameters are grouped because Adam updates them
# together.
ORDER = [
    "pre.l1.weight", "pre.l1.bias", "pre.l2.weight", "pre.l2.bias",
    "pre.l3.weight", "pre.l3.bias",
    "batch.x", "batch.y",
    "fwd.m1", "fwd.a1", "fwd.r1",
    "fwd.m2", "fwd.a2", "fwd.r2",
    "fwd.m3", "fwd.a3",
    "loss",
    "grad.l3.weight", "grad.l3.bias", "grad.l2.weight", "grad.l2.bias",
    "grad.l1.weight", "grad.l1.bias",
    "post.l1.weight", "post.l1.bias", "post.l2.weight", "post.l2.bias",
    "post.l3.weight", "post.l3.bias",
]


def differences(left, right):
    """The recorded values that are not bit-identical, in production
    order, with the worst absolute difference of each."""
    import torch

    found = []
    for name in ORDER:
        if name not in left or name not in right:
            continue
        a, b = left[name].double(), right[name].double()
        if a.shape != b.shape:
            found.append((name, float("inf"), "shape"))
            continue
        worst = float((a - b).abs().max()) if a.numel() else 0.0
        if worst != 0.0:
            found.append((name, worst, f"{a.numel()} values"))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", default="explicit",
                        choices=["native", "explicit"])
    parser.add_argument("--first", type=int, default=0)
    parser.add_argument("--last", type=int, default=40)
    parser.add_argument("--run-id", default="bisect")
    options = parser.parse_args()

    print(f"tabular {options.variant}: "
          f"updates {options.first}..{options.last}")
    first_report = None
    for n in range(options.first, options.last + 1):
        run.both("tabular", "trace", (options.variant, n), 1, options.run_id,
                 f"trace-{options.variant}-{n}")
        left = common.load_tensors(common.output("tabular-x2c-trace.pt"))
        right = common.load_tensors(common.output("tabular-python-trace.pt"))
        found = differences(left, right)
        if not found:
            print(f"  update {n:3d}  identical")
            continue
        head = ", ".join(f"{name} {worst:.3e}" for name, worst, _ in found[:4])
        print(f"  update {n:3d}  {len(found)} of {len(ORDER)} differ: {head}")
        if first_report is None:
            first_report = (n, found)
    if first_report is None:
        print("no difference in this range")
        return 0
    n, found = first_report
    print(f"\nfirst difference at update {n}, at `{found[0][0]}`, "
          f"worst absolute {found[0][1]:.3e}")
    print("every value that differs at that update, in production order:")
    for name, worst, note in found:
        print(f"  {name:<20} {worst:.6e}  ({note})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
