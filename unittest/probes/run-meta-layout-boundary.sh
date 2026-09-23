#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
x2c=${X2C:-"$root/builds/0/x2c"}
build="$root/unittest/build/meta-layout-boundary"
rm -rf "$build"
mkdir -p "$build"

for shape in conditional conditional_include conditional_push once_replay \
             split aligned balanced_includes conditional_natural \
             once_natural natural; do
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
    conditional_include)
      cat >"$dir/pop.h" <<'HEADER'
#pragma pack(pop)
HEADER
      cat >"$dir/layout.h" <<'HEADER'
#pragma pack(push, 1)
#if 0
#include "pop.h"
#endif
struct Pair { char lead; long value; };
#pragma pack(pop)
HEADER
      ;;
    conditional_push)
      cat >"$dir/push.h" <<'HEADER'
#pragma pack(push, 1)
HEADER
      cat >"$dir/empty.h" <<'HEADER'
/* A source segment follows this include. */
HEADER
      cat >"$dir/layout.h" <<'HEADER'
#if 0
#include "push.h"
#endif
#pragma pack(1)
#pragma pack(pop)
#include "empty.h"
struct Pair { char lead; long value; };
#pragma pack()
HEADER
      ;;
    once_replay)
      cat >"$dir/pop.h" <<'HEADER'
#pragma once
#pragma pack(pop)
HEADER
      cat >"$dir/layout.h" <<'HEADER'
#pragma pack(push, 1)
#include "pop.h"
#pragma pack(push, 1)
#include "pop.h"
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
    balanced_includes)
      cat >"$dir/open.h" <<'HEADER'
#pragma pack(push, 1)
HEADER
      cat >"$dir/close.h" <<'HEADER'
#pragma pack(pop)
HEADER
      cat >"$dir/layout.h" <<'HEADER'
#include "open.h"
#include "close.h"
struct Pair { char lead; long value; };
HEADER
      ;;
    aligned)
      cat >"$dir/layout.h" <<'HEADER'
typedef long Aligned __attribute__((aligned(16)));
struct Pair { char lead; Aligned value; char end; };
HEADER
      ;;
    conditional_natural)
      cat >"$dir/neutral.h" <<'HEADER'
#pragma pack(push, 1)
#pragma pack(pop)
HEADER
      cat >"$dir/layout.h" <<'HEADER'
#if 0
#include "neutral.h"
#endif
struct Pair { char lead; long value; };
HEADER
      ;;
    once_natural)
      cat >"$dir/neutral.h" <<'HEADER'
#pragma once
#pragma pack(push, 1)
#pragma pack(pop)
HEADER
      cat >"$dir/layout.h" <<'HEADER'
#include "neutral.h"
#include "neutral.h"
struct Pair { char lead; long value; };
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
    if [[ "$shape" == natural || "$shape" == balanced_includes ||
          "$shape" == conditional_natural ||
          "$shape" == once_natural ]]; then
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
    if [[ "$shape" == conditional_include || "$shape" == conditional_push ||
          "$shape" == once_replay ||
          "$shape" == balanced_includes ||
          "$shape" == conditional_natural || "$shape" == once_natural ]]; then
      mkdir -p "$dir/$mode-cold" "$dir/$mode-warm"
      "$x2c" translate -q "${flags[@]}" -I "$dir" \
        --native-module "$dir/$mode.so" --out-dir "$dir/$mode-cold" \
        "$dir/bridge.x" >"$dir/$mode-cold.log" 2>&1 && cold=0 || cold=$?
      "$x2c" translate -q "${flags[@]}" -I "$dir" \
        --out-dir "$dir/$mode-warm" "$dir/helper.x" \
        >"$dir/$mode-interface.log" 2>&1
      "$x2c" translate -q "${flags[@]}" -I "$dir" \
        --native-module "$dir/$mode.so" --out-dir "$dir/$mode-warm" \
        "$dir/bridge.x" >"$dir/$mode-warm.log" 2>&1 && warm=0 || warm=$?
      if [[ "$shape" == *_natural || "$shape" == balanced_includes ]]; then
        [[ $cold == 0 && $warm == 0 ]]
      else
        [[ $cold != 0 && $warm != 0 ]]
        grep -q 'a compile-time struct with no host layout' \
          "$dir/$mode-cold.log"
        grep -q 'a compile-time struct with no host layout' \
          "$dir/$mode-warm.log"
      fi
    fi
    printf '%s %s passed\n' "$shape" "$mode"
  done
done
