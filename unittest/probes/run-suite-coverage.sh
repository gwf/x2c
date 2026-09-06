#!/usr/bin/env bash
set -euo pipefail

# Discovery (unittest/*.x via wildcard) and execution (the hand-maintained
# $test.suite call list in test-all.x main) can silently drift: a new
# test-foo.x compiles and links but is never called. Fail loudly if the
# counts do not match.

probe_dir=$(cd "$(dirname "$0")" && pwd)
unittest_dir=$(cd "$probe_dir/.." && pwd)

# Exceptions: files matching unittest/test-*.x that are not themselves a
# suite (the driver and shared test-harness support code).
declare -A exceptions=(
  [test-all.x]=1
  [test-support.x]=1
)

file_count=0
for source in "$unittest_dir"/test-*.x; do
  [[ -e "$source" ]] || continue
  name=$(basename "$source")
  if [[ -n ${exceptions[$name]+set} ]]; then
    continue
  fi
  file_count=$((file_count + 1))
done

suite_call_count=$(grep -c '\$test\.suite(' "$unittest_dir/test-all.x")

if [[ "$file_count" -ne "$suite_call_count" ]]; then
  echo "suite coverage mismatch: $file_count discoverable test-*.x files" \
    "(excluding test-all.x, test-support.x) but $suite_call_count" \
    "\$test.suite calls in test-all.x main" >&2
  echo "a test-*.x file was added or removed without updating" \
    "test-all.x, or an exception needs to be added to" \
    "$probe_dir/run-suite-coverage.sh" >&2
  exit 1
fi

echo "suite coverage: $file_count test files match $suite_call_count" \
  "suite calls in test-all.x"
