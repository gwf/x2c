#!/usr/bin/env python3
"""Copy generated paths and reconnect includes to the same copied artifacts."""

from pathlib import Path
import argparse
import importlib.util
import sys
import shutil


ROOT = Path(__file__).resolve().parents[1]
PROJECTION_SPEC = importlib.util.spec_from_file_location(
    'native_layout_project', ROOT / 'tools/native-layout-project.py')
PROJECTION = importlib.util.module_from_spec(PROJECTION_SPEC)
sys.modules[PROJECTION_SPEC.name] = PROJECTION
PROJECTION_SPEC.loader.exec_module(PROJECTION)
INCLUDE = PROJECTION.INCLUDE
copied_text = PROJECTION.copied_native_text


def generated(tree):
    return sorted(source for component in ("lib", "src")
                  for source in (tree / component).rglob("*")
                  if source.is_file() and source.suffix in (".c", ".h", ".xnm"))


def native_headers(files, generated_placements, bootstrap):
    """Copy checkout-native quoted header closure at its original structure."""
    pending, headers = list(files), {}
    while pending:
        source = pending.pop()
        if source.suffix == '.xnm':
            continue
        for match in INCLUDE.finditer(source.read_text(encoding='ascii')):
            spelling = Path(match[2])
            target = (spelling if spelling.is_absolute() else
                      source.parent / spelling).resolve()
            if target in generated_placements or target in headers:
                continue
            if not target.is_file() or not target.is_relative_to(ROOT):
                continue
            relative = target.relative_to(ROOT)
            headers[target] = bootstrap / 'native' / relative
            pending.append(target)
    return headers


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
        placements.update(native_headers(generated(right), placements, left))
        destination = left / relative
        return 0 if destination.read_text(encoding="ascii") == copied_text(
            right / relative, destination, placements) else 1

    stage, bootstrap = ROOT / "builds/0", ROOT / "bootstrap"
    files = generated(stage)
    placements = {p.resolve(): bootstrap / p.relative_to(stage) for p in files}
    native = native_headers(files, placements, bootstrap)
    placements.update(native)
    for source in [*files, *native]:
        destination = placements[source.resolve()]
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
