#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)

: "${COSMOCC:?set COSMOCC to the pinned cosmocc executable}"
: "${COSMOAR:?set COSMOAR to the matching cosmoar executable}"

OUTPUT=${OUTPUT:-"$REPO_ROOT/dist/x2c.com"}
COSMO_LICENSE_DIR=${COSMO_LICENSE_DIR:-"$(dirname "$COSMOCC")/.."}
HOST_CC=${HOST_CC:-cc}

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

for source in "$REPO_ROOT"/src/*.x "$REPO_ROOT"/src/*.xmacro; do
  cp "$source" "$WORK/payload/x2c/src/$(basename "$source")"
done
for source in "$REPO_ROOT"/lib/*.x "$REPO_ROOT"/lib/*.xmacro \
              "$REPO_ROOT"/lib/*.xlisp; do
  cp "$source" "$WORK/payload/x2c/lib/$(basename "$source")"
  cp "$source" "$WORK/payload/x2c/include/$(basename "$source")"
done
for header in "$REPO_ROOT"/builds/0/lib/*.h; do
  cp "$header" "$WORK/payload/x2c/include/$(basename "$header")"
done
for artifact in "$REPO_ROOT"/etc/*.xlisp "$REPO_ROOT"/etc/*.xmacro; do
  cp "$artifact" "$WORK/payload/x2c/etc/$(basename "$artifact")"
done
for license in "$COSMO_LICENSE_DIR"/LICENSE.*; do
  test -f "$license" || continue
  name=cosmopolitan-$(basename "$license")
  cp "$license" "$WORK/payload/x2c/licenses/$name"
done

"$HOST_CC" -O2 "$SCRIPT_DIR/fnv64.c" -o "$WORK/fnv64"
MANIFEST_BODY="$WORK/manifest.body"
: >"$MANIFEST_BODY"
find "$WORK/payload/x2c" -type f | LC_ALL=C sort |
while IFS= read -r file; do
  relative=${file#"$WORK/payload/x2c/"}
  hash=$("$WORK/fnv64" "$file")
  size=$(wc -c <"$file" | tr -d ' ')
  printf '%s %s %s\n' "$hash" "$size" "$relative"
done >"$MANIFEST_BODY"
identity="fnv64-$("$WORK/fnv64" "$MANIFEST_BODY")"
{
  printf 'x2c-bootstrap-v1 %s\n' "$identity"
  sed -n 'p' "$MANIFEST_BODY"
} >"$WORK/payload/x2c/.x2c-bootstrap-manifest"

mkdir -p "$(dirname "$OUTPUT")"
cp "$WORK/x2c.com" "$OUTPUT"
(cd "$WORK/payload" && zip -q -r "$OUTPUT" x2c)
chmod +x "$OUTPUT"
printf 'x2c: wrote %s (%s)\n' "$OUTPUT" "$identity"
