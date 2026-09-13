#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/artifact-atomicity"

rm -rf "$BUILD"
mkdir -p "$BUILD/etc" "$BUILD/src" "$BUILD/lib" "$BUILD/builds/0"
cp "$ROOT/etc/header-symbols.xlisp" "$BUILD/etc/header-symbols.xlisp"
cp "$ROOT/etc/symbols.xlisp" "$BUILD/etc/symbols.xlisp"
cp "$ROOT/etc/symbol-source.x" "$BUILD/etc/symbol-source.x"
cp "$ROOT/etc/help.mk" "$ROOT/etc/branch.mk" "$ROOT/etc/build-config.mk" \
  "$ROOT/etc/make-command.mk" "$BUILD/etc/"

marker="$BUILD/fail-dump.ran"
cat >"$BUILD/dump-driver" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ \${DUMP_FAIL:-0} == 1 ]]; then
  printf 'partial output\n'
  touch "$marker"
  exit 23
fi
cat "\${DUMP_SOURCE:?missing DUMP_SOURCE}"
EOF
chmod +x "$BUILD/dump-driver"

cat >"$BUILD/Test.mk" <<EOF
include $ROOT/Makefile
configure:
	@:
bootstrap-ready:
	@:
build:
	@:
EOF
cp "$BUILD/Test.mk" "$BUILD/Makefile"

fail() {
  echo "artifact atomicity failure: $1" >&2
  exit 1
}

header="$BUILD/etc/header-symbols.xlisp"
symbols="$BUILD/etc/symbols.xlisp"
symbol_state="$BUILD/builds/.symbol-snapshot-state"
symbol_changed="$BUILD/builds/.symbol-snapshot-changed"
cp "$header" "$BUILD/header.before"
cp "$symbols" "$BUILD/symbols.before"
printf 'void probe(void);\n' >"$BUILD/lib/probe.x"

# A current artifact must not be rewritten.
inode_before=$(ls -di "$header" | awk '{print $1}')
DUMP_SOURCE="$BUILD/header.before" \
  make -s --no-print-directory -C "$BUILD" -f Test.mk hdr-sync \
    STAGE0_X2C="$BUILD/dump-driver" >"$BUILD/current.log" \
    2>"$BUILD/current.stderr"
inode_after=$(ls -di "$header" | awk '{print $1}')
[[ $inode_before == "$inode_after" ]] ||
  fail "current header artifact was replaced"
cmp "$BUILD/header.before" "$header" ||
  fail "current header artifact changed"
[[ ! -s "$BUILD/current.log" ]] ||
  fail "current header sync produced refresh output"

# A stale artifact must be replaced once and show the reviewed diff.
printf 'updated header symbols\n' >"$BUILD/header.updated"
DUMP_SOURCE="$BUILD/header.updated" \
  make -s --no-print-directory -C "$BUILD" -f Test.mk hdr-sync \
    STAGE0_X2C="$BUILD/dump-driver" >"$BUILD/stale.log" \
    2>"$BUILD/stale.stderr"
cmp "$BUILD/header.updated" "$header" ||
  fail "stale header artifact was not repaired"
grep -q '^Refreshing etc/header-symbols.xlisp$' "$BUILD/stale.log" ||
  fail "stale header sync did not announce the refresh"
grep -q '^[-+]updated header symbols$' "$BUILD/stale.log" ||
  fail "stale header sync did not print its diff"

# A failed generation after the repair must preserve the repaired artifact.
cp "$header" "$BUILD/header.repaired"
rm -f "$marker"
status=0
DUMP_FAIL=1 DUMP_SOURCE="$BUILD/header.updated" \
  make -s --no-print-directory -C "$BUILD" -f Test.mk hdr-sync \
    STAGE0_X2C="$BUILD/dump-driver" >/dev/null 2>&1 || status=$?
[[ $status -ne 0 ]] || fail "failed header dump reported success"
[[ -f $marker ]] || fail "injected header failure never ran"
cmp "$BUILD/header.repaired" "$header" ||
  fail "failed header dump replaced the tracked artifact"

# Ordinary builds cache a successful symbol comparison, replace stale output
# atomically, and preserve the last good artifact after a failed refresh.
DUMP_SOURCE="$BUILD/symbols.before" \
  python3 "$ROOT/tools/sync-symbol-snapshot.py" --root "$BUILD" \
    --compiler "$BUILD/dump-driver" --artifact "$symbols" \
    --state "$symbol_state" --changed "$symbol_changed"
[[ ! -e $symbol_changed ]] || fail "current symbol cache reported a change"

DUMP_FAIL=1 DUMP_SOURCE="$BUILD/symbols.before" \
  python3 "$ROOT/tools/sync-symbol-snapshot.py" --root "$BUILD" \
    --compiler "$BUILD/dump-driver" --artifact "$symbols" \
    --state "$symbol_state" --changed "$symbol_changed"

printf 'void changed_probe(void);\n' >"$BUILD/lib/probe.x"
printf '%s\n' '(snapshot 3 ((updated)))' >"$BUILD/symbols.updated"
DUMP_SOURCE="$BUILD/symbols.updated" \
  python3 "$ROOT/tools/sync-symbol-snapshot.py" --root "$BUILD" \
    --compiler "$BUILD/dump-driver" --artifact "$symbols" \
    --state "$symbol_state" --changed "$symbol_changed"
cmp "$BUILD/symbols.updated" "$symbols" ||
  fail "stale symbol cache was not repaired"
[[ -e $symbol_changed ]] || fail "stale symbol cache hid its update"

cp "$symbols" "$BUILD/symbols.repaired"
printf 'void failed_probe(void);\n' >"$BUILD/lib/probe.x"
status=0
DUMP_FAIL=1 DUMP_SOURCE="$BUILD/symbols.updated" \
  python3 "$ROOT/tools/sync-symbol-snapshot.py" --root "$BUILD" \
    --compiler "$BUILD/dump-driver" --artifact "$symbols" \
    --state "$symbol_state" --changed "$symbol_changed" \
    >/dev/null 2>&1 || status=$?
[[ $status -ne 0 ]] || fail "failed cached symbol refresh reported success"
cmp "$BUILD/symbols.repaired" "$symbols" ||
  fail "failed cached symbol refresh replaced the tracked artifact"

echo "artifact atomicity: current, stale, and failed header sync paths pass;" \
  "cached symbol refreshes are atomic and preserve the last good artifact"
