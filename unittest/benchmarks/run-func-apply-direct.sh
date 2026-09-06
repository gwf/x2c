#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
X2C=${X2C:-"$ROOT/builds/0/x2c"}
RUNTIME_ROOT=${X2C_RUNTIME_ROOT:-"$ROOT"}
LABEL=${FUNC_APPLY_LABEL:-current}
SAMPLES=${FUNC_APPLY_SAMPLES:-5}
ITERATIONS=1000000
BUILD="$ROOT/unittest/build/func-apply-direct-$LABEL"
PROGRAM="$BUILD/func-apply-direct"
SOURCE="$ROOT/unittest/benchmarks/func-apply-direct.x"
mkdir -p "$BUILD"

"$X2C" translate --out-dir "$BUILD" "$SOURCE" >/dev/null
"${CC:-cc}" -O2 -iquote "$RUNTIME_ROOT/include" \
  -iquote "$RUNTIME_ROOT/builds/0/src" "$BUILD/func-apply-direct.c" \
  -L"$RUNTIME_ROOT/builds/0" -lx2c -lm -o "$PROGRAM"

sample_file=$(mktemp)
trap 'rm -f "$sample_file"' EXIT
for ((sample = 1; sample <= SAMPLES; sample++)); do
  while IFS=, read -r lane elapsed; do
    printf '%s,%s\n' "$lane" "$elapsed" >>"$sample_file"
    printf 'sample,%s-%s,%d,%s\n' "$LABEL" "$lane" "$sample" "$elapsed"
  done < <("$PROGRAM")
done

for lane in uncaptured captured; do
  median=$(awk -F, -v lane="$lane" '$1 == lane { print $2 }' \
    "$sample_file" | sort -n | sed -n "$(((SAMPLES + 1) / 2))p")
  awk -v label="$LABEL-$lane" -v samples="$SAMPLES" \
      -v elapsed="$median" -v iterations="$ITERATIONS" \
    'BEGIN {
      printf "median,%s,%d,%.3f\n", label, samples, elapsed / iterations
    }'
done
