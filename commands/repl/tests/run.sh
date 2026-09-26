#!/bin/sh
set -eu

cd "$(dirname "$0")/../../.."
tmp=${TMPDIR:-/tmp}/x2c-repl-tests.$$
mkdir -p "$tmp"
repl=
trap 'test -z "$repl" || kill -9 "$repl" 2>/dev/null; rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

# Staged modules resolve the session's print and the runtime in this binary.
export_flags=
case $(uname -s) in
  Linux) export_flags="-Xlinker -export-dynamic" ;;
esac
# shellcheck disable=SC2086
builds/0/x2c build --plain $export_flags \
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

# A crash returns to the prompt with earlier state intact, including a
# runaway recursion twice in a row on the same signal stack.
printf '%s\n' 'int keep = 41;' 'int *p = 0;' '*p;' \
  'int deep(int n) { return deep(n + 1) + 1; }' 'deep(0);' 'deep(0);' \
  'keep + 1;' >"$tmp/crash-in"
if builds/0/libexec/x2c-repl <"$tmp/crash-in" >"$tmp/crash-out" \
     2>"$tmp/crash-err"; then
  echo "crashing REPL submissions unexpectedly succeeded" >&2
  exit 1
fi
printf 'ok\nok\ndefined deep\n=> 42\n' >"$tmp/crash-expected"
cmp "$tmp/crash-expected" "$tmp/crash-out"
test "$(grep -c '^evaluation failed: (crash (signal' "$tmp/crash-err")" -eq 3

# The first Ctrl-C during a runaway loop only warns; the second stops it
# and the session keeps its state. The REPL starts with SIGINT ignored, so
# a Ctrl-C that arrives while the loop still compiles is lost; the harness
# presses again until each step shows, and gives up after 30 seconds.
mkfifo "$tmp/fifo"
(trap '' INT; exec builds/0/libexec/x2c-repl) \
  <"$tmp/fifo" >"$tmp/int-out" 2>"$tmp/int-err" &
repl=$!
exec 3>"$tmp/fifo"
printf 'int keep = 41;\nwhile (1) keep = 41;\n' >&3
press_until() {
  tries=0
  until grep -q "$1" "$tmp/int-err"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 60 ]; then
      echo "REPL interrupt check timed out waiting for: $1" >&2
      exit 1
    fi
    kill -INT "$repl"
    sleep 0.5
  done
}
press_until 'press Ctrl-C again'
press_until '^evaluation failed: (interrupt (signal'
printf 'keep + 1;\n' >&3
exec 3>&-
set +e
wait "$repl"
result=$?
set -e
repl=
test "$result" -eq 1
printf 'ok\n=> 42\n' >"$tmp/int-expected"
cmp "$tmp/int-expected" "$tmp/int-out"

echo "REPL command checks passed"
