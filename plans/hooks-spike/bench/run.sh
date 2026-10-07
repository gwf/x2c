#!/bin/bash
# run.sh COMPILER [UNIT...] -- generates the benchmark units in a scratch
# directory and measures each UNIT at N=50 and N=400 with measure.sh.
# Prints: unit-N, min instructions retired (compiler process only), min real
# seconds, min user seconds (user time includes the reaped meta helper).
here=$(cd "$(dirname "$0")" && pwd)
compiler=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
shift
work=${BENCH_DIR:-${TMPDIR:-/tmp}/hooks-spike-bench}
mkdir -p "$work"
cp "$here"/gen.py "$here"/gen-ident.py "$here"/ident.x \
  "$here"/../string-switch.x "$here"/../trace.x "$work"/
git -C "$here" show 72432607:plans/hooks-spike/string-switch.x \
  >"$work/string-switch-orig.x"
cd "$work" || exit 1
python3 gen.py
python3 gen-ident.py
units=("$@")
if [ ${#units[@]} = 0 ]; then
  units=(sw-hand sw-dec sw-dec2 sw-hook tr-plain tr-hand tr-dec tr-hook
         id-tpl id-meta)
fi
for unit in "${units[@]}"; do
  for n in 50 400; do
    printf '%s-%s %s\n' "$unit" "$n" \
      "$(bash "$here/measure.sh" "$compiler" out "$unit-$n.x")"
  done
done
