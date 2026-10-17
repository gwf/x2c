#!/usr/bin/env python3
"""List compiler or runtime entry units, excluding their module members."""
import argparse
from pathlib import Path


def sources(root, area="src"):
    src = Path(root) / area
    entries = list(src.glob("*.x"))
    if area == "src":
        entries += list((src / "components").glob("*.x"))
    entries.extend(path for directory in src.iterdir() if directory.is_dir()
                   if (path := directory / (directory.name + '.x')).is_file())
    return sorted(entries)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='.')
    parser.add_argument("--area", choices=("src", "lib"), default="src")
    args = parser.parse_args()
    for path in sources(args.root, args.area):
        print(path)
