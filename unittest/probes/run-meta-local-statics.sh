#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
BUILD="$ROOT/unittest/build/meta-local-statics"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
mkdir -p "$BUILD"

# One cached imported definition must use each consuming unit's storage.
cat >"$BUILD/shared.xmacro" <<'SRC'
meta static int shared_next(void) {
  static int value;
  value += 1;
  return value;
}
SRC
cat >"$BUILD/first.x" <<'SRC'
#include "x2c.x"
$(import "shared.xmacro")
int second(void);
int main(void) {
  printf("units %d %d %d\n", $shared_next(), $shared_next(), second());
  return 0;
}
SRC
cat >"$BUILD/second.x" <<'SRC'
#include "x2c.x"
$(import "shared.xmacro")
int second(void) { return 10 * $shared_next() + $shared_next(); }
SRC
"$X2C" build -q --output "$BUILD/units" \
  "$BUILD/first.x" "$BUILD/second.x"
[[ $("$BUILD/units") == 'units 1 2 12' ]]

# Even const statics and their transitive callers must remain runtime calls.
cat >"$BUILD/constant.x" <<'SRC'
#include "x2c.x"
meta int constant(void) { static const int value = 17; return value; }
meta int forward(void) { return constant(); }
int main(void) { return forward() == $constant() ? 0 : 1; }
SRC
mkdir -p "$BUILD/constant"
"$X2C" translate -q --out-dir "$BUILD/constant" "$BUILD/constant.x"
grep -q 'return forward() == 17' "$BUILD/constant/constant.c"

case $(uname -s) in
  MSYS* | MINGW* | CYGWIN*)
    echo "meta local statics passed (native retry probe unsupported)"
    exit 0
    ;;
esac

# A native boundary catches evaluator errors, then invokes the same source
# function again. This exercises retry through the real meta lowering.
cat >"$BUILD/retry.x" <<'SRC'
#include "x2c.x"
meta int initialize(int *target);
meta int catch_init(Var callable);
#pragma private
static int attempts;
static int *reserved;
int initialize(int *target) {
  attempts++;
  if (*target || (reserved && reserved != target)) return -100;
  reserved = target;
  if (attempts == 1) {
    *target = 99;
    raise %(init-test);
  }
  return 40 + attempts;
}
int catch_init(Var callable) {
  Func callback = callable;
  try return callback();
  catch %(init-test): return -1;
  catch %(bad-state *): return -2;
}
SRC
cat >"$BUILD/main.x" <<'SRC'
#include "x2c.x"
#include "retry.x"
meta int retry_value(void) {
  static int value = initialize(&value);
  return value;
}
meta int recursive_value(int n) {
  static int value = n ? recursive_value(0) : 21;
  return value;
}
meta int run_retry(void) {
  Func read = retry_value;
  int failed = catch_init(read);
  int first = retry_value();
  return 10000 * failed + 100 * first + retry_value();
}
meta int run_recursive(void) {
  Func read = %!() => recursive_value(1);
  int failed = catch_init(read);
  return 100 * failed + recursive_value(0);
}
int main(void) {
  int native_retry = run_retry();
  int native_recursive = run_recursive();
  printf("retry %d %d recursive %d %d\n",
    $run_retry(), native_retry, $run_recursive(), native_recursive);
  return 0;
}
SRC
"$X2C" build -q --kind meta-module "$BUILD/retry.x" \
  --output "$BUILD/retry.so"
"$X2C" build -q --native-module "$BUILD/retry.so" \
  --output "$BUILD/retry" "$BUILD/main.x" "$BUILD/retry.x"
[[ $("$BUILD/retry") == 'retry -5758 -5758 recursive -179 -179' ]]
echo "meta local statics passed"
