#!/usr/bin/env bash
# Optional: native stack geometry/guards and production unsupported fallback.
# Use an existing supported native build. CC may select another installed target.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/task-backend"
mkdir -p "$BUILD"
ulimit -c 0
"${CC:-cc}" -g -Wall -Wextra -Werror \
  "$ROOT/unittest/probes/task-stack-layout.c" -o "$BUILD/layout"
"$BUILD/layout"
"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/probes/task-unsupported.x"
# Select the existing unsupported branch only in the backend translation unit.
"${CC:-cc}" -g -Wall -Wextra -Werror -D__EMSCRIPTEN__ \
  -c "$ROOT/lib/task/stack.c" -o "$BUILD/unsupported.o"
"${CC:-cc}" -g -fsigned-char -pthread -iquote "$ROOT/include/x2c" \
  "$BUILD/task-unsupported.c" "$BUILD/unsupported.o" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$BUILD/unsupported"
"$BUILD/unsupported"
echo "Task backend probes passed"
