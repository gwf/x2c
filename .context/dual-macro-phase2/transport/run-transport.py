#!/usr/bin/env python3
"""One-off research runner; does not add a repository test requirement."""
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
scratch = Path(tempfile.mkdtemp(prefix='x2c-dual-domain-'))
cache = scratch / 'cache'
env = dict(os.environ, X2C_CACHE_DIR=str(cache))
helpers = (source_dir / 'domain-helpers.xmacro').read_text()
(scratch / 'domain-helpers.xmacro').write_text(helpers)
main = '''#include "meta.x"
#include <assert.h>
static int helper(int x) => x + 1;
static int other(int x) => x + 100;
$(import "domain-helpers.xmacro")
int main(void) {
  int price = 20, tax = 1, discount = 2;
  assert($composed(helper, tax, helper(price + tax)) == 22);
  assert($composed(helper, tax, helper(price + discount)) == 0);
  assert($bridge(helper(price)) == 21);
  {
    int (*helper)(int) = other;
    assert($bridge(helper(price)) == 0);
  }
  $typed(int, price, price += 1;);
  assert(price == 21);
  puts("domain hydration: rigid free mismatch, composition, typed rebuild pass");
  return 0;
}
'''
source = scratch / 'domain-main.x'

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
    return {'binding_ids': re.findall(r'binding (\d+) "(helper|price)"',
                                     proc.stdout), 'stdout': run.stdout}

def helpers_snapshot():
    return {str(p): {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                     'mtime_ns': p.stat().st_mtime_ns}
            for p in cache.rglob('helper') if p.is_file()}

before = build('baseline', main)
helper_before = helpers_snapshot()
shifted = main.replace('static int helper(int x)',
                       'static int global_pad;\nstatic int helper(int x)')
shifted = shifted.replace('  int price = 20,',
                         '  int shift_a = 1, shift_b = 2, shift_c = 3;\n'
                         '  (void) shift_a, (void) shift_b, (void) shift_c;\n'
                         '  int price = 20,')
after = build('shifted', shifted)
helper_after = helpers_snapshot()
assert helper_before == helper_after, 'helper was rebuilt'
assert before['binding_ids'] != after['binding_ids'], 'program IDs did not shift'
summary = {'baseline': before, 'shifted': after,
           'helper_unchanged': helper_before == helper_after,
           'helper': helper_after, 'scratch': str(scratch)}
(scratch / 'summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
