#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/varops-benchmark"
SOURCE="$ROOT/unittest/benchmarks/varops-hot-paths.x"
CSV="$BUILD/results.csv"
mkdir -p "$BUILD"
read -r -a link_flags <<<"${BUILD_LDFLAGS:-}"

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" "$SOURCE"
"${CC:-cc}" -g -iquote "$ROOT/include" \
  "$BUILD/varops-hot-paths.c" -L"$ROOT/builds/0" -lx2c -lm \
  "${link_flags[@]}" \
  -o "$BUILD/varops-hot-paths-debug"
"${CC:-cc}" -O2 -iquote "$ROOT/include" \
  "$BUILD/varops-hot-paths.c" -L"$ROOT/builds/0" -lx2c -lm \
  "${link_flags[@]}" \
  -o "$BUILD/varops-hot-paths-optimized"

: >"$CSV"
for mode in debug optimized; do
  for sample in 1 2 3 4 5; do
    "$BUILD/varops-hot-paths-$mode" | while IFS=, read -r name value; do
      printf '%s,%d,%s,%s\n' "$mode" "$sample" "$name" "$value"
    done | tee -a "$CSV"
  done
done

median() {
  local name=$1
  awk -F, -v wanted="$name" \
    '$1 == "optimized" && $3 == wanted { print $4 }' "$CSV" |
    sort -n | sed -n '3p'
}

report_lane() {
  local lane=$1
  local value
  value=$(median "$lane")
  printf '%s optimized median: %.3f ns\n' "$lane" "$value"
}

check_lane() {
  local lane=$1
  local baseline fast
  baseline=$(median "$lane-baseline")
  fast=$(median "$lane-fast")
  if ! awk -v baseline="$baseline" -v fast="$fast" \
    'BEGIN { exit !(fast <= baseline * 0.60) }'; then
    echo "$lane: optimized median $fast ns is not 40% below $baseline ns" \
      >&2
    return 1
  fi
  awk -v lane="$lane" -v baseline="$baseline" -v fast="$fast" \
    'BEGIN {
      printf "%s optimized median: %.3f -> %.3f ns (%.1f%% lower)\n",
             lane, baseline, fast, 100.0 * (baseline - fast) / baseline
    }'
}

check_lane i32
check_lane f32
check_lane f64
report_lane i32-update
report_lane u32-update
report_lane f32-update
report_lane f64-update
report_lane mixed-update
report_lane wide-update
report_lane array-existing-update
report_lane map-existing-update
report_lane map-missing-update
