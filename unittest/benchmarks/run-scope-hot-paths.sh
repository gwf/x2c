#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/scope-benchmark"
PROGRAM="$BUILD/scope-hot-paths"
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

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/benchmarks/scope-hot-paths.x"
"${CC:-cc}" "${flags[@]}" -iquote "$ROOT/include" \
  -iquote "$ROOT/builds/0/src" "$BUILD/scope-hot-paths.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"

echo "Scope hot paths: $MODE, 5 samples (nanoseconds per operation)"
for sample in 1 2 3 4 5; do
  "$PROGRAM"
done
