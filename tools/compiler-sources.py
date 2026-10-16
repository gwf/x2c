#!/usr/bin/env python3
"""List compiler translation units, excluding explicitly listed module members."""
import argparse
from pathlib import Path


def sources(root):
    src = Path(root) / 'src'
    entries = list(src.glob('*.x')) + list((src / 'components').glob('*.x'))
    entries.extend(path for directory in src.iterdir() if directory.is_dir()
                   if (path := directory / (directory.name + '.x')).is_file())
    return sorted(entries)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='.')
    args = parser.parse_args()
    for path in sources(args.root):
        print(path)
