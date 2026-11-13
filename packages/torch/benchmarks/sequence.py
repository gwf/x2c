#!/usr/bin/env python3
"""Application 3, Python side: stateful sequence forecasting with TBPTT.

A tanh recurrent cell written out of three Linear applications. The plan
forbids substituting a fused native RNN here, so this runs the same three
affine terms per step that the x2c program runs.

    python3 packages/torch/benchmarks/sequence.py diagnose <artifacts> <out> <count>
    python3 packages/torch/benchmarks/sequence.py check <artifacts> <out>
    python3 packages/torch/benchmarks/sequence.py time <artifacts> <out> \\
        <window8|window32|window128> <windows>
    python3 packages/torch/benchmarks/sequence.py memory <artifacts> <out> \\
        4 <windows>
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

from prepare import SequenceRnn

sys.path.insert(0, os.path.join(common.PACKAGE, "tests"))
from adam_control import optimizer_for as adam_optimizer

PROFILE = common.PROFILE["sequence"]
WARMUP = 50


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


def configure():
    torch.set_num_threads(int(os.environ.get("X2C_TORCH_THREADS", "1")))
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError:
        # Already fixed by an earlier parallel region; report, do not fake.
        text("interop_threads_note", "already-set")
    record("interop_threads", torch.get_num_interop_threads())
    torch.manual_seed(0)


def optimizer_for(model):
    return adam_optimizer(model.parameters(), lr=PROFILE["lr"],
                            betas=(0.9, 0.999), eps=1e-8, weight_decay=0.0,
                            amsgrad=False, foreach=False, fused=False)


def load(artifacts):
    data = common.load_tensors(os.path.join(artifacts, "sequence-data.pt"))
    common.check_artifact_version(data, "sequence-data.pt")
    init = common.load_tensors(os.path.join(artifacts, "sequence-init.pt"))
    common.check_artifact_version(init, "sequence-init.pt")
    return data, init


def build(init):
    model = SequenceRnn(PROFILE)
    with torch.no_grad():
        for name, parameter in model.named_parameters():
            parameter.copy_(init[name])
    return model


def zero_state(model, streams):
    return torch.zeros(streams, PROFILE["hidden"])


def window_loss(model, inputs, targets, h):
    """One truncation window. The graph spans the window on purpose; it is
    released between windows, and only the detached state survives."""
    total = None
    for t in range(inputs.shape[1]):
        h = model.step(inputs[:, t], h)
        loss = torch.nn.functional.mse_loss(model.out(h), targets[:, t])
        total = loss if total is None else total + loss
    return total / inputs.shape[1], h


def windows_per_epoch(steps, window):
    return (steps - 1) // window


def train(model, optimizer, streams, count, window, offset=0, observe=None,
          microbatches=1):
    per_epoch = windows_per_epoch(streams.shape[1], window)
    h = zero_state(model, streams.shape[0])
    for index in range(count):
        position = (offset + index) % per_epoch
        if position == 0:
            # Stream boundary: the state resets, it does not carry over.
            h = zero_state(model, streams.shape[0])
        start = position * window
        inputs = streams[:, start:start + window]
        targets = streams[:, start + 1:start + window + 1]
        optimizer.zero_grad()
        if microbatches == 1:
            loss, h = window_loss(model, inputs, targets, h)
            loss.backward()
        else:
            # Gradient accumulation: backward per microbatch, one update.
            size = inputs.shape[0] // microbatches
            pieces, value = [], 0.0
            for m in range(microbatches):
                rows = slice(m * size, (m + 1) * size)
                part, part_h = window_loss(model, inputs[rows], targets[rows],
                                           h[rows])
                (part / microbatches).backward()
                pieces.append(part_h.detach())
                value += float(part.detach()) / microbatches
            h = torch.cat(pieces, dim=0)
            loss = torch.tensor(value)
        optimizer.step()
        h = h.detach()
        if observe:
            observe(index, loss)
    return h


def score(model, streams):
    """Held-out MSE of the next observation, hidden carried through."""
    with torch.inference_mode():
        h = zero_state(model, streams.shape[0])
        total, count = 0.0, 0
        for t in range(streams.shape[1] - 1):
            h = model.step(streams[:, t], h)
            total += float(torch.nn.functional.mse_loss(
                model.out(h), streams[:, t + 1]))
            count += 1
        return total / count


def baselines(train_streams, val_streams):
    with torch.inference_mode():
        target = val_streams[:, 1:]
        mean = train_streams.mean(dim=(0, 1))
        mean_mse = float(((target - mean) ** 2).mean())
        last_mse = float(torch.nn.functional.mse_loss(
            val_streams[:, :-1], target))
        return mean_mse, last_mse


def mode_check(artifacts, out):
    data, init = load(artifacts)
    train_streams, val_streams = data["data.train"], data["data.val"]
    window = PROFILE["window"]

    # One window, full values: outputs, loss, gradients, parameters after
    # the update.
    model = build(init)
    optimizer = optimizer_for(model)
    h = zero_state(model, train_streams.shape[0])
    inputs = train_streams[:, 0:window]
    targets = train_streams[:, 1:window + 1]
    loss, h_after = window_loss(model, inputs, targets, h)
    optimizer.zero_grad()
    loss.backward()
    step_one = {"probe.loss": loss.detach().clone(),
                "probe.state": h_after.detach().clone()}
    for name, parameter in model.named_parameters():
        step_one[f"grad.{name}"] = parameter.grad.detach().clone()
    optimizer.step()
    for name, parameter in model.named_parameters():
        step_one[f"step1.{name}"] = parameter.detach().clone()
    common.save_tensors(step_one,
                        os.path.join(out, "sequence-python-step1.pt"))
    record("probe_loss", float(loss.detach()))

    record("untrained_val_mse", score(build(init), val_streams))
    mean_mse, last_mse = baselines(train_streams, val_streams)
    record("mean_val_mse", mean_mse)
    record("last_value_val_mse", last_mse)

    model = build(init)
    optimizer = optimizer_for(model)
    curve = []
    train(model, optimizer, train_streams, PROFILE["windows"], window,
          observe=lambda i, loss: curve.append((i, float(loss))))
    record("trained_val_mse", score(model, val_streams))
    final = {f"final.{n}": p.detach().clone()
             for n, p in model.named_parameters()}
    common.save_tensors(final, os.path.join(out, "sequence-python-final.pt"))
    with open(os.path.join(out, "sequence-python-curve.txt"), "w") as handle:
        for index, value in curve:
            handle.write(f"{index} {value:.10g}\n")
            print(f"curve {index} {value:.10g}")

    # Save, reload, resume, optimizer state included.
    resumed = build(init)
    resume_optimizer = optimizer_for(resumed)
    half = PROFILE["windows"] // 2
    train(resumed, resume_optimizer, train_streams, half, window)
    checkpoint = os.path.join(out, "sequence-python-resume.pt")
    common.save_tensors(dict(resumed.state_dict()), checkpoint)
    torch.save(resume_optimizer.state_dict(),
               os.path.join(out, "sequence-python-optimizer.pt"))
    fresh = SequenceRnn(PROFILE)
    fresh.load_state_dict(common.load_tensors(checkpoint))
    fresh_optimizer = optimizer_for(fresh)
    fresh_optimizer.load_state_dict(
        torch.load(os.path.join(out, "sequence-python-optimizer.pt"),
                   weights_only=False))
    train(fresh, fresh_optimizer, train_streams, PROFILE["windows"] - half,
          window, offset=half)
    record("resumed_val_mse", score(fresh, val_streams))

    # The window sweep, as a correctness counterpart to its timings.
    for length in PROFILE["window_sweep"]:
        swept = build(init)
        train(swept, optimizer_for(swept), train_streams, 64, length)
        record(f"window{length}_val_mse", score(swept, val_streams))
    return 0


def mode_time(artifacts, out, variant, count):
    data, init = load(artifacts)
    text("variant", variant)
    record("threads", torch.get_num_threads())
    window = int(variant[len("window"):])
    streams = data["data.train"]

    warm = build(init)
    warm_start = time.monotonic()
    train(warm, optimizer_for(warm), streams, WARMUP, window)
    record("warmup_seconds", time.monotonic() - warm_start)

    model = build(init)
    optimizer = optimizer_for(model)
    start = time.monotonic()
    train(model, optimizer, streams, count, window)
    seconds = time.monotonic() - start
    record("windows", count)
    record("window_length", window)
    record("steady_seconds", seconds)
    record("windows_per_second", count / seconds)
    record("steps_per_second", count * window / seconds)
    return 0


def mode_memory(artifacts, out, profile, count):
    if profile != 4:
        sys.exit(f"sequence.py: no memory profile {profile}")
    sample("baseline", 0)
    data, init = load(artifacts)
    streams = data["data.train"]
    sample("loaded", 0)

    # Peak against window length: the graph is retained inside a window
    # and released between windows, which is the point of the sweep.
    for window in PROFILE["window_sweep"]:
        model = build(init)
        optimizer = optimizer_for(model)
        sample(f"window{window}-start", window)
        train(model, optimizer, streams, count, window)
        sample(f"window{window}-done", window)
        del model, optimizer
        sample("window-released", window)

    # Gradient accumulation over four microbatches, backward per
    # microbatch and one optimizer update.
    model = build(init)
    optimizer = optimizer_for(model)
    sample("accumulate-start", 4)
    train(model, optimizer, streams, count, PROFILE["window"], microbatches=4)
    sample("accumulate-done", 4)
    record("accumulated_val_mse", score(model, data["data.val"]))
    del model, optimizer
    sample("accumulate-released", 4)
    sample("final", 0)
    flush()
    return 0


def mode_diagnose(artifacts, out, count):
    start = time.monotonic()
    data, init = load(artifacts)
    streams = data["data.train"]
    record("load_seconds", time.monotonic() - start)
    warm = build(init)
    train(warm, optimizer_for(warm), streams, 50, PROFILE["window"])
    del warm
    start = time.monotonic()
    model = build(init)
    optimizer = optimizer_for(model)
    record("setup_seconds", time.monotonic() - start)
    window = PROFILE["window"]
    per_epoch = windows_per_epoch(streams.shape[1], window)
    h = None
    batch = forward = backward = optimize = cleanup = 0.0
    last_loss = 0.0
    for index in range(count):
        start = time.monotonic()
        position = index % per_epoch
        offset = position * window
        if position == 0 or h is None:
            h = zero_state(model, streams.shape[0])
        inputs = streams[:, offset:offset + window]
        targets = streams[:, offset + 1:offset + window + 1]
        optimizer.zero_grad()
        batch += time.monotonic() - start
        start = time.monotonic()
        loss, ended = window_loss(model, inputs, targets, h)
        forward += time.monotonic() - start
        start = time.monotonic()
        loss.backward()
        backward += time.monotonic() - start
        start = time.monotonic()
        optimizer.step()
        optimize += time.monotonic() - start
        if index + 1 == count:
            last_loss = float(loss.detach())
        start = time.monotonic()
        h = ended.detach()
        del inputs, targets, loss, ended
        cleanup += time.monotonic() - start
    start = time.monotonic()
    del h
    cleanup += time.monotonic() - start
    record("diagnostic_steps", count)
    record("diagnostic_loss", last_loss)
    for name, value in (("batch", batch), ("forward", forward),
                        ("backward", backward), ("optimizer", optimize),
                        ("cleanup", cleanup)):
        record(name + "_seconds", value)
    saved_model = os.path.join(out, "sequence-python-diagnostic-model.pt")
    saved_adam = os.path.join(out, "sequence-python-diagnostic-adam.pt")
    start = time.monotonic()
    common.save_tensors(dict(model.state_dict()), saved_model)
    torch.save(optimizer.state_dict(), saved_adam)
    record("checkpoint_save_seconds", time.monotonic() - start)
    restored = SequenceRnn(PROFILE)
    restored_optimizer = optimizer_for(restored)
    start = time.monotonic()
    restored.load_state_dict(common.load_tensors(saved_model))
    restored_optimizer.load_state_dict(
        torch.load(saved_adam, weights_only=False))
    record("checkpoint_load_seconds", time.monotonic() - start)
    with torch.no_grad():
        inputs, targets = streams[:, :window], streams[:, 1:window + 1]
        state = zero_state(model, streams.shape[0])
        original = float(window_loss(model, inputs, targets, state)[0])
        reloaded = float(window_loss(restored, inputs, targets, state)[0])
    record("diagnostic_reloaded_loss", reloaded)
    record("diagnostic_reload_difference", abs(original - reloaded))
    return 0


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    mode, artifacts, out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    configure()
    text("language", "python")
    text("torch_version", torch.__version__)
    if mode == "startup":
        return 0
    if mode == "check":
        return mode_check(artifacts, out)
    if mode == "diagnose":
        return mode_diagnose(artifacts, out, int(sys.argv[4]))
    if mode == "time":
        return mode_time(artifacts, out, sys.argv[4], int(sys.argv[5]))
    if mode == "memory":
        return mode_memory(artifacts, out, int(sys.argv[4]), int(sys.argv[5]))
    sys.exit(f"sequence.py: no mode {mode}")


if __name__ == "__main__":
    sys.exit(main())
