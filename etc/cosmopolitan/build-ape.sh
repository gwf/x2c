#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)

: "${COSMOCC:?set COSMOCC to the pinned cosmocc executable}"
: "${COSMOAR:?set COSMOAR to the matching cosmoar executable}"

OUTPUT=${OUTPUT:-"$REPO_ROOT/dist/x2c.com"}
COSMO_LICENSE_DIR=${COSMO_LICENSE_DIR:-"$(dirname "$COSMOCC")/.."}

for tool in "$COSMOCC" "$COSMOAR"; do
  test -x "$tool" || {
    printf '%s\n' "x2c: missing executable: $tool" >&2
    exit 2
  }
done
command -v zip >/dev/null 2>&1 || {
  printf '%s\n' "x2c: the optional APE release build requires zip" >&2
  exit 2
}

"$REPO_ROOT/tools/check-generated-stages.sh" \
  "$REPO_ROOT/bootstrap" "$REPO_ROOT/builds/0"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/x2c-cosmopolitan.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/lib" "$WORK/src" "$WORK/payload/x2c/include"
mkdir -p "$WORK/payload/x2c/src" "$WORK/payload/x2c/lib"
mkdir -p "$WORK/payload/x2c/etc" "$WORK/payload/x2c/licenses"

set --
for source in "$REPO_ROOT"/bootstrap/lib/*.c; do
  object="$WORK/lib/$(basename "${source%.c}").o"
  "$COSMOCC" -Os \
    -iquote "$REPO_ROOT/bootstrap/lib" -c "$source" -o "$object"
  set -- "$@" "$object"
done
"$COSMOAR" rcs "$WORK/libx2c.a" "$@"

set --
for source in "$REPO_ROOT"/bootstrap/src/*.c; do
  object="$WORK/src/$(basename "${source%.c}").o"
  "$COSMOCC" -Os \
    -iquote "$REPO_ROOT/bootstrap/lib" \
    -iquote "$REPO_ROOT/bootstrap/src" -c "$source" -o "$object"
  set -- "$@" "$object"
done
"$COSMOCC" -Os -o "$WORK/x2c.com" "$@" "$WORK/libx2c.a" -lm

identity=$(python3 "$REPO_ROOT/etc/x2c-payload.py" support \
  "$WORK/payload/x2c" --licenses "$COSMO_LICENSE_DIR")

mkdir -p "$(dirname "$OUTPUT")"
cp "$WORK/x2c.com" "$OUTPUT"
(cd "$WORK/payload" && zip -q -r "$OUTPUT" x2c)
chmod +x "$OUTPUT"
printf 'x2c: wrote %s (%s)\n' "$OUTPUT" "$identity"
