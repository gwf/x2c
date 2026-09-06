#!/usr/bin/env bash
# Lisp AUTO acceptance runner.
#
# Builds the benchmark in debug, optimized, and sanitized forms,
# proves the correctness gate in each, then collects one discarded
# warm process plus 21 fresh optimized processes with alternating arm
# order.  Gate: median paired prepared_hit / evaluator_hit at most
# 0.90.  Transition, third-call, and nil lanes are reported without
# reweighting the gate.  Raw artifacts land under debug/lisp-auto-*.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/lisp-auto-benchmark"
DEBUG_DIR="$ROOT/debug"
SOURCE="$ROOT/unittest/benchmarks/lisp-auto-benchmark.x"
SAMPLES="$DEBUG_DIR/lisp-auto-samples.csv"
SUMMARY="$DEBUG_DIR/lisp-auto-summary.txt"
mkdir -p "$BUILD" "$DEBUG_DIR"

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" "$SOURCE"

CC=${CC:-cc}
common=(-iquote "$ROOT/include" -iquote "$ROOT/builds/0/src"
        "$BUILD/lisp-auto-benchmark.c" -L"$ROOT/builds/0" -lx2c -lm)
"$CC" -g -O0 "${common[@]}" -o "$BUILD/lab-debug"
"$CC" -O2 "${common[@]}" -o "$BUILD/lab"
"$CC" -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
  "${common[@]}" -o "$BUILD/lab-san"

echo "lisp-auto: correctness (debug)"
"$BUILD/lab-debug" --check
echo "lisp-auto: correctness (optimized)"
"$BUILD/lab" --check
echo "lisp-auto: correctness (asan/ubsan)"
"$BUILD/lab-san" --check

echo "lisp-auto: discard warm process"
"$BUILD/lab" --time 0 >/dev/null

: > "$SAMPLES"
for sample in $(seq 1 21); do
  echo "lisp-auto: sample $sample/21"
  "$BUILD/lab" --time "$sample" >> "$SAMPLES"
done

awk -F, -v summary="$SUMMARY" '
$1 == "sample" { sample_id = $2; samples[sample_id] = 1 }
$1 == "lane" {
  lane[$2] = 1
  value[$2 "," sample_id] = $4 / $3
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
  printf "samples,%d\n", count
  for (l in lane) {
    m = 0
    for (s = 1; s <= count; s++) lv[++m] = value[l "," s]
    printf "lane,%s,ns,%.3f\n", l, median(lv, m)
  }
  n = 0
  for (s = 1; s <= count; s++)
    ratios[++n] = value["prepared-hit," s] / value["evaluator-hit," s]
  gate = median(ratios, n)
  printf "prepared-hit-over-evaluator-hit,%.9f,%s\n", gate,
    (gate <= 0.90 ? "pass" : "FAIL")
  exit gate <= 0.90 ? 0 : 1
}' "$SAMPLES" | tee "$SUMMARY"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  echo "lisp-auto: GATE FAILED (see $SUMMARY)" >&2
  exit 1
fi
echo "lisp-auto: all gates passed"
