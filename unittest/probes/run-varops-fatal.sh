#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/varops-probes"
PROGRAM="$BUILD/varops-fatal"
read -r -a build_cflags <<<"${BUILD_CFLAGS:-}"
mkdir -p "$BUILD"

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/probes/varops-fatal.x"
"${CC:-cc}" ${build_cflags[@]+"${build_cflags[@]}"} \
  -iquote "$ROOT/include/x2c" "$BUILD/varops-fatal.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"

check_case() {
  local name=$1
  local expected=$2
  local probe_status

  set +e
  ( "$PROGRAM" "$name" \
      >"$BUILD/$name.stdout" 2>"$BUILD/$name.stderr.raw"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null
  probe_status=$?
  set -e
  cp "$BUILD/$name.stderr.raw" "$BUILD/$name.stderr"

  if [[ $probe_status -eq 0 ]]; then
    echo "$name: expected terminal failure" >&2
    return 1
  fi
  test ! -s "$BUILD/$name.stdout"
  test "$(cat "$BUILD/$name.stderr")" = "$expected"
}

check_case convert 'x2c: uncaught <void-op>: operation Var.convert, target i32'
check_case truth 'x2c: uncaught <void-op>: operation Var.truth'
check_case hash 'x2c: uncaught <void-op>: operation Var.hash'
check_case compare 'x2c: uncaught <void-op>: operation Var.compare'
check_case iter 'x2c: uncaught <void-op>: operation Var.iter'
check_case binary 'x2c: uncaught <void-op>: op +'
check_case update 'x2c: uncaught <void-op>: op +'
check_case postfix 'x2c: uncaught <void-op>: op ++'
echo "Var fatal probes passed"
