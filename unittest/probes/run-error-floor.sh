#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/error-probes"
PROGRAM="$BUILD/error-fatal"
PREINIT="$BUILD/error-fatal-preinit"
MODE=$(cat "$ROOT/etc/build-mode" 2>/dev/null || echo debug)
mkdir -p "$BUILD"

case "$MODE" in
  debug) flags=(-g) ;;
  optimize) flags=(-O2) ;;
  *)
    echo "unknown build mode: $MODE" >&2
    exit 2
    ;;
esac

"$ROOT/builds/0/x2c" translate --live-symbols --out-dir "$BUILD" \
  "$ROOT/unittest/probes/error-fatal.x"
"${CC:-cc}" "${flags[@]}" -iquote "$ROOT/include" \
  "$BUILD/error-fatal.c" -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"
"${CC:-cc}" "${flags[@]}" -iquote "$ROOT/builds/0/lib" \
  "$ROOT/unittest/probes/error-fatal-preinit.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$PREINIT"

# The floor prints the Symbol as hex, whose value is not stable across
# vocabulary edits, so match the fixed prefix and the reason suffix rather
# than the whole line.
check_case() {
  local name=$1
  local reason=$2
  local status output

  set +e
  if [[ $name == preinit ]]; then
    ( "$PREINIT" >"$BUILD/$name.stdout" 2>"$BUILD/$name.stderr"
      child_status=$?
      exit "$child_status"
    ) 2>/dev/null
  else
    ( "$PROGRAM" "$name" >"$BUILD/$name.stdout" 2>"$BUILD/$name.stderr"
      child_status=$?
      exit "$child_status"
    ) 2>/dev/null
  fi
  status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    echo "$name: expected terminal failure" >&2
    return 1
  fi
  test ! -s "$BUILD/$name.stdout"
  output=$(tail -1 "$BUILD/$name.stderr")
  if [[ $output != "x2c error floor: code 0x"* ]]; then
    echo "$name: final stderr line lacks the floor prefix: $output" >&2
    return 1
  fi
  if [[ $output != *": $reason" ]]; then
    echo "$name: stderr lacks reason '$reason': $output" >&2
    return 1
  fi
}

check_case preinit "raise before initialization"
check_case abort-policy "unhandled and policy is abort"
check_case uncaught-invariant "non-returning error was not caught"
check_case uncaught-format "non-returning error was not caught"
check_case uncaught-not-found "non-returning error was not caught"
check_case uncaught-malformed "non-returning error was not caught"
check_case after-shutdown "raise re-entered or after shutdown"
check_case dynamic-invalid "error detail contains an identity-bearing value"
check_case context-bound "error stack exceeded its bound"
check_case handled-alloc "non-returning error was not caught"
check_case handled-size "non-returning error was not caught"
check_case handled-format "non-returning error was not caught"
check_case handled-io-fail "non-returning error was not caught"
check_case handled-bad-arity "non-returning error was not caught"
check_case handled-invariant "non-returning error was not caught"

"$PROGRAM" pool-isolation \
  >"$BUILD/pool-isolation.stdout" 2>"$BUILD/pool-isolation.stderr"
test ! -s "$BUILD/pool-isolation.stdout"
test ! -s "$BUILD/pool-isolation.stderr"

"$PROGRAM" shutdown-order \
  >"$BUILD/shutdown-order.stdout" 2>"$BUILD/shutdown-order.stderr"
test ! -s "$BUILD/shutdown-order.stdout"
test "$(grep -c 'code=<hook-probe>' "$BUILD/shutdown-order.stderr")" -eq 1
test "$(grep -c 'code=<late-probe>' "$BUILD/shutdown-order.stderr")" -eq 1
test "$(grep -c 'shutdown-hook: before raise' \
  "$BUILD/shutdown-order.stderr")" -eq 1
test "$(grep -c 'shutdown-hook: after raise' \
  "$BUILD/shutdown-order.stderr")" -eq 1
test "$(tail -1 "$BUILD/shutdown-order.stderr")" = \
  "shutdown-complete: error-ready=0"

echo "error floor and shutdown probes: 17 passed"
