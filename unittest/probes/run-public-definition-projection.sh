#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/public-definition-projection"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
CC=${CC:-cc}

rm -rf "$BUILD"
mkdir -p "$BUILD/source" "$BUILD/cold" "$BUILD/warm"

cat >"$BUILD/source/imported.x" <<'EOF'
/** Returns its argument from another unit. */
int imported_api(int value) { return value; }
EOF
cat >"$BUILD/source/without.x" <<'EOF'
#include "imported.x"

macro Unit $make_api() => {
  /** Returns the next integer from the generated function. */
  int $(x2c.ident "generated_api")(int value) => value + 1;
}

$make_api();

int prototype_only(int value);
#if 0
/** Must not appear in the selected surface. */
int inactive_api(int value) { return value; }
#endif
/** Must remain private. */
static int private_api(int value) { return value; }
/** Returns twice its argument. */
int direct_api(int value) { return value * 2; }
EOF
awk '$0 == "$make_api();" { print "int generated_api(int value);" }
     { print }' "$BUILD/source/without.x" >"$BUILD/source/with.x"

for mode in cold warm; do
  flags=()
  if [[ "$mode" == cold ]]; then flags=(--no-interfaces); fi
  for name in imported without with; do
    "$X2C" translate "${flags[@]+"${flags[@]}"}" \
      --out-dir "$BUILD/$mode" "$BUILD/source/$name.x" >/dev/null
  done
  "$CC" -iquote "$ROOT/include/x2c" \
    -I"$BUILD/$mode" -c "$BUILD/$mode/without.c" \
    -o "$BUILD/$mode/without.o"
  "$CC" -iquote "$ROOT/include/x2c" \
    -I"$BUILD/$mode" -c "$BUILD/$mode/with.c" \
    -o "$BUILD/$mode/with.o"
done

for name in imported without with; do
  cmp "$BUILD/cold/$name.xi" "$BUILD/warm/$name.xi"
done

python3 - "$ROOT" "$BUILD" <<'PY'
import importlib.util
import pathlib
import sys

root, build = map(pathlib.Path, sys.argv[1:])
sys.path.insert(0, str(root / "tools"))
from x2c_symbols import HeaderSymbols, read_sexp, definitions_with_symbols
import x2c_source

interfaces = [read_sexp((build / "warm" / f"{name}.xi").read_text())
              for name in ("imported", "without", "with")]
symbols = HeaderSymbols(interfaces)

def no_text_expansion(*args, **kwargs):
    raise AssertionError("documentation used Python macro substitution")

x2c_source._unit_macro_definitions = no_text_expansion
for name in ("with", "without"):
    source = build / "source" / f"{name}.x"
    key = source.relative_to(root).as_posix()
    selected = symbols.selected_definitions(key)
    assert [row[0] for row in selected] == ["generated_api", "direct_api"]
    assert selected[0][5].strip() == \
        "Returns the next integer from the generated function."
    definitions = definitions_with_symbols(source, symbols, root=root)
    assert [definition.name for definition in definitions] == \
        ["generated_api", "direct_api"]
    assert definitions[0].doc == \
        "Returns the next integer from the generated function."
    assert "int" in definitions[0].signature

spec = importlib.util.spec_from_file_location(
    "gen_api_reference", root / "tools" / "gen-api-reference.py")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
for name in ("with", "without"):
    source = build / "source" / f"{name}.x"
    audit = module._collect_public_surface(
        source, source.relative_to(root).as_posix(), symbols,
        compiler=True, check_hash=True, root=root)
    assert [item.name for item in audit.callables] == \
        ["generated_api", "direct_api"]
PY

echo "public definition projection: zero-hole, visibility, docs, cold/warm passed"
