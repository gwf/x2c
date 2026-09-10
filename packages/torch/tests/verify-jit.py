#!/usr/bin/env python3
"""Check that x2c runs a TorchScript model the way Python does.

Run through `make -C packages/torch verify-jit`. TORCH_PYTHON names an
interpreter with the pinned torch wheel; this script re-executes itself
there when the interpreter it started under has no torch.

Step 1  Python scripts a 2-layer MLP with fixed weights into
        builds/scripted.pt, and a second module returning a tuple of
        (logits, predicted class) into builds/scripted-pair.pt.
Step 2  examples/jit-infer.x loads both, runs the same fixed batch, and
        prints its logits and classes.
Step 3  Python runs the same batch through the same modules and compares.
"""

import os
import subprocess
import sys

DEFAULT_PYTHON = "/Users/gary/Git/Bonsai-demo/.venv/bin/python"
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROGRAM = os.path.join(PACKAGE, "builds", "jit-infer")
SCRIPTED = os.path.join(PACKAGE, "builds", "scripted.pt")
SCRIPTED_PAIR = os.path.join(PACKAGE, "builds", "scripted-pair.pt")
TOLERANCE = 1e-5

try:
    import torch
except ImportError:
    interpreter = os.environ.get("TORCH_PYTHON", DEFAULT_PYTHON)
    if os.environ.get("X2C_TORCH_REEXEC") or not os.path.exists(interpreter):
        sys.exit("no interpreter with torch; set TORCH_PYTHON")
    os.environ["X2C_TORCH_REEXEC"] = "1"
    os.execv(interpreter, [interpreter, os.path.abspath(__file__)])

from torch import nn


class Mlp(nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = nn.Linear(4, 8)
        self.l2 = nn.Linear(8, 3)

    def forward(self, x):
        return self.l2(torch.tanh(self.l1(x)))


class MlpWithClass(nn.Module):
    def __init__(self, mlp):
        super().__init__()
        self.mlp = mlp

    def forward(self, x):
        logits = self.mlp(x)
        return logits, logits.argmax(1).to(torch.float32)


def fixed_weights(model):
    # Weights a Python run and an x2c run can both reproduce exactly.
    with torch.no_grad():
        for index, parameter in enumerate(model.parameters()):
            values = torch.arange(parameter.numel(), dtype=torch.float32)
            step = 0.05 if index % 2 == 0 else 0.1
            parameter.copy_((values * step - 0.5).reshape(parameter.shape))
    return model


def main():
    print(f"torch {torch.__version__} at {sys.executable}")
    model = fixed_weights(Mlp()).eval()
    torch.jit.script(model).save(SCRIPTED)
    torch.jit.script(MlpWithClass(model).eval()).save(SCRIPTED_PAIR)

    finished = subprocess.run([PROGRAM], cwd=PACKAGE, capture_output=True,
                              text=True, check=True)
    print(finished.stdout, end="")
    printed = {}
    for line in finished.stdout.splitlines():
        parts = line.split()
        if parts[0] == "logits":
            printed[f"logits {parts[1]}"] = [float(v) for v in parts[2:]]
        elif parts[0] == "classes":
            printed["classes"] = [float(v) for v in parts[1:]]

    x = torch.arange(0.0, 8.0, 1.0, dtype=torch.float32).reshape(2, 4) / 8.0
    with torch.no_grad():
        logits, classes = MlpWithClass(model)(x)

    checked = 0
    for row in range(logits.shape[0]):
        expected = logits[row].tolist()
        actual = printed[f"logits {row}"]
        for left, right in zip(actual, expected):
            if abs(left - right) > TOLERANCE:
                sys.exit(f"row {row} disagrees: {actual} vs {expected}")
            checked += 1
    if printed["classes"] != classes.tolist():
        sys.exit(f"classes disagree: {printed['classes']} vs {classes}")
    checked += len(printed["classes"])
    print(f"verify-jit: agreed on {checked} values")


main()
