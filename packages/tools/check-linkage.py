#!/usr/bin/env python3
"""Reject non-system dynamic dependencies in static libuv and BLIS examples."""

import argparse
import pathlib
import platform
import re
import subprocess
import sys


def dependencies(binary, system):
    if system == "Darwin":
        output = subprocess.check_output(["otool", "-L", binary], text=True)
        return [line.strip().split(" (", 1)[0]
                for line in output.splitlines()[1:] if line.strip()]
    if system == "Linux":
        output = subprocess.check_output(["readelf", "-d", binary], text=True)
        return re.findall(r"\(NEEDED\).*\[([^]]+)\]", output)
    raise ValueError(f"unsupported linkage inspection platform: {system}")


def allowed(name, system, package):
    if system == "Darwin":
        if package == "libuv":
            return name == "/usr/lib/libSystem.B.dylib"
        return name.startswith(("/usr/lib/", "/System/Library/"))
    return name in {
        "libc.so.6", "libm.so.6", "libpthread.so.0", "libdl.so.2",
        "librt.so.1", "ld-linux-x86-64.so.2", "ld-linux-aarch64.so.1",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", choices=("libuv", "blis"), required=True)
    parser.add_argument("binary", type=pathlib.Path, nargs="+")
    args = parser.parse_args()
    system = platform.system()
    for binary in args.binary:
        try:
            names = dependencies(str(binary), system)
        except (OSError, subprocess.CalledProcessError, ValueError) as error:
            print(f"linkage inspection failed: {error}", file=sys.stderr)
            return 1
        unexpected = [name for name in names
                      if not allowed(name, system, args.package)]
        if unexpected:
            print("unexpected dynamic dependencies: " + ", ".join(unexpected),
                  file=sys.stderr)
            return 1
        print(f"{binary}: system dynamic dependencies only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
