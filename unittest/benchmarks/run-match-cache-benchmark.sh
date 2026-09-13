#!/usr/bin/env bash
# Production Match cache-boundary acceptance runner.
#
# Builds the benchmark in debug, optimized, and sanitized forms, proves
# the correctness gate in each, then collects one discarded warm
# process plus 21 fresh optimized processes with alternating arm order.
# Gates: paired six-family aggregate at least 2.0x and no family with a
# median reference/candidate ratio below 1.0. Lane and product-workload
# medians are reported without reweighting the gate. Raw artifacts land
# under debug/match-cache-*.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/match-cache-benchmark"
DEBUG_DIR="$ROOT/debug"
SOURCE="$ROOT/unittest/benchmarks/match-cache-benchmark.x"
TEST_SUPPORT="$ROOT/unittest/test-support.x"
SAMPLES="$DEBUG_DIR/match-cache-samples.csv"
SUMMARY="$DEBUG_DIR/match-cache-summary.txt"
mkdir -p "$BUILD" "$DEBUG_DIR"

# The benchmark includes "../test-support.x", so the generated header
# includes "../test-support.h". Mirror that layout in the output instead
# of flattening both units into one directory.
mkdir -p "$BUILD/benchmarks"
"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" "$TEST_SUPPORT"
"$ROOT/builds/0/x2c" translate --out-dir "$BUILD/benchmarks" "$SOURCE"

CC=${CC:-cc}
common=(-iquote "$ROOT/include" -iquote "$ROOT/builds/0/src"
        "$BUILD/test-support.c" "$BUILD/benchmarks/match-cache-benchmark.c"
        -L"$ROOT/builds/0" -lx2c -lm)
"$CC" -g -O0 "${common[@]}" -o "$BUILD/mcb-debug"
"$CC" -O2 "${common[@]}" -o "$BUILD/mcb"
"$CC" -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
  "${common[@]}" -o "$BUILD/mcb-san"

echo "match-cache: correctness (debug)"
"$BUILD/mcb-debug" --check
echo "match-cache: correctness (optimized)"
"$BUILD/mcb" --check
echo "match-cache: correctness (asan/ubsan)"
"$BUILD/mcb-san" --check

echo "match-cache: discard warm process"
"$BUILD/mcb" --time 0 >/dev/null

: > "$SAMPLES"
for sample in $(seq 1 21); do
  echo "match-cache: sample $sample/21"
  "$BUILD/mcb" --time "$sample" >> "$SAMPLES"
done

awk -F, -v summary="$SUMMARY" '
$1 == "family" {
  family[$2] = 1
  ref[$2 "," sample_id] = $4 / $3
  cand[$2 "," sample_id] = $5 / $3
}
$1 == "sample" { sample_id = $2; samples[sample_id] = 1 }
$1 == "lane" {
  lane[$2] = 1
  lane_ref[$2 "," sample_id] = $4 / $3
  lane_cand[$2 "," sample_id] = $5 / $3
}
function median(values, count,   i, j, tmp) {
  for (i = 1; i < count; i++)
    for (j = i + 1; j <= count; j++)
      if (values[j] < values[i]) {
        tmp = values[i]; values[i] = values[j]; values[j] = tmp
      }
  if (count % 2) return values[(count + 1) / 2]
  return (values[count / 2] + values[count / 2 + 1]) / 2
}
END {
  count = 0
  for (s in samples) count++
  status = 0
  n = 0
  for (s = 1; s <= count; s++) {
    ref_sum = 0; cand_sum = 0
    for (f in family) {
      ref_sum += ref[f "," s]
      cand_sum += cand[f "," s]
    }
    ratios[++n] = ref_sum / cand_sum
  }
  aggregate = median(ratios, n)
  printf "samples,%d\n", count
  for (f in family) {
    m = 0
    for (s = 1; s <= count; s++) {
      fr[++m] = ref[f "," s]
      fc[m] = cand[f "," s]
      fratio[m] = ref[f "," s] / cand[f "," s]
    }
    fm = median(fratio, m)
    printf "family,%s,ref_ns,%.1f,cand_ns,%.1f,ratio,%.6f,%s\n", f,
      median(fr, m), median(fc, m), fm, (fm >= 1.0 ? "pass" : "FAIL")
    if (fm < 1.0) status = 1
  }
  printf "aggregate,%.12f,%s\n", aggregate,
    (aggregate >= 2.0 ? "pass" : "FAIL")
  if (aggregate < 2.0) status = 1
  for (l in lane) {
    m = 0
    for (s = 1; s <= count; s++) {
      lr[++m] = lane_ref[l "," s]
      lc[m] = lane_cand[l "," s]
    }
    printf "lane,%s,ref_ns,%.1f,cand_ns,%.1f,ratio,%.6f\n", l,
      median(lr, m), median(lc, m), median(lr, m) / median(lc, m)
  }
  exit status
}' "$SAMPLES" | tee "$SUMMARY"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  echo "match-cache: GATE FAILED (see $SUMMARY)" >&2
  exit 1
fi
echo "match-cache: all gates passed"
