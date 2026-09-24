#!/bin/sh
# Runs x2c-lint over its fixtures and compares the findings and exit
# statuses with tests/expected.txt.
set -eu

cd "$(dirname "$0")/../../.."
tool=$PWD/builds/0/libexec/x2c-lint
tests=commands/lint/tests
work=${TMPDIR:-/tmp}/x2c-lint-tests.$$
out=$work/findings
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work"
# Repository files stay ASCII, so the non-ASCII case is written here.
printf '// caf\303\251\n' >"$work/ascii.x"

run() {
  status=0
  "$tool" "$@" 2>/dev/null || status=$?
  echo "exit $status"
}

{
  echo "# language rules"
  run "$tests/src/style.x" "$tests/src/indent.x" "$tests/lib/runtime.x"
  echo "# all rules"
  run --all "$tests/src/style.x" "$tests/src/clean.x" "$tests/src/indent.x" \
    "$tests/lib/runtime.x"
  echo "# selected rules"
  run --rule tab --rule negated-is "$tests/src/style.x"
  echo "# a unit that does not parse"
  run --all "$tests/broken.x"
  echo "# non-ASCII text"
  (cd "$work" && run --rule non-ascii ascii.x)
  echo "# comment rules"
  run --all "$tests/src/comments.x"
  echo "# reference parameters"
  run --rule reference-parameter "$tests/src/references.x"
  echo "# idiom fixes proven by the generated C"
  cp "$tests/src/idioms.x" "$work/idioms.x"
  (cd "$work" && run --all --fix idioms.x)
} >"$out"
diff -u "$tests/expected.txt" "$out"
diff -u "$tests/fixed/idioms.x" "$work/idioms.x"

# The driver must run the same executable with unchanged arguments.
builds/0/x2c lint --all "$tests/src/style.x" >"$work/dispatched"
"$tool" --all "$tests/src/style.x" >"$work/direct"
cmp "$work/direct" "$work/dispatched"

builds/0/x2c help lint >"$work/help" 2>&1
grep -q '^usage: x2c-lint ' "$work/help"
