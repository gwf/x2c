#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
tmp=${TMPDIR:-/tmp}/x2c-repl-program.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export TMPDIR="$tmp" X2C="$PWD/builds/0/x2c"

builds/0/x2c build --plain --build-dir "$tmp/cc" --output "$tmp/program-api" \
  --x-include-dir commands/repl --x-include-dir commands/repl/tests \
  --x-include-dir src --c-include-dir builds/0/src \
  commands/repl/tests/program-api.x commands/repl/repl-program.x \
  commands/repl/repl-types.x commands/repl/tests/library/program-check.c \
  builds/0/commands/identity.x builds/0/libx2c-dev.a
"$tmp/program-api" "$PWD/commands/repl/tests/library/playground.c"

cc -fPIC -c commands/repl/tests/library/playground.c -o "$tmp/playground.o"
ar rcs "$tmp/libplayground.a" "$tmp/playground.o"
"$tmp/program-api" "$PWD/commands/repl/tests/library/playground.h" \
  "$tmp/libplayground.a"
