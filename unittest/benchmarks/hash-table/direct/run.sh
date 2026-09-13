#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
build_dir="$root/unittest/build/benchmarks/hash-table/direct"
vendor_dir="$build_dir/vendor"
header="$vendor_dir/khashl.h"
results_root="$build_dir/results"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
result_dir="$results_root/$timestamp"
if [ -e "$result_dir" ]; then
  result_dir="$results_root/$timestamp-$$"
fi
binary="$result_dir/map-comparison"
raw_results="$result_dir/results.csv"
summary="$result_dir/summary.csv"

khashl_commit=97a0fcb790b43b9e5da8994f4671021fec036f19
khashl_sha256=ae4a4faa2aee719b0d7a9ab9bc51a50baea3b5d0b37e948dc2702c7cd8f86ff0
khashl_base=https://raw.githubusercontent.com/attractivechaos/klib
khashl_url="$khashl_base/$khashl_commit/khashl.h"

samples=${MAP_BENCH_SAMPLES:-14}
counts=${MAP_BENCH_COUNTS:-"32768 1048576"}
probe_multiplier=${MAP_BENCH_PROBE_MULTIPLIER:-4}
iteration_repeats=${MAP_BENCH_ITERATION_REPEATS:-8}
cc=${CC:-cc}

case "$samples" in
  *[!0-9]*|"")
    echo "MAP_BENCH_SAMPLES must be a positive integer" >&2
    exit 2
    ;;
esac
if [ "$samples" -lt 1 ]; then
  echo "MAP_BENCH_SAMPLES must be a positive integer" >&2
  exit 2
fi

if [ "$(cat "$root/etc/build-mode" 2>/dev/null || true)" != optimize ]; then
  echo "map-comparison requires the optimized x2c build mode" >&2
  echo "run 'make config-optimize', clean, and rebuild before benchmarking" >&2
  exit 2
fi

mkdir -p "$vendor_dir" "$result_dir"
current_sha=
if [ -f "$header" ]; then
  current_sha=$(shasum -a 256 "$header" | awk '{ print $1 }')
fi
if [ "$current_sha" != "$khashl_sha256" ]; then
  temporary="$header.tmp.$$"
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  curl -fsSL "$khashl_url" -o "$temporary"
  downloaded_sha=$(shasum -a 256 "$temporary" | awk '{ print $1 }')
  if [ "$downloaded_sha" != "$khashl_sha256" ]; then
    echo "khashl.h checksum mismatch" >&2
    exit 2
  fi
  mv "$temporary" "$header"
  trap - EXIT HUP INT TERM
fi

generated_dir="$build_dir/generated"
mkdir -p "$generated_dir"
"$root/builds/0/x2c" translate --out-dir "$generated_dir" \
  "$root/unittest/benchmarks/hash-table/x2c/flat-map.x" >/dev/null

"$cc" -O2 -DNDEBUG -Wall -Wextra -Werror \
  -iquote "$root/include" -I"$vendor_dir" -I"$generated_dir" \
  -I"$root/unittest/benchmarks/hash-table/x2c" \
  "$root/unittest/benchmarks/hash-table/direct/map-comparison.c" \
  "$root/unittest/benchmarks/hash-table/x2c/khashl-map.c" \
  "$generated_dir/flat-map.c" \
  -L"$root/builds/0" -lx2c -lm -o "$binary"

cp "$root/unittest/benchmarks/hash-table/x2c/flat-map.x" \
  "$result_dir/flat-map.x"

cp "$root/lib/map.x" "$result_dir/map.x"

printf '%s\n' \
  "reference=attractivechaos/klib@$khashl_commit khashl r30" \
  "reference_sha256=$khashl_sha256" \
  "x2c_commit=$(git -C "$root" rev-parse HEAD)" \
  "compiler=$("$cc" --version | sed -n '1p')" \
  "samples=$samples" \
  "counts=$counts" \
  "probe_multiplier=$probe_multiplier" \
  "iteration_repeats=$iteration_repeats" \
  "compile_flags=-O2 -DNDEBUG -Wall -Wextra -Werror" \
  "binary_sha256=$(shasum -a 256 "$binary" | awk '{ print $1 }')" \
  "map_source_sha256=$(shasum -a 256 "$result_dir/map.x" | awk '{ print $1 }')" \
  | tee "$result_dir/metadata.txt"

result_header=sample,implementation,count,capacity,operation,operations
result_header=$result_header,ns_per_operation,checksum
printf '%s\n' "$result_header" >"$raw_results"

sample=1
while [ "$sample" -le "$samples" ]; do
  if [ $((sample % 2)) -eq 1 ]; then
    order=x2c-first
  else
    order=khashl-first
  fi
  for count in $counts; do
    echo "sample=$sample count=$count order=$order" >&2
    "$binary" \
      "$count" "$probe_multiplier" "$iteration_repeats" "$sample" "$order" \
      >>"$raw_results"
  done
  sample=$((sample + 1))
done

awk -f "$root/unittest/benchmarks/hash-table/direct/summarize.awk" \
  "$raw_results" >"$summary"
cat "$summary"

echo "raw_results=$raw_results"
echo "summary=$summary"
echo "results=$result_dir"
