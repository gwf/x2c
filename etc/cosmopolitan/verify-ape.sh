#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
APE=${1:-"$REPO_ROOT/dist/x2c.com"}

for tool in cc ar unzip cmp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'x2c: APE verification requires %s\n' "$tool" >&2
    exit 2
  fi
done
if [ ! -f "$APE" ]; then
  printf 'x2c: APE not found: %s\n' "$APE" >&2
  exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/x2c-ape-verify.XXXXXX")
cleanup() {
  if [ "${X2C_APE_VERIFY_KEEP:-0}" = 1 ]; then
    printf 'x2c: kept APE verification workspace at %s\n' "$WORK"
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT HUP INT TERM

SEED="$WORK/x2c.com"
NATIVE="$WORK/native"
NEXT="$WORK/next"
GEN_NATIVE="$WORK/gen-native"
GEN_NEXT="$WORK/gen-next"

cp "$APE" "$SEED"
chmod +x "$SEED"
"$SEED" --version
unzip -t "$SEED" >/dev/null
(
  unset X2C_CC CC X2C_AR AR
  "$SEED" bootstrap --prefix "$NATIVE"
)

cp -R "$NATIVE" "$NEXT"
"$NEXT/bin/x2c" build --kind static-library \
  --output "$NEXT/lib/libx2c.a" "$NEXT"/lib/*.x
"$NEXT/bin/x2c" build --output "$NEXT/bin/x2c-stage1" "$NEXT"/src/*.x
mv "$NEXT/bin/x2c-stage1" "$NEXT/bin/x2c"
"$NEXT/bin/x2c" --version

# Give both compilers the same installation root before comparing output.
cp "$NEXT/bin/x2c" "$NATIVE/bin/x2c-next"
mkdir "$GEN_NATIVE" "$GEN_NEXT"
"$NATIVE/bin/x2c" translate --out-dir "$GEN_NATIVE" \
  "$NATIVE"/lib/*.x "$NATIVE"/src/*.x
"$NATIVE/bin/x2c-next" translate --out-dir "$GEN_NEXT" \
  "$NATIVE"/lib/*.x "$NATIVE"/src/*.x

generated_count=0
for source in "$NATIVE"/lib/*.x "$NATIVE"/src/*.x; do
  name=${source##*/}
  stem=${name%.x}
  for suffix in c h; do
    cmp "$GEN_NATIVE/$stem.$suffix" "$GEN_NEXT/$stem.$suffix"
    generated_count=$((generated_count + 1))
  done
done

cat >"$WORK/smoke.x" <<'X2C'
int main(void) {
  String value = %"native-portable";
  puts(value);
  return 0;
}
X2C
"$NEXT/bin/x2c" build --output "$WORK/smoke" "$WORK/smoke.x"
test "$("$WORK/smoke")" = native-portable

compiler_count=$(find "$NATIVE/src" -type f -name '*.x' | wc -l | tr -d ' ')
runtime_count=$(find "$NATIVE/lib" -type f -name '*.x' | wc -l | tr -d ' ')
printf 'x2c: APE native rebuild verified (%s compiler, %s runtime, %s C/H)\n' \
  "$compiler_count" "$runtime_count" "$generated_count"
