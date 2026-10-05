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
mkdir -p "$work/docs" "$work/lib"
# The internal-module fixture uses the current library documentation tier.
cp docs/library-manifest.txt "$work/docs/library-manifest.txt"
cp "$tests/src/doc-tier.x" "$work/lib/scan.x"
# Repository files stay ASCII, so the non-ASCII case is written here.
printf '// caf\303\251\n' >"$work/ascii.x"
# Formatting input that the fixtures would otherwise have to hold.
printf '/* spacing.x */\nint add(int a,int b) {\n  int total = a + b ;\n\n\n  if(total) return total;\n  for (;;) break;\n  return 0;\n}\n' >"$work/spacing.x"

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
  echo "# structure and validation rules"
  run --all "$tests/src/review.x"
  echo "# shared Error causes outside the repository"
  cp "$tests/src/review.x" "$work/review.x"
  (cd "$work" && run --rule return-after-raise review.x)
  echo "# missing rule fixtures"
  run --rule fresh-literal-null-guard --rule growth-check \
    --rule manual-shape-checks --rule validator-shape \
    --rule recursive-validator --rule validation-framework \
    --rule static-match-capture --rule enum-table-switch \
    --rule duplicate-function-body "$tests/src/signals.x" \
    "$tests/src/duplicate-a.x" "$tests/src/duplicate-b.x"
  echo "# internal module documentation"
  (cd "$work" && run --rule doc-comment-tier lib/scan.x)
  echo "# shape rules"
  run --all "$tests/src/shape.x"
  echo "# accepted and invalid suppressions"
  run --rule contains-in --rule plain-string --rule long-name \
    "$tests/src/suppression-accepted.x" "$tests/src/suppressions.x"
  echo "# allowance for a nonselected rule"
  run --rule long-name "$tests/src/suppression-accepted.x"
  echo "# suppression also prevents fixes"
  cp "$tests/src/suppression-accepted.x" "$work/suppression.x"
  (cd "$work" && run --rule contains-in --fix suppression.x)
  echo "# a script unit"
  run --all "$tests/src/script.x"
  echo "# a preloaded macro library"
  run --rule negated-is lib/error-macros.xmacro
  echo "# reference parameters"
  run --rule reference-parameter "$tests/src/references.x"
  echo "# spacing that formatting changes"
  (cd "$work" && run --fmt-check spacing.x)
  run --fmt-check "$tests/src/clean.x"
  echo "# idiom fixes proven by the generated C"
  cp "$tests/src/idioms.x" "$work/idioms.x"
  (cd "$work" && run --all --fix idioms.x)
} >"$out"
diff -u "$tests/expected.txt" "$out"
diff -u "$tests/fixed/idioms.x" "$work/idioms.x"
cmp "$tests/src/suppression-accepted.x" "$work/suppression.x"

# Expanded catalogues and direct diagnostics use the same existing rules.
"$tool" -I src --rule return-after-raise --rule return-after-report-error \
  --rule fallback-shared-cause --rule shape-diagnostics \
  --rule validator-diagnostics "$tests/src/validation-macros.x" \
  >"$work/validation-macros" 2>"$work/validation-macros.errors"
test ! -s "$work/validation-macros.errors"
diff -u "$tests/validation-macros.expected" "$work/validation-macros"

read_failure() {
  path=$1
  shift
  status=0
  "$tool" "$@" >"$work/read.out" 2>"$work/read.err" || status=$?
  test "$status" = 1
  grep -F -- "$path" "$work/read.err" >/dev/null
  ! grep -q 'error floor' "$work/read.err"
}

# Input failures stay ordinary in both modes; readable files still run.
cp "$tests/src/clean.x" "$work/denied.x"
chmod 000 "$work/denied.x"
for mode in normal format; do
  set --
  if test "$mode" = format; then set -- --fmt-check --fmt-diff; fi
  read_failure "$work/missing.x" "$@" "$work/missing.x"
  read_failure "$work/denied.x" "$@" "$work/denied.x"
  read_failure "$work" "$@" "$work"
  (cd "$work" && read_failure '-' "$@" -- -)
done
chmod 600 "$work/denied.x"
read_failure '-' -
for missing_first in yes no; do
  if test "$missing_first" = yes; then
    set -- "$work/missing.x" "$tests/src/review.x"
  else set -- "$tests/src/review.x" "$work/missing.x"; fi
  read_failure "$work/missing.x" --rule return-after-raise "$@"
  grep -q 'return-after-raise' "$work/read.out"
done
read_failure "$work/missing.x" --fmt-check \
  "$work/missing.x" "$work/spacing.x"
grep -q 'lines to format' "$work/read.out"
# An empty file and a file literally named '-' are readable inputs.
: >"$work/empty.x"
cp "$tests/src/clean.x" "$work/-"
"$tool" "$work/empty.x" >/dev/null
(cd "$work" && "$tool" -- - >/dev/null && "$tool" --fmt-check -- -)

# A support-file failure during meta preparation has the same boundary.
printf 'not a directory\n' >"$work/cache-file"
printf '%s\n' 'meta int input_value(int n) { return n + 1; }' \
  'int value(void) { return $input_value(1); }' >"$work/meta.x"
X2C_CACHE_DIR="$work/cache-file" read_failure "$work/cache-file" \
  "$work/meta.x"

# The driver must run the same executable with unchanged arguments.
builds/0/x2c lint --all "$tests/src/style.x" >"$work/dispatched"
"$tool" --all "$tests/src/style.x" >"$work/direct"
cmp "$work/direct" "$work/dispatched"

builds/0/x2c help lint >"$work/help" 2>&1
grep -q '^usage: x2c-lint ' "$work/help"
