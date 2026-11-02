#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/iter-benchmark"
PROGRAM="$BUILD/iter-hot-paths"
mkdir -p "$BUILD"
read -r -a build_cflags <<<"${BUILD_CFLAGS:-}"
read -r -a link_flags <<<"${BUILD_LDFLAGS:-}"

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/benchmarks/iter-hot-paths.x"
"${CC:-cc}" ${build_cflags[@]+"${build_cflags[@]}"} \
  -iquote "$ROOT/include/x2c" \
  -iquote "$ROOT/builds/0/src" "$BUILD/iter-hot-paths.c" \
  -L"$ROOT/builds/0" -lx2c -lm "${link_flags[@]}" -o "$PROGRAM"

echo "Iter hot paths: ${BUILD_MODE:-}, 5 samples (nanoseconds per operation)"
for sample in 1 2 3 4 5; do
  "$PROGRAM"
done
