#!/usr/bin/env python3
"""Check that x2c training and Python training agree, in both directions.

Run through `make -C packages/torch verify-python`. TORCH_PYTHON names an
interpreter with the pinned torch wheel; this script re-executes itself
there when the interpreter it started under has no torch.

Step 1  the x2c program trains 20 Adam steps from seed 0 and writes
        builds/x2c-init.pt (initial parameters plus the data) and
        builds/x2c-model.pt.
Step 2  Python rebuilds the same model from those initial parameters,
        replays the same 20 steps, and compares the final loss.
Step 3  Python writes builds/python-model.pt, the x2c program loads it,
        and the two evaluations of the Python-trained weights are compared.
Step 4  builds/module-names prints what each native layer enumerates, and
        Python compares it with the same module's state_dict() keys.
"""

import os
import subprocess
import sys

DEFAULT_PYTHON = "/Users/gary/Git/Bonsai-demo/.venv/bin/python"
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROGRAM = os.path.join(PACKAGE, "builds", "checkpoint-roundtrip")
NAMES = os.path.join(PACKAGE, "builds", "module-names")
INIT = os.path.join(PACKAGE, "builds", "x2c-init.pt")
PYTHON_MODEL = os.path.join(PACKAGE, "builds", "python-model.pt")
STEPS = 20
LR = 0.05
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
        self.l2 = nn.Linear(8, 1)

    def forward(self, x):
        return self.l2(torch.tanh(self.l1(x)))


def run_x2c(*args):
    finished = subprocess.run([PROGRAM, *args], cwd=PACKAGE,
                              capture_output=True, text=True, check=True)
    line = finished.stdout.strip().splitlines()[-1]
    assert line.startswith("loss "), line
    return float(line.split()[1])


def agree(what, left, right):
    scale = max(abs(left), abs(right), 1e-12)
    relative = abs(left - right) / scale
    print(f"{what:<28} x2c {left:.8f}  python {right:.8f}  "
          f"relative {relative:.2e}")
    if relative > TOLERANCE:
        sys.exit(f"{what} disagree beyond {TOLERANCE}")


def python_modules():
    return {
        "Conv2d": nn.Conv2d(1, 8, 3),
        "Conv1d": nn.Conv1d(2, 4, 3),
        "BatchNorm2d": nn.BatchNorm2d(3),
        "BatchNorm1d": nn.BatchNorm1d(3),
        "LayerNorm": nn.LayerNorm([4]),
        "LSTM": nn.LSTM(3, 4, 1, batch_first=True),
        "GRU": nn.GRU(3, 4, 1, batch_first=True),
        "Embedding": nn.Embedding(5, 3),
        "Linear": nn.Linear(3, 2),
        "Sequential": nn.Sequential(nn.Linear(3, 4), nn.ReLU(),
                                    nn.Linear(4, 2)),
    }


def compare_names():
    finished = subprocess.run([NAMES], cwd=PACKAGE, capture_output=True,
                              text=True, check=True)
    expected = python_modules()
    compared = 0
    for line in finished.stdout.splitlines():
        kind, *names = line.split()
        wanted = list(expected[kind].state_dict().keys())
        if names != wanted:
            sys.exit(f"{kind} names disagree: {names} vs {wanted}")
        compared += len(names)
    print(f"module state names          {len(expected)} modules, "
          f"{compared} names identical")


def main():
    print(f"torch {torch.__version__} at {sys.executable}")
    x2c_loss = run_x2c()

    # The C++ pickler tags its dict with torch.jit._pickle.restore_type_tag,
    # which weights_only=True does not allow.
    start = torch.load(INIT, weights_only=False)
    x, y = start["data.x"], start["data.y"]

    model = Mlp()
    with torch.no_grad():
        for name, parameter in model.named_parameters():
            parameter.copy_(start[name])

    optimizer = torch.optim.Adam(model.parameters(), lr=LR)
    for _ in range(STEPS):
        optimizer.zero_grad()
        loss = nn.functional.mse_loss(model(x), y)
        loss.backward()
        optimizer.step()
    with torch.no_grad():
        python_loss = nn.functional.mse_loss(model(x), y).item()
    agree("trained loss", x2c_loss, python_loss)

    # Python must save a plain dict; the C++ unpickler cannot read the
    # OrderedDict that state_dict() returns.
    torch.save(dict(model.state_dict()), PYTHON_MODEL)
    reloaded = run_x2c("load")
    agree("python weights in x2c", reloaded, python_loss)
    compare_names()
    print("verify-python: agreed")


main()
