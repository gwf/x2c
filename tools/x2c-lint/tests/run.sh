#!/bin/sh
# Runs x2c-lint over its fixtures and compares the findings and exit
# statuses with tests/expected.txt.
set -eu

cd "$(dirname "$0")/../../.."
tool=$PWD/builds/0/lint/x2c-lint
tests=tools/x2c-lint/tests
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
} >"$out"
diff -u "$tests/expected.txt" "$out"
