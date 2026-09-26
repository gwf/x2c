#!/usr/bin/env bash
set -euo pipefail

# The project meta helper's cache: a change to any input of its build (a
# meta .xmacro, a member of its import chain, a header meta code includes
# by relative, absolute, or angle spelling, -D or -U, the compiler, the
# host C compiler, or the meta C compiler flags) builds the helper again,
# and a change to program code alone does not. The target --cc is never
# used for meta code.

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
BUILD="$ROOT/unittest/build/meta-cache-key"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
export X2C_CACHE_DIR="$BUILD/cache"
unset X2C_META_CC META_CC

rm -rf "$BUILD"
mkdir -p "$BUILD/inc" "$BUILD/abs" "$BUILD/bin"
cd "$BUILD"

fail() {
  echo "meta cache key probe failure: $1" >&2
  exit 1
}

cat > bin/fail-cc <<'EOF'
#!/bin/sh
echo "target compiler used for meta code" >&2
exit 1
EOF
cat > bin/host-cc <<EOF
#!/bin/sh
# $RANDOM
exec cc "\$@"
EOF
chmod +x bin/fail-cc bin/host-cc

echo '#define REL_K 1' > cfg.h
echo '#define ABS_K 10' > abs/abs.h
echo '#define NAT_K 100' > inc/nat.h
cat > chain.xmacro <<EOF
meta static int chained(void) => REL_K + ABS_K + NAT_K;
EOF
cat > top.xmacro <<'EOF'
$(import "chain.xmacro")
meta static int total(void) {
#ifdef EXTRA
  return chained() + 1000;
#else
  return chained();
#endif
}
EOF
# Meta code sees the headers of the unit that imports it.
cat > prog.x <<EOF
#include "cfg.h"
#include "$BUILD/abs/abs.h"
#include <nat.h>
\$(import "top.xmacro")
int value(void) { return \$total(); }
EOF

# Compiles prog.x with the arguments given and records the identity of
# every helper in the cache: its directory and inode.
helper_id=
translate() {
  "$X2C" build -c --build-dir bd -I . -I inc "$@" prog.x >out.log 2>&1 ||
    fail "build failed: $(cat out.log)"
  helper_id=$(ls -i "$X2C_CACHE_DIR"/meta/project-*/helper | tr '\n' ' ')
}

expect() {
  local c
  c=$(find bd -name prog.c | head -1)
  grep -q "return $1;" "$c" || fail "$2: expected $1, got $(grep return "$c")"
}

rebuilt() {
  local before=$helper_id
  translate "${@:2}"
  [ "$helper_id" != "$before" ] || fail "$1 did not rebuild the helper"
}

kept() {
  local before=$helper_id
  translate "${@:2}"
  [ "$helper_id" = "$before" ] || fail "$1 rebuilt the helper: $before -> $helper_id"
}

translate
expect 111 "first build"
kept "an unchanged translation"

echo 'int other(void) { return 7; }' >> prog.x
kept "a new program function"
sed -i.bak 's/return 7;/return 8;/' prog.x
kept "a program function body change"
expect 111 "program change"

sed -i.bak 's/return chained();/return chained() + 5000;/' top.xmacro
rebuilt "a meta .xmacro change"
expect 5111 "meta .xmacro"

sed -i.bak 's/NAT_K;/NAT_K + 20000;/' chain.xmacro
rebuilt "an imported .xmacro change"
expect 25111 "imported .xmacro"

echo '#define REL_K 2' > cfg.h
rebuilt "a relative header change"
expect 25112 "relative header"

echo '#define ABS_K 20' > abs/abs.h
rebuilt "an absolute header change"
expect 25122 "absolute header"

echo '#define NAT_K 200' > inc/nat.h
rebuilt "a native header change"
expect 25222 "native header"

rebuilt "a -D option" -DEXTRA
expect 21222 "-D"
rebuilt "a -U option" -DEXTRA -UEXTRA
expect 25222 "-U"

rebuilt "the meta C compiler" --meta-cc "$BUILD/bin/host-cc"
expect 25222 "--meta-cc"
printf '#!/bin/sh\n# changed\nexec cc "$@"\n' > bin/host-cc
rebuilt "a host C compiler change" --meta-cc "$BUILD/bin/host-cc"

rebuilt "a meta C compiler flag" -O0

# A different compiler binary is a different helper.
cp "$X2C" bin/x2c
printf 'x' >> bin/x2c
X2C="$BUILD/bin/x2c" rebuilt "a compiler change"

# The target compiler is never used for meta code.
rm -rf "$X2C_CACHE_DIR" bd
X2C_CC="$BUILD/bin/fail-cc" CC="$BUILD/bin/fail-cc" \
  "$X2C" translate -I . -I inc prog.x >out.log 2>&1 ||
  fail "translation with a failing target compiler: $(cat out.log)"
grep -q "return 25222;" prog.c || fail "meta built with the target compiler"
status=0
"$X2C" build -c --build-dir bd --cc "$BUILD/bin/fail-cc" -I . -I inc \
  prog.x >out.log 2>&1 || status=$?
[ "$status" -ne 0 ] || fail "build with a failing --cc succeeded"
grep -q "return 25222;" "$(find bd -name prog.c | head -1)" ||
  fail "meta built with --cc: $(cat out.log)"

echo "meta cache key probes passed"
