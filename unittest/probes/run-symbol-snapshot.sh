#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/symbol-probes"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

copy_runtime_sources() {
  local destination=$1 source
  cp "$ROOT"/lib/*.x "$ROOT"/lib/*.xmacro "$destination"
  for source in "$ROOT"/lib/*.xlisp; do
    [[ -e "$source" ]] && cp "$source" "$destination"
  done
  return 0
}

rm -rf "$BUILD"
mkdir -p "$BUILD/default" "$BUILD/live" "$BUILD/overlay-default" \
  "$BUILD/overlay-live" "$BUILD/main-default" "$BUILD/main-live"
mkdir -p "$BUILD/hygiene-default" "$BUILD/hygiene-repeat" \
  "$BUILD/hygiene-live" "$BUILD/collision-default" "$BUILD/collision-live"

"$X2C" translate --out-dir "$BUILD/default" "$ROOT/examples/foreach.x"
"$X2C" translate --live-symbols --out-dir "$BUILD/live" "$ROOT/examples/foreach.x"
diff -u "$BUILD/live/foreach.c" "$BUILD/default/foreach.c"
diff -u "$BUILD/live/foreach.h" "$BUILD/default/foreach.h"

"$X2C" translate --out-dir "$BUILD/main-default" "$ROOT/src/main.x"
"$X2C" translate --live-symbols --out-dir "$BUILD/main-live" "$ROOT/src/main.x"
diff -u "$BUILD/main-live/main.c" "$BUILD/main-default/main.c"
diff -u "$BUILD/main-live/main.h" "$BUILD/main-default/main.h"

hygiene="$ROOT/unittest/compiler-fixtures/generated-name-hygiene.x"
"$X2C" translate --out-dir "$BUILD/hygiene-default" "$hygiene"
"$X2C" translate --out-dir "$BUILD/hygiene-repeat" "$hygiene"
"$X2C" translate --live-symbols --out-dir "$BUILD/hygiene-live" "$hygiene"
diff -u "$BUILD/hygiene-default/generated-name-hygiene.c" \
  "$BUILD/hygiene-repeat/generated-name-hygiene.c"
diff -u "$BUILD/hygiene-default/generated-name-hygiene.c" \
  "$BUILD/hygiene-live/generated-name-hygiene.c"

collision="$ROOT/unittest/compiler-fixtures/func-native-collision.x"
"$X2C" translate --out-dir "$BUILD/collision-default" "$collision"
"$X2C" translate --live-symbols --out-dir "$BUILD/collision-live" \
  "$collision"
diff -u "$BUILD/collision-default/func-native-collision.c" \
  "$BUILD/collision-live/func-native-collision.c"
for output in "$BUILD/collision-default/func-native-collision.c" \
              "$BUILD/collision-live/func-native-collision.c"; do
  grep -E 'return (int_var|long_var)\(_is_list_literal\(' "$output" >/dev/null
  if grep -F 'x2c__is_list_literal' "$output" >/dev/null; then
    echo "private x2c spelling adapted imported native target: $output" >&2
    exit 1
  fi
done

"$X2C" translate -I "$ROOT/unittest/probes" --out-dir "$BUILD/overlay-default" \
  "$ROOT/unittest/probes/snapshot-overlay.x"
"$X2C" translate --live-symbols -I "$ROOT/unittest/probes" \
  --out-dir "$BUILD/overlay-live" "$ROOT/unittest/probes/snapshot-overlay.x"
diff -u "$BUILD/overlay-live/snapshot-overlay.c" \
  "$BUILD/overlay-default/snapshot-overlay.c"
diff -u "$BUILD/overlay-live/snapshot-overlay.h" \
  "$BUILD/overlay-default/snapshot-overlay.h"

set +e
"$X2C" translate --dump-ast "$ROOT/unittest/compiler-fixtures/invalid-scalar-type.x" \
  >"$BUILD/default.stdout" 2>"$BUILD/default.stderr"
default_status=$?
"$X2C" translate --live-symbols --dump-ast \
  "$ROOT/unittest/compiler-fixtures/invalid-scalar-type.x" \
  >"$BUILD/live.stdout" 2>"$BUILD/live.stderr"
live_status=$?
set -e
[[ $default_status == "$live_status" ]]
diff -u "$BUILD/live.stdout" "$BUILD/default.stdout"
diff -u "$BUILD/live.stderr" "$BUILD/default.stderr"

# A home without runtime sources cannot build its prelude. The root lacks a
# compile-time SDK, so it is not a home by discovery and X2C_HOME selects it.
fake_root="$BUILD/fake-root"
mkdir -p "$fake_root/etc" "$fake_root/lib" "$BUILD/missing" "$BUILD/cold"
cp "$X2C" "$fake_root/x2c"
ln -s "$ROOT/src" "$fake_root/src"
ln -s "$ROOT/include" "$fake_root/include"
set +e
X2C_HOME="$fake_root" \
"$fake_root/x2c" translate --out-dir "$BUILD/missing" "$ROOT/examples/foreach.x" \
  >"$BUILD/missing.stdout" 2>"$BUILD/missing.stderr"
missing_status=$?
set -e
[[ $missing_status -ne 0 ]]
grep -F "cannot read runtime source" "$BUILD/missing.stderr" >/dev/null

# A home with runtime sources but no interfaces walks the prelude cold and
# produces the same C as the stage build's replayed interfaces.
cold_root="$BUILD/cold-root"
mkdir -p "$cold_root/etc" "$cold_root/lib" "$cold_root/include" \
  "$cold_root/bin"
cp "$X2C" "$cold_root/bin/x2c"
cp "$ROOT/etc/"*.xlisp "$ROOT/etc/"*.xmacro "$cold_root/etc/"
copy_runtime_sources "$cold_root/lib/"
[[ -z "$("$cold_root/bin/x2c" env prelude)" ]]
"$cold_root/bin/x2c" translate --out-dir "$BUILD/cold" "$ROOT/examples/foreach.x"
diff -u "$BUILD/cold/foreach.c" "$BUILD/default/foreach.c"
diff -u "$BUILD/cold/foreach.h" "$BUILD/default/foreach.h"
# Interfaces its own compiler wrote make the same home replay the prelude
# and still produce the same C.
mkdir -p "$BUILD/cold-interfaces" "$BUILD/warm"
"$cold_root/bin/x2c" translate --out-dir "$BUILD/cold-interfaces" \
  "$cold_root"/lib/*.x >/dev/null 2>&1
cp "$BUILD/cold-interfaces/"*.xi "$cold_root/lib/"
[[ -n "$("$cold_root/bin/x2c" env prelude)" ]]
"$cold_root/bin/x2c" translate --out-dir "$BUILD/warm" "$ROOT/examples/foreach.x"
diff -u "$BUILD/warm/foreach.c" "$BUILD/default/foreach.c"
diff -u "$BUILD/warm/foreach.h" "$BUILD/default/foreach.h"

# Collection must translate every source the fixture suite does not already
# reach. `make build` covers src/ and lib/, and the compiler fixtures cover
# their own directory, so what is left is the top-level examples and the
# benchmark sources. Excluded examples are the manifest rows whose check is
# `none`, which need optional packages.
sweep="$BUILD/sweep"
mkdir -p "$sweep"
swept=0
for src in "$ROOT"/examples/*.x "$ROOT"/unittest/benchmarks/*.x; do
  name=$(basename "$src" .x)
  grep -q "^$name|.*|none|" "$ROOT/examples/manifest.txt" && continue
  "$X2C" translate --out-dir "$sweep" "$src" >/dev/null ||
    { echo "raw collection failed to translate ${src#"$ROOT/"}" >&2; exit 1; }
  swept=$((swept + 1))
done

echo "Symbol probes: prelude and live C/H, overlays, diagnostics, homes,"\
  "and $swept swept sources agree"
