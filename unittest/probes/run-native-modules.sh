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
"$X2C" translate -q --native-module helpers.so --out-dir out -I src \
  src/main.x
grep -Fq '9, triple(5)' out/main.c || fail "module result"

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
  "$X2C" translate -q --native-module wrong.x --out-dir out src/main.x

# Sources with one name stay distinct, however they are spelled. The
# compiler links the runtime modules that register no Var class, such as
# DisjointSet.
cat >a/util.x <<'EOF'
meta int fa(int);
#pragma private
int fa(int x) { return x + 1; }
EOF
cat >b/util.x <<'EOF'
meta int fb(int);
#pragma private
int fb(int x) { return x + 2; }
EOF
cat >c/fa.x <<'EOF'
meta int fa(int);
#pragma private
int fa(int x) { return 100; }
EOF
cat >sets.x <<'EOF'
#include "lib.x"
meta int components(int);
#pragma private
int components(int n) { return DisjointSet.new(n).num_components(); }
EOF
cat >both.x <<'EOF'
meta int fa(int);
meta int fb(int);
meta int components(int);
meta static int v(void) => fa(1) * 100 + fb(1) * 10 + components(4);
int main(void) { return $v(); }
EOF
"$X2C" build -q --kind meta-module a/util.x b/util.x sets.x --output ab.so
(cd a && "$X2C" build -q --kind meta-module ../c/fa.x --output ../fa.so)
"$X2C" translate -q --native-module ab.so --native-module fa.so \
  --out-dir out both.x 2>warn.out
grep -Fq "return 234;" out/both.c || fail "module with same-named sources"
[[ ! -e a/util.h && ! -e b/util.h && ! -e c/fa.h ]] ||
  fail "header written beside a source"
grep -Fq "native: more than one native module defines" warn.out ||
  fail "duplicate module warning"

if [[ $(uname -s) == Darwin ]]; then
  cat >rx.x <<'EOF'
#include "regex.x"
meta int groups(int);
#pragma private
int groups(int n) { return Regex.compile("(a)").capture_count() + n; }
EOF
  expect_error "_Regex_compile" \
    "$X2C" build -q --kind meta-module rx.x --output rx.so
fi

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
grep -Fq "unchanged link $BUILD/.x2c-build/helpers.so" rebuild.out ||
  fail "unchanged module output replaced"
grep -Fq "up-to-date translate $BUILD/src/main.x" rebuild.out ||
  fail "consumer retranslated after an unchanged module"
sed -i.bak 's/3 \* x/4 * x/' src/helpers.x
[[ $("$X2C" run -q) == "12 20" ]] || fail "consumer after a module edit"
# `other` names no module, so the one `lib` loaded does not reach it.
expect_error "no binding for triple" "$X2C" build -q --target other

# A library selected by -L/-l is not part of the explicit operand list.
# Rebuild it without touching the module source, then confirm the consumer
# observes the new value. An identical relink preserves the module file.
mkdir -p link
cat >link/external.c <<'EOF'
int external_value(void) { return 2; }
EOF
cat >link/helpers.x <<'EOF'
meta int value(void);
#pragma private
int external_value(void);
int value(void) { return external_value(); }
EOF
cat >link/main.x <<'EOF'
#include <stdio.h>
meta int value(void);
meta static int computed(void) => value();
int main(void) { printf("%d\n", $computed()); return 0; }
EOF
cat >link/x2c.toml <<'EOF'
[project]
default-target = "app"
[target.helpers]
kind = "meta-module"
sources = ["helpers.x"]
library-dirs = ["."]
libraries = ["external"]
[target.app]
sources = ["main.x"]
native-modules = ["helpers"]
EOF
(
  cd link
  cc -c external.c -o external.o
  ar rcs libexternal.a external.o
  [[ $("$X2C" run -q) == 2 ]] || fail "initial linked archive result"
  sed -i.bak 's/return 2/return 3/' external.c
  cc -c external.c -o external.o
  ar rcs libexternal.a external.o
  [[ $("$X2C" run -q) == 3 ]] || fail "changed linked archive result"
  cp .x2c-build/helpers.so old.so
  "$X2C" build -v >relink.out 2>&1
  grep -Fq "unchanged link $BUILD/link/.x2c-build/helpers.so" relink.out ||
    fail "identical module output replaced"
  cmp -s old.so .x2c-build/helpers.so || fail "identical module bytes changed"
  grep -Fq "up-to-date translate $BUILD/link/main.x" relink.out ||
    fail "identical module caused consumer translation"
  sed -i.bak 's/libraries = \["external"\]/libraries = ["missing"]/' x2c.toml
  if "$X2C" build -q >failed-link.out 2>&1; then
    fail "missing library linked"
  fi
  cmp -s old.so .x2c-build/helpers.so || fail "failed link replaced module"
)

printf 'meta int triple(int);\nprintln(%%"${triple(4)}");\n' |
  "$X2C" repl --native-module .x2c-build/helpers.so >repl.out 2>&1
grep -qx "16" repl.out || {
  cat repl.out >&2
  fail "REPL module call"
}

echo "native module probes passed"
