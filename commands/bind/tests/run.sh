#!/bin/sh
# Binds tests/feed.h, compares the package files with tests/expected/,
# builds the package and a consumer, and checks regeneration, refusal, and
# driver dispatch. Binds the host's sqlite3.h too when one is present.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
X2C="$ROOT/builds/0/x2c"
TOOL="$ROOT/builds/0/libexec/x2c-bind"
TESTS="$ROOT/commands/bind/tests"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/x2c-bind-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/packages"
cp "$ROOT/packages/package.mk" "$WORK/packages/package.mk"
PACKAGE="$WORK/packages/feed"

bind_feed() {
  "$@" --package feed --header "$TESTS/feed.h" -I "$TESTS" -o "$PACKAGE"
}

# Shows a step's log only when it fails.
quietly() {
  log=$1
  shift
  if ! "$@" >"$log" 2>&1; then
    cat "$log"
    exit 1
  fi
}

bind_feed "$TOOL" >"$WORK/summary"
grep -Fxq "x2c bind: $PACKAGE: 2 handles, 9 methods, 2 releases, \
2 raw functions, 1 not forwarded" "$WORK/summary"
diff -u "$TESTS/expected/feed.x" "$PACKAGE/src/feed.x"
diff -u "$TESTS/expected/feed-raw.h" "$PACKAGE/src/feed-raw.h"
diff -u "$TESTS/expected/README.md" "$PACKAGE/README.md"
sed "s|$TESTS|TESTS|g" "$PACKAGE/Makefile" |
  diff -u "$TESTS/expected/Makefile" -

# The generated package builds with package.mk, and a consumer imports it.
quietly "$WORK/package.log" make -C "$PACKAGE" build X2C="$X2C"
quietly "$WORK/consumer.log" "$X2C" build --plain -q \
  --package-dir "$WORK/packages" --build-dir "$WORK/consumer-cc" \
  --output "$WORK/consumer" "$TESTS/consumer.x" "$TESTS/feed.c"
"$WORK/consumer" >"$WORK/consumer.out"
printf '3 items\nbeta, ok\n' | diff -u - "$WORK/consumer.out"

# A rerun replaces the region, keeps text after it, and keeps other files.
printf 'int feed_extra(void) => 1;\n' >>"$PACKAGE/src/feed.x"
printf 'edited\n' >"$PACKAGE/README.md"
bind_feed "$TOOL" >/dev/null
{ cat "$TESTS/expected/feed.x"; printf 'int feed_extra(void) => 1;\n'; } |
  diff -u - "$PACKAGE/src/feed.x"
printf 'edited\n' | diff -u - "$PACKAGE/README.md"

# An entry unit without the markers is refused and left unchanged.
printf 'int other(void) => 0;\n' >"$PACKAGE/src/feed.x"
status=0
bind_feed "$TOOL" >/dev/null 2>"$WORK/refused" || status=$?
[ "$status" = 1 ]
grep -q 'has no complete x2c bind region' "$WORK/refused"
printf 'int other(void) => 0;\n' | diff -u - "$PACKAGE/src/feed.x"

# Invalid options exit with status 2.
status=0
"$TOOL" --package Feed --header "$TESTS/feed.h" 2>/dev/null || status=$?
[ "$status" = 2 ]
status=0
"$TOOL" --package feed --header "$WORK/missing.h" 2>/dev/null || status=$?
[ "$status" = 2 ]

# The driver runs the same executable and its help.
rm -rf "$PACKAGE"
bind_feed "$X2C" bind >/dev/null
diff -u "$TESTS/expected/feed.x" "$PACKAGE/src/feed.x"
"$X2C" help bind >"$WORK/help" 2>&1
grep -q '^  x2c bind \[options\]' "$WORK/help"

# A real header: bind the host's sqlite3.h and run a consumer of it.
SQLITE_HEADER=
if command -v xcrun >/dev/null 2>&1; then
  sdk=$(xcrun --show-sdk-path 2>/dev/null || true)
  if [ -n "$sdk" ] && [ -f "$sdk/usr/include/sqlite3.h" ]; then
    SQLITE_HEADER="$sdk/usr/include/sqlite3.h"
  fi
fi
if [ -z "$SQLITE_HEADER" ] && [ -f /usr/include/sqlite3.h ]; then
  SQLITE_HEADER=/usr/include/sqlite3.h
fi
if [ -z "$SQLITE_HEADER" ]; then
  echo "bind command: no sqlite3.h on this host; skipped the SQLite check"
else
  "$TOOL" --package sqlite3 --header "$SQLITE_HEADER" -l sqlite3 \
    -o "$WORK/packages/sqlite3" >/dev/null
  quietly "$WORK/sqlite.log" \
    make -C "$WORK/packages/sqlite3" build X2C="$X2C"
  quietly "$WORK/sqlite-consumer.log" "$X2C" build --plain -q \
    --package-dir "$WORK/packages" --build-dir "$WORK/sqlite-cc" \
    --output "$WORK/sqlite-consumer" "$TESTS/sqlite-consumer.x"
  "$WORK/sqlite-consumer" >"$WORK/sqlite.out"
  printf 'answer 42\n' | diff -u - "$WORK/sqlite.out"
fi
echo "bind command smoke tests passed"
