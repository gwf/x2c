#!/bin/sh
# Check the rendered PNGs' signature and dimensions.
#
#   ./verify-renders.sh <png> <expected first 24 bytes in hex> ...
#
# The Makefile calls this rather than comparing in a recipe: a long
# continued recipe line is where Apple's make 3.81 on x86_64 loses bytes.
set -eu

while [ $# -gt 0 ]; do
  png=$1
  expected=$2
  shift 2
  actual=$(od -An -tx1 -N24 "$png" | tr -d '[:space:]')
  if [ "$actual" != "$expected" ]; then
    echo "raylib renders: $png starts $actual, not $expected" >&2
    exit 1
  fi
done
