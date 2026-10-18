#!/bin/sh
set -eu

cd "$(dirname "$0")/../../.."
tmp=${TMPDIR:-/tmp}/x2c-repl-tests.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

builds/0/x2c build --plain ${BUILD_JOBS:+-j "$BUILD_JOBS"} \
  --build-dir "$tmp/api-cc" --output "$tmp/api-check" \
  --x-include-dir commands/repl --x-include-dir src \
  --c-include-dir builds/0/src \
  commands/repl/tests/api-check.x commands/repl/repl-session.x \
  commands/repl/repl-lower.x commands/repl/repl-runtime.x \
  commands/repl/repl-native.x commands/repl/repl-globals.x \
  commands/repl/repl-native-types.x \
  commands/repl/decline-errors.x commands/repl/refusal-errors.x \
  builds/0/libx2c-dev.a
"$tmp/api-check"

builds/0/x2c build --plain ${BUILD_JOBS:+-j "$BUILD_JOBS"} \
  --build-dir "$tmp/func-cc" --output "$tmp/func-call" \
  commands/repl/tests/func-call.x
"$tmp/func-call"

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

# Interpreted and compiled code both reach printf and puts.
printf '%s\n' 'printf("%s=%04d\n", "answer", 42);' 'puts("done");' \
  'int f(int x) { printf("f%d\n", x); puts("p"); return x; }' 'f(7);' |
  builds/0/libexec/x2c-repl >"$tmp/stdio"
printf '%s\n' 'answer=0042' '=> 12' 'done' '=> 5' 'defined f' 'f7' 'p' \
  '=> 7' >"$tmp/stdio-expected"
cmp "$tmp/stdio-expected" "$tmp/stdio"

set +e
builds/0/x2c repl extra </dev/null >"$tmp/bad-out" \
  2>"$tmp/bad-err"
result=$?
set -e
test "$result" -eq 2
grep -qx 'x2c repl: unexpected operand' "$tmp/bad-err"

printf '%s\n' 'int n = 0;' \
  'for (int i = 0; i < 100000; i++) n += i;' 'n;' |
  builds/0/libexec/x2c-repl >"$tmp/loop"
printf 'ok\nok\n=> 704982704\n' >"$tmp/loop-expected"
cmp "$tmp/loop-expected" "$tmp/loop"

# A List literal continues across lines until its closing parenthesis.
printf '%s\n' 'List code = %(block' '  (if (not ready)' '    (call wait))' \
  '  (call save));' 'code;' '%(a' 'b);' |
  builds/0/libexec/x2c-repl >"$tmp/list"
printf '%s\n' 'ok' '=> (block (if (not ready) (call wait)) (call save))' \
  '=> (a b)' >"$tmp/list-expected"
cmp "$tmp/list-expected" "$tmp/list"

# SIGINT stops the running submission, and the next one still runs. A
# background job starts with SIGINT ignored, so a signal sent before the
# submission runs is lost and the loop sends another.
printf '%s\n' 'while (1) {}' '1 + 2;' >"$tmp/interrupt-in"
builds/0/libexec/x2c-repl <"$tmp/interrupt-in" >"$tmp/interrupt-out" \
  2>"$tmp/interrupt-err" &
pid=$!
tries=0
until grep -q 'interrupt' "$tmp/interrupt-err"; do
  tries=$((tries + 1))
  test "$tries" -le 100
  kill -INT "$pid"
  sleep 0.2
done
set +e
wait "$pid"
result=$?
set -e
test "$result" -eq 1
printf '=> 3\n' >"$tmp/interrupt-expected"
cmp "$tmp/interrupt-expected" "$tmp/interrupt-out"
grep -q 'evaluation failed: (interrupt ' "$tmp/interrupt-err"

echo "REPL command checks passed"
sh commands/repl/tests/load.sh
