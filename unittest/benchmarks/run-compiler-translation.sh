#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/compiler-translation"
SAMPLES=${SAMPLES:-5}

sources=(
  src/transform.x
  src/emit.x
  src/expressions.x
  src/generate.x
  src/parse.x
  src/type.x
)
if [[ -f "$ROOT/lib/tokenizer.x" ]]; then
  sources+=(lib/tokenizer.x)
else
  sources+=(src/tokenizer.x)
fi

measure() {
  local stage=$1
  local mode=$2
  local compiler="$ROOT/builds/$stage/x2c"
  local -a flags=()
  if [[ $mode == live ]]; then flags+=(--live-symbols); fi
  local output="$BUILD/stage-$stage-$mode"

  rm -rf "$output"
  mkdir -p "$output"
  for source in "${sources[@]}"; do
    "$compiler" translate "${flags[@]}" --out-dir "$output" "$ROOT/$source" >/dev/null
  done

  local bytes digest
  bytes=$(find "$output" -type f \( -name '*.c' -o -name '*.h' \) \
    -exec wc -c {} + | awk 'END { print $1 }')
  digest=$(find "$output" -type f \( -name '*.c' -o -name '*.h' \) \
    -print0 | sort -z | xargs -0 shasum -a 256 | awk '{ print $1 }' | \
    shasum -a 256 | \
    awk '{ print $1 }')

  for sample in $(seq 1 "$SAMPLES"); do
    local start finish elapsed
    start=$(perl -MTime::HiRes=time -e 'printf "%.9f", time')
    for source in "${sources[@]}"; do
      "$compiler" translate "${flags[@]}" --out-dir "$output" "$ROOT/$source" >/dev/null
    done
    finish=$(perl -MTime::HiRes=time -e 'printf "%.9f", time')
    elapsed=$(awk -v start="$start" -v finish="$finish" \
      'BEGIN { printf "%.6f", finish - start }')
    printf 'translation,stage-%s,%s,%s,%s,%s,%s\n' \
      "$stage" "$mode" "$sample" "$elapsed" "$bytes" "$digest"
  done
}

mkdir -p "$BUILD"
printf 'benchmark,stage,mode,sample,seconds,bytes,sha256\n'
for stage in 0 1; do
  compiler="$ROOT/builds/$stage/x2c"
  [[ -x $compiler ]] || continue
  measure "$stage" default
  if { "$compiler" translate --help 2>&1 || true; } |
      grep -q -- '--live-symbols'; then
    measure "$stage" live
  fi
done
