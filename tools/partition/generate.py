#!/usr/bin/env python3
"""Build the current checkout's exporter and atomically refresh its graph."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def units(root, area):
    """Entry units of an area; each module entry stands for its members."""
    paths = subprocess.check_output(
        [str(root / 'tools/sources.sh'), '--root', str(root), '--area', area], text=True)
    units = [Path(p).relative_to(root).as_posix() for p in paths.splitlines()]
    return [p for p in units if p != 'lib/x2c.x']


def command_files(root):
    """Source files of each external command, whose calls count as callers."""
    names = [line.split('|', 1)[0] for line in (root / 'commands/manifest.txt').read_text().splitlines() if line]
    return [p.relative_to(root).as_posix() for name in names for p in sorted((root / 'commands' / name).glob('*.x'))]


def generate(root, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['make', 'build-safe'], cwd=root, check=True)
    subprocess.run(['make', 'commands', 'COMMAND_NAMES=graph'], cwd=root, check=True)
    with tempfile.TemporaryDirectory(prefix='partition-') as temporary:
        datasets = Path(temporary) / 'datasets'
        subprocess.run([str(root / 'builds/0/libexec/x2c-graph'), 'datasets', str(datasets),
                        '-I', '.', '-I', 'src', '-I', 'lib',
                        *units(root, 'src'), '--', *units(root, 'lib'), '--', *command_files(root)],
                       cwd=root, check=True)
        # Stage beside the destination so replacement is atomic across filesystems.
        with tempfile.NamedTemporaryFile(dir=output.parent, suffix='.json', delete=False) as staged:
            path = Path(staged.name)
        try:
            subprocess.run([sys.executable, str(HERE / 'build-data.py'), str(root),
                            str(datasets), str(path)], check=True)
            os.replace(path, output)
        finally:
            path.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=HERE / 'data/graph.json')
    args = parser.parse_args()
    generate(args.repo.resolve(), args.output.resolve())
