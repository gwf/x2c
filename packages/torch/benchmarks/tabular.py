#!/usr/bin/env python3
"""Application 1, Python side: tabular regression and batched prediction.

Ordinary eager PyTorch. It reads the same artifacts the x2c program reads
and prints the same `record` and `sample` lines, so `run.py` compares the
two without either side knowing about the other.

    python3 packages/torch/benchmarks/tabular.py check <artifacts> <out>
    python3 packages/torch/benchmarks/tabular.py time <artifacts> <out> \\
        <native|explicit|predict1|predict32|predict256> <updates>
    python3 packages/torch/benchmarks/tabular.py memory <artifacts> <out> \\
        <1|2|3|5|6> <steps> [churn-lifetime]
    python3 packages/torch/benchmarks/tabular.py trace <artifacts> <out> \\
        <native|explicit> <update>
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

from prepare import TabularMlp

sys.path.insert(0, os.path.join(common.PACKAGE, "tests"))
from adam_control import optimizer_for as adam_optimizer

PROFILE = common.PROFILE["tabular"]


def record(name, value):
    print(f"record {name} {value:.12g}")


def text(name, value):
    print(f"text {name} {value}")


SAMPLES = []


def sample(label, index):
    SAMPLES.append((label, index, time.monotonic() - START,
                    membytes.footprint(), membytes.footprint_peak(),
                    membytes.resident(), membytes.resident_peak()))


def flush():
    for row in SAMPLES:
        # The Scope and pool columns have no Python counterpart; zero
        # stands for "this layer does not exist here", never for "empty".
        print("sample {} {} {:.6f} {} {} {} {} 0 0 0 0 0 0 0 0 0".format(*row))
    print("dropped 0")


def threads():
    return int(os.environ.get("X2C_TORCH_THREADS", "1"))


def configure():
    torch.set_num_threads(threads())
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError:
        # Already fixed by an earlier parallel region; report, do not fake.
        text("interop_threads_note", "already-set")
    record("interop_threads", torch.get_num_interop_threads())
    torch.manual_seed(0)


def optimizer_for(model):
    """Use the explicitly selected stock or operation-matched Adam."""
    return adam_optimizer(model.parameters(), lr=PROFILE["lr"],
                            betas=(0.9, 0.999), eps=1e-8, weight_decay=0.0,
                            amsgrad=False, foreach=False, fused=False)


def load(artifacts):
    data = common.load_tensors(os.path.join(artifacts, "tabular-data.pt"))
    common.check_artifact_version(data, "tabular-data.pt")
    init = common.load_tensors(os.path.join(artifacts, "tabular-init.pt"))
    common.check_artifact_version(init, "tabular-init.pt")
    batches = common.load_tensors(os.path.join(artifacts,
                                               "tabular-batches.pt"))
    common.check_artifact_version(batches, "tabular-batches.pt")
    return data, init, batches


def build(init):
    model = TabularMlp(PROFILE)
    with torch.no_grad():
        for name, parameter in model.named_parameters():
            parameter.copy_(init[name])
    return model


def explicit_forward(model, x):
    """The documented parameter-enumeration forward, for the separately
    labelled lane. It changes calls and lifetime pressure, not the model."""
    for layer, last in ((model.l1, False), (model.l2, False),
                        (model.l3, True)):
        parameters = list(layer.parameters())
        x = x @ parameters[0].t() + parameters[1]
        if not last:
            x = torch.relu(x)
    return x


def evaluate(model, x, y, forward):
    with torch.inference_mode():
        return float(torch.nn.functional.mse_loss(forward(model, x), y))


def train(model, optimizer, data, batches, count, forward, offset=0,
          observe=None):
    x, y = data["data.x_train"], data["data.y_train"]
    rows = batches["batches"]
    for step in range(count):
        pick = rows[(offset + step) % rows.shape[0]]
        optimizer.zero_grad()
        loss = torch.nn.functional.mse_loss(
            forward(model, x.index_select(0, pick)), y.index_select(0, pick))
        loss.backward()
        optimizer.step()
        if observe:
            observe(step, loss)


def native_forward(model, x):
    return model(x)


FORWARDS = {"native": native_forward, "explicit": explicit_forward}


def mode_check(artifacts, out):
    data, init, batches = load(artifacts)
    x_val, y_val = data["data.x_val"], data["data.y_val"]

    # One update, full values: outputs, loss, every gradient, every
    # parameter after the step. This is what the tolerances are stated on.
    model = build(init)
    optimizer = optimizer_for(model)
    pick = batches["batches"][0]
    probe_x = data["data.x_train"].index_select(0, pick)
    probe_y = data["data.y_train"].index_select(0, pick)
    output = model(probe_x)
    loss = torch.nn.functional.mse_loss(output, probe_y)
    optimizer.zero_grad()
    loss.backward()
    step_one = {"probe.output": output.detach().clone(),
                "probe.loss": loss.detach().clone()}
    for name, parameter in model.named_parameters():
        step_one[f"grad.{name}"] = parameter.grad.detach().clone()
    optimizer.step()
    for name, parameter in model.named_parameters():
        step_one[f"step1.{name}"] = parameter.detach().clone()
    common.save_tensors(step_one, os.path.join(out, "tabular-python-step1.pt"))
    record("probe_loss", float(loss.detach()))

    # The two baselines the trained model must beat.
    untrained = build(init)
    record("untrained_val_mse", evaluate(untrained, x_val, y_val,
                                         native_forward))
    mean = data["data.y_train"].mean(dim=0, keepdim=True)
    record("mean_val_mse",
           float(torch.nn.functional.mse_loss(mean.expand_as(y_val), y_val)))

    # Full fixed profile, native Linear forward.
    model = build(init)
    optimizer = optimizer_for(model)
    curve = []
    train(model, optimizer, data, batches, PROFILE["updates"], native_forward,
          observe=lambda step, loss: curve.append((step, float(loss))))
    trained_mse = evaluate(model, x_val, y_val, native_forward)
    record("trained_val_mse", trained_mse)
    with torch.inference_mode():
        predictions = model(x_val).clone()
    final = {f"final.{n}": p.detach().clone()
             for n, p in model.named_parameters()}
    final["predictions"] = predictions
    common.save_tensors(final, os.path.join(out, "tabular-python-final.pt"))
    with open(os.path.join(out, "tabular-python-curve.txt"), "w") as handle:
        for step, value in curve:
            handle.write(f"{step} {value:.10g}\n")

    # The same training with the explicit parameter-enumeration forward.
    explicit = build(init)
    train(explicit, optimizer_for(explicit), data, batches,
          PROFILE["updates"], explicit_forward)
    record("explicit_val_mse", evaluate(explicit, x_val, y_val,
                                        explicit_forward))

    # Uninterrupted against save, reload, and resume, optimizer included.
    resumed = build(init)
    resume_optimizer = optimizer_for(resumed)
    half = PROFILE["updates"] // 2
    train(resumed, resume_optimizer, data, batches, half, native_forward)
    checkpoint = os.path.join(out, "tabular-python-resume.pt")
    common.save_tensors(dict(resumed.state_dict()), checkpoint)
    torch.save(resume_optimizer.state_dict(),
               os.path.join(out, "tabular-python-optimizer.pt"))
    fresh = TabularMlp(PROFILE)
    fresh.load_state_dict(common.load_tensors(checkpoint))
    fresh_optimizer = optimizer_for(fresh)
    fresh_optimizer.load_state_dict(
        torch.load(os.path.join(out, "tabular-python-optimizer.pt"),
                   weights_only=False))
    train(fresh, fresh_optimizer, data, batches, PROFILE["updates"] - half,
          native_forward, offset=half)
    record("resumed_val_mse", evaluate(fresh, x_val, y_val, native_forward))

    # Batched prediction under inference mode, one request scope.
    for size in PROFILE["predict_batches"]:
        rows = batches[f"requests.{size}"]
        with torch.inference_mode():
            total = 0.0
            for index in range(rows.shape[0]):
                batch = x_val.index_select(0, rows[index])
                total += float(model(batch).abs().sum())
        record(f"predict{size}_checksum", total)
    return 0


def mode_time(artifacts, out, variant, updates):
    data, init, batches = load(artifacts)
    text("variant", variant)
    record("threads", torch.get_num_threads())

    if variant.startswith("predict"):
        size = int(variant[len("predict"):])
        model = build(init)
        model.eval()
        rows = batches[f"requests.{size}"]
        x_val = data["data.x_val"]
        with torch.inference_mode():
            for index in range(50):
                model(x_val.index_select(0, rows[index % rows.shape[0]]))
        start = time.monotonic()
        with torch.inference_mode():
            checksum = 0.0
            for index in range(updates):
                batch = x_val.index_select(0, rows[index % rows.shape[0]])
                checksum += float(model(batch).abs().sum())
        seconds = time.monotonic() - start
        record("requests", updates)
        record("steady_seconds", seconds)
        record("requests_per_second", updates / seconds)
        record("checksum", checksum)
        return 0

    forward = FORWARDS[variant]
    # Warm lazy kernels and Adam state, then restore the initial state so
    # the measured window trains the same problem from the same point.
    warm = build(init)
    warm_start = time.monotonic()
    train(warm, optimizer_for(warm), data, batches, 50, forward)
    record("warmup_seconds", time.monotonic() - warm_start)

    model = build(init)
    optimizer = optimizer_for(model)
    start = time.monotonic()
    train(model, optimizer, data, batches, updates, forward)
    seconds = time.monotonic() - start
    record("updates", updates)
    record("steady_seconds", seconds)
    record("updates_per_second", updates / seconds)
    record("final_train_loss",
           evaluate(model, data["data.x_val"], data["data.y_val"], forward))
    return 0


def mode_trace(artifacts, out, variant, n):
    """The forward one ATen call at a time, so a comparison can name the
    operation that first differs. Dumps update `n`: the parameters before
    it, the batch, every intermediate, the loss, the gradients, and the
    parameters after."""
    data, init, batches = load(artifacts)
    model = build(init)
    optimizer = optimizer_for(model)
    forward = FORWARDS[variant]
    train(model, optimizer, data, batches, n, forward)

    trace = {}
    for name, parameter in model.named_parameters():
        trace[f"pre.{name}"] = parameter.detach().clone()
    rows = batches["batches"]
    pick = rows[n % rows.shape[0]]
    x = data["data.x_train"].index_select(0, pick)
    target = data["data.y_train"].index_select(0, pick)
    trace["batch.x"] = x
    trace["batch.y"] = target

    optimizer.zero_grad()
    h = x
    for index, layer in enumerate((model.l1, model.l2, model.l3)):
        parameters = list(layer.parameters())
        product = h @ parameters[0].t()
        affine = product + parameters[1]
        trace[f"fwd.m{index + 1}"] = product.detach().clone()
        trace[f"fwd.a{index + 1}"] = affine.detach().clone()
        h = affine
        if index < 2:
            h = torch.relu(affine)
            trace[f"fwd.r{index + 1}"] = h.detach().clone()
    loss = torch.nn.functional.mse_loss(h, target)
    trace["loss"] = loss.detach().clone()
    loss.backward()
    for name, parameter in model.named_parameters():
        trace[f"grad.{name}"] = parameter.grad.detach().clone()
    optimizer.step()
    for name, parameter in model.named_parameters():
        trace[f"post.{name}"] = parameter.detach().clone()
    common.save_tensors(trace, os.path.join(out, "tabular-python-trace.pt"))
    record("trace_update", n)
    record("trace_loss", float(loss.detach()))
    return 0


def mode_memory(artifacts, out, profile, steps, lifetime="ordinary"):
    sample("baseline", 0)
    data, init, batches = load(artifacts)
    sample("loaded", 0)

    if profile == 1:
        model = build(init)
        optimizer = optimizer_for(model)
        sample("setup", 0)
        train(model, optimizer, data, batches, 50, native_forward)
        sample("warm", 0)
        every = max(1, steps // 16)
        def observe(step, loss):
            if (step + 1) % every == 0:
                sample("step", step + 1)
        train(model, optimizer, data, batches, steps, native_forward,
              observe=observe)
        sample("trained", steps)
        rows = batches["requests.32"]
        x_val = data["data.x_val"]
        with torch.inference_mode():
            for index in range(steps):
                model(x_val.index_select(0, rows[index % rows.shape[0]]))
                if (index + 1) % every == 0:
                    sample("request", index + 1)
        sample("served", steps)
    elif profile == 2:
        model = build(init)
        input = data["data.x_val"]
        shapes = (1, 8, 32, 128)
        hoisted = lifetime == "hoisted"
        if hoisted:
            stable_named = list(model.named_parameters())
            parameters = [list(layer.parameters())
                          for layer in (model.l1, model.l2, model.l3)]
        text("churn_lifetime", lifetime)
        values_sum = 0.0
        indices_sum = named_elements = name_bytes = 0
        every = max(1, steps // 16)
        sample("setup", 0)
        for step in range(-50, steps):
            if step == 0:
                values_sum = 0.0
                indices_sum = named_elements = name_bytes = 0
                sample("warm", 0)
            with torch.inference_mode():
                named = (stable_named if hoisted
                         else list(model.named_parameters()))
                named_elements += sum(value.numel() for _, value in named)
                name_bytes += sum(len(name) for name, _ in named)
                count = shapes[(step + 50 if step < 0 else step) % 4]
                output = input.narrow(0, 0, count)
                if hoisted:
                    for index, (weight, bias) in enumerate(parameters):
                        output = output @ weight.t() + bias
                        if index < 2:
                            output = torch.relu(output)
                else:
                    output = explicit_forward(model, output)
                ranked = output.topk(2, dim=1, largest=True, sorted=True)
                values_sum += float(ranked.values.sum())
                indices_sum += int(ranked.indices.sum())
                del named, output, ranked
            if step >= 0 and (step + 1) % every == 0:
                sample("request", step + 1)
        record("churn_requests", steps)
        record("churn_values_sum", values_sum)
        record("churn_indices_sum", indices_sum)
        record("churn_named_elements", named_elements)
        record("churn_name_bytes", name_bytes)
        sample("served", steps)
    elif profile == 3:
        # A large tensor, a small survivor taken from it, and the same
        # small result cloned. A view pins its whole backing storage.
        sample("before", 0)
        big = torch.randn(4 * 1024 * 1024, 4)
        sample("allocated", 0)
        view = big.narrow(0, 0, 16)
        detached = (big[:16] * 2.0).detach()
        cloned = view.clone()
        del big
        sample("view-survives", 0)
        record("view_sum", float(view.sum()))
        record("detached_sum", float(detached.sum()))
        del view, detached
        sample("view-released", 0)
        record("clone_sum", float(cloned.sum()))
        del cloned
        sample("clone-released", 0)
    elif profile == 5:
        # Repeated lifetime and error recovery over one overwritten file.
        checkpoint = os.path.join(out, "tabular-python-cycle.pt")
        requests = 0
        for cycle in range(steps):
            model = build(init)
            optimizer = optimizer_for(model)
            scheduler = torch.optim.lr_scheduler.StepLR(optimizer, 10, 0.5)
            train(model, optimizer, data, batches, 20, native_forward,
                  offset=cycle * 20)
            scheduler.step()
            common.save_tensors(dict(model.state_dict()), checkpoint)
            reloaded = TabularMlp(PROFILE)
            reloaded.load_state_dict(common.load_tensors(checkpoint))
            requests += 20
            if requests % 100 == 0:
                try:
                    reloaded(torch.randn(4, PROFILE["features"] + 1))
                except RuntimeError:
                    pass
                # Valid work must still run, and the mode must survive.
                reloaded.eval()
                with torch.inference_mode():
                    reloaded(data["data.x_val"][:4])
                reloaded.train()
                record("mode_after_error", 1.0 if reloaded.training else 0.0)
            del model, optimizer, scheduler, reloaded
            if (cycle + 1) % max(1, steps // 16) == 0:
                sample("cycle", cycle + 1)
        sample("cycles-done", steps)
    elif profile == 6:
        # Positive control: retain outputs and their graphs deliberately,
        # capped at 128 MiB, then release and watch the counters return.
        model = build(init)
        x_val = data["data.x_val"]
        cap = 128 * 1024 * 1024
        retained, held = [], 0
        block = x_val[:2048]
        for index in range(steps):
            output = model(block) * 1.0
            held += output.numel() * 4 + block.numel() * 4
            if held > cap:
                record("control_capped_at", index)
                break
            retained.append(output)
            if (index + 1) % max(1, steps // 16) == 0:
                sample("retained", index + 1)
        record("control_retained", len(retained))
        sample("retained-peak", len(retained))
        retained.clear()
        sample("released", 0)
    else:
        sys.exit(f"tabular.py: no memory profile {profile}")

    sample("final", 0)
    flush()
    return 0


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    mode, artifacts, out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    configure()
    text("language", "python")
    text("torch_version", torch.__version__)
    text("torch_lib", os.path.join(os.path.dirname(torch.__file__), "lib"))
    if mode == "check":
        return mode_check(artifacts, out)
    if mode == "time":
        return mode_time(artifacts, out, sys.argv[4], int(sys.argv[5]))
    if mode == "trace":
        return mode_trace(artifacts, out, sys.argv[4], int(sys.argv[5]))
    if mode == "memory":
        return mode_memory(artifacts, out, int(sys.argv[4]), int(sys.argv[5]),
                           sys.argv[6] if len(sys.argv) > 6 else "ordinary")
    sys.exit(f"tabular.py: no mode {mode}")


START = time.monotonic()
sys.exit(main())
