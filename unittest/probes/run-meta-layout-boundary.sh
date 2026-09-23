#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
x2c=${X2C:-"$root/builds/0/x2c"}
build="$root/unittest/build/meta-layout-boundary"
rm -rf "$build"
mkdir -p "$build"

for shape in conditional split aligned natural; do
  dir="$build/$shape"
  mkdir -p "$dir"
  case "$shape" in
    conditional)
      cat >"$dir/layout.h" <<'HEADER'
#define ACTIVE 1
#define INACTIVE 0
#if ACTIVE
#pragma pack(push, 1)
#endif
#if INACTIVE
#pragma pack(pop)
#endif
struct Pair { char lead; long value; };
#pragma pack(pop)
HEADER
      ;;
    split)
      cat >"$dir/open.h" <<'HEADER'
#pragma pack(push, 1)
HEADER
      cat >"$dir/close.h" <<'HEADER'
#pragma pack(pop)
HEADER
      cat >"$dir/layout.h" <<'HEADER'
#include "open.h"
struct Pair { char lead; long value; };
#include "close.h"
HEADER
      ;;
    aligned)
      cat >"$dir/layout.h" <<'HEADER'
typedef long Aligned __attribute__((aligned(16)));
struct Pair { char lead; Aligned value; char end; };
HEADER
      ;;
    natural)
      cat >"$dir/layout.h" <<'HEADER'
struct Pair { char lead; long value; };
HEADER
      ;;
  esac

  cat >"$dir/helper.x" <<'SOURCE'
#include "x2c.x"
#include "layout.h"
meta int read_pair(struct Pair *);
#pragma private
int read_pair(struct Pair *pair) { return (int) pair->value; }
SOURCE
  cat >"$dir/bridge.x" <<'SOURCE'
#include "helper.x"
meta int check(int offset) {
  struct Pair pair = {.value=12345+offset};
  return read_pair(&pair);
}
int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $check(0), check(argc-1));
  return 0;
}
SOURCE

  for mode in raw cpp; do
    flags=()
    if [[ "$mode" == cpp ]]; then flags=(--cpp-symbols); fi
    "$x2c" build -q "${flags[@]}" --kind meta-module \
      --c-include-dir "$dir" --output "$dir/$mode.so" \
      "$dir/helper.x" >"$dir/$mode-module.log" 2>&1
    if [[ "$shape" == natural ]]; then
      "$x2c" build -q "${flags[@]}" --c-include-dir "$dir" \
        --native-module "$dir/$mode.so" --output "$dir/$mode" \
        "$dir/bridge.x" "$dir/helper.x" >"$dir/$mode-bridge.log" 2>&1
      [[ $("$dir/$mode") == '12345 12345' ]]
    else
      if "$x2c" build -q "${flags[@]}" --c-include-dir "$dir" \
        --native-module "$dir/$mode.so" --output "$dir/$mode" \
        "$dir/bridge.x" "$dir/helper.x" \
        >"$dir/$mode-bridge.log" 2>&1; then
        echo "unsafe meta layout accepted: $shape $mode" >&2
        exit 1
      fi
      if ! grep -q 'a compile-time struct with no host layout' \
        "$dir/$mode-bridge.log"; then
        echo "wrong meta layout failure: $shape $mode" >&2
        exit 1
      fi
    fi
    printf '%s %s passed\n' "$shape" "$mode"
  done
done
