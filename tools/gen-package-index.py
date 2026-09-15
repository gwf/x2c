#!/usr/bin/env python3
"""Write the package index `x2c install <name>` resolves names through.

Each row is `name version kind platform url sha256`. Source rows come from
pure-x2c packages (a `src/<name>.x` tree with no dependency manifest);
bundle rows come from `<name>-native.tar.gz` files named on the command
line, one per platform, tagged by their BUNDLE.json and copied beside the
index as `<name>-<platform>-native.tar.gz`. URLs are `<base>/<file>`.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
  return hashlib.sha256(path.read_bytes()).hexdigest()


def source_archive(package, output):
  name = package.name
  archive = output / f"{name}-source.tar.gz"
  with tarfile.open(archive, "w:gz") as tar:
    for path in sorted(package.rglob("*")):
      relative = path.relative_to(package)
      if "builds" in relative.parts or "deps" in relative.parts:
        continue
      tar.add(path, arcname=str(Path(name) / relative), recursive=False)
  return archive


def source_rows(packages, output, base):
  for package in packages:
    manifests = list(package.glob("dependency*.json"))
    if manifests or not (package / "src" / f"{package.name}.x").is_file():
      continue
    archive = source_archive(package, output)
    yield (package.name, "0", "source", "-", f"{base}/{archive.name}",
           digest(archive))


def bundle_row(tarball, output, base):
  with tempfile.TemporaryDirectory() as work:
    with tarfile.open(tarball) as tar:
      member = next(m for m in tar.getmembers()
                    if m.name.endswith("/BUNDLE.json"))
      tar.extract(member, work)
      identity = json.loads((Path(work) / member.name).read_text())
  platform = f"{identity['platform']}-{identity['machine']}"
  version = identity.get("dependency_version") or "0"
  # Every platform's bundle is named <name>-native.tar.gz by its producer,
  # so the published copy carries the platform to keep them apart.
  published = output / f"{identity['package']}-{platform}-native.tar.gz"
  if tarball.resolve() != published.resolve():
    shutil.copy2(tarball, published)
  return (identity["package"], version, "bundle", platform,
          f"{base}/{published.name}", digest(published))


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--base", required=True,
                      help="URL prefix under which the files are published")
  parser.add_argument("--output", required=True, type=Path,
                      help="directory receiving index.txt and source archives")
  parser.add_argument("--package-dir", action="append", default=[],
                      type=Path, help="directory of source packages")
  parser.add_argument("--x2c-version",
                      help="version line for the index header; defaults to "
                           "what builds/0/x2c --version prints")
  parser.add_argument("bundles", nargs="*", type=Path,
                      help="<name>-native.tar.gz bundles to list")
  args = parser.parse_args()
  args.output.mkdir(parents=True, exist_ok=True)
  rows = []
  for directory in args.package_dir or [ROOT / "packages"]:
    packages = sorted(p for p in directory.iterdir() if p.is_dir())
    rows.extend(source_rows(packages, args.output, args.base))
  for tarball in args.bundles:
    rows.append(bundle_row(tarball, args.output, args.base))
  version = args.x2c_version or subprocess.check_output(
    [str(ROOT / "builds/0/x2c"), "--version"], text=True).strip()
  lines = [f"# x2c package index for {version}",
           "# name version kind platform url sha256"]
  lines.extend(" ".join(row) for row in sorted(rows))
  (args.output / "index.txt").write_text("\n".join(lines) + "\n")
  print(f"x2c: wrote {args.output / 'index.txt'} ({len(rows)} rows)")


if __name__ == "__main__":
  try:
    main()
  except (OSError, ValueError, StopIteration,
          subprocess.CalledProcessError) as error:
    print(f"x2c: {error}", file=sys.stderr)
    sys.exit(1)
