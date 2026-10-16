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


def generate(root, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['make', 'build-safe'], cwd=root, check=True)
    subprocess.run(['make', 'commands', 'COMMAND_NAMES=graph'], cwd=root, check=True)
    with tempfile.TemporaryDirectory(prefix='partition-') as temporary:
        datasets = Path(temporary) / 'datasets'
        sources = sorted(p.relative_to(root).as_posix()
                         for p in list((root / 'src').glob('*.x')) + list((root / 'src').glob('*/*.x'))
                         if p.parent == root / 'src' or p.parent.name == 'components'
                         or p.stem == p.parent.name)
        library = sorted(p.relative_to(root).as_posix() for p in (root / 'lib').glob('*.x') if p.name != 'x2c.x')
        subprocess.run([str(root / 'builds/0/libexec/x2c-graph'), 'datasets', str(datasets),
                        '-I', '.', '-I', 'src', '-I', 'lib', *sources, '--', *library],
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
