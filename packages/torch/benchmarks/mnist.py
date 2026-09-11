#!/usr/bin/env python3
"""Application 2, Python side: MNIST convolutional classification.

Native modules on both sides: the model is one `nn.Sequential`, which is
what the x2c program builds with `Module.sequential`/`push`, and the child
names match by position. No dropout, so neither side draws an RNG mask.

    python3 packages/torch/benchmarks/mnist.py check <artifacts> <out>
    python3 packages/torch/benchmarks/mnist.py time <artifacts> <out> \\
        <epoch> <batches>
"""

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

from torch import nn
from prepare import mnist_model, mnist_tensors

sys.path.insert(0, os.path.join(common.PACKAGE, "tests"))
from adam_control import optimizer_for as adam_optimizer

PROFILE = common.PROFILE["mnist"]


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


def optimizer_for(model):
    return adam_optimizer(model.parameters(), lr=PROFILE["lr"],
                            betas=(0.9, 0.999), eps=1e-8, weight_decay=0.0,
                            amsgrad=False, foreach=False, fused=False)


def load(artifacts):
    init = common.load_tensors(os.path.join(artifacts, "mnist-init.pt"))
    common.check_artifact_version(init, "mnist-init.pt")
    order = common.load_tensors(os.path.join(artifacts, "mnist-batches.pt"))
    common.check_artifact_version(order, "mnist-batches.pt")
    train = mnist_tensors(common.mnist_root(), True)
    test = mnist_tensors(common.mnist_root(), False)
    return init, order, train, test


def build(init):
    model = mnist_model(PROFILE)
    state = {k: v for k, v in init.items() if not k.startswith("meta.")}
    model.load_state_dict(state)
    return model


def accuracy(model, images, targets):
    """In chunks, so the whole test set never forms one batch."""
    model.eval()
    correct = 0
    with torch.inference_mode():
        for start in range(0, images.shape[0], 1000):
            block = images[start:start + 1000]
            predicted = model(block).argmax(dim=1)
            correct += int((predicted == targets[start:start + 1000]).sum())
    model.train()
    return correct / images.shape[0]


def train_batches(model, optimizer, images, targets, order, count,
                  offset=0, observe=None):
    batch = PROFILE["batch"]
    per_epoch = (images.shape[0] + batch - 1) // batch
    for index in range(count):
        position = (offset + index) % per_epoch
        epoch = ((offset + index) // per_epoch) % order.shape[0]
        start = position * batch
        span = min(batch, images.shape[0] - start)
        pick = order[epoch][start:start + span]
        optimizer.zero_grad()
        loss = nn.functional.cross_entropy(
            model(images.index_select(0, pick)),
            targets.index_select(0, pick))
        loss.backward()
        optimizer.step()
        if observe:
            observe(index, loss)


def mode_check(artifacts, out):
    init, order, train, test = load(artifacts)
    images, targets = train
    test_images, test_targets = test
    record("data_checksum", float(images[:1000].sum()))
    record("test_checksum", float(test_images[:1000].sum()))

    model = build(init)
    model.train()
    optimizer = optimizer_for(model)
    pick = order["order"][0][:PROFILE["batch"]]
    output = model(images.index_select(0, pick))
    loss = nn.functional.cross_entropy(output, targets.index_select(0, pick))
    optimizer.zero_grad()
    loss.backward()
    step_one = {"probe.output": output.detach().clone(),
                "probe.loss": loss.detach().clone()}
    for name, parameter in model.named_parameters():
        step_one[f"grad.{name}"] = parameter.grad.detach().clone()
    optimizer.step()
    for name, parameter in model.named_parameters():
        step_one[f"step1.{name}"] = parameter.detach().clone()
    # BatchNorm's running statistics move in train mode; they are part of
    # the comparison, not an implementation detail.
    for name, buffer in model.named_buffers():
        step_one[f"buffer.{name}"] = buffer.detach().clone().float()
    common.save_tensors(step_one, os.path.join(out, "mnist-python-step1.pt"))
    record("probe_loss", float(loss.detach()))

    record("untrained_accuracy", accuracy(build(init), test_images,
                                          test_targets))

    model = build(init)
    model.train()
    optimizer = optimizer_for(model)
    batches = PROFILE["batches_per_epoch"] * PROFILE["epochs"]
    curve = []
    train_batches(model, optimizer, images, targets, order["order"], batches,
                  observe=lambda i, loss: curve.append((i, float(loss))))
    record("trained_accuracy", accuracy(model, test_images, test_targets))
    final = {f"final.{n}": p.detach().clone()
             for n, p in model.named_parameters()}
    for name, buffer in model.named_buffers():
        final[f"buffer.{name}"] = buffer.detach().clone().float()
    model.eval()
    with torch.inference_mode():
        final["predictions"] = model(test_images[:2000]).clone()
    model.train()
    common.save_tensors(final, os.path.join(out, "mnist-python-final.pt"))
    with open(os.path.join(out, "mnist-python-curve.txt"), "w") as handle:
        for index, value in curve:
            handle.write(f"{index} {value:.10g}\n")

    # Reload must reproduce the predictions, buffers included.
    checkpoint = os.path.join(out, "mnist-python-model.pt")
    common.save_tensors(dict(model.state_dict()), checkpoint)
    reloaded = mnist_model(PROFILE)
    reloaded.load_state_dict(common.load_tensors(checkpoint))
    record("reloaded_accuracy", accuracy(reloaded, test_images, test_targets))
    record("mode_after_reload", 1.0 if reloaded.training else 0.0)
    return 0


def mode_time(artifacts, out, variant, batches):
    init, order, train, test = load(artifacts)
    images, targets = train
    text("variant", variant)
    record("threads", torch.get_num_threads())
    sample("loaded", 0)

    warm = build(init)
    warm.train()
    warm_start = time.monotonic()
    train_batches(warm, optimizer_for(warm), images, targets, order["order"],
                  20)
    record("warmup_seconds", time.monotonic() - warm_start)

    model = build(init)
    model.train()
    optimizer = optimizer_for(model)
    sample("ready", 0)
    start = time.monotonic()
    train_batches(model, optimizer, images, targets, order["order"], batches)
    seconds = time.monotonic() - start
    sample("trained", batches)
    record("batches", batches)
    record("steady_seconds", seconds)
    record("batches_per_second", batches / seconds)
    record("images_per_second", batches * PROFILE["batch"] / seconds)
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
        # Already fixed by an earlier parallel region; report, do not fake.
        text("interop_threads_note", "already-set")
    record("interop_threads", torch.get_num_interop_threads())
    torch.manual_seed(0)
    text("language", "python")
    text("torch_version", torch.__version__)
    if mode == "check":
        return mode_check(artifacts, out)
    if mode == "time":
        return mode_time(artifacts, out, sys.argv[4], int(sys.argv[5]))
    sys.exit(f"mnist.py: no mode {mode}")


if __name__ == "__main__":
    sys.exit(main())
