#!/usr/bin/env python3
"""Copy generated paths and reconnect includes to the same copied artifacts."""

from pathlib import Path
import argparse
import json
import os
import re
import shutil


ROOT = Path(__file__).resolve().parents[1]
INCLUDE = re.compile(r'^(\s*#\s*include\s*)"([^"\n]+)"', re.MULTILINE)


def generated(tree):
    return sorted(source for component in ("lib", "src")
                  for source in (tree / component).rglob("*")
                  if source.is_file() and source.suffix in (".c", ".h", ".xnm"))


def copied_text(source, destination, placements):
    def reconnect(match):
        spelling = Path(match[2])
        if not spelling.is_absolute():
            return match[0]
        placed = placements.get(spelling.resolve())
        if placed is None:
            return match[0]
        relative = os.path.relpath(placed, destination.parent)
        return f'{match[1]}"{relative}"'

    if source.suffix == ".xnm":
        metadata = json.loads(source.read_text(encoding="ascii"))
        for row in metadata["regions"]:
            for field in ("includeTarget", "includePath"):
                spelling = row.get(field)
                if not spelling or not Path(spelling).is_absolute():
                    continue
                placed = placements.get(Path(spelling).resolve())
                if placed is not None:
                    row[field] = os.path.relpath(placed, destination.parent)
        return json.dumps(metadata, separators=(",", ":"), ensure_ascii=True)
    return INCLUDE.sub(reconnect, source.read_text(encoding="ascii"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compare", nargs=3, metavar=("LEFT", "RIGHT", "FILE"))
    args = parser.parse_args()
    if args.compare:
        left, right, relative = args.compare
        left, right = Path(left), Path(right)
        if left.resolve() != (ROOT / "bootstrap").resolve():
            return 1
        placements = {p.resolve(): left / p.relative_to(right)
                      for p in generated(right)}
        destination = left / relative
        return 0 if destination.read_text(encoding="ascii") == copied_text(
            right / relative, destination, placements) else 1

    stage, bootstrap = ROOT / "builds/0", ROOT / "bootstrap"
    files = generated(stage)
    placements = {p.resolve(): bootstrap / p.relative_to(stage) for p in files}
    for source in files:
        destination = bootstrap / source.relative_to(stage)
        destination.parent.mkdir(parents=True, exist_ok=True)
        rewritten = copied_text(source, destination, placements)
        if source.read_text(encoding="ascii") == rewritten:
            shutil.copyfile(source, destination)
        else:
            destination.write_text(rewritten, encoding="ascii")
    shutil.copyfile(ROOT / "tools/native-layout-project.py",
                    bootstrap / "native-layout-project.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
