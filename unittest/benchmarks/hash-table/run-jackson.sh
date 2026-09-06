#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
campaign_dir="$root/unittest/build/benchmarks/hash-table/jackson"
source_dir="$campaign_dir/source"
results_root="$campaign_dir/results"
adapter_dir="$root/unittest/benchmarks/hash-table/jackson"
summarizer="$adapter_dir/summarize.awk"

suite_url=https://github.com/JacksonAllan/c_cpp_hash_tables_benchmark.git
suite_commit=71f0e4075b30d3b0e9baadc07bc7e889b04836ea

mode=${1:-smoke}
profile=${2:-matched}
cc=${CC:-cc}
cxx=${CXX:-c++}

case "$mode" in
  smoke|full) ;;
  *)
    echo "usage: $0 [smoke|full] [matched|fixed-policy|pointer|string|string-fixed-policy]" >&2
    exit 2
    ;;
esac

case "$profile" in
  matched)
    profile_flags=
    ;;
  pointer)
    profile_flags=-DX2C_POINTER_PROFILE
    ;;
  string)
    profile_flags=-DX2C_STRING_PROFILE
    ;;
  string-fixed-policy)
    profile_flags="-DX2C_STRING_PROFILE -DX2C_FIXED_POLICY_PROFILE"
    ;;
  fixed-policy)
    profile_flags=-DX2C_FIXED_POLICY_PROFILE
    ;;
  *)
    echo "usage: $0 [smoke|full] [matched|fixed-policy|pointer|string|string-fixed-policy]" >&2
    exit 2
    ;;
esac

if [ "$(cat "$root/etc/build-mode" 2>/dev/null || true)" != optimize ]; then
  echo "Jackson benchmark requires the optimized x2c build mode" >&2
  echo "run 'make optimize', clean, and rebuild before benchmarking" >&2
  exit 2
fi

mkdir -p "$campaign_dir" "$results_root"
if [ ! -d "$source_dir/.git" ]; then
  git clone "$suite_url" "$source_dir"
fi

if ! git -C "$source_dir" cat-file \
  -e "$suite_commit^{commit}" 2>/dev/null
then
  git -C "$source_dir" fetch origin "$suite_commit"
fi

head_commit=$(git -C "$source_dir" rev-parse HEAD)
if [ "$head_commit" != "$suite_commit" ]; then
  if [ -n "$(git -C "$source_dir" status --short)" ]; then
    echo "generated Jackson checkout is dirty at the wrong commit" >&2
    echo "remove $source_dir and rerun" >&2
    exit 2
  fi
  git -C "$source_dir" checkout --detach "$suite_commit"
fi

mkdir -p \
  "$source_dir/blueprints/x2c_var_var" \
  "$source_dir/blueprints/x2c_pointer_var" \
  "$source_dir/blueprints/x2c_string_cstring" \
  "$source_dir/shims/x2c_map" \
  "$source_dir/shims/x2c_typed_string_map" \
  "$source_dir/shims/x2c_ankerl_unordered_dense" \
  "$source_dir/shims/x2c_boost_unordered_flat_map"
cp "$adapter_dir/config.h" "$source_dir/config.h"
cp "$adapter_dir/blueprint.h" \
  "$source_dir/blueprints/x2c_var_var/blueprint.h"
cp "$adapter_dir/pointer-blueprint.h" \
  "$source_dir/blueprints/x2c_pointer_var/blueprint.h"
cp "$adapter_dir/string-blueprint.h" \
  "$source_dir/blueprints/x2c_string_cstring/blueprint.h"
cp "$adapter_dir/shim.h" "$source_dir/shims/x2c_map/shim.h"
cp "$adapter_dir/typed-string-shim.h" \
  "$source_dir/shims/x2c_typed_string_map/shim.h"
cp "$adapter_dir/ankerl-shim.h" \
  "$source_dir/shims/x2c_ankerl_unordered_dense/shim.h"
cp "$adapter_dir/boost-shim.h" \
  "$source_dir/shims/x2c_boost_unordered_flat_map/shim.h"
cp "$adapter_dir/abi.h" "$source_dir/x2c-benchmark-abi.h"

if [ "$mode" = smoke ]; then
  mode_flags="-DKEY_COUNT=5000
    -DKEY_COUNT_MEASUREMENT_INTERVAL=500
    -DRUN_COUNT=2
    -DDISCARDED_RUNS_COUNT=0
    -DAPPROXIMATE_CACHE_SIZE=1000000
    -DMILLISECOND_COOLDOWN_BETWEEN_BENCHMARKS=0"
else
  mode_flags=
fi

binary="$campaign_dir/jackson-$mode-$profile"
abi_object="$campaign_dir/x2c-benchmark-abi.o"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
results_dir="$results_root/$timestamp-$mode-$profile"
mkdir -p "$results_dir"

"$cc" -O3 -DNDEBUG -iquote "$root/include" \
  -c "$adapter_dir/abi.c" -o "$abi_object"

(
  cd "$source_dir"
  # Deliberate word splitting expands the compile-time flag lists.
  # shellcheck disable=SC2086
  "$cxx" -I. -iquote "$root/include" -std=c++20 -O3 -DNDEBUG \
    -Wall -Wpedantic $mode_flags $profile_flags main.cpp \
    "$abi_object" -L"$root/builds/0" -lx2c -lm -o "$binary"
)

{
  dirty_files=$(git -C "$root" status --porcelain | wc -l | tr -d ' ')
  cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -p)
  echo "suite=$suite_url"
  echo "suite_commit=$suite_commit"
  echo "x2c_commit=$(git -C "$root" rev-parse HEAD)"
  echo "x2c_dirty_files=$dirty_files"
  if git -C "$root" diff --quiet origin/dev -- lib/map.x; then
    echo "map_matches_origin_dev=yes"
  else
    echo "map_matches_origin_dev=no"
  fi
  echo "mode=$mode"
  echo "profile=$profile"
  echo "max_load_factor=$(awk '/^#define MAX_LOAD_FACTOR / { print $3 }' \
    "$adapter_dir/config.h")"
  echo "host=$(uname -srm)"
  echo "hardware=$(uname -m)"
  echo "cpu=$cpu"
  echo "c_compiler=$("$cc" --version | sed -n '1p')"
  echo "cxx_compiler=$("$cxx" --version | sed -n '1p')"
} | tee "$results_dir/metadata.txt"

(
  cd "$results_dir"
  "$binary"
) >"$results_dir/run.log" 2>&1
cat "$results_dir/run.log"

csv=$(find "$results_dir" -maxdepth 1 -name '*.csv' -print)
if [ -z "$csv" ]; then
  echo "Jackson benchmark did not produce a CSV result" >&2
  exit 1
fi
awk -v profile="$profile" -f "$summarizer" "$csv" \
  >"$results_dir/summary.tsv"
cat "$results_dir/summary.tsv"

echo "results=$results_dir"
