#!/usr/bin/env python3
"""Check Lisp generation in a source-only home, without cached interfaces."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ("init", "builtin-macros", "lisp-bindings")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default=str(ROOT / "builds/0/x2c"))
    args = parser.parse_args()
    compiler = Path(args.compiler).resolve()
    with tempfile.TemporaryDirectory(prefix="x2c-lisp-init-") as directory:
        home = Path(directory)
        # Tracked inputs include working-tree edits, but no build products or
        # .xi caches. A clean tree has the same contents as git archive HEAD.
        tracked = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
        for entry in tracked:
            if not entry:
                continue
            relative = Path(os.fsdecode(entry))
            target = home / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target, follow_symlinks=False)
        previous = None
        for generation in (1, 2):
            subprocess.run(
                [sys.executable, str(home / "tools/gen-lisp-init.py"),
                 "--compiler", str(compiler)], cwd=home, check=True,
            )
            current = {name: (home / f"etc/{name}.xlisp").read_bytes()
                       for name in ARTIFACTS}
            if previous is not None:
                changed = [name for name in ARTIFACTS
                           if current[name] != previous[name]]
                if changed:
                    raise AssertionError("second pass changed " +
                                         ", ".join(changed))
            previous = current
            print(f"Lisp generation pass {generation} passed", flush=True)
    print("Source-only Lisp generation is byte-identical on its second pass")


if __name__ == "__main__":
    main()
