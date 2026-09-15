#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/artifact-atomicity"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

rm -rf "$BUILD"
mkdir -p "$BUILD/first" "$BUILD/second" "$BUILD/blocked"

fail() {
  echo "artifact atomicity failure: $1" >&2
  exit 1
}

cat >"$BUILD/probe.x" <<'EOF'
typedef struct ProbeRow { int value; } ProbeRow;
int probe_value(ProbeRow row) { return row.value; }
EOF

# A translated unit publishes its interface beside its C, and two complete
# runs write the same bytes.
"$X2C" translate --out-dir "$BUILD/first" "$BUILD/probe.x"
"$X2C" translate --out-dir "$BUILD/second" "$BUILD/probe.x"
[[ -s "$BUILD/first/probe.xi" ]] || fail "unit interface was not written"
cmp -s "$BUILD/first/probe.xi" "$BUILD/second/probe.xi" ||
  fail "repeated translations wrote different interfaces"
grep -q '^(interface 1 ' "$BUILD/first/probe.xi" ||
  fail "interface lacks its version header"
grep -Fq '"ProbeRow"' "$BUILD/first/probe.xi" ||
  fail "interface omits the unit's declarations"
ls "$BUILD/first" | grep -q 'tmp' &&
  fail "a temporary interface file survived a successful write"

# A failed publication leaves no partial interface and preserves whatever
# already occupies the destination. A directory in the interface's place
# makes the final rename fail after the C and header were written.
mkdir -p "$BUILD/blocked/probe.xi"
status=0
"$X2C" translate --out-dir "$BUILD/blocked" "$BUILD/probe.x" \
  >"$BUILD/blocked.stdout" 2>"$BUILD/blocked.stderr" || status=$?
[[ $status -ne 0 ]] || fail "blocked interface write reported success"
grep -q "failed to write interface file" "$BUILD/blocked.stderr" ||
  fail "blocked interface write did not report its cause"
[[ -d "$BUILD/blocked/probe.xi" ]] ||
  fail "blocked interface write replaced the occupied path"
[[ -s "$BUILD/blocked/probe.c" ]] ||
  fail "generated C was not written before the interface"
ls "$BUILD/blocked" | grep -q 'tmp' &&
  fail "a temporary interface file survived a failed write"

echo "artifact atomicity: interfaces are complete, repeatable, and never partial"
