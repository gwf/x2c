#!/usr/bin/env bash
set -eu
cp ../harness/tools/one-time-stdin-probe.c /tmp/repl-stdin-fork-probe.c
sh ../harness/tools/one-time-stdin-probe.sh
mkdir -p debug
make build-safe >debug/repl-bootstrap.log 2>&1
make commands >debug/repl-commands.log 2>&1
# Bound the existing regression suite; retain its diagnostics on failure.
timeout 360 bash -x commands/repl/tests/program.sh >debug/repl-program.log 2>&1 || { cat debug/repl-program.log; exit 1; }
cat debug/repl-program.log
python3 commands/repl/tests/playground.py
python3 commands/repl/tests/terminal.py
