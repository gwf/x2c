#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SOURCE="$ROOT/unittest/probes/expression-bodied-functions"
BUILD="$ROOT/unittest/build/expression-bodied-functions"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
CC=${CC:-cc}

rm -rf "$BUILD"
mkdir -p "$BUILD/source"

fail() {
  echo "expression-bodied function probe failure: $1" >&2
  exit 1
}

compare_ast() {
  "$X2C" script "$SOURCE/compare-ast" "$1" "$2" ||
    fail "canonical AST parity failed"
}

for mode in snapshot cpp live; do
  flags=()
  case "$mode" in
    cpp) flags=(--cpp-symbols) ;;
    live) flags=(--live-symbols) ;;
  esac
  mode_build="$BUILD/$mode"
  mkdir -p "$mode_build/braced" "$mode_build/arrow"

  for form in braced arrow; do
    source="$BUILD/source/parity.x"
    out="$mode_build/$form"
    cp "$SOURCE/$form/parity.x" "$source"
    "$X2C" translate "${flags[@]+"${flags[@]}"}" --dump-ast "$source" \
      >"$out/parity.ast"
    "$X2C" translate "${flags[@]+"${flags[@]}"}" \
      --out-dir "$out" "$source"
    "$CC" -iquote "$ROOT/include/x2c" "$out/parity.c" \
      -L"$ROOT/builds/0" -lx2c -lm -o "$out/parity"
    "$out/parity" >"$out/parity.stdout"
  done

  compare_ast "$mode_build/braced/parity.ast" \
    "$mode_build/arrow/parity.ast"
  cmp -s "$mode_build/braced/parity.c" "$mode_build/arrow/parity.c" ||
    fail "$mode generated C differs"
  cmp -s "$mode_build/braced/parity.h" "$mode_build/arrow/parity.h" ||
    fail "$mode generated H differs"
  cmp -s "$mode_build/braced/parity.stdout" \
    "$mode_build/arrow/parity.stdout" ||
    fail "$mode runtime output differs"
  grep -qx '130 value=8' "$mode_build/arrow/parity.stdout" ||
    fail "$mode runtime result is wrong"
done

echo "expression-bodied functions: AST, C/H, and runtime parity passed"
