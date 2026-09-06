#!/usr/bin/env bash
set -euo pipefail

probe_dir=$(cd "$(dirname "$0")" && pwd)
unittest_dir=$(cd "$probe_dir/.." && pwd)
root=$(cd "$unittest_dir/.." && pwd)
generated_tests="$unittest_dir/build"
generated_runtime="$root/builds/0/lib"
generated_compiler="$root/builds/0/src"
sanitizer_dir="$generated_tests/sanitizer"
runtime_objects="$sanitizer_dir/runtime"
test_objects="$sanitizer_dir/tests"
compiler_objects="$sanitizer_dir/compiler"
runtime_archive="$sanitizer_dir/libx2c-sanitized.a"
test_program="$sanitizer_dir/test-all"

cc=${CC:-cc}
ar=${AR:-ar}
ranlib=${RANLIB:-ranlib}
detect_leaks=${X2C_DETECT_LEAKS:-0}
linker_flags=()
if [[ $(uname -s) == Linux ]]; then
  linker_flags+=(-rdynamic)
fi
sanitizer_flags=(
  -g
  -O1
  -fno-omit-frame-pointer
  -fsanitize=address,undefined
  -fno-sanitize-recover=all
  -Wno-invalid-pp-token
  -iquote "$root/include"
  -iquote "$generated_runtime"
  -iquote "$generated_compiler"
)

if [[ ! -f "$generated_tests/test-all.c" ]]; then
  make -C "$unittest_dir" test-all
fi

rm -rf "$sanitizer_dir"
mkdir -p "$runtime_objects" "$test_objects" "$compiler_objects"

archive_members=()
while IFS= read -r member; do
  [[ "$member" == __* ]] && continue
  archive_members+=("$member")
done < <("$ar" -t "$root/builds/0/libx2c.a")

for member in "${archive_members[@]}"; do
  name=${member%.o}
  "$cc" "${sanitizer_flags[@]}" -c "$generated_runtime/$name.c" \
    -o "$runtime_objects/$member"
done

ordered_runtime_objects=()
for member in "${archive_members[@]}"; do
  ordered_runtime_objects+=("$runtime_objects/$member")
done
"$ar" rcs "$runtime_archive" "${ordered_runtime_objects[@]}"
"$ranlib" "$runtime_archive"

test_sources=("$generated_tests"/test-*.c)
for source in "${test_sources[@]}"; do
  name=$(basename "$source" .c)
  test_flags=()
  if [[ $(uname -s) == Linux && "$name" == test-logger ]]; then
    test_flags+=(-D_GNU_SOURCE)
  fi
  "$cc" "${sanitizer_flags[@]}" "${test_flags[@]}" -c "$source" \
    -o "$test_objects/$name.o"
done

for name in ast diagnostics report; do
  "$cc" "${sanitizer_flags[@]}" -c "$generated_compiler/$name.c" \
    -o "$compiler_objects/$name.o"
done

suite_objects=()
for object in "$test_objects"/test-*.o; do
  [[ "$object" == "$test_objects/test-all.o" ]] && continue
  suite_objects+=("$object")
done

"$cc" "${sanitizer_flags[@]}" \
  "${linker_flags[@]}" \
  -o "$test_program" \
  "$test_objects/test-all.o" \
  "${suite_objects[@]}" \
  "$runtime_archive" \
  "$compiler_objects/ast.o" \
  "$compiler_objects/diagnostics.o" \
  "$compiler_objects/report.o" \
  -lm

(
  cd "$unittest_dir"
  ASAN_OPTIONS="detect_leaks=$detect_leaks:halt_on_error=1:abort_on_error=1" \
  UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
    "$test_program"
)
