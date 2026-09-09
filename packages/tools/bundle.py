#!/usr/bin/env python3
"""Bundle a built x2c package with its declared native inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile

from deps import DependencyError, _format, _load_manifest


def copy(source: Path, destination: Path) -> None:
  destination.parent.mkdir(parents=True, exist_ok=True)
  if source.is_dir():
    shutil.copytree(source, destination, dirs_exist_ok=True)
  else:
    shutil.copy2(source, destination)


def digest(path: Path) -> str:
  return hashlib.sha256(path.read_bytes()).hexdigest()


def quoted(argument: str) -> str:
  return '"' + argument.replace('\\', '\\\\').replace('"', '\\"') + '"'


def bundle(args: argparse.Namespace) -> None:
  package = Path.cwd()
  name = PurePosixPath(args.package)
  if len(name.parts) != 1 or name.name in (".", ".."):
    raise DependencyError("package must be one path component")
  manifest = {}
  if args.manifest:
    manifest, _ = _load_manifest(Path(args.manifest))
    if 'distribution' not in manifest:
      raise DependencyError('dependency manifest has no distribution data')
  distribution = manifest.get('distribution', {})
  native_args = distribution.get('native_args', []) + distribution.get(
    'platform_args', {}).get(sys.platform, [])
  legacy = package / 'builds' / (args.package + '.link')
  if not manifest and legacy.read_text().strip():
    raise DependencyError('native link inputs require distribution data')
  output = Path(args.output).absolute()
  output.mkdir(parents=True, exist_ok=True)
  with tempfile.TemporaryDirectory(prefix='.bundle-', dir=output) as work:
    stage = Path(work) / args.package
    stage.mkdir()
    copy(package / 'src', stage / 'src')
    for header in sorted((package / 'builds').glob('*.h')):
      copy(header, stage / 'builds' / header.name)
    archive = 'lib' + args.package + '.a'
    copy(package / 'builds' / archive, stage / 'builds' / archive)
    for pattern in ('README*', 'LICENSE*', 'PROFILE*', 'dependency*.json'):
      for source in sorted(package.glob(pattern)):
        copy(source, stage / source.name)
    variables = {'prefix': args.prefix, 'package': str(package)}
    for item in distribution.get('copies', []):
      relative = PurePosixPath(item['to'])
      if relative.is_absolute() or '..' in relative.parts:
        raise DependencyError('bundle copy destination must be relative')
      copy(Path(_format(item['from'], variables)), stage / relative)
    response = stage / 'builds' / (args.package + '.native.rsp')
    response.write_text(''.join(quoted(arg) + '\n' for arg in native_args))
    compiler = Path(shutil.which(args.compiler) or args.compiler).resolve()
    runtime = compiler.parent / 'libx2c.a'
    if not runtime.is_file():
      runtime = compiler.parent.parent / 'lib/libx2c.a'
    if not runtime.is_file():
      runtime = compiler.parent.parent / 'bootstrap/lib/libx2c.a'
    receipt = (Path(args.prefix).parent / 'receipt.json'
               if args.prefix else None)
    dependency_identity = None
    if receipt and receipt.is_file():
      dependency_identity = json.loads(receipt.read_text()).get('identity')
    identity = {
      'package': args.package,
      'platform': sys.platform,
      'machine': platform.machine(),
      'x2c_version': subprocess.check_output(
        [str(compiler), '--version'], text=True).strip(),
      'x2c_sha256': digest(compiler),
      'runtime_sha256': digest(runtime),
      'archive_sha256': digest(stage / 'builds' / archive),
      'dependency_version': manifest.get('version'),
      'dependency_profile': manifest.get('profile'),
      'dependency_toolchain': dependency_identity,
    }
    (stage / 'BUNDLE.json').write_text(json.dumps(identity, indent=2) + '\n')
    tar_path = Path(work) / (args.package + '-native.tar.gz')
    with tarfile.open(tar_path, 'w:gz') as output_tar:
      output_tar.add(stage, arcname=args.package)
    destination = output / args.package
    if destination.exists():
      if not (destination / 'BUNDLE.json').is_file():
        raise DependencyError(f'refusing to replace unowned {destination}')
      destination.rename(Path(work) / 'previous')
    stage.rename(destination)
    os.replace(tar_path, output / tar_path.name)
  print(f'x2c: bundled {destination}')
  print(f'x2c: wrote {output / tar_path.name}')


def main() -> None:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--package', required=True)
  parser.add_argument('--compiler', required=True)
  parser.add_argument('--manifest', default='')
  parser.add_argument('--prefix', default='')
  parser.add_argument('--output', default='builds/bundle')
  bundle(parser.parse_args())


if __name__ == '__main__':
  try:
    main()
  except (DependencyError, OSError, ValueError,
          subprocess.CalledProcessError) as error:
    print(f'x2c: {error}', file=sys.stderr)
    sys.exit(1)
