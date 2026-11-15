#!/usr/bin/env bash
set -eu
mkdir -p debug
make build-safe >debug/repl-bootstrap.log 2>&1
make commands >debug/repl-commands.log 2>&1
# Run the unchanged repository suite, including parser, program, and PTY checks.
timeout 900 sh commands/repl/tests/run.sh >debug/repl-suite.log 2>&1 || { tail -n 100 debug/repl-suite.log; exit 1; }
cat debug/repl-suite.log
