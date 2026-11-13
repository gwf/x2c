#!/usr/bin/env python3
"""Compare custom swish with Python custom and ordinary autograd on each device."""
from pathlib import Path
import subprocess
import torch

ROOT = Path(__file__).resolve().parents[1]


class Swish(torch.autograd.Function):
    @staticmethod
    def forward(context, value):
        context.save_for_backward(value)
        return value * value.sigmoid()

    @staticmethod
    def backward(context, gradient):
        value, = context.saved_tensors
        sigmoid = value.sigmoid()
        return gradient * (sigmoid + value * sigmoid * (1 - sigmoid))


devices = ['cpu'] + (['mps'] if torch.backends.mps.is_available() else [])
for device in devices:
    path = ROOT / 'builds' / f'custom-{device}.pt'
    subprocess.run([str(ROOT / 'builds' / 'custom-parity'), device, str(path)],
                   cwd=ROOT, check=True)
    native = torch.load(path, weights_only=False, map_location='cpu')
    for name, operation in [('custom', Swish.apply),
                            ('ordinary', lambda value: value * value.sigmoid())]:
        value = native['input'].to(device).detach().requires_grad_()
        output = operation(value)
        output.square().sum().backward()
        for key, actual in [('output', output), ('gradient', value.grad)]:
            torch.testing.assert_close(native[key], actual.detach().cpu(),
                                       rtol=2e-6, atol=1e-6,
                                       msg=f'{device} {name} {key}')
        print(f'{device}: custom values and gradients agree with Python {name}')
print('custom autograd parity passed')
