#!/bin/bash
# catch.sh COMPILER -- measures catch selection in a scratch directory:
# c-catch and c-same from gen-catch.py at N=50 and N=400 with measure.sh, then
# catch-runtime.x built and run three times.
here=$(cd "$(dirname "$0")" && pwd)
compiler=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
work=${BENCH_DIR:-${TMPDIR:-/tmp}/hooks-spike-catch}
mkdir -p "$work"
cp "$here"/gen-catch.py "$here"/catch-runtime.x "$work"/
cd "$work" || exit 1
python3 gen-catch.py
for unit in c-catch c-same; do
  for n in 50 400; do
    printf '%s-%s %s\n' "$unit" "$n" \
      "$(bash "$here/measure.sh" "$compiler" out "$unit-$n.x")"
  done
done
"$compiler" build -q --output catch-runtime catch-runtime.x || exit 1
for i in 1 2 3; do ./catch-runtime; done
