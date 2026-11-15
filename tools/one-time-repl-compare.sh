#!/usr/bin/env bash
set -u
python3 ../harness/tools/one-time-manifest-probe.py
# Baseline uses a pipe to bypass the separately reproduced file-input hang.
python3 - <<'PY2'
from pathlib import Path
p=Path('commands/repl/tests/program.sh');s=p.read_text()
s=s.replace('if ! builds/0/x2c repl --manifest-path', 'if ! cat "$tmp/manifest-reload.repl" | builds/0/x2c repl --manifest-path')
s=s.replace('<"$tmp/manifest-reload.repl" >', '>')
if 'LD_LIBRARY_PATH="$tmp' not in s:
 s=s.replace('REPL_PROGRAM_REMOVE_NATIVE="$shared"', 'LD_LIBRARY_PATH="$tmp${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" REPL_PROGRAM_REMOVE_NATIVE="$shared"')
p.write_text(s)
PY2
for test in program playground terminal; do
  case "$test" in
    program) timeout 240 bash commands/repl/tests/program.sh >debug/compare-program.log 2>&1 ;;
    *) timeout 240 python3 commands/repl/tests/$test.py >debug/compare-$test.log 2>&1 ;;
  esac
  echo "$test status=$?"
  tail -8 debug/compare-$test.log
done
