#!/bin/bash
# match.sh COMPILER -- measures the match component in a scratch directory:
# m-plain, m-comp, and m-hand from gen-match.py at N=50 and N=400 with
# measure.sh, then match-runtime.x built with and without the component,
# three runs each.
here=$(cd "$(dirname "$0")" && pwd)
compiler=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
work=${BENCH_DIR:-${TMPDIR:-/tmp}/hooks-spike-match}
mkdir -p "$work"
cp "$here"/gen-match.py "$here"/match-runtime.x "$here"/../match-component.x \
  "$work"/
cd "$work" || exit 1
python3 gen-match.py
for unit in m-plain m-comp m-hand; do
  for n in 50 400; do
    files=("$unit-$n.x")
    [ "$unit" = m-comp ] && files=(match-component.x "$unit-$n.x")
    printf '%s-%s %s\n' "$unit" "$n" \
      "$(bash "$here/measure.sh" "$compiler" out "${files[@]}")"
  done
done
{ echo '#include "match-component.x"'; cat match-runtime.x; } \
  >match-runtime-comp.x
"$compiler" build -q --output plain match-runtime.x || exit 1
"$compiler" build -q --output comp match-component.x match-runtime-comp.x ||
  exit 1
for i in 1 2 3; do
  echo "built-in:  $(./plain)"
  echo "component: $(./comp)"
done
