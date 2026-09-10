#!/usr/bin/env python3
"""Write the fixed artifacts both languages read.

Equal seeds are not equal initial conditions across two libraries, so
nothing here is regenerated inside either program: the data, the exact
initial parameters, and the batch indices are produced once, hashed, and
loaded from disk by x2c and by Python alike.

    python3 packages/torch/benchmarks/prepare.py

Artifacts land in unittest/build/torch-comparison/artifacts, beside a
config.json recording the profile and every file's SHA-256.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

try:
    import torch
except ImportError:
    common.reexec_with_torch(__file__)

from torch import nn


def generator(seed):
    g = torch.Generator()
    g.manual_seed(seed)
    return g


def meta(mapping):
    mapping["meta.version"] = torch.tensor(
        [common.ARTIFACT_VERSION], dtype=torch.int64)
    return mapping


def tabular_teacher(profile, g):
    """A frozen two-layer nonlinear teacher. It is a controlled synthetic
    target, not a claim about any real dataset."""
    features = profile["features"]
    hidden = profile["teacher_hidden"]
    targets = profile["targets"]
    scale1 = features ** -0.5
    scale2 = hidden ** -0.5
    return {
        "w1": torch.randn(hidden, features, generator=g) * scale1,
        "b1": torch.randn(hidden, generator=g) * 0.1,
        "w2": torch.randn(targets, hidden, generator=g) * scale2,
        "b2": torch.randn(targets, generator=g) * 0.1,
    }


def tabular_rows(teacher, count, profile, g):
    x = torch.randn(count, profile["features"], generator=g)
    hidden = torch.tanh(x @ teacher["w1"].t() + teacher["b1"])
    y = hidden @ teacher["w2"].t() + teacher["b2"]
    y = y + torch.randn(y.shape, generator=g) * profile["noise"]
    return x.contiguous().float(), y.contiguous().float()


class TabularMlp(nn.Module):
    """128-256-128-8 with ReLU. The child names are l1, l2, l3, which is
    what the x2c composed module registers, so one checkpoint fits both."""

    def __init__(self, profile):
        super().__init__()
        self.l1 = nn.Linear(profile["features"], profile["hidden1"])
        self.l2 = nn.Linear(profile["hidden1"], profile["hidden2"])
        self.l3 = nn.Linear(profile["hidden2"], profile["targets"])

    def forward(self, x):
        return self.l3(torch.relu(self.l2(torch.relu(self.l1(x)))))


class SequenceRnn(nn.Module):
    """A tanh recurrent cell composed from three affine terms. The plan
    forbids substituting a fused native RNN here: both languages must run
    the same three Linear applications per step."""

    def __init__(self, profile):
        super().__init__()
        self.ih = nn.Linear(profile["observed"], profile["hidden"])
        self.hh = nn.Linear(profile["hidden"], profile["hidden"], bias=False)
        self.out = nn.Linear(profile["hidden"], profile["observed"])

    def step(self, x, h):
        return torch.tanh(self.ih(x) + self.hh(h))

    def forward(self, x, h):
        h = self.step(x, h)
        return self.out(h), h


def prepare_tabular():
    profile = common.PROFILE["tabular"]
    g = generator(profile["seed"])
    teacher = tabular_teacher(profile, g)
    x_train, y_train = tabular_rows(teacher, profile["train_rows"], profile, g)
    x_val, y_val = tabular_rows(teacher, profile["val_rows"], profile, g)

    data = meta({
        "data.x_train": x_train, "data.y_train": y_train,
        "data.x_val": x_val, "data.y_val": y_val,
        "teacher.w1": teacher["w1"].float(),
        "teacher.b1": teacher["b1"].float(),
        "teacher.w2": teacher["w2"].float(),
        "teacher.b2": teacher["b2"].float(),
    })
    common.save_tensors(data, common.artifact("tabular-data.pt"))

    torch.manual_seed(profile["seed"] + 1)
    model = TabularMlp(profile)
    common.save_tensors(
        meta({name: parameter.detach().clone()
              for name, parameter in model.named_parameters()}),
        common.artifact("tabular-init.pt"))

    # Precomputed batch rows: neither language draws from its own RNG.
    g = generator(profile["seed"] + 2)
    batches = torch.randint(0, profile["train_rows"],
                            (profile["updates"], profile["batch"]),
                            generator=g, dtype=torch.int64)
    # Request rows for the batched-prediction lane, one block per size.
    requests = {}
    for size in profile["predict_batches"]:
        requests[f"requests.{size}"] = torch.randint(
            0, profile["val_rows"],
            (profile["predict_requests"], size), generator=g,
            dtype=torch.int64)
    common.save_tensors(meta({"batches": batches, **requests}),
                        common.artifact("tabular-batches.pt"))


def sequence_streams(profile, count, steps, g, phase_offset):
    """A driven nonlinear system: tanh state update, four sinusoidal
    drivers, fixed observation noise. The forcing keeps the task from
    decaying to a constant."""
    latent, observed, drivers = (profile["latent"], profile["observed"],
                                 profile["drivers"])
    a = torch.randn(latent, latent, generator=g)
    a = a * (profile["spectral_norm"] / torch.linalg.matrix_norm(a, ord=2))
    b = torch.randn(latent, drivers, generator=g) * 0.5
    c = torch.randn(observed, latent, generator=g) * (latent ** -0.5)

    frequency = 0.01 + 0.09 * torch.rand(count, drivers, generator=g)
    phase = phase_offset + 2.0 * torch.pi * torch.rand(count, drivers,
                                                       generator=g)
    t = torch.arange(steps, dtype=torch.float32).reshape(steps, 1, 1)
    drive = torch.sin(t * frequency.unsqueeze(0) + phase.unsqueeze(0))

    z = torch.zeros(count, latent)
    observations = torch.zeros(steps, count, observed)
    for step in range(steps):
        z = torch.tanh(z @ a.t() + drive[step] @ b.t())
        observations[step] = z @ c.t()
    observations = observations + torch.randn(
        observations.shape, generator=g) * profile["noise"]
    # (streams, steps, observed) so a stream is contiguous.
    return observations.permute(1, 0, 2).contiguous().float(), (a, b, c)


def prepare_sequence():
    profile = common.PROFILE["sequence"]
    g = generator(profile["seed"])
    train, system = sequence_streams(profile, profile["train_streams"],
                                     profile["train_steps"], g, 0.0)
    # Held-out phases are offset, so evaluation is not a memorized driver.
    g = generator(profile["seed"] + 1)
    held, _ = sequence_streams(profile, profile["val_streams"],
                               profile["val_steps"], g, 1.0)
    common.save_tensors(
        meta({"data.train": train, "data.val": held,
              "system.a": system[0].float(), "system.b": system[1].float(),
              "system.c": system[2].float()}),
        common.artifact("sequence-data.pt"))

    torch.manual_seed(profile["seed"] + 2)
    model = SequenceRnn(profile)
    common.save_tensors(
        meta({name: parameter.detach().clone()
              for name, parameter in model.named_parameters()}),
        common.artifact("sequence-init.pt"))


def prepare_interop():
    """Inputs for the diagnostic chain, one triple per element count."""
    profile = common.PROFILE["interop"]
    g = generator(profile["seed"])
    values = {}
    for count in profile["elements"]:
        values[f"x.{count}"] = torch.randn(count, generator=g)
        # a just below 1 and a small b keep a 512-operation chain finite.
        values[f"a.{count}"] = 0.99 + 0.01 * torch.rand(count, generator=g)
        values[f"b.{count}"] = 0.01 * torch.randn(count, generator=g)
    common.save_tensors(meta(values), common.artifact("interop-init.pt"))


def mnist_model(profile):
    """The plan's architecture as one Sequential. The positions are the
    state names, and they are the same ones Module.sequential produces."""
    return nn.Sequential(
        nn.Conv2d(1, profile["channels1"], profile["kernel"],
                  padding=profile["padding"]),
        nn.BatchNorm2d(profile["channels1"]),
        nn.ReLU(),
        nn.MaxPool2d(profile["pool"]),
        nn.Conv2d(profile["channels1"], profile["channels2"],
                  profile["kernel"], padding=profile["padding"]),
        nn.BatchNorm2d(profile["channels2"]),
        nn.ReLU(),
        nn.MaxPool2d(profile["pool"]),
        nn.Flatten(),
        nn.Linear(profile["flat"], profile["hidden"]),
        nn.ReLU(),
        nn.Linear(profile["hidden"], profile["classes"]),
    )


def read_idx(path):
    """The IDX format: a magic word naming the element type and rank, the
    dimensions, then the bytes. Only unsigned-byte files exist in MNIST."""
    import numpy

    with open(path, "rb") as handle:
        data = handle.read()
    magic = int.from_bytes(data[0:4], "big")
    if magic >> 8 != 0x08:
        raise ValueError(f"{path}: not an unsigned-byte IDX file")
    rank = magic & 0xFF
    shape = [int.from_bytes(data[4 + 4 * i:8 + 4 * i], "big")
             for i in range(rank)]
    values = numpy.frombuffer(data[4 + 4 * rank:], dtype=numpy.uint8)
    return torch.from_numpy(values.reshape(shape).copy())


def mnist_tensors(root, train):
    """The same two tensors Torch.mnist returns in x2c: N x 1 x 28 x 28
    float32 scaled to [0, 1], then the fixed normalization, and N int64
    classes."""
    profile = common.PROFILE["mnist"]
    prefix = "train" if train else "t10k"
    images = read_idx(os.path.join(root, f"{prefix}-images-idx3-ubyte"))
    targets = read_idx(os.path.join(root, f"{prefix}-labels-idx1-ubyte"))
    images = images.unsqueeze(1).to(torch.float32).div(255.0)
    images = (images - profile["mean"]) / profile["std"]
    return images.contiguous(), targets.to(torch.int64).contiguous()


def prepare_mnist():
    """The IDX files are read in place; only the initial parameters and
    the epoch permutations become artifacts."""
    profile = common.PROFILE["mnist"]
    root = common.mnist_root()
    missing = [name for name in common.MNIST_FILES
               if not os.path.exists(os.path.join(root, name))]
    if missing:
        print(f"mnist: {root} is missing {', '.join(missing)}; "
              f"set TORCH_MNIST to the directory holding the four IDX files")
        return None

    torch.manual_seed(profile["seed"])
    model = mnist_model(profile)
    common.save_tensors(meta(dict(model.state_dict())),
                        common.artifact("mnist-init.pt"))

    g = generator(profile["seed"] + 1)
    rows = read_idx(os.path.join(root, "train-labels-idx1-ubyte")).shape[0]
    order = torch.stack([torch.randperm(rows, generator=g)
                         for _ in range(profile["epochs"])])
    common.save_tensors(meta({"order": order.to(torch.int64)}),
                        common.artifact("mnist-batches.pt"))
    return {name: {"sha256": common.sha256(os.path.join(root, name)),
                   "bytes": os.path.getsize(os.path.join(root, name))}
            for name in common.MNIST_FILES}


def main():
    common.ensure_directories()
    prepare_tabular()
    prepare_sequence()
    prepare_interop()
    mnist = prepare_mnist()

    files = {}
    for name in sorted(os.listdir(common.ARTIFACTS)):
        if name.endswith(".pt"):
            path = common.artifact(name)
            files[name] = {"sha256": common.sha256(path),
                           "bytes": os.path.getsize(path)}
    config = dict(common.PROFILE)
    config["torch_version"] = torch.__version__
    config["artifacts"] = files
    config["mnist_root"] = common.mnist_root()
    config["mnist_files"] = mnist
    with open(common.config_path(), "w") as handle:
        json.dump(config, handle, indent=2, sort_keys=True)
        handle.write("\n")
    for name, entry in files.items():
        print(f"{name:<24} {entry['bytes']:>12} bytes  "
              f"{entry['sha256'][:16]}")
    print(f"config {common.config_path()}")


if __name__ == "__main__":
    main()
