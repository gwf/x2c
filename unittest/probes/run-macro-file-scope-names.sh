#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
source_dir="$root/unittest/probes/fixtures/macro-file-scope"
work=$(mktemp -d "${TMPDIR:-/tmp}/x2c-macro-file-scope.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

"$root/builds/0/x2c" build -q --output "$work/probe" \
  "$source_dir/main.x" "$source_dir/a/util.x" "$source_dir/b/util.x"
[ "$("$work/probe")" = '1 2' ]
