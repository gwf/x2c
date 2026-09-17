#!/usr/bin/env bash
# Compare owned protocol conformance rows between prelude and live
# symbol modes. A row is owned when its adoption row's
# file matches the unit being dumped; adapter emission is keyed
# separately, to the unit defining the forward converter. If the two
# modes disagree, the collected conformance table depends on which
# symbol transport built the tree. Each mode runs the same batched
# invocations the stage build uses, so cross-unit collection state
# matches a real translation.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
x2c=${X2C:-"$root/builds/0/x2c"}
cd "$root"

if [[ ! -x "$x2c" ]]; then
  echo "check-conformance-coherence: missing compiler: $x2c" >&2
  exit 2
fi

lib_units=(lib/*.x)
src_units=(src/*.x)

snap=$(mktemp)
live=$(mktemp)
trap 'rm -f "$snap" "$live"' EXIT

# Capture whole dumps first, so a compiler failure stops the check.
dump() {
  "$x2c" translate "$@" --dump-conformance "${lib_units[@]}"
  "$x2c" translate "$@" --dump-conformance "${src_units[@]}"
}
dump >"$snap"
dump --live-symbols >"$live"

units=$(grep -c '^(unit ' "$snap" || true)
if [[ $units -eq 0 ]]; then
  echo "conformance coherence failure: $x2c dumped no units" >&2
  exit 1
fi

filter='^\((unit|conformance owned)'
if ! difference=$(diff -u <(grep -E "$filter" "$snap") \
                         <(grep -E "$filter" "$live")); then
  echo "conformance coherence failure:" \
       "owned conformance rows differ by symbol mode." >&2
  echo "--- prelude symbols / +++ live symbols" >&2
  printf '%s\n' "$difference" | tail -n +3 >&2
  echo "Generated adapters would depend on the build mode." \
       "Investigate before publishing artifacts" \
       "(a stale stage usually means: make build)." >&2
  exit 1
fi
echo "conformance: owned rows agree between prelude and live symbol modes" \
     "($units units)"
