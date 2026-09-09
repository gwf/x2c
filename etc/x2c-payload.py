#!/usr/bin/env python3
"""Materialize compiler support and install a native dedicated prefix."""

import argparse
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
INSTALL_MANIFEST = ".x2c-install-manifest"


def fnv64(data):
    value = 1469598103934665603
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return f"{value:016x}"


def copy_support(destination):
    for folder, patterns, outputs in (
        ("src", ("*.x", "*.xmacro"), ("src",)),
        ("lib", ("*.x", "*.xmacro", "*.xlisp"), ("lib", "include")),
        ("builds/0/lib", ("*.h",), ("include",)),
        ("etc", ("*.xlisp", "*.xmacro"), ("etc",)),
        (".", ("LICENSE",), ("licenses",)),
    ):
        for pattern in patterns:
            for source in sorted((ROOT / folder).glob(pattern)):
                for output in outputs:
                    target = destination / output / source.name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)


def write_manifest(destination, name, kind):
    rows = []
    for path in sorted(destination.rglob("*")):
        if path.is_file():
            data = path.read_bytes()
            relative = path.relative_to(destination).as_posix()
            rows.append(f"{fnv64(data)} {len(data)} {relative}\n")
    body = "".join(rows)
    identity = "fnv64-" + fnv64(body.encode("ascii"))
    (destination / name).write_text(f"{kind} {identity}\n" + body)
    return identity


def owned_files(prefix):
    manifest = prefix / INSTALL_MANIFEST
    if not manifest.exists():
        return set()
    lines = manifest.read_text().splitlines()
    if not lines or not lines[0].startswith("x2c-native-v1 "):
        raise ValueError(f"unrecognized installation inventory: {manifest}")
    files = set()
    for line in lines[1:]:
        _, _, relative = line.split(" ", 2)
        path = PurePosixPath(relative)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"invalid installed file path: {relative}")
        files.add(relative)
    return files | {INSTALL_MANIFEST}


def installed_path(prefix, relative):
    path = prefix / relative
    for parent in path.parents:
        if parent == prefix:
            break
        if parent.is_symlink():
            raise ValueError(f"installation directory is a symlink: {parent}")
    return path


def install(prefix, destdir):
    if not prefix.is_absolute():
        raise ValueError("PREFIX must be an absolute dedicated x2c prefix")
    target = Path(destdir + str(prefix)) if destdir else prefix
    target = target.absolute()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        raise ValueError(f"installation prefix is a symlink: {target}")
    with tempfile.TemporaryDirectory(prefix=".x2c-install-",
                                     dir=target.parent) as temporary:
        stage = Path(temporary)
        copy_support(stage)
        (stage / "bin").mkdir()
        shutil.copy2(ROOT / "builds/0/x2c", stage / "bin/x2c")
        shutil.copy2(ROOT / "builds/0/libx2c.a", stage / "lib/libx2c.a")
        (stage / "lib/x2c").mkdir()
        (stage / "lib/x2c/toolchain").write_text("CC=cc\nAR=ar\n")
        identity = write_manifest(stage, INSTALL_MANIFEST, "x2c-native-v1")
        previous = owned_files(target)
        current = owned_files(stage)
        for relative in previous | current:
            path = installed_path(target, relative)
            exists = path.exists() or path.is_symlink()
            if exists and relative not in previous:
                raise FileExistsError(f"refusing to replace unowned: {path}")
            if path.is_dir():
                raise IsADirectoryError(path)
        target.mkdir(exist_ok=True)
        for relative in sorted(current - {INSTALL_MANIFEST}):
            path = installed_path(target, relative)
            path.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage / relative, path)
        for relative in sorted(previous - current):
            installed_path(target, relative).unlink(missing_ok=True)
        os.replace(stage / INSTALL_MANIFEST, target / INSTALL_MANIFEST)
    print(f"x2c: installed {target}/bin/x2c ({identity})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    support = commands.add_parser("support")
    support.add_argument("destination", type=Path)
    support.add_argument("--licenses", type=Path)
    native = commands.add_parser("install")
    native.add_argument("--prefix", required=True, type=Path)
    native.add_argument("--destdir", default="")
    args = parser.parse_args()
    if args.command == "install":
        install(args.prefix, args.destdir)
    else:
        copy_support(args.destination)
        if args.licenses:
            for source in sorted(args.licenses.glob("LICENSE.*")):
                shutil.copy2(source, args.destination / "licenses" /
                             ("cosmopolitan-" + source.name))
        identity = write_manifest(args.destination, ".x2c-bootstrap-manifest",
                                  "x2c-bootstrap-v1")
        print(identity)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"x2c: {error}", file=sys.stderr)
        sys.exit(1)
