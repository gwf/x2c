#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/artifact-atomicity"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

rm -rf "$BUILD"
mkdir -p "$BUILD/first" "$BUILD/second" "$BUILD/blocked" "$BUILD/partial"

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
grep -q '^(interface 2 ' "$BUILD/first/probe.xi" ||
  fail "interface lacks its version header"
grep -Fq '"ProbeRow"' "$BUILD/first/probe.xi" ||
  fail "interface omits the unit's declarations"
ls "$BUILD/first" | grep -q 'tmp' &&
  fail "a temporary interface file survived a successful write"

# A failed write replaces no output. The subshell execs the compiler under
# its own process id, so a dangling link at the C file's process-specific
# sibling fails that write after the header's sibling was written.
printf 'old header\n' >"$BUILD/partial/probe.h"
printf 'old source\n' >"$BUILD/partial/probe.c"
status=0
(
  ln -s "$BUILD/missing/probe.c" "$BUILD/partial/probe.c.tmp.$BASHPID"
  exec "$X2C" translate --out-dir "$BUILD/partial" "$BUILD/probe.x"
) >"$BUILD/partial.stdout" 2>"$BUILD/partial.stderr" || status=$?
[[ $status -ne 0 ]] || fail "failed output write reported success"
grep -q "failed to write generated file" "$BUILD/partial.stderr" ||
  fail "failed output write did not report its cause"
[[ "$(cat "$BUILD/partial/probe.h")" == "old header" ]] ||
  fail "a failed C write replaced the header"
[[ "$(cat "$BUILD/partial/probe.c")" == "old source" ]] ||
  fail "a failed C write replaced the C file"
[[ ! -e "$BUILD/partial/probe.xi" ]] ||
  fail "a failed C write published the interface"
ls "$BUILD/partial" | grep -q 'tmp' &&
  fail "a temporary output file survived a failed write"

# A failed rename leaves the earlier outputs complete and preserves whatever
# already occupies its destination. A directory in the interface's place
# makes the last rename fail after the header and C were replaced.
mkdir -p "$BUILD/blocked/probe.xi"
status=0
"$X2C" translate --out-dir "$BUILD/blocked" "$BUILD/probe.x" \
  >"$BUILD/blocked.stdout" 2>"$BUILD/blocked.stderr" || status=$?
[[ $status -ne 0 ]] || fail "blocked interface write reported success"
grep -q "failed to write generated file" "$BUILD/blocked.stderr" ||
  fail "blocked interface write did not report its cause"
[[ -d "$BUILD/blocked/probe.xi" ]] ||
  fail "blocked interface write replaced the occupied path"
cmp -s "$BUILD/first/probe.c" "$BUILD/blocked/probe.c" ||
  fail "generated C was not written before the interface"
ls "$BUILD/blocked" | grep -q 'tmp' &&
  fail "a temporary output file survived a failed rename"

echo "artifact atomicity: outputs are complete, repeatable, and never partial"
