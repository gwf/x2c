#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/scope-probes"
PROGRAM="$BUILD/scope-shutdown"
PREINIT="$BUILD/scope-preinit"
mkdir -p "$BUILD"

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/probes/scope-shutdown.x"
cc -g -iquote "$ROOT/include" -iquote "$ROOT/builds/0/src" \
  "$BUILD/scope-shutdown.c" -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"
cc -g -iquote "$ROOT/builds/0/lib" \
  "$ROOT/unittest/probes/scope-preinit.c" \
  "$ROOT/builds/0/lib/scope.o" "$ROOT/builds/0/lib/thread-state.o" \
  -pthread -lm -o "$PREINIT"

for mode in allocate shutdown; do
  "$PREINIT" "$mode" >"$BUILD/preinit-$mode.stdout" \
    2>"$BUILD/preinit-$mode.stderr"
  test ! -s "$BUILD/preinit-$mode.stdout"
  test ! -s "$BUILD/preinit-$mode.stderr"
done

for mode in malloc-overflow calloc-overflow; do
  if ( "$PREINIT" "$mode" >"$BUILD/preinit-$mode.stdout" \
        2>"$BUILD/preinit-$mode.stderr"
      child_status=$?
      exit "$child_status"
    ) 2>/dev/null; then
    echo "$mode: expected terminal failure" >&2
    exit 1
  fi
  test ! -s "$BUILD/preinit-$mode.stdout"
done
test "$(head -1 "$BUILD/preinit-malloc-overflow.stderr")" = \
  "Scope: allocation size overflow"
test "$(head -1 "$BUILD/preinit-calloc-overflow.stderr")" = \
  "Scope: calloc size overflow"

if ( "$PREINIT" reinitialize >"$BUILD/preinit-reinitialize.stdout" \
      2>"$BUILD/preinit-reinitialize.stderr"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null; then
  echo "post-shutdown initialization restarted Scope" >&2
  exit 1
fi
test ! -s "$BUILD/preinit-reinitialize.stdout"
test "$(head -1 "$BUILD/preinit-reinitialize.stderr")" = \
  "Scope: operation attempted after shutdown"

"$PROGRAM" clean >"$BUILD/clean.stdout" 2>"$BUILD/clean.stderr"
test ! -s "$BUILD/clean.stdout"
test ! -s "$BUILD/clean.stderr"

"$PROGRAM" leak >"$BUILD/leak.stdout" 2>"$BUILD/leak.stderr"
test ! -s "$BUILD/leak.stdout"
expected_leak=$'Scope leak detected:\n\tlive_scopes: 1\n\tlive_allocations: 1'
expected_leak+=$'\n\tscope "probe leak": 1 allocations'
expected_leak+=$'\n\tlive_backing_allocations: 2'
test "$(cat "$BUILD/leak.stderr")" = "$expected_leak"

"$PROGRAM" repeat >"$BUILD/repeat.stdout" 2>"$BUILD/repeat.stderr"
test ! -s "$BUILD/repeat.stdout"
test ! -s "$BUILD/repeat.stderr"

"$PROGRAM" thread-state >"$BUILD/thread-state.stdout" \
  2>"$BUILD/thread-state.stderr"
test ! -s "$BUILD/thread-state.stdout"
test ! -s "$BUILD/thread-state.stderr"

"$PROGRAM" hooks >"$BUILD/hooks.stdout" 2>"$BUILD/hooks.stderr"
test ! -s "$BUILD/hooks.stdout"
test ! -s "$BUILD/hooks.stderr"

"$PROGRAM" overflow >"$BUILD/overflow.stdout" 2>"$BUILD/overflow.stderr"
test ! -s "$BUILD/overflow.stdout"
test ! -s "$BUILD/overflow.stderr"

if ( "$PROGRAM" after >"$BUILD/after.stdout" 2>"$BUILD/after.stderr"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null; then
  echo "post-shutdown allocation unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$BUILD/after.stdout"
test "$(head -1 "$BUILD/after.stderr")" = \
  "Scope: operation attempted after shutdown"

"$PROGRAM" push-null >"$BUILD/push-null.stdout" \
  2>"$BUILD/push-null.stderr"
test ! -s "$BUILD/push-null.stdout"
test ! -s "$BUILD/push-null.stderr"

"$PROGRAM" slot-null >"$BUILD/slot-null.stdout" \
  2>"$BUILD/slot-null.stderr"
test ! -s "$BUILD/slot-null.stdout"
test ! -s "$BUILD/slot-null.stderr"

"$PROGRAM" hook-null >"$BUILD/hook-null.stdout" \
  2>"$BUILD/hook-null.stderr"
test ! -s "$BUILD/hook-null.stdout"
test ! -s "$BUILD/hook-null.stderr"

if ( "$PROGRAM" live-thread-match \
      >"$BUILD/live-thread-match.stdout" \
      2>"$BUILD/live-thread-match.stderr"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null; then
  echo "live worker unexpectedly survived shutdown" >&2
  exit 1
fi
test ! -s "$BUILD/live-thread-match.stdout"
test "$(head -1 "$BUILD/live-thread-match.stderr")" = \
  "Thread: 1 worker(s) still live at shutdown"

if ( "$PROGRAM" completed-thread \
      >"$BUILD/completed-thread.stdout" \
      2>"$BUILD/completed-thread.stderr"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null; then
  echo "completed unjoined worker unexpectedly survived shutdown" >&2
  exit 1
fi
test ! -s "$BUILD/completed-thread.stdout"
test "$(head -1 "$BUILD/completed-thread.stderr")" = \
  "Thread: 1 worker(s) still live at shutdown"

echo "Scope lifecycle probes: 17 passed"
