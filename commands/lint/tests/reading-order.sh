#!/bin/sh
# Optional rule checks; deliberately outside the recurring --all census.
set -eu
cd "$(dirname "$0")/../../.."
python3 - <<'CHECK'
import hashlib
import subprocess
from pathlib import Path

root = Path.cwd()
tool = root / 'builds/0/libexec/x2c-lint'
fixtures = Path('commands/lint/tests/order')
rule = ['--rule', 'function-reading-order']

def run(files, extra=(), expected_status=0):
    result = subprocess.run([str(tool), *extra, *(str(fixtures/f) for f in files)],
                            capture_output=True, text=True)
    assert result.returncode == expected_status, (files, result.stdout, result.stderr)
    return result.stdout, result.stderr

out, coverage = run(['inversions.x'], rule)
assert out.count(': candidate function-reading-order FI-4:') == 7, out
for text in ['public_after_private follows private hidden_first',
             'public_caller -> public_leaf',
             'public_through_private -> private_bridge -> public_target',
             'private_caller -> private_leaf',
             'callback_caller -> callback_leaf',
             'self_caller -> self_leaf',
             'public mixed_public follows private mixed_helper']:
    assert text in out, (text, out)
for filename in ['accepted.x', 'script.x', 'suppressed.x', 'types.x', 'script-boundary.x']:
    out, coverage = run([filename], rule)
    assert not out, (filename, out)
    assert 'function-reading-order coverage:' in coverage, (filename, coverage)
out, _ = run(['script-inversion.x'], rule)
assert ':3: candidate function-reading-order' in out and 'script_caller -> script_leaf' in out, out
out, _ = run(['script-main.x'], rule)
assert ':3: candidate function-reading-order' in out and 'public main follows private' in out, out
out, _ = run(['generated.x'], rule)
assert out.count(': candidate function-reading-order') == 1, out
assert 'main follows dependency OrderBox.init' in out and ' -> OrderBox.init' in out, out
out, _ = run(['layout.xp'], rule)
assert ':3: candidate function-reading-order' in out, out
out, _ = run(['boundaries.x'], rule)
assert out.count(': candidate function-reading-order') == 2, out
assert 'ordinary_caller -> ordinary_leaf' in out and 'pragma_caller -> pragma_leaf' in out, out
assert 'decorated' not in out and 'after_meta' not in out and 'after_directive' not in out, out

out, coverage = run(['module.x', 'module-two.x'], rule)
assert out.count('caller member_after_private follows') == 1, out
assert 'member.x:6: candidate' in out, out
assert 'caller later_module_root follows' not in out, out
assert out.count('caller module_later_caller follows') == 1, out
assert 'module_caller -> member_bridge -> module_target' in out, out
assert out.count('caller module_caller follows') == 2, out
assert out.count('caller member_public_caller follows') == 1, out
assert 'types.x: function-reading-order coverage: 0 ordinary definitions' in coverage, coverage

for extra in [(), ('--all',)]:
    out, coverage = run(['inversions.x'], extra)
    assert 'function-reading-order' not in out + coverage, (extra, out, coverage)
out, _ = run(['inversions.x'], [*rule, '--all'])
assert out.count(': candidate function-reading-order') == 7, out

before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures.iterdir() if p.is_file()}
out, _ = run(['inversions.x'], [*rule, '--fix'])
assert out.count(': candidate function-reading-order') == 7, out
assert before == {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in before}, 'rule rewrote source'
print('function-reading-order: focused graph, boundaries, module, layout, selection, suppression and read-only checks passed')
CHECK
