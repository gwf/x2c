#!/bin/sh
set -eu

cd "$(dirname "$0")/../../.."
tool=builds/0/libexec/x2c-graph
fixtures=commands/graph/tests/fixtures
tmp=${TMPDIR:-/tmp}/x2c-certify-tests.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

certify_check() {
  expected=$1
  root=$2
  shift 2
  if $tool certify --root "$root" "$@" >"$tmp/certify-$root"; then
    actual=0
  else
    actual=$?
  fi
  if [ "$actual" -ne "$expected" ]; then
    echo "certify $root exited $actual, expected $expected" >&2
    cat "$tmp/certify-$root" >&2
    exit 1
  fi
  tr '\n' ' ' <"$tmp/certify-$root" | sed 's/  */ /g' \
    >"$tmp/certify-$root-line"
}

certify_check 0 certify_safe "$fixtures/certify.x"
grep -q '(status proved)' "$tmp/certify-certify_safe-line"
grep -q '(obstacles)' "$tmp/certify-certify_safe-line"
certify_check 0 certify_nested "$fixtures/certify.x"
grep -q '(status proved)' "$tmp/certify-certify_nested-line"
certify_check 1 certify_dangle "$fixtures/certify.x"
grep -q 'violation .*certify_dangle.*region' \
  "$tmp/certify-certify_dangle-line"
certify_check 0 certify_transfer "$fixtures/certify.x"
grep -q 'transferred storage must be released by its destination' \
  "$tmp/certify-certify_transfer-line"
certify_check 3 certify_unclosed "$fixtures/certify.x"
grep -q 'region opening and lexical closing do not match' \
  "$tmp/certify-certify_unclosed-line"
certify_check 3 certify_native_call "$fixtures/certify.x"
grep -q 'call has no project body or lifetime effect contract' \
  "$tmp/certify-certify_native_call-line"
certify_check 0 certify_native_call \
  --contracts "$fixtures/certify-native.effects" "$fixtures/certify.x"
grep -q '(assumptions (native "certify_native" (summary 0 ())))' \
  "$tmp/certify-certify_native_call-line"
certify_check 3 certify_pointer_arithmetic "$fixtures/certify.x"
grep -q 'pointer arithmetic is outside the lifetime model' \
  "$tmp/certify-certify_pointer_arithmetic-line"
certify_check 3 certify_pointer_cast "$fixtures/certify.x"
grep -q 'pointer cast is outside the lifetime model' \
  "$tmp/certify-certify_pointer_cast-line"
certify_check 3 certify_indirect "$fixtures/certify.x"
grep -q 'call has no project body or lifetime effect contract' \
  "$tmp/certify-certify_indirect-line"
certify_check 3 certify_missing "$fixtures/certify.x"
grep -q 'selected root is unresolved' \
  "$tmp/certify-certify_missing-line"
certify_check 3 certify_aggregate "$fixtures/certify.x"
grep -q 'aggregate return may hide a borrowed pointer' \
  "$tmp/certify-certify_aggregate-line"
certify_check 3 certify_top_root "$fixtures/certify-top.x"
grep -q 'file-scope execution is outside the region walk' \
  "$tmp/certify-certify_top_root-line"
certify_check 1 certify_from_a "$fixtures/certify-static-a.x" \
  "$fixtures/certify-static-b.x"
grep -q 'certify-static-a.x" "certify_static"' \
  "$tmp/certify-certify_from_a-line"
certify_check 0 certify_from_b "$fixtures/certify-static-a.x" \
  "$fixtures/certify-static-b.x"
cp "$tmp/certify-certify_from_b" "$tmp/certify-static-order"
certify_check 0 certify_from_b "$fixtures/certify-static-b.x" \
  "$fixtures/certify-static-a.x"
cmp "$tmp/certify-static-order" "$tmp/certify-certify_from_b"

cat >"$tmp/certify-invalid.effects" <<'EOF'
(native "Scope_malloc" (summary 0 ()))
EOF
if $tool certify --root certify_safe \
     --contracts "$tmp/certify-invalid.effects" "$fixtures/certify.x" \
     >"$tmp/certify-invalid.out" 2>"$tmp/certify-invalid.err"; then
  echo "built-in lifetime effect was overridden" >&2
  exit 1
fi
test ! -s "$tmp/certify-invalid.out"
grep -q 'invalid or duplicate native contract' "$tmp/certify-invalid.err"
cat >"$tmp/certify-invalid.effects" <<'EOF'
(native "certify_native" (summary 0 ()))
(native "certify_native" (summary 0 ()))
EOF
if $tool certify --root certify_native_call \
     --contracts "$tmp/certify-invalid.effects" "$fixtures/certify.x" \
     >"$tmp/certify-invalid.out" 2>"$tmp/certify-invalid.err"; then
  echo "duplicate native lifetime contract was accepted" >&2
  exit 1
fi
grep -q 'invalid or duplicate native contract' "$tmp/certify-invalid.err"
cat >"$tmp/certify-invalid.effects" <<'EOF'
(native "certify_safe" (summary 0 ()))
EOF
if $tool certify --root certify_safe \
     --contracts "$tmp/certify-invalid.effects" "$fixtures/certify.x" \
     >"$tmp/certify-invalid.out" 2>"$tmp/certify-invalid.err"; then
  echo "source function was overridden by a native contract" >&2
  exit 1
fi
grep -q 'contract shadows source function' "$tmp/certify-invalid.err"
