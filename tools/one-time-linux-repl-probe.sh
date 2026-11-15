#!/usr/bin/env bash
set -eu
mkdir -p debug
make build-safe >debug/repl-bootstrap.log 2>&1
make commands >debug/repl-commands.log 2>&1
printf 'int reads=0;\nint next(void) { reads++; return 13; }\n:info next()\n:quit\n' >/tmp/repl-info-input
command -v gdb || { sudo apt-get update && sudo apt-get install -y gdb; }
timeout 120 gdb -q -batch -ex 'set pagination off' -ex 'set follow-fork-mode child' -ex 'set detach-on-fork on' -ex 'handle SIGCHLD nostop noprint' -ex 'break _worker_serve' -ex 'run < /tmp/repl-info-input' -ex 'set follow-fork-mode parent' -ex 'continue' -ex 'bt full' --args builds/0/libexec/x2c-repl --plain >debug/repl-info-gdb.log 2>&1 || true
cat debug/repl-info-gdb.log
# Keep generated units for inspection on this disposable runner.
sed -i '/^trap /d' commands/repl/tests/program.sh
for suite in program playground terminal; do
  case "$suite" in
    program) command=(bash -x commands/repl/tests/program.sh);;
    *) command=(python3 commands/repl/tests/$suite.py);;
  esac
  set +e
  timeout 360 "${command[@]}" >"debug/repl-$suite.log" 2>&1
  result=$?
  set -e
  printf '%s exit %s\n' "$suite" "$result"
  tail -n 12 "debug/repl-$suite.log"
done
find /tmp/x2c-repl-program.* -type f -name 'unit-*.h' -exec cp --parents '{}' debug/ \; || true
