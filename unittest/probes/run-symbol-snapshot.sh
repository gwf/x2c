#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/symbol-snapshot"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

rm -rf "$BUILD"
mkdir -p "$BUILD/overlay-default" "$BUILD/hygiene-default" \
  "$BUILD/hygiene-repeat" "$BUILD/collision-default"

(cd "$ROOT" && make sym-check >/dev/null)
if grep -F '<"' "$ROOT/etc/symbols.xlisp" >/dev/null; then
  echo "symbol snapshot contains noncanonical quoted angle symbols" >&2
  exit 1
fi
grep -F '((enum "FileReadStatus") (enum))' \
  "$ROOT/etc/symbols.xlisp" >/dev/null
head -n 1 "$ROOT/etc/symbols.xlisp" | grep -Fx '(snapshot 3 (' >/dev/null

literal_source="$BUILD/snapshot-literal.x"
literal_output="$BUILD/snapshot-literal"
mkdir -p "$literal_output"
{
  printf '#include "x2c.x"\n\nList snapshot_literal(void) {\n  return %%'
  sed -n '1,$p' "$ROOT/etc/symbols.xlisp"
  printf ';\n}\n'
} >"$literal_source"
"$X2C" translate --out-dir "$literal_output" "$literal_source"

hygiene="$ROOT/unittest/compiler-fixtures/generated-name-hygiene.x"
"$X2C" translate --out-dir "$BUILD/hygiene-default" "$hygiene"
"$X2C" translate --out-dir "$BUILD/hygiene-repeat" "$hygiene"
diff -u "$BUILD/hygiene-default/generated-name-hygiene.c" \
  "$BUILD/hygiene-repeat/generated-name-hygiene.c"

collision="$ROOT/unittest/compiler-fixtures/func-native-collision.x"
"$X2C" translate --out-dir "$BUILD/collision-default" "$collision"
output="$BUILD/collision-default/func-native-collision.c"
grep -E 'return (int_var|long_var)\(_is_list_literal\(' "$output" >/dev/null
if grep -F 'x2c__is_list_literal' "$output" >/dev/null; then
  echo "private x2c spelling adapted imported native target: $output" >&2
  exit 1
fi

fake_root="$BUILD/fake-root"
mkdir -p "$fake_root/etc"
mkdir -p "$BUILD/missing" "$BUILD/version" "$BUILD/header" \
  "$BUILD/malformed" "$BUILD/trailing" "$BUILD/v1"
cp "$X2C" "$fake_root/x2c"
ln -s "$ROOT/src" "$fake_root/src"
ln -s "$ROOT/include" "$fake_root/include"
ln -s "$ROOT/lib" "$fake_root/lib"

set +e
"$fake_root/x2c" translate --out-dir "$BUILD/missing" "$ROOT/examples/foreach.x" \
  >"$BUILD/missing.stdout" 2>"$BUILD/missing.stderr"
missing_status=$?
set -e
[[ $missing_status -ne 0 ]]
grep -F "missing symbol snapshot:" "$BUILD/missing.stderr" >/dev/null

printf '%s\n' '(snapshot 2 ())' >"$fake_root/etc/symbols.xlisp"
set +e
"$fake_root/x2c" translate --out-dir "$BUILD/version" "$ROOT/examples/foreach.x" \
  >"$BUILD/version.stdout" 2>"$BUILD/version.stderr"
version_status=$?
set -e
[[ $version_status -ne 0 ]]
grep -F 'driver: malformed symbol snapshot:' \
  "$BUILD/version.stderr" >/dev/null

printf '%s\n' '(snapshot 3)' >"$fake_root/etc/symbols.xlisp"
set +e
"$fake_root/x2c" translate --out-dir "$BUILD/header" "$ROOT/examples/foreach.x" \
  >"$BUILD/header.stdout" 2>"$BUILD/header.stderr"
header_status=$?
set -e
[[ $header_status -ne 0 ]]
grep -F 'driver: malformed symbol snapshot:' \
  "$BUILD/header.stderr" >/dev/null

printf '%s\n' '(snapshot 3 ((bad)))' >"$fake_root/etc/symbols.xlisp"
set +e
"$fake_root/x2c" translate --out-dir "$BUILD/malformed" "$ROOT/examples/foreach.x" \
  >"$BUILD/malformed.stdout" 2>"$BUILD/malformed.stderr"
malformed_status=$?
set -e
[[ $malformed_status -ne 0 ]]
grep -F 'driver: malformed symbol snapshot:' \
  "$BUILD/malformed.stderr" >/dev/null

printf '%s\n' '(snapshot 3 ())' '(extra)' \
  >"$fake_root/etc/symbols.xlisp"
set +e
"$fake_root/x2c" translate --out-dir "$BUILD/trailing" "$ROOT/examples/foreach.x" \
  >"$BUILD/trailing.stdout" 2>"$BUILD/trailing.stderr"
trailing_status=$?
set -e
[[ $trailing_status -ne 0 ]]
grep -F 'driver: malformed symbol snapshot:' \
  "$BUILD/trailing.stderr" >/dev/null

printf '%s\n' '(def x2c.symbols.version 1)' \
  "(def x2c.symbols.entries '())" >"$fake_root/etc/symbols.xlisp"
set +e
"$fake_root/x2c" translate --out-dir "$BUILD/v1" "$ROOT/examples/foreach.x" \
  >"$BUILD/v1.stdout" 2>"$BUILD/v1.stderr"
v1_status=$?
set -e
[[ $v1_status -ne 0 ]]
grep -F 'driver: malformed symbol snapshot:' \
  "$BUILD/v1.stderr" >/dev/null

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

echo "Symbol snapshot probes: artifacts, C/H, overlays, diagnostics, failures,"\
  "and $swept swept sources agree"
