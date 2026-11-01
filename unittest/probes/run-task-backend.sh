#!/usr/bin/env bash
# Optional: native stack geometry/guards, ASan UAR, and the unsupported target.
# Use an existing supported native build. CC may select another installed target.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/task-backend"
mkdir -p "$BUILD"
ulimit -c 0
"${CC:-cc}" -g -Wall -Wextra -Werror \
  "$ROOT/unittest/probes/task-stack-layout.c" -o "$BUILD/layout"
"$BUILD/layout"
"${CC:-cc}" -g -O1 -Wall -Wextra -Werror -fsigned-char \
  -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all \
  "$ROOT/unittest/probes/task-stack-uar.c" -o "$BUILD/uar"
ASAN_OPTIONS=detect_leaks=0:detect_stack_use_after_return=1 \
  UBSAN_OPTIONS=halt_on_error=1 "$BUILD/uar"
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
