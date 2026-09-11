"""CPU Adam control using libtorch 2.10's scalar operation order.

This is an experimental reference, not the stock PyTorch optimizer.
Algorithm owner: pytorch/v2.10.0/torch/csrc/api/src/optim/adam.cpp.
"""

import math
import os

import torch


class LibtorchAdam(torch.optim.Adam):
    @torch.no_grad()
    def step(self, closure=None):
        loss = None
        if closure is not None:
            with torch.enable_grad():
                loss = closure()
        for group in self.param_groups:
            if any(group.get(key) for key in (
                    "maximize", "capturable", "differentiable", "foreach",
                    "fused", "decoupled_weight_decay")):
                raise ValueError("control requires ordinary scalar Adam")
            beta1, beta2 = group["betas"]
            for parameter in group["params"]:
                gradient = parameter.grad
                if gradient is None:
                    continue
                if gradient.is_sparse or parameter.is_complex():
                    raise ValueError("control requires dense real tensors")
                state = self.state[parameter]
                if not state:
                    state["step"] = torch.tensor(0.0)
                    for name in ("exp_avg", "exp_avg_sq"):
                        state[name] = torch.zeros_like(parameter)
                    if group["amsgrad"]:
                        state["max_exp_avg_sq"] = torch.zeros_like(parameter)
                state["step"] += 1
                count = int(state["step"].item())
                if group["weight_decay"]:
                    gradient = gradient.add(parameter,
                                            alpha=group["weight_decay"])
                moment, square = state["exp_avg"], state["exp_avg_sq"]
                moment.mul_(beta1).add_(gradient, alpha=1 - beta1)
                square.mul_(beta2).addcmul_(gradient, gradient, value=1 - beta2)
                variance = square
                if group["amsgrad"]:
                    variance = state["max_exp_avg_sq"]
                    torch.maximum(variance, square, out=variance)
                denominator = variance.sqrt().div_(math.sqrt(
                    1 - math.pow(beta2, count))).add_(group["eps"])
                parameter.addcdiv_(moment, denominator,
                                  value=-group["lr"] / (1 - math.pow(beta1, count)))
        return loss


def optimizer_for(parameters, **options):
    kind = os.environ.get("X2C_TORCH_OPTIMIZER", "stock")
    if kind not in ("stock", "matched"):
        raise ValueError(f"unknown optimizer comparison: {kind}")
    owner = LibtorchAdam if kind == "matched" else torch.optim.Adam
    return owner(parameters, **options)
