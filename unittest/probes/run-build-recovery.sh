#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/build-recovery"
AR=${AR:-ar}

rm -rf "$BUILD"
mkdir -p "$BUILD"

fail() {
  echo "build recovery failure: $1" >&2
  exit 1
}

# Fault-inject against a scratch copy of builds/0, not the real one: a
# mid-probe failure or a concurrent build must not corrupt the tracked
# archive that other targets depend on. stage.mk resolves the compiler
# and sources relative to the stage directory (../../bin/x2c,
# ../../etc, ../../src, ../../lib), so the scratch tree mirrors that
# shape and points back at the real, read-only source and compiler.
SCRATCH="$BUILD/scratch"
mkdir -p "$SCRATCH/builds"
ln -s "$ROOT/bin" "$SCRATCH/bin"
ln -s "$ROOT/etc" "$SCRATCH/etc"
ln -s "$ROOT/src" "$SCRATCH/src"
ln -s "$ROOT/lib" "$SCRATCH/lib"
cp -Rp "$ROOT/builds/0" "$SCRATCH/builds/0"

OBJECT="$SCRATCH/builds/0/lib/string.o"
SOURCE="$SCRATCH/builds/0/lib/string.c"
ARCHIVE="$SCRATCH/builds/0/libx2c.a"

cat >"$BUILD/failing-cc.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=
previous=
for argument in "$@"; do
  if [[ "$previous" == -o ]]; then
    output=$argument
    break
  fi
  previous=$argument
done
[[ -n "$output" ]] || exit 2
printf 'partial compiler output\n' >"$output"
exit 1
EOF
chmod +x "$BUILD/failing-cc.sh"

touch "$SOURCE"
if make -s -f "$ROOT/builds/stage.mk" -C "$SCRATCH/builds/0" lib/string.o \
    CC="$BUILD/failing-cc.sh" >"$BUILD/failure.stdout" \
    2>"$BUILD/failure.stderr"; then
  fail "fault-injected compiler unexpectedly succeeded"
fi
[[ ! -e "$OBJECT" ]] ||
  fail ".DELETE_ON_ERROR preserved a partial object"

make -s -f "$ROOT/builds/stage.mk" -C "$SCRATCH/builds/0" lib/string.o \
  >"$BUILD/recovery.log" 2>&1
[[ -s "$OBJECT" ]] || fail "normal build did not recover the deleted object"
make -s -W lib/string.o -f "$ROOT/builds/stage.mk" -C "$SCRATCH/builds/0" \
  libx2c.a >>"$BUILD/recovery.log" 2>&1

cp "$OBJECT" "$BUILD/stale-member.o"
"$AR" r "$ARCHIVE" "$BUILD/stale-member.o"
"$AR" t "$ARCHIVE" | grep -qx 'stale-member.o' ||
  fail "probe did not inject a stale archive member"
make -s -W lib/string.o -f "$ROOT/builds/stage.mk" -C "$SCRATCH/builds/0" \
  libx2c.a >"$BUILD/archive.log" 2>&1
if "$AR" t "$ARCHIVE" | grep -qx 'stale-member.o'; then
  fail "archive rebuild retained a removed member"
fi

echo "build recovery: partial objects are removed and archives are replaced"
