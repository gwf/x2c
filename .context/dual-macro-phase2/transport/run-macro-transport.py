#!/usr/bin/env python3
"""One-off source Macro helper hydration probe; requires parser spike compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
args = parser.parse_args()
compiler = str(Path(args.compiler).resolve())
source_dir = Path(__file__).resolve().parent
scratch = Path(tempfile.mkdtemp(prefix='x2c-real-macro-domain-'))
cache = scratch / 'cache'
env = dict(os.environ, X2C_CACHE_DIR=str(cache))
main = (source_dir / 'macro-hydration.x').read_text()
shift = ('  int shift_a = 1, shift_b = 2, shift_c = 3;\n'
         '  (void) shift_a, (void) shift_b, (void) shift_c;\n')
main = main.replace(shift, '')
source = scratch / 'macro-hydration.x'

def build(label, text):
    source.write_text(text)
    output = scratch / label
    proc = subprocess.run([compiler, 'build', '--output', str(output),
                           str(source)], env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (scratch / (label + '.log')).write_text(proc.stdout)
    if proc.returncode:
        raise RuntimeError(proc.stdout)
    run = subprocess.run([str(output)], text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert run.returncode == 0, run.stdout
    return {'binding_ids': re.findall(r'binding (\d+) "(helper|other)"',
                                     proc.stdout), 'stdout': run.stdout}

def helpers_snapshot():
    return {str(p): {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                     'mtime_ns': p.stat().st_mtime_ns}
            for p in cache.rglob('helper') if p.is_file()}

before = build('baseline', main)
helper_before = helpers_snapshot()
after = build('shifted', main.replace('  int price = 20;',
                                    shift + '  int price = 20;'))
helper_after = helpers_snapshot()
assert helper_before == helper_after, 'helper was rebuilt'
assert before['binding_ids'] != after['binding_ids'], 'program IDs did not shift'
summary = {'baseline': before, 'shifted': after,
           'helper_unchanged': helper_before == helper_after,
           'helper': helper_after, 'scratch': str(scratch)}
(scratch / 'summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
