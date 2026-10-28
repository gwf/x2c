#!/bin/sh
# Exercise discovery, build failures, options, and parallel output.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
X2C="$ROOT/builds/0/x2c"
TOOL="$ROOT/builds/0/libexec/x2c-test"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/x2c-test-command.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/project/tests/deep" "$WORK/project/.x2c-build/tests" \
  "$WORK/project/include" "$WORK/project/packages" "$WORK/project/src" \
  "$WORK/empty"
cat >"$WORK/project/x2c.toml" <<'MANIFEST'
[target.app]
sources = ["src/main.x"]
include-dirs = ["include"]
package-dirs = ["packages"]
MANIFEST
printf 'int main(void) => 0;\n' >"$WORK/project/src/main.x"
printf 'int test_value(void) => 42;\n' >"$WORK/project/include/value.x"
cat >"$WORK/project/a_test.x" <<'PASS'
#include "test.x"
#include "value.x"
$test()
static void passing(void) { $expect_eq(test_value(), 42); }
$test.main();
PASS
cat >"$WORK/project/tests/deep/b.x" <<'FAIL'
#include "test.x"
$test()
static void failing(void) { $expect_eq(1, 2); }
$test.main();
FAIL
# Generated build sources and ordinary non-test files are not discovered.
printf 'this is not source\n' >"$WORK/project/.x2c-build/tests/ignored_test.x"
printf 'this is not source\n' >"$WORK/project/ordinary.x"
run() {
  status=0
  (cd "$WORK/project" && "$TOOL" "$@") >"$WORK/out" 2>&1 || status=$?
}
run -j 2
[ "$status" = 1 ]
grep -Fxq 'files: 1 passed, 1 failed; tests: 1 passed, 1 failed' "$WORK/out"
[ "$(sed -n '1p' "$WORK/out")" = 'ok passing' ]
# The command recognizes both filename patterns and deduplicates operands.
cp "$WORK/project/a_test.x" "$WORK/project/test_copy.x"
run a_test.x test_copy.x a_test.x --quiet
[ "$status" = 0 ]
grep -Fxq 'files: 2 passed, 0 failed; tests: 2 passed, 0 failed' "$WORK/out"
! grep -q '^ok ' "$WORK/out"
mkdir -p "$WORK/project/tests/same"
cp "$WORK/project/a_test.x" "$WORK/project/tests/same/a_test.x"
run -j 2 a_test.x tests/same/a_test.x
[ "$status" = 0 ]
grep -Fxq 'files: 2 passed, 0 failed; tests: 2 passed, 0 failed' "$WORK/out"
[ "$(find "$WORK/project/.x2c-build/tests/scripts" -maxdepth 1 -type d -name 'a_test-*' | wc -l | tr -d ' ')" = 2 ]
run a_test.x --filter absent --filter pass --list
[ "$status" = 0 ]
grep -Fxq passing "$WORK/out"
! grep -q '^ok ' "$WORK/out"
run a_test.x --filter absent
[ "$status" = 1 ]
# Build errors count as failed files and do not stop other files.
printf 'this is not source\n' >"$WORK/project/broken_test.x"
run -j 2 a_test.x broken_test.x
[ "$status" = 1 ]
grep -Fxq 'files: 1 passed, 1 failed; tests: 1 passed, 0 failed' "$WORK/out"
# Native build failures retain their diagnostics after the failed Job is read.
printf '#error "native-build-diagnostic %s"\n' \
  'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
  >"$WORK/project/include/failing.h"
cat >"$WORK/project/native_test.x" <<NATIVE
#include "$WORK/project/include/failing.h"
int main(void) => 0;
NATIVE
run native_test.x
[ "$status" = 1 ]
grep -Fq 'native-build-diagnostic' "$WORK/out"
grep -Fxq 'files: 0 passed, 1 failed; tests: 0 passed, 0 failed' "$WORK/out"
run "$WORK/empty"
[ "$status" = 2 ]
for jobs in 0 -1 nope ''; do
  run -j "$jobs"
  [ "$status" = 2 ]
done
(cd "$WORK/empty" && "$TOOL" --manifest "$WORK/project/x2c.toml" \
  --target app "$WORK/project/a_test.x") >"$WORK/explicit-manifest"
grep -Fxq 'files: 1 passed, 0 failed; tests: 1 passed, 0 failed' \
  "$WORK/explicit-manifest"
# Tests also belong to library projects; selecting settings does not run a target.
cat >"$WORK/project/x2c.toml" <<'LIBRARY'
[target.app]
kind = "static-library"
sources = ["src/main.x"]
include-dirs = ["include"]
LIBRARY
run a_test.x
[ "$status" = 0 ]
grep -Fxq 'files: 1 passed, 0 failed; tests: 1 passed, 0 failed' "$WORK/out"
"$TOOL" --help >"$WORK/help"
grep -q 'x2c test' "$WORK/help"
# The normal dispatcher routes to the same command and help.
"$X2C" test --help >"$WORK/dispatched-help"
cmp "$WORK/help" "$WORK/dispatched-help"
echo 'test command smoke tests passed'
