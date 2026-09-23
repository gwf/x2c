#!/usr/bin/env bash
set -euo pipefail

# Native modules: a project function built with `--kind meta-module` runs in
# compile-time code when a translation, build, manifest target, or REPL
# loads it. A module from another compiler is rejected before its code runs,
# a prototype whose signature differs is rejected, and a translation binds
# only the modules its own request names.

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
BUILD="$ROOT/unittest/build/native-modules"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$BUILD/out" "$BUILD/a" "$BUILD/b" "$BUILD/c"
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

bundle() {
  if [[ $(uname -s) == Darwin ]]; then
    cc -bundle -undefined dynamic_lookup "$1" -o "$2"
  else
    cc -fPIC -shared "$1" -o "$2"
  fi
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

# The stamp is read from the file, so a stale module's code never runs.
cat >stale.c <<'EOF'
#include <stdlib.h>
const char x2c_module_stamp[] = "x2c-module-stamp:0000000000000000";
void *x2c_module_targets(void) { return 0; }
__attribute__((constructor)) static void ran(void) { abort(); }
EOF
bundle stale.c stale.so
expect_error "native module 'stale.so' was built by another compiler" \
  "$X2C" translate -q --native-module stale.so --out-dir out src/main.x
expect_error "not an x2c native module" \
  "$X2C" translate -q --native-module app --out-dir out src/main.x

# Sources with one name stay distinct, however they are spelled.
printf 'meta int fa(int);\n#pragma private\nint fa(int x) { return x + 1; }\n' \
  >a/util.x
printf 'meta int fb(int);\n#pragma private\nint fb(int x) { return x + 2; }\n' \
  >b/util.x
printf 'meta int fa(int);\n#pragma private\nint fa(int x) { return 100; }\n' \
  >c/fa.x
cat >both.x <<'EOF'
meta int fa(int);
meta int fb(int);
meta static int v(void) => fa(1) * 10 + fb(1);
int main(void) { return $v(); }
EOF
"$X2C" build -q --kind meta-module a/util.x b/util.x --output ab.so
"$X2C" translate -q --native-module ab.so --out-dir out both.x
grep -Fq "return 23;" out/both.c || fail "module with same-named sources"
[[ ! -e a/util.h && ! -e b/util.h ]] || fail "header written beside a source"
(cd c && "$X2C" build -q --kind meta-module ../a/util.x --output ../dots.so)
"$X2C" build -q --kind meta-module c/fa.x --output fa.so
cat >first.x <<'EOF'
meta int fa(int);
meta static int v(void) => fa(1);
int main(void) { return $v(); }
EOF
"$X2C" translate -q --native-module dots.so --native-module fa.so \
  --out-dir out first.x 2>warn.out
grep -Fq "return 2;" out/first.c || fail "first named module supplies"
grep -Fq "both define 'fa'" warn.out || fail "duplicate module warning"

printf 'int unrelated;\n' >empty.x
expect_error "native module sources declare no meta function" \
  "$X2C" build -q --kind meta-module empty.x --output empty.so

cat >x2c.toml <<'EOF'
[project]
default-target = "app"

[target.helpers]
kind = "meta-module"
sources = ["src/helpers.x"]

[target.lib]
kind = "static-library"
sources = ["lib.x"]
native-modules = ["helpers"]

[target.app]
sources = ["src/*.x"]
native-modules = ["helpers"]

[target.other]
sources = ["other.x"]
dependencies = ["lib"]
EOF
cat >lib.x <<'EOF'
meta int triple(int);
meta static int twelve(void) => triple(4);
int twelve_value(void) { return $twelve(); }
EOF
cat >other.x <<'EOF'
meta int triple(int);
int twelve_value(void);
meta static int nine(void) => triple(3);
int main(void) { return $nine() + twelve_value(); }
EOF
[[ $("$X2C" run -q) == "9 15" ]] || fail "manifest module result"
"$X2C" build -v >rebuild.out 2>&1
grep -Fq "up-to-date link $BUILD/.x2c-build/helpers.so" rebuild.out ||
  fail "unchanged module relinked"
grep -Fq "up-to-date translate $BUILD/src/main.x" rebuild.out ||
  fail "consumer retranslated after an unchanged module"
sed -i.bak 's/3 \* x/4 * x/' src/helpers.x
[[ $("$X2C" run -q) == "12 20" ]] || fail "consumer after a module edit"
# `other` names no module, so the one `lib` loaded does not reach it.
expect_error "no binding for triple" "$X2C" build -q --target other

printf 'meta int triple(int);\nprintln(%%"${triple(4)}");\n' |
  "$X2C" repl --native-module .x2c-build/helpers.so >repl.out 2>&1
grep -qx "16" repl.out || {
  cat repl.out >&2
  fail "REPL module call"
}

echo "native module probes passed"
