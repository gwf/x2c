#!/bin/sh
set -eu
export X2C_SCOPE_ACCOUNTING=1
cd "$(dirname "$0")/../../.."
tmp=${TMPDIR:-/tmp}/x2c-repl-tests.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export X2C="$PWD/builds/0/x2c"

builds/0/x2c build --plain ${BUILD_JOBS:+-j "$BUILD_JOBS"} \
  --build-dir "$tmp/native-cc" --output "$tmp/native-check" \
  --x-include-dir commands/repl --x-include-dir src \
  --c-include-dir builds/0/src -Wl,-force_load,builds/0/libx2c.a \
  commands/repl/tests/native-check.x commands/repl/repl-types.x \
  commands/repl/repl-session.x commands/repl/repl-native.x \
  commands/repl/repl-inspect.x commands/repl/repl-prompt-types.x \
  commands/repl/repl-ledgers.x builds/0/libx2c-dev.a
for suite in shared objects prompt-types callbacks collections rollback cleanup completion; do
  "$tmp/native-check" "$suite"
done

builds/0/x2c build --plain ${BUILD_JOBS:+-j "$BUILD_JOBS"} \
  --build-dir "$tmp/inspect-cc" --output "$tmp/inspect-check" \
  --x-include-dir commands/repl --x-include-dir src \
  --c-include-dir builds/0/src \
  commands/repl/tests/inspect-check.x commands/repl/repl-types.x \
  commands/repl/repl-inspect.x builds/0/libx2c-dev.a
"$tmp/inspect-check"

builds/0/x2c build --plain ${BUILD_JOBS:+-j "$BUILD_JOBS"} \
  --build-dir "$tmp/func-cc" --output "$tmp/func-call" \
  commands/repl/tests/func-call.x
"$tmp/func-call"

sh commands/repl/tests/program.sh
python3 commands/repl/tests/playground.py
python3 commands/repl/tests/terminal.py

printf '1+2;\n' | builds/0/x2c repl >"$tmp/dispatch"
printf '=> int 3\n' >"$tmp/dispatch-expected"
cmp "$tmp/dispatch-expected" "$tmp/dispatch"
builds/0/x2c repl --help >"$tmp/help"
grep -q 'native library playground' "$tmp/help"
echo 'REPL playground checks passed'
