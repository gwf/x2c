#!/usr/bin/env python3
"""Optional counter build, isolated from the package's ordinary native objects."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'builds' / 'lifetimes'
OUT.mkdir(exist_ok=True)
PREFIX = Path(os.environ['TORCH_PREFIX'])
CXX = shlex.split(os.environ.get('CXX', 'c++'))
CC = shlex.split(os.environ.get('CC', 'cc'))
X2C = str(Path(os.environ['X2C']).resolve())


def run(arguments):
    subprocess.run([str(value) for value in arguments], cwd=ROOT, check=True)


includes = ['-I' + str(PREFIX / 'include'),
            '-I' + str(PREFIX / 'include/torch/csrc/api/include'),
            '-I' + str(ROOT / 'src'), '-I' + str(ROOT / 'generated')]
for source, output in [('src/torch-shim.cpp', 'shim.o'),
                       ('generated/xt_ops.cpp', 'ops.o')]:
    run(CXX + ['-std=c++17', '-O1', '-DXT_HANDLE_COUNTERS'] + includes +
        ['-c', ROOT / source, '-o', OUT / output])
run(CC + ['-O1', '-DXT_HANDLE_COUNTERS', '-I' + str(ROOT / 'src'), '-c',
          ROOT / 'benchmarks/handles.c', '-o', OUT / 'handles.o'])
package = OUT / 'packages' / 'torch'
(package / 'builds').mkdir(parents=True, exist_ok=True)
shutil.copytree(ROOT / 'src', package / 'src', dirs_exist_ok=True)
for header in (ROOT / 'builds').glob('*.h'):
    shutil.copy2(header, package / 'builds' / header.name)
shutil.copy2(ROOT / 'builds/libtorch.a', package / 'builds/libtorch.a')
# A private response file reuses the established package distribution reader.
# It never changes the ordinary package's native link inputs.
arguments = ['-L' + str(PREFIX / 'lib'),
             '-ltorch', '-ltorch_cpu', '-lc10',
             '-lc++' if os.uname().sysname == 'Darwin' else '-lstdc++']
(package / 'builds/torch.native.rsp').write_text(
    ''.join('"' + arg.replace('\\', '\\\\').replace('"', '\\"') + '"\n'
            for arg in arguments))
run([X2C, 'build', '--output', OUT / 'probe', '--build-dir', OUT / 'cc',
     '--package-dir', OUT / 'packages', '--c-include-dir', ROOT / 'src',
     '--c-include-dir', ROOT / 'generated', '--c-include-dir', ROOT / 'benchmarks',
     '-Xlinker', OUT / 'shim.o', '-Xlinker', OUT / 'ops.o',
     '-Xlinker', OUT / 'handles.o', '-Wl,-rpath,' + str(PREFIX / 'lib'),
     ROOT / 'tests/lifetimes.x'])
run([OUT / 'probe'])
