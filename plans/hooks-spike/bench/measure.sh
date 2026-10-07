#!/bin/bash
# measure.sh COMPILER OUTDIR FILE...
# One warm-up translation, then the minimum over five translations of
# instructions retired (compiler process only), real seconds, and user
# seconds (which include the reaped meta helper).
compiler=$1
out=$2
shift 2
mkdir -p "$out"
"$compiler" translate -j 1 -q --out-dir "$out" "$@" >/dev/null 2>&1 || {
  echo "translate failed: $compiler $*"
  "$compiler" translate -j 1 --out-dir "$out" "$@" 2>&1 | tail -20
  exit 1
}
for i in 1 2 3 4 5; do
  /usr/bin/time -l "$compiler" translate -j 1 -q --out-dir "$out" "$@" 2>&1 >/dev/null |
    awk '/instructions retired/ {n=$1} / real / {r=$1; u=$3} END {print n, r, u}'
done | awk 'NR==1 {n=$1; r=$2; u=$3}
  {if ($1<n) n=$1; if ($2<r) r=$2; if ($3<u) u=$3}
  END {print n, r, u}'
