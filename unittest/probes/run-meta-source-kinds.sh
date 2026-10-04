#!/usr/bin/env bash
set -euo pipefail

# Project meta discovery follows the same indentation source kinds as parsing.
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
BUILD=${META_SOURCE_BUILD:-"$ROOT/unittest/build/meta-source-kinds"}
X2C=${X2C:-"$ROOT/builds/0/x2c"}
export X2C_CACHE_DIR="$BUILD/cache"
mkdir -p "$BUILD/out"
cd "$BUILD"

cat >plain.xmacro <<'EOF'
meta static int twice(int n) => n * 2;
EOF
cat >indent.xpmacro <<'EOF'
meta static int twice(int n):
  if (n < 0):
    return -n
  return n * 2
EOF
printf 'export $(import "plain.xmacro")\n' >bridge.x
printf 'export $(import "indent.xpmacro")\n' >bridge.xp

for kind in plain indent included-plain included-indent; do
  case "$kind" in
    plain) directive='$(import "plain.xmacro")' ;;
    indent) directive='$(import "indent.xpmacro")' ;;
    included-plain) directive='#include "bridge.x"' ;;
    included-indent) directive='#include "bridge.xp"' ;;
  esac
  printf '%s\nint answer(void) => $twice(21);\n' "$directive" >"$kind.x"
  "$X2C" translate -q --out-dir out "$kind.x" >"$kind.log" 2>&1
  grep -Fq 'return 42;' "out/$kind.c"
done

cat >direct.xp <<'EOF'
meta static int twice(int n):
  int value = n * 2
  return value
int answer(void) => $twice(21)
EOF
"$X2C" translate -q --out-dir out direct.xp >direct.log 2>&1
grep -Fq 'return 42;' out/direct.c
echo 'meta source-kind probes passed'
