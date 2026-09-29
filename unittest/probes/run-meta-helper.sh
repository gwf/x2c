#!/usr/bin/env bash
set -euo pipefail

# The project meta helper: a body that crashes, exits, overflows the stack,
# or passes the deadline is reported at its call, the next call runs in a
# new helper, and no helper outlives the translation that started it, with
# one translation worker or eight.

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
BUILD="$ROOT/unittest/build/meta-helper"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
export X2C_CACHE_DIR="$BUILD/cache"

rm -rf "$BUILD"
mkdir -p "$BUILD/out" "$BUILD/jobs"
cd "$BUILD"

fail() {
  echo "meta helper probe failure: $1" >&2
  exit 1
}

helpers() {
  pgrep -f "$X2C_CACHE_DIR/meta/project-" || true
}

cat > calls.xmacro <<'EOF'
meta static int boom(int x) {
  volatile int *p = (volatile int *) (long) (x - 1);
  *p = x;
  return x;
}

meta static int bye(int x) {
  exit(x);
  return x;
}

meta static int deep(int x) {
  volatile char buf[4096];
  buf[0] = (char) x;
  return deep(x + 1) + buf[0];
}

meta static int spin(int x) {
  for (;;) x++;
  return x;
}

meta static int twice(int x) => x * 2;
EOF

# The first call starts the helper, so the crashing call's deadline covers
# only the call itself.
cat > crash.x <<'EOF'
#include <stdlib.h>
$(import "calls.xmacro")
int w = $twice(0);
int a = $boom(1);
int b = $twice(1);
int c = $bye(3);
int d = $twice(2);
int e = $deep(0);
int f = $twice(3);
int g = $spin(0);
int h = $twice(4);
EOF

status=0
X2C_META_TIMEOUT=2 "$X2C" translate --out-dir out crash.x \
  >crash.out 2>&1 || status=$?
[ "$status" -ne 0 ] || fail "crashing calls translated"
grep -q "crash.x:4:9: macro: this meta call stopped" crash.out ||
  fail "crash not reported"
grep -q "reason: the body exited with status 3" crash.out ||
  fail "exit not reported"
grep -q "crash.x:8:9: macro: this meta call stopped" crash.out ||
  fail "stack overflow not reported"
grep -q "crash.x:10:9: macro: this meta call ran longer than 2 s" crash.out ||
  fail "timeout not reported"
for line in 3 5 7 9 11; do
  if grep -q "crash.x:$line:" crash.out; then
    fail "call after a helper ended failed on line $line"
  fi
done
[ -z "$(helpers)" ] || fail "helper left running after a failed translation"

for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf '#include <stdio.h>\n$(import "../calls.xmacro")\n' >"jobs/u$i.x"
  printf 'int v%d(void) { return $twice(%d); }\n' "$i" "$i" >>"jobs/u$i.x"
done
"$X2C" translate -j 8 --out-dir out jobs/u*.x >jobs.out 2>&1 ||
  fail "parallel translation failed: $(cat jobs.out)"
grep -q "return 24;" out/u12.c || fail "parallel result missing"
[ -z "$(helpers)" ] || fail "helper left running after -j 8"

# An input whose own group does not compile falls back to the group of its
# imports alone.
cat > clash.x <<'EOF'
#include <stdio.h>
$(import "calls.xmacro")
static int List_len(int a) { return a; }
int v = $twice(3) + List_len(0);
EOF
"$X2C" translate --out-dir out clash.x >clash.out 2>&1 ||
  fail "an input's failing group did not fall back: $(cat clash.out)"
grep -q "v = 6 + List_len(0)" out/clash.c || fail "fallback result missing"

# An editor request mounts the helper as a translation does.
"$X2C" editor "$BUILD/editor.json" "$BUILD/jobs/u1.x" hover 0 0 -- \
  translate "$BUILD/jobs/u1.x" >editor.out 2>&1 ||
  fail "editor request failed: $(cat editor.out)"
grep -q '"diagnostics":\[\]' editor.json ||
  fail "editor request reported: $(cat editor.json)"
[ -z "$(helpers)" ] || fail "helper left running after an editor request"

# A helper that cannot start is reported at the call. The first
# translation builds the helper, so the second, limited to one process,
# forks only to start it. The limit does not apply to root.
if [ "$(id -u)" != 0 ]; then
  cat > nofork.x <<'EOF'
#include <stdlib.h>
$(import "calls.xmacro")
int b = $twice(1);
EOF
  "$X2C" translate --out-dir out nofork.x >nofork.out 2>&1 ||
    fail "helper build for the fork probe failed: $(cat nofork.out)"
  (ulimit -u 1; exec "$X2C" translate --out-dir out nofork.x) \
    >nofork.out 2>&1 || true
  grep -q "reason: the compile-time helper did not start" nofork.out ||
    fail "helper that did not start not reported: $(cat nofork.out)"
fi

echo "meta helper probes passed"
