#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
tmp=${TMPDIR:-/tmp}/x2c-repl-program.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export TMPDIR="$tmp" X2C="$PWD/builds/0/x2c"

builds/0/x2c build --plain --build-dir "$tmp/cc" --output "$tmp/program-api" \
  --x-include-dir commands/repl --x-include-dir commands/repl/tests \
  --x-include-dir src --c-include-dir builds/0/src \
  commands/repl/tests/program-api.x commands/repl/repl-program.x \
  commands/repl/repl-types.x commands/repl/tests/library/program-check.c \
  builds/0/commands/identity.x builds/0/libx2c-dev.a
"$tmp/program-api" "$PWD/commands/repl/tests/library/playground.c"

cc -fPIC -c commands/repl/tests/library/playground.c -o "$tmp/playground.o"
ar rcs "$tmp/libplayground.a" "$tmp/playground.o"
"$tmp/program-api" "$PWD/commands/repl/tests/library/playground.h" \
  "$tmp/libplayground.a"

cp commands/repl/tests/library/playground.c "$tmp/manifest.c"
cp commands/repl/tests/library/playground.h "$tmp/playground.h"
cat >>"$tmp/manifest.c" <<'EOF'
int dependency_value(void);
int manifest_value(void) { return dependency_value() + SELECTED_VALUE; }
EOF
cat >"$tmp/dependency.c" <<'EOF'
int dependency_value(void) { return DEPENDENCY_VALUE; }
EOF
cat >"$tmp/x2c.toml" <<'EOF'
[project]
name = "repl-program-probe"
default-target = "app"
[target.dependency]
kind = "static-library"
sources = ["dependency.c"]
c-flags = ["-DDEPENDENCY_VALUE=7"]
[target.app]
sources = ["manifest.c"]
dependencies = ["dependency"]
c-flags = ["-DSELECTED_VALUE=10", "-DDEPENDENCY_VALUE=99"]
EOF
"$tmp/program-api" --manifest-path "$tmp/x2c.toml" --target app

cat >"$tmp/main-args.c" <<'EOF'
int main(int argc, char **argv) { return argc * 10 + (argv[1][0] == 'a' ? 3 : 0); }
EOF
cat >"$tmp/main-void.x" <<'EOF'
int main(void) { return 11; }
EOF
"$tmp/program-api" "$tmp/main-args.c"
"$tmp/program-api" "$tmp/main-void.x"

REPL_PROGRAM_REPLACE="$tmp/main-void.x" "$tmp/program-api" "$tmp/main-args.c"
if "$tmp/program-api" "$tmp/main-args.c" "$tmp/main-void.x" \
  >"$tmp/main-conflict.log" 2>&1; then
  echo "conflicting startup main roots unexpectedly succeeded" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) shared="$tmp/libplayground.dylib"; cc -dynamiclib -fPIC \
    commands/repl/tests/library/playground.c -o "$shared" ;;
  *) shared="$tmp/libplayground.so"; cc -shared -fPIC \
    commands/repl/tests/library/playground.c -o "$shared" ;;
esac
REPL_PROGRAM_REMOVE_NATIVE="$shared" "$tmp/program-api" \
  "$PWD/commands/repl/tests/library/playground.h" -L"$tmp" -lplayground

cat >"$tmp/sqlite-wrapper.h" <<'EOF'
#include <sqlite3.h>
EOF
"$tmp/program-api" "$tmp/sqlite-wrapper.h" -lsqlite3

cat >"$tmp/wrapper.h" <<'EOF'
#include "playground.h"
EOF
"$tmp/program-api" "$tmp/wrapper.h" "$tmp/libplayground.a"

mkdir -p "$tmp/packages"
cp -R unittest/probes/packages/tally "$tmp/packages/"
make -s -C "$tmp/packages/tally" build ROOT="$PWD" X2C="$X2C" \
  >"$tmp/package-build.log" 2>&1
cat >"$tmp/import-main.x" <<'EOF'
import "tally";
int main(void) { return $tally.sum4() + 1; }
EOF
"$tmp/program-api" --package-dir "$tmp/packages" "$tmp/import-main.x"

cc -fPIC -fvisibility=hidden -c commands/repl/tests/library/playground.c \
  -o "$tmp/playground-hidden.o"
ar rcs "$tmp/libplayground-hidden.a" "$tmp/playground-hidden.o"
"$tmp/program-api" "$tmp/wrapper.h" "$tmp/libplayground-hidden.a"

printf 'int unavailable_example(int value);\n' >"$tmp/missing.h"
REPL_PROGRAM_MISSING=unavailable_example "$tmp/program-api" "$tmp/missing.h"
printf 'int duplicate(void) { return 1; }\n' >"$tmp/duplicate-a.c"
printf 'int duplicate(void) { return 2; }\n' >"$tmp/duplicate-b.c"
if "$tmp/program-api" "$tmp/duplicate-a.c" "$tmp/duplicate-b.c" \
  >"$tmp/duplicate.log" 2>&1; then
  echo "duplicate native source definitions unexpectedly succeeded" >&2
  exit 1
fi
