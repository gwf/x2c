#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
campaign_dir="$root/unittest/build/benchmarks/hash-table/udb3"
source_dir="$campaign_dir/source"
results_root="$campaign_dir/results"
adapter="$root/unittest/benchmarks/hash-table/udb3/test.c"
verifier="$root/unittest/benchmarks/hash-table/udb3/verify.awk"

suite_url=https://github.com/attractivechaos/udb3.git
suite_commit=4ac803847c27accc3ddc66f13caffcbd099aa5d2

mode=${1:-smoke}
cc=${CC:-cc}
cxx=${CXX:-c++}
implementations=${UDB3_IMPLEMENTATIONS:-"x2c verstable khashl CC STC \
robin_hood ska_bytell unordered_dense"}

case "$mode" in
  smoke)
    run_arguments="-N 200000 -n 20000 -k 5"
    expected_rows=10
    ;;
  full)
    run_arguments=
    expected_rows=22
    ;;
  *)
    echo "usage: $0 [smoke|full]" >&2
    exit 2
    ;;
esac

if [ "$(cat "$root/etc/build-mode" 2>/dev/null || true)" != optimize ]; then
  echo "udb3 benchmark requires the optimized x2c build mode" >&2
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
    echo "generated udb3 checkout is dirty at the wrong commit" >&2
    echo "remove $source_dir and rerun" >&2
    exit 2
  fi
  git -C "$source_dir" checkout --detach "$suite_commit"
fi

x2c_binary="$campaign_dir/run-test-x2c"
"$cc" -O3 -DNDEBUG -Wall -Wextra \
  -I"$source_dir" -iquote "$root/include" "$adapter" \
  -L"$root/builds/0" -lx2c -lm -o "$x2c_binary"

for implementation in $implementations; do
  case "$implementation" in
    x2c)
      ;;
    verstable|khashl|robin_hood|ska_bytell|unordered_dense)
      make -B -C "$source_dir/$implementation" \
        CC="$cc" CXX="$cxx" run-test
      ;;
    CC|STC)
      make -B -C "$source_dir/$implementation" \
        CC="$cc" CXX="$cxx" run-test
      ;;
    *)
      echo "unknown udb3 implementation: $implementation" >&2
      exit 2
      ;;
  esac
done

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
results_dir="$results_root/$timestamp-$mode"
combined="$results_dir/combined.tsv"
mkdir -p "$results_dir"

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
  echo "implementations=$implementations"
  echo "host=$(uname -srm)"
  echo "hardware=$(uname -m)"
  echo "cpu=$cpu"
  echo "c_compiler=$("$cc" --version | sed -n '1p')"
  echo "cxx_compiler=$("$cxx" --version | sed -n '1p')"
} | tee "$results_dir/metadata.txt"

header="implementation	mode	inputs	table_size	checksum"
header="$header	elapsed_s	peak_mb	us_per_input	bytes_per_entry"
printf '%s\n' "$header" >"$combined"

for implementation in $implementations; do
  if [ "$implementation" = x2c ]; then
    binary="$x2c_binary"
  else
    binary="$source_dir/$implementation/run-test"
  fi

  for workload in insert delete; do
    raw="$results_dir/$implementation-$workload.log"
    if [ "$workload" = delete ]; then
      delete_flag=-d
    else
      delete_flag=
    fi

    echo "implementation=$implementation workload=$workload" >&2
    # Deliberate word splitting expands the suite's argument list.
    # shellcheck disable=SC2086
    "$binary" $delete_flag $run_arguments >"$raw"
    cat "$raw"

    awk -v implementation="$implementation" '
      BEGIN { FS = "\t"; OFS = "\t" }
      $1 == "MI" || $1 == "MD" {
        print implementation, $1, $2, $3, $4, $5, $6, $7, $8
      }
    ' "$raw" >>"$combined"
  done
done

for implementation in $implementations; do
  actual_rows=$(awk -F '	' -v name="$implementation" '
    NR > 1 && $1 == name {
      count++
    }
    END {
      print count + 0
    }
  ' "$combined")
  if [ "$actual_rows" -ne "$expected_rows" ]; then
    printf '%s produced %s rows; expected %s\n' \
      "$implementation" "$actual_rows" "$expected_rows" >&2
    exit 1
  fi
done

awk -f "$verifier" "$combined"
echo "checksums=matched"
echo "results=$results_dir"
