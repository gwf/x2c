#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/varops-probes"
PROGRAM="$BUILD/varops-fatal"
MODE=$(cat "$ROOT/etc/build-mode" 2>/dev/null || echo debug)
mkdir -p "$BUILD"

case "$MODE" in
  debug) flags=(-g) ;;
  optimize) flags=(-O2) ;;
  *)
    echo "unknown build mode: $MODE" >&2
    exit 2
    ;;
esac

"$ROOT/builds/0/x2c" translate --out-dir "$BUILD" \
  "$ROOT/unittest/probes/varops-fatal.x"
"${CC:-cc}" "${flags[@]}" -iquote "$ROOT/include" \
  "$BUILD/varops-fatal.c" -L"$ROOT/builds/0" -lx2c -lm -o "$PROGRAM"

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
  sed -E '
    /^[0-9]+:[0-9][0-9]\.[0-9][0-9][0-9] (trace|debug|info|warn|error|fatal)\// {
      s/^[0-9]+:[0-9][0-9]\.[0-9][0-9][0-9]/<elapsed>/
      s/start_time="[^"]*"/start_time="<wall-time>"/
    }
    s/\(line [0-9]+\)/(line <line>)/
  ' "$BUILD/$name.stderr.raw" >"$BUILD/$name.stderr"

  if [[ $probe_status -eq 0 ]]; then
    echo "$name: expected terminal failure" >&2
    return 1
  fi
  test ! -s "$BUILD/$name.stdout"
  test "$(cat "$BUILD/$name.stderr")" = "$expected"
}

check_case convert \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((owner "Var.convert")) location=\n((file "../../lib/varconvert.x") (line <line>)\x20\n (function "Var_convert"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
check_case truth \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((owner "Var.truth")) location=\n((file "../../lib/varops.x") (line <line>) (function "Var_fallback_truth"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
check_case hash \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((owner "Var.hash")) location=\n((file "../../lib/dispatch.x") (line <line>)\x20\n (function "Var_hash"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
check_case compare \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((owner "Var.compare")) location=\n((file "../../lib/dispatch.x") (line <line>)\x20\n (function "Var_compare"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
check_case iter \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((owner "Var.iter")) location=\n((file "../../lib/dispatch.x") (line <line>)\x20\n (function "Var_iter"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
check_case binary \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((op +)) location=\n((file "../../lib/varops.x") (line <line>) (function "_protocol_arithmetic"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
check_case update \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((op +)) location=\n((file "../../lib/varops.x") (line <line>) (function "Var_update"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
check_case postfix \
  $'<elapsed> error/err-report start_time="<wall-time>" code=<void-op> detail=\n((op ++)) location=\n((file "../../lib/varops.x") (line <line>) (function "Var_postfix"))\nx2c error floor: code 0xb3d24fbe0: non-returning error was not caught'
echo "Var fatal probes: 8 passed"
