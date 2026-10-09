#!/usr/bin/env python3
"""Build and run the optional component spike examples; no gate integration."""
import argparse
import difflib
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path)
args = parser.parse_args()
suite = Path(__file__).resolve().parent
root = suite.parents[1]
compiler = (args.compiler or root / 'builds/0/x2c').resolve()
output = Path(tempfile.mkdtemp(prefix='x2c-components-', dir='/tmp'))
failures = 0
cases = sorted(suite.rglob('*.stdout'))
for expected in cases:
    source = expected.with_suffix('.x')
    name = source.relative_to(suite).with_suffix('').as_posix()
    work = output / name
    work.mkdir(parents=True)
    binary = work / 'program'
    sources = [source]
    manifest = source.with_suffix('.sources')
    if manifest.exists():
        sources.extend(source.parent / line.strip()
                       for line in manifest.read_text().splitlines()
                       if line.strip() and not line.startswith('#'))
    command = [str(compiler), 'build', '--plain', '--build-dir', str(work / 'build'),
               '--output', str(binary), *map(str, sources)]
    build = subprocess.run(command, cwd=root, text=True, capture_output=True)
    (work / 'build.log').write_text(build.stdout + build.stderr)
    if build.returncode:
        print(f'FAIL {name}: build; {work / "build.log"}')
        failures += 1
        continue
    result = subprocess.run([str(binary)], text=True, capture_output=True)
    (work / 'actual.stdout').write_text(result.stdout)
    (work / 'actual.stderr').write_text(result.stderr)
    wanted = expected.read_text()
    if result.returncode or result.stdout != wanted or result.stderr:
        print(f'FAIL {name}: exit {result.returncode}; {work}')
        print(''.join(difflib.unified_diff(wanted.splitlines(True),
                                         result.stdout.splitlines(True))), end='')
        failures += 1
    else:
        print(f'PASS {name}')
print(f'{len(cases) - failures}/{len(cases)} passed; logs: {output}')
raise SystemExit(bool(failures))
