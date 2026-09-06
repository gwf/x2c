#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 LEFT_STAGE RIGHT_STAGE" >&2
  exit 2
fi

left=$1
right=$2
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

if [[ ! -d "$left/lib" || ! -d "$left/src" ]]; then
  echo "generated-stage comparison: missing lib/src under $left" >&2
  exit 1
fi
if [[ ! -d "$right/lib" || ! -d "$right/src" ]]; then
  echo "generated-stage comparison: missing lib/src under $right" >&2
  exit 1
fi

list_generated() {
  local root=$1
  find "$root/lib" "$root/src" -type f \
    \( -name '*.c' -o -name '*.h' \) -print |
    sed "s#^$root/##" |
    LC_ALL=C sort
}

list_generated "$left" >"$scratch/left.files"
list_generated "$right" >"$scratch/right.files"
if ! diff -u "$scratch/left.files" "$scratch/right.files"; then
  echo "generated-stage comparison: file sets differ" >&2
  exit 1
fi

count=0
while IFS= read -r relative; do
  if ! cmp -s "$left/$relative" "$right/$relative"; then
    echo "generated-stage comparison: bytes differ: $relative" >&2
    exit 1
  fi
  count=$((count + 1))
done <"$scratch/left.files"

echo "generated-stage comparison: $left == $right ($count C/H files)"
