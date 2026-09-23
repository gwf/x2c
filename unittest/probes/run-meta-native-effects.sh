#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
BUILD="$ROOT/unittest/build/meta-native-effects"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

case $(uname -s) in
  MSYS* | MINGW* | CYGWIN*)
    echo "meta native effects skipped (native modules unsupported)"
    exit 0
    ;;
esac

mkdir -p "$BUILD"
cat >"$BUILD/counter.x" <<'EOF'
meta int counter_next(void);
meta int counter_read(void);
#pragma private
static int value;
int counter_next(void) { return ++value; }
int counter_read(void) { return value; }
EOF
cat >"$BUILD/main.x" <<'EOF'
#include "x2c.x"
#include "counter.x"
meta int inner(int ignored) { (void) ignored; return counter_next(); }
meta int outer(int ignored) => inner(ignored);
int main(int argc, char **argv) {
  (void) argv;
  int explicit_value = $outer(0);
  int first = outer(1);
  int second = outer(argc);
  printf("%d %d %d %d\n",
    explicit_value, first, second, counter_read());
  return 0;
}
EOF

"$X2C" build -q --kind meta-module "$BUILD/counter.x" \
  --output "$BUILD/counter.so"
"$X2C" build -q --native-module "$BUILD/counter.so" \
  --output "$BUILD/main" "$BUILD/main.x" "$BUILD/counter.x"
actual=$("$BUILD/main")
[[ "$actual" == '1 1 2 2' ]] || {
  printf 'meta native effects: expected 1 1 2 2, got %s\n' "$actual" >&2
  exit 1
}
echo "meta native effects passed"
