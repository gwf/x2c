#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
X2C="$ROOT/builds/0/x2c"
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/x2c-editor-test.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
export X2C_CACHE_DIR="$BUILD/cache"
cat > "$BUILD/calls.x" <<'SOURCE'
meta int twice(int x) => x * 2;
SOURCE
cat > "$BUILD/input.x" <<'SOURCE'
#include "calls.x"
int value(void) { return $twice(1); }
SOURCE
# Relocated from the meta-helper probe: editor requests own helper cleanup.
"$X2C" editor "$BUILD/editor.json" "$BUILD/input.x" hover 0 0 -- \
  translate "$BUILD/input.x"
grep -q '"diagnostics":\[\]' "$BUILD/editor.json"
if pgrep -f "$X2C_CACHE_DIR/meta/project-" >/dev/null; then
  echo "helper left running after an editor request" >&2
  exit 1
fi
