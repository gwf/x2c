#!/bin/sh
set -eu

cd "$(dirname "$0")/../../.."
tmp=${TMPDIR:-/tmp}/x2c-repl-tests.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

builds/0/x2c build --plain \
  --build-dir "$tmp/api-cc" --output "$tmp/api-check" \
  --x-include-dir commands/repl --x-include-dir src \
  --c-include-dir builds/0/src \
  commands/repl/tests/api-check.x commands/repl/repl-session.x \
  builds/0/libx2c-dev.a
"$tmp/api-check"

if builds/0/libexec/x2c-repl < commands/repl/tests/demo.txt \
     >"$tmp/out" 2>"$tmp/err"; then
  echo "rejected REPL submission unexpectedly succeeded" >&2
  exit 1
fi
cat >"$tmp/expected" <<'EOF'
ok
ok
=> 12
defined plus
=> 15
defined twice
=> 32
=> 32
ok
=> 48
EOF
cmp "$tmp/expected" "$tmp/out"
grep -q 'expected atomic expression' "$tmp/err"

printf '1+2;\n' | builds/0/x2c repl >"$tmp/dispatch"
printf '=> 3\n' >"$tmp/dispatch-expected"
cmp "$tmp/dispatch-expected" "$tmp/dispatch"

set +e
builds/0/x2c repl extra </dev/null >"$tmp/bad-out" \
  2>"$tmp/bad-err"
result=$?
set -e
test "$result" -eq 2
grep -qx 'x2c repl: unexpected operand' "$tmp/bad-err"

echo "REPL command checks passed"
