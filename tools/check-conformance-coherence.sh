#!/usr/bin/env bash
# Compare owned protocol conformance rows between snapshot and live
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

filter='^\((unit|conformance owned)'
{
  "$x2c" translate --dump-conformance "${lib_units[@]}"
  "$x2c" translate --dump-conformance "${src_units[@]}"
} | grep -E "$filter" > "$snap" || true
{
  "$x2c" translate --live-symbols --dump-conformance "${lib_units[@]}"
  "$x2c" translate --live-symbols --dump-conformance "${src_units[@]}"
} | grep -E "$filter" > "$live" || true

if ! diff -u "$snap" "$live" > /dev/null; then
  echo "conformance coherence failure:" \
       "owned conformance rows differ by symbol mode." >&2
  echo "--- snapshot symbols / +++ live symbols" >&2
  diff -u "$snap" "$live" | tail -n +3 >&2 || true
  echo "Generated adapters would depend on the build mode." \
       "Investigate before publishing artifacts" \
       "(a stale snapshot usually means: make sym-refresh)." >&2
  exit 1
fi
units=$(grep -c '^(unit ' "$snap" || true)
echo "conformance: owned rows agree between snapshot and live symbol modes" \
     "($units units)"
