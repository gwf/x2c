#!/usr/bin/env bash
set -euo pipefail

# The project meta helper: a body that crashes, exits, overflows the stack,
# or passes the deadline is reported at its call, the next call runs in a
# new helper, and no helper outlives the translation that started it, with
# one translation worker or eight. No process that compile-time code starts
# outlives the helper either.

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
  if (getenv("META_HELPER_SPIN")) for (;;) x++;
  return x;
}

meta static int twice(int x) => x * 2;
EOF

cat > crash.x <<'EOF'
#include <stdlib.h>
$(import "calls.xmacro")

int a = $boom(1);
int b = $twice(1);
int c = $bye(3);
int d = $twice(2);
int e = $deep(0);
int f = $twice(3);
EOF

status=0
"$X2C" translate --out-dir out crash.x >crash.out 2>&1 || status=$?
[ "$status" -ne 0 ] || fail "crashing calls translated"
grep -q "crash.x:4:9: macro: this meta call stopped" crash.out ||
  fail "crash not reported"
grep -q "reason: the body exited with status 3" crash.out ||
  fail "exit not reported"
grep -q "crash.x:8:9: macro: this meta call stopped" crash.out ||
  fail "stack overflow not reported"
for line in 5 7 9; do
  if grep -q "crash.x:$line:" crash.out; then
    fail "call after a helper ended failed on line $line"
  fi
done
[ -z "$(helpers)" ] || fail "helper left running after a failed translation"

# A deadline also covers starting the helper, and a new helper's first
# start can take seconds on a loaded host. So the unit is translated first
# with the default limit, where spin returns at once, and then with a short
# limit, where it loops and the helper has already run.
cat > slow.x <<'EOF'
#include <stdlib.h>
$(import "calls.xmacro")

int g = $spin(0);
int h = $twice(4);
EOF
"$X2C" translate --out-dir out slow.x >slow.out 2>&1 ||
  fail "helper build for the timeout probe failed: $(cat slow.out)"
META_HELPER_SPIN=1 X2C_META_TIMEOUT=2 "$X2C" translate --out-dir out slow.x \
  >slow.out 2>&1 || true
grep -q "slow.x:4:9: macro: this meta call ran longer than 2 s" slow.out ||
  fail "timeout not reported"
if grep -q "slow.x:5:" slow.out; then
  fail "call after a timeout failed"
fi
[ -z "$(helpers)" ] || fail "helper left running after a timeout"

# A job that a call starts ends with the call, and one that a unit's
# `meta static` initializer starts ends by the next unit's reset. Whatever
# compile-time code leaves running ends with the helper, whether it quits,
# crashes, passes the deadline, or loses the translation that started it.
# Each job records its pid in jobs.pids.
export META_HELPER_JOBS="$BUILD/jobs.pids" META_HELPER_UNIT="$BUILD/unit.pid"
mkdir -p units
for unit in a b; do
  cat > "units/$unit.x" <<'EOF'
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include "process.x"

meta static long started(void) {
  Job job = List.job(%(sleep 30));
  job.start();
  FILE *out = fopen(getenv("META_HELPER_JOBS"), "a");
  fprintf(out, "%ld\n", job.pids[0]);
  fclose(out);
  return job.pids[0];
}

meta static long unit_job = started();

/* Whether the job that the last unit's initializer started has ended;
   this unit's takes its place. */
meta static int last_ended(void) {
  long last = 0;
  FILE *in = fopen(getenv("META_HELPER_UNIT"), "r");
  if (in) {
    if (fscanf(in, "%ld", &last) != 1) last = 0;
    fclose(in);
  }
  FILE *out = fopen(getenv("META_HELPER_UNIT"), "w");
  fprintf(out, "%ld\n", unit_job);
  fclose(out);
  return last > 0 && kill((pid_t) last, 0) == -1 && errno == ESRCH;
}

meta static int run(int x) {
  started();
  if (getenv("META_HELPER_CRASH")) {
    volatile int *p = (volatile int *) (long) (x - 1);
    *p = x;
  }
  if (getenv("META_HELPER_SPIN")) for (;;) x++;
  return x;
}

int ended = $last_ended();
int ran = $run(1);
EOF
done

# Whether every job in jobs.pids has ended, allowing three seconds for a
# killed one to be reaped. Jobs still running are killed.
jobs_ended() {
  local pid alive
  [ -s jobs.pids ] || return 1
  for _ in $(seq 30); do
    alive=
    while read -r pid; do
      if kill -0 "$pid" 2>/dev/null; then alive=$pid; fi
    done <jobs.pids
    [ -z "$alive" ] && return 0
    sleep 0.1
  done
  xargs kill -KILL <jobs.pids 2>/dev/null || true
  return 1
}

: >jobs.pids
rm -f unit.pid
"$X2C" translate -j 1 --out-dir out units/a.x units/b.x >units.out 2>&1 ||
  fail "job units did not translate: $(cat units.out)"
grep -q "int ended = 1;" out/b.c ||
  fail "an initializer's job outlived the next unit's reset"
jobs_ended || fail "a job outlived its translation"

: >jobs.pids
META_HELPER_CRASH=1 X2C_META_TIMEOUT=20 "$X2C" translate --out-dir out \
  units/a.x >units.out 2>&1 || true
grep -q "units/a.x:.*: macro: this meta call stopped" units.out ||
  fail "crash with a job running not reported: $(cat units.out)"
jobs_ended || fail "a job outlived a crashed helper"

: >jobs.pids
META_HELPER_SPIN=1 X2C_META_TIMEOUT=2 "$X2C" translate --out-dir out \
  units/a.x >units.out 2>&1 || true
grep -q "units/a.x:.*: macro: this meta call ran longer than 2 s" \
  units.out || fail "timeout with a job running not reported"
jobs_ended || fail "a job outlived a helper past its deadline"

# The helper leads its own process group, which a signal to the
# translation's group does not reach, so it ends itself and its jobs when
# the translation that started it is killed.
: >jobs.pids
META_HELPER_SPIN=1 X2C_META_TIMEOUT=0 "$X2C" translate --out-dir out \
  units/a.x >units.out 2>&1 &
translation=$!
for _ in $(seq 100); do
  (($(wc -l <jobs.pids) >= 3)) && break
  sleep 0.1
done
kill -KILL "$translation"
wait "$translation" 2>/dev/null || true
jobs_ended || fail "a job outlived a killed translation"
for _ in $(seq 30); do
  [ -z "$(helpers)" ] && break
  sleep 0.1
done
[ -z "$(helpers)" ] || fail "helper left running after a killed translation"

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
