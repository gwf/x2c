#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/match-capture-benchmark"
PROGRAM="$BUILD/match-capture-benchmark"
ITERATIONS=${MATCH_CAPTURE_BENCH_ITERATIONS:-100000}
SAMPLES=${MATCH_CAPTURE_BENCH_SAMPLES:-15}
mkdir -p "$BUILD/benchmarks"
read -r -a flags <<<"${BUILD_CFLAGS:-}"

# The build's flags set the optimization; MATCH_CAPTURE_BENCH_MODE=sanitize
# adds AddressSanitizer and UBSan.
case "${MATCH_CAPTURE_BENCH_MODE:-build}" in
  build) ;;
  sanitize)
    flags+=(-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer)
    ;;
  *)
    echo "unknown benchmark mode: $MATCH_CAPTURE_BENCH_MODE" >&2
    exit 2
    ;;
esac

# The benchmark includes "../match-recursive.x", so the generated header
# includes "../match-recursive.h". Mirror that layout in the output.
"$ROOT/builds/0/x2c" translate --live-symbols --out-dir "$BUILD" \
  "$ROOT/unittest/match-recursive.x"
"$ROOT/builds/0/x2c" translate --live-symbols --out-dir "$BUILD/benchmarks" \
  "$ROOT/unittest/benchmarks/match-capture-benchmark.x"
"${CC:-cc}" ${flags[@]+"${flags[@]}"} -iquote "$ROOT/include/x2c" \
  -iquote "$ROOT/builds/0/src" "$BUILD/benchmarks/match-capture-benchmark.c" \
  "$BUILD/match-recursive.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"

echo "route,binders,outcome,consumer,iterations,elapsed_ns"
for ((sample = 1; sample <= SAMPLES; sample++)); do
  "$PROGRAM" "$ITERATIONS" "$sample"
done
