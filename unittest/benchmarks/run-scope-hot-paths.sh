#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/scope-benchmark"
PROGRAM="$BUILD/scope-hot-paths"
mkdir -p "$BUILD"
read -r -a build_cflags <<<"${BUILD_CFLAGS:-}"

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/benchmarks/scope-hot-paths.x"
"${CC:-cc}" ${build_cflags[@]+"${build_cflags[@]}"} \
  -iquote "$ROOT/include/x2c" \
  -iquote "$ROOT/builds/0/src" "$BUILD/scope-hot-paths.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"

echo "Scope hot paths: ${BUILD_MODE:-}, 5 samples (nanoseconds per operation)"
for sample in 1 2 3 4 5; do
  "$PROGRAM"
done
