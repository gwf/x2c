#!/usr/bin/env python3
"""Compare every Adam moment, option and parameter after cross-language resume."""
from pathlib import Path
import copy
import subprocess
import torch
from adam_control import LibtorchAdam

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'builds' / 'interchange'
OUT.mkdir(exist_ok=True)
X = torch.tensor([[1., 2.], [2., 1.], [-1., 3.], [0., 2.]], dtype=torch.float64)
Y = torch.tensor([[2.], [4.], [-3.], [-1.]], dtype=torch.float64)


def load(path):
    return torch.load(path, weights_only=False)


def run(model, state, name, steps, invalid=None):
    prefix = OUT / name
    arguments = [str(ROOT / 'builds' / 'optimizer-interchange'), str(model),
                 str(state), str(prefix), str(steps)]
    if invalid is not None:
        arguments.append(str(invalid))
    subprocess.run(arguments, cwd=ROOT, check=True)
    return prefix


def path(prefix, suffix):
    return Path(f'{prefix}-{suffix}.pt')


def same(left, right, name='state'):
    if isinstance(left, torch.Tensor):
        assert isinstance(right, torch.Tensor), name
        torch.testing.assert_close(left, right, atol=1e-12, rtol=1e-12,
                                   check_dtype=False, msg=name)
    elif isinstance(left, dict):
        assert left.keys() == right.keys(), (name, left.keys(), right.keys())
        for key in left:
            same(left[key], right[key], f'{name}.{key}')
    elif isinstance(left, (list, tuple)):
        assert len(left) == len(right), name
        for i, (a, b) in enumerate(zip(left, right)):
            same(a, b, f'{name}[{i}]')
    else:
        assert left == right, (name, left, right)


def step(model, optimizer):
    optimizer.zero_grad()
    torch.nn.functional.mse_loss(model(X), Y).backward()
    optimizer.step()


def compare_resume(model_path, state_path, name):
    model = torch.nn.Linear(2, 1, dtype=torch.float64)
    model.load_state_dict(load(model_path))
    saved = load(state_path)
    flat = list(model.parameters())
    groups, offset = [], 0
    for group in saved['param_groups']:
        n = len(group['params'])
        groups.append({'params': flat[offset:offset+n]})
        offset += n
    optimizer = LibtorchAdam(groups)
    optimizer.load_state_dict(saved)
    result = run(model_path, state_path, name, 3)
    for _ in range(3):
        step(model, optimizer)
    same(load(path(result, 'model')), model.state_dict(), 'parameters')
    actual = load(path(result, 'optim'))
    expected = optimizer.state_dict()
    for group in expected['param_groups']:
        group['foreach'] = False
        group['fused'] = False
    same(actual, expected)
    print(f'{name}: every parameter and optimizer field agrees after 3 updates')
    return result


initial = run('-', '-', 'x2c', 5)
resumed = compare_resume(path(initial, 'model'), path(initial, 'optim'),
                         'x2c-to-python')
model = torch.nn.Linear(2, 1, dtype=torch.float64)
model.load_state_dict(load(path(initial, 'before-model')))
optimizer = LibtorchAdam([
    {'params': [model.weight], 'lr': .02},
    {'params': [model.bias], 'lr': .04}], betas=(.8, .95), eps=1e-7,
    weight_decay=.02, amsgrad=True, foreach=False, fused=False)
for _ in range(5):
    step(model, optimizer)
torch.save(dict(model.state_dict()), OUT / 'python-model.pt')
torch.save(optimizer.state_dict(), OUT / 'python-optim.pt')
compare_resume(OUT / 'python-model.pt', OUT / 'python-optim.pt',
               'python-groups-to-x2c')
for name, options in [
        ('python-default-adam', {}),
        ('python-integer-options', {'lr': 1, 'eps': 0, 'weight_decay': 0}),
        ('python-tensor-rate', {'lr': torch.tensor(.001, dtype=torch.float64)})]:
    model = torch.nn.Linear(2, 1, dtype=torch.float64)
    model.load_state_dict(load(path(initial, 'before-model')))
    optimizer = torch.optim.Adam(model.parameters(), **options)
    for _ in range(5):
        step(model, optimizer)
    model_path, state_path = OUT / f'{name}-model.pt', OUT / f'{name}-optim.pt'
    torch.save(dict(model.state_dict()), model_path)
    torch.save(optimizer.state_dict(), state_path)
    compare_resume(model_path, state_path, name)
empty = run('-', '-', 'empty', 0)
assert load(path(empty, 'optim'))['state'] == {}
compare_resume(path(empty, 'model'), path(empty, 'optim'), 'uninitialized')
for name in ['moment-shape', 'duplicate-id', 'negative-rate', 'fractional-step']:
    invalid = copy.deepcopy(load(path(initial, 'optim')))
    if name == 'moment-shape':
        invalid['state'][0]['exp_avg'] = torch.ones(1, dtype=torch.float64)
    elif name == 'duplicate-id':
        invalid['param_groups'][0]['params'] = [0, 0]
    elif name == 'negative-rate':
        invalid['param_groups'][0]['lr'] = -1
    else:
        invalid['state'][0]['step'] = torch.tensor(1.5)
    invalid_path = OUT / f'{name}.pt'
    torch.save(invalid, invalid_path)
    result = run(path(initial, 'model'), path(initial, 'optim'), name, 3,
                 invalid_path)
    same(load(path(result, 'optim')), load(path(resumed, 'optim')))
    same(load(path(result, 'model')), load(path(resumed, 'model')))
    print(f'{name}: rejected without changing the next 3 updates')
print('Adam interchange passed')
