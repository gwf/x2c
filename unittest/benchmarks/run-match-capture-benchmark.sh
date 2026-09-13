#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/match-capture-benchmark"
PROGRAM="$BUILD/match-capture-benchmark"
MODE=${MATCH_CAPTURE_BENCH_MODE:-$(cat "$ROOT/etc/build-mode" \
  2>/dev/null || echo debug)}
ITERATIONS=${MATCH_CAPTURE_BENCH_ITERATIONS:-100000}
SAMPLES=${MATCH_CAPTURE_BENCH_SAMPLES:-15}
mkdir -p "$BUILD"

case "$MODE" in
  debug) flags=(-g) ;;
  optimize) flags=(-O2) ;;
  sanitize)
    flags=(-O1 -g -fsanitize=address,undefined
           -fno-omit-frame-pointer)
    ;;
  *)
    echo "unknown benchmark mode: $MODE" >&2
    exit 2
    ;;
esac

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/benchmarks/match-capture-benchmark.x"
"${CC:-cc}" "${flags[@]}" -iquote "$ROOT/include" \
  -iquote "$ROOT/builds/0/src" "$BUILD/match-capture-benchmark.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"

echo "route,binders,outcome,consumer,iterations,elapsed_ns"
for ((sample = 1; sample <= SAMPLES; sample++)); do
  "$PROGRAM" "$ITERATIONS" "$sample"
done
