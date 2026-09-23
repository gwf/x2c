#!/usr/bin/env bash
set -euo pipefail

# Native modules: a project function built with `--kind meta-module` runs in
# compile-time code when a translation, build, manifest target, or REPL
# loads it. A module from another compiler and a prototype whose signature
# differs are rejected, and nothing is loaded without an explicit request.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/native-modules"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$BUILD/out"
cd "$BUILD"

fail() {
  echo "native module probe failure: $1" >&2
  exit 1
}

expect_error() {
  local message=$1
  shift
  if "$@" >error.out 2>&1; then fail "accepted: $*"; fi
  grep -Fq "$message" error.out || {
    cat error.out >&2
    fail "expected '$message'"
  }
}

cat >src/helpers.x <<'EOF'
meta int triple(int);

#pragma private

int triple(int x) { return 3 * x; }
EOF
cat >src/main.x <<'EOF'
#include <stdio.h>
#include "helpers.x"

meta static int nine(void) => triple(3);

int main(void) {
  printf("%d %d\n", $nine(), triple(5));
  return 0;
}
EOF

case $(uname -s) in
  MSYS* | MINGW* | CYGWIN*)
    expect_error "native modules are not supported on this platform" \
      "$X2C" translate -q --native-module helpers.so --out-dir out \
      src/main.x
    echo "native module probes passed (unsupported platform)"
    exit 0
    ;;
esac

"$X2C" build -q --kind meta-module src/helpers.x --output helpers.so
"$X2C" build -q --native-module helpers.so src/helpers.x src/main.x \
  --output app
[[ $(./app) == "9 15" ]] || fail "module result"

expect_error "no binding for triple" \
  "$X2C" translate -q --out-dir out -I src src/main.x

cat >wrong.x <<'EOF'
meta long triple(int);
meta static long nine(void) => triple(3);
int main(void) { return $nine(); }
EOF
expect_error "native meta function declaration does not match its target" \
  "$X2C" translate -q --native-module helpers.so --out-dir out wrong.x

cat >stale.c <<'EOF'
const char x2c_module_stamp[] = "0000000000000000";
void *x2c_module_targets(void) { return 0; }
EOF
if [[ $(uname -s) == Darwin ]]; then
  cc -bundle -undefined dynamic_lookup stale.c -o stale.so
else
  cc -fPIC -shared stale.c -o stale.so
fi
expect_error "native module was built by another compiler" \
  "$X2C" translate -q --native-module stale.so --out-dir out src/main.x

cat >x2c.toml <<'EOF'
[project]
default-target = "app"

[target.helpers]
kind = "meta-module"
sources = ["src/helpers.x"]

[target.app]
sources = ["src/*.x"]
native-modules = ["helpers"]
EOF
[[ $("$X2C" run -q) == "9 15" ]] || fail "manifest module result"
"$X2C" build -v >rebuild.out 2>&1
grep -Fq "up-to-date link $BUILD/.x2c-build/helpers.so" rebuild.out ||
  fail "unchanged module relinked"
grep -Fq "up-to-date translate $BUILD/src/main.x" rebuild.out ||
  fail "consumer retranslated after an unchanged module"

printf 'meta int triple(int);\nprintln(%%"${triple(4)}");\n' |
  "$X2C" repl --native-module helpers.so >repl.out 2>&1
grep -qx "12" repl.out || {
  cat repl.out >&2
  fail "REPL module call"
}

echo "native module probes passed"
