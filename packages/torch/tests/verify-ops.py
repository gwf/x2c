#!/usr/bin/env python3
"""Compare the generated bindings against the pinned Python torch.

Runs builds/verify-ops, recomputes every printed value with the same
arguments in Python, and reports the largest difference. Optional: it needs
an interpreter with torch installed, named by TORCH_PYTHON, and is not part
of `make test`.

    make -C packages/torch verify-ops
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
PROGRAM = os.path.join(PACKAGE, "builds", "verify-ops")
DEFAULT_PYTHON = "/Users/gary/Git/Bonsai-demo/.venv/bin/python"
TOLERANCE = 1e-9

PYTHON_SIDE = r'''
import json
import torch

a = torch.tensor([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], dtype=torch.float64)
mask = a > 3

values = {
    "softmax_first": a.softmax(1).flatten()[0].item(),
    "cumsum_last": a.cumsum(1).flatten()[5].item(),
    "clamp_sum": a.clamp(2, 5).sum().item(),
    "clamp_min_only_sum": a.clamp(min=2).sum().item(),
    "clamp_max_float_sum": a.clamp(max=2.5).sum().item(),
    "maximum_sum": torch.maximum(a, a.flip([1])).sum().item(),
    "flip_first": a.flip([1]).flatten()[0].item(),
    "argmax_dim_sum": a.argmax(dim=1).double().sum().item(),
    "argmax_flat": float(a.argmax().item()),
    "amax_sum": a.amax([1]).sum().item(),
    "prod_all": a.prod().item(),
    "logsumexp_first": a.logsumexp([1]).flatten()[0].item(),
    "narrow_sum": a.narrow(1, 0, 2).sum().item(),
    "topk_values_sum": a.topk(2, dim=1).values.sum().item(),
    "sort_desc_first": a.sort(1, descending=True).values.flatten()[0].item(),
    "split_second_sum": a.split(1, 0)[1].sum().item(),
    "chunk_third_sum": a.chunk(3, 1)[2].sum().item(),
    "cat_sum": torch.cat([a, a], 0).sum().item(),
    "stack_rank": float(torch.stack([a, a], 0).dim()),
    "linspace_sum": torch.linspace(0, 1, 5, dtype=torch.float64).sum().item(),
    "eye_sum": torch.eye(3, dtype=torch.float64).sum().item(),
    "where_sum": torch.where(mask, a, torch.zeros(2, 3,
                             dtype=torch.float64)).sum().item(),
    "masked_select_sum": a.masked_select(mask).sum().item(),
}
print(json.dumps(values))
'''


def main():
    if not os.path.exists(PROGRAM):
        print("build builds/verify-ops first: make -C packages/torch "
              "verify-ops")
        return 1
    output = subprocess.run([PROGRAM], capture_output=True, text=True,
                            check=True).stdout
    x2c = {}
    for line in output.splitlines():
        name, _, value = line.partition(" ")
        if name:
            x2c[name] = float(value)

    python = os.environ.get("TORCH_PYTHON", DEFAULT_PYTHON)
    if not os.path.exists(python):
        print("no interpreter at %s; set TORCH_PYTHON" % python)
        return 1
    result = subprocess.run([python, "-c", PYTHON_SIDE], capture_output=True,
                            text=True)
    if result.returncode != 0:
        print(result.stderr.strip())
        return 1
    expected = json.loads(result.stdout)

    worst, failures = 0.0, 0
    for name in sorted(expected):
        if name not in x2c:
            print("%-22s missing from the x2c output" % name)
            failures += 1
            continue
        delta = abs(expected[name] - x2c[name])
        worst = max(worst, delta)
        if delta > TOLERANCE:
            print("%-22s x2c %.12g python %.12g delta %.3g"
                  % (name, x2c[name], expected[name], delta))
            failures += 1
    print("%d operators compared, %d disagreed, largest delta %.3g"
          % (len(expected), failures, worst))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
