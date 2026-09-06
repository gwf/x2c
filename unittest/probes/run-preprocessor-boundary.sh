#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/preprocessor-probes"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
SOURCE_NAME='source; touch injected-marker; true.x'

rm -rf "$BUILD"
mkdir -p "$BUILD/bin" "$BUILD/include first" "$BUILD/include second" \
  "$BUILD/x include"
cp "$ROOT/unittest/probes/preprocessor-source.x" "$BUILD/$SOURCE_NAME"
ln -s "$ROOT/unittest/probes/fake-preprocessor-cc.sh" "$BUILD/bin/cc"

args_log="$BUILD/args.log"
success_stderr="$BUILD/success.stderr"
(
  cd "$BUILD"
  X2C_CC="$BUILD/bin/cc" CPP_ARGS_LOG="$args_log" \
    "$X2C" translate --dump-cpp-text \
    -I "$BUILD/include first" -I "$BUILD/include second" \
    --x-include-dir "$BUILD/x include" "$SOURCE_NAME" \
    >"$BUILD/success.stdout" 2>"$success_stderr"
)

grep -Fq '#define PROBE_VALUE 37' "$success_stderr"
grep -Fxq "$SOURCE_NAME" "$args_log"
grep -Fxq -- '-P' "$args_log"
grep -Fxq -- '-Wno-pragma-once-outside-header' "$args_log"
awk -v first="$BUILD/include first" -v second="$BUILD/include second" \
    -v xonly="$BUILD/x include" '
  previous == "-I" && $0 == first { first_line = NR }
  previous == "-I" && $0 == second { second_line = NR }
  previous == "-I" && $0 == xonly { xonly_line = NR }
  { previous = $0 }
  END {
    exit !(first_line && second_line && xonly_line &&
           first_line < second_line && second_line < xonly_line)
  }
' "$args_log"
[[ ! -e "$BUILD/injected-marker" ]]

active="$ROOT/unittest/compiler-fixtures/preprocess-missing-include.x"
inactive="$ROOT/unittest/compiler-fixtures/preprocess-inactive-missing-include.x"
mkdir -p "$BUILD/active-translate" "$BUILD/active-cpp"
"$X2C" translate --no-cpp --out-dir "$BUILD/active-translate" "$active" \
  >"$BUILD/active-translate.stdout" 2>"$BUILD/active-translate.stderr"
grep -Fq '#include "missing-x2c-preprocessor-fixture.h"' \
  "$BUILD/active-translate/preprocess-missing-include.h"
if "$X2C" build --no-cpp --output "$BUILD/active" "$active" \
    >"$BUILD/active-build.stdout" 2>"$BUILD/active-build.stderr"; then
  echo "active missing include unexpectedly compiled" >&2
  exit 1
fi
grep -Fq 'compile failed' "$BUILD/active-build.stderr"
grep -Fq 'missing-x2c-preprocessor-fixture.h' "$BUILD/active-build.stderr"
if "$X2C" translate --cpp-symbols --out-dir "$BUILD/active-cpp" "$active" \
    >"$BUILD/active-cpp.stdout" 2>"$BUILD/active-cpp.stderr"; then
  echo "active missing include unexpectedly preprocessed" >&2
  exit 1
fi
grep -Fq 'failed to run C preprocessor' "$BUILD/active-cpp.stderr"
"$X2C" run --no-cpp "$inactive" \
  >"$BUILD/inactive.stdout" 2>"$BUILD/inactive.stderr"
grep -Fxq 'inactive include ignored' "$BUILD/inactive.stdout"
"$X2C" run --cpp-symbols "$inactive" \
  >"$BUILD/inactive-cpp.stdout" 2>"$BUILD/inactive-cpp.stderr"
grep -Fxq 'inactive include ignored' "$BUILD/inactive-cpp.stdout"

set +e
(
  cd "$BUILD"
  X2C_CC="$BUILD/bin/cc" CPP_ARGS_LOG="$args_log" CPP_FAIL=1 \
    "$X2C" translate --dump-cpp-text "$SOURCE_NAME" \
    >"$BUILD/failure.stdout" 2>"$BUILD/failure.stderr"
)
failure_status=$?
set -e

[[ $failure_status == 1 ]]
grep -Fq 'deterministic preprocessor failure' "$BUILD/failure.stderr"
grep -Fq 'driver: failed to run C preprocessor' "$BUILD/failure.stderr"
grep -Fq 'status: 23' "$BUILD/failure.stderr"
[[ ! -e "$BUILD/injected-marker" ]]

cp "$ROOT/unittest/probes/fake-toolchain.sh" "$BUILD/bin/fake-cc"
cp "$ROOT/unittest/probes/fake-toolchain.sh" "$BUILD/bin/fake-ar"
chmod +x "$BUILD/bin/fake-cc" "$BUILD/bin/fake-ar"
printf 'int helper(void) { return 1; }\n' >"$BUILD/tool source.c"

tool_log="$BUILD/tool-args.log"
dry_dir="$BUILD/dry build"
TOOL_ARGS_LOG="$tool_log" X2C_CC="$BUILD/bin/fake-cc" CC=wrong-cc \
  X2C_AR="$BUILD/bin/fake-ar" AR=wrong-ar \
  "$X2C" build -### --build-dir "$dry_dir" -O2 -g \
  -I "$BUILD/include first" --x-include-dir "$BUILD/x only" \
  --c-include-dir "$BUILD/include second" \
  --c-system-dir "$BUILD/x include" -D FEATURE=1 -U OLD \
  -Xcc -fno-common -L "$BUILD/lib dir" -l widget \
  -Wl,-rpath,"$BUILD/lib dir" -Xlinker -dead_strip \
  --output "$BUILD/dry output" "$BUILD/tool source.c" \
  >"$BUILD/tool-dry.stdout" 2>"$BUILD/tool-dry.stderr"
[[ ! -e "$dry_dir" && ! -e "$BUILD/dry output" && ! -e "$tool_log" ]]
grep -Fq "$BUILD/bin/fake-cc" "$BUILD/tool-dry.stderr"
grep -Fq -- "-fsigned-char" "$BUILD/tool-dry.stderr"
# -rdynamic is gone: it exported symbols for Func.load's dlsym lookup.
grep -Fq -- "-rdynamic" "$BUILD/tool-dry.stderr" && exit 1
grep -Fq -- "-MMD -MP -MF" "$BUILD/tool-dry.stderr"
grep -Fq -- "-MT" "$BUILD/tool-dry.stderr"
grep -Fq -- "-O2 -g" "$BUILD/tool-dry.stderr"
grep -Fq -- "-D FEATURE=1 -U OLD" "$BUILD/tool-dry.stderr"
! grep -Fq "$BUILD/x only" \
  <(grep 'x2c: compile ' "$BUILD/tool-dry.stderr")
[[ $(grep 'x2c: compile ' "$BUILD/tool-dry.stderr" |
      grep -o -- '-MMD' | wc -l | tr -d ' ') == 1 ]]

TOOL_ARGS_LOG="$tool_log" X2C_AR="$BUILD/bin/fake-ar" AR=wrong-ar \
  "$X2C" build -### --kind static-library \
  --build-dir "$BUILD/dry archive" --output "$BUILD/dry.a" \
  "$BUILD/tool source.c" >"$BUILD/ar-dry.stdout" \
  2>"$BUILD/ar-dry.stderr"
grep -Fq "$BUILD/bin/fake-ar" "$BUILD/ar-dry.stderr"

"$X2C" build -### --build-dir "$BUILD/no defaults" \
  --output "$BUILD/no-defaults" "$BUILD/tool source.c" \
  >"$BUILD/no-defaults.stdout" 2>"$BUILD/no-defaults.stderr"
! grep 'x2c: compile ' "$BUILD/no-defaults.stderr" |
  grep -Eq -- '(^| )-O|(^| )-g( |$)'

: >"$tool_log"
TOOL_ARGS_LOG="$tool_log" X2C_CC=wrong-cc CC=also-wrong \
  "$X2C" build --cc "$BUILD/bin/fake-cc" \
  --build-dir "$BUILD/tool build" --output "$BUILD/tool output" \
  "$BUILD/tool source.c"
[[ -e "$BUILD/tool output" ]]
grep -Fxq "$BUILD/tool source.c" "$tool_log"
grep -Fxq "$BUILD/tool build/obj/tool source-"*".o" "$tool_log"
[[ $(grep -c '^BEGIN compile$' "$tool_log") == 1 ]]
[[ $(grep -c '^BEGIN link$' "$tool_log") == 1 ]]

: >"$tool_log"
TOOL_ARGS_LOG="$tool_log" \
  "$X2C" build --cc "$BUILD/bin/fake-cc" --ar "$BUILD/bin/fake-ar" \
  --kind static-library --build-dir "$BUILD/archive build" \
  --output "$BUILD/libfake.a" "$BUILD/tool source.c"
[[ -e "$BUILD/libfake.a" ]]
[[ $(grep -c '^BEGIN archive$' "$tool_log") == 1 ]]

: >"$tool_log"
set +e
TOOL_ARGS_LOG="$tool_log" TOOL_FAIL_PHASE=compile TOOL_FAIL_STATUS=23 \
  "$X2C" build --cc "$BUILD/bin/fake-cc" \
  --build-dir "$BUILD/fail build" --output "$BUILD/fail output" \
  "$BUILD/tool source.c" >"$BUILD/tool-fail.stdout" \
  2>"$BUILD/tool-fail.stderr"
tool_fail_status=$?
set -e
[[ $tool_fail_status == 1 ]]
grep -Fq 'compile failed with status 23' "$BUILD/tool-fail.stderr"

printf 'int second(void) { return 2; }\n' >"$BUILD/tool second.c"
: >"$tool_log"
TOOL_ARGS_LOG="$tool_log" TOOL_DELAY_PHASE=compile \
  TOOL_DELAY_SECONDS=0.2 \
  "$X2C" build --cc "$BUILD/bin/fake-cc" -j2 \
  --build-dir "$BUILD/parallel build" \
  --output "$BUILD/parallel output" \
  "$BUILD/tool source.c" "$BUILD/tool second.c"
awk '
  /^BEGIN compile$/ { starts++ }
  /^END compile$/ && !first_end { first_end = NR; starts_at_end = starts }
  END { exit !(starts == 2 && starts_at_end == 2) }
' "$tool_log"

program_log="$BUILD/program-args.log"
: >"$tool_log"
set +e
TOOL_ARGS_LOG="$tool_log" TOOL_PROGRAM_LOG="$program_log" \
  TOOL_PROGRAM_STATUS=17 \
  "$X2C" run --cc "$BUILD/bin/fake-cc" \
  --build-dir "$BUILD/run build" "$BUILD/tool source.c" -- \
  -leading program.x "two words" >"$BUILD/run.stdout" \
  2>"$BUILD/run.stderr"
run_status=$?
set -e
[[ $run_status == 17 ]]
printf '%s\n' -leading program.x "two words" >"$BUILD/program-expected.log"
cmp "$BUILD/program-expected.log" "$program_log"

rm -f "$program_log"
: >"$tool_log"
set +e
TOOL_ARGS_LOG="$tool_log" TOOL_PROGRAM_LOG="$program_log" \
  TOOL_FAIL_PHASE=compile \
  "$X2C" run --cc "$BUILD/bin/fake-cc" \
  --build-dir "$BUILD/run fail build" "$BUILD/tool source.c" \
  >"$BUILD/run-fail.stdout" 2>"$BUILD/run-fail.stderr"
run_fail_status=$?
set -e
[[ $run_fail_status == 1 && ! -e "$program_log" ]]
[[ $(grep -c '^BEGIN link$' "$tool_log") == 0 ]]

rm -f "$tool_log"
set +e
TOOL_ARGS_LOG="$tool_log" \
  "$X2C" build --cc "$BUILD/bin/fake-cc" -Xcc -MMD \
  "$BUILD/tool source.c" >"$BUILD/tool-owned.stdout" \
  2>"$BUILD/tool-owned.stderr"
owned_status=$?
set -e
[[ $owned_status == 2 && ! -e "$tool_log" ]]
grep -Fq 'C dependency option is driver-owned' "$BUILD/tool-owned.stderr"

echo "Preprocessor and toolchain boundary probes passed"
