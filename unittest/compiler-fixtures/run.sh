#!/usr/bin/env bash
set -euo pipefail

mode=${1:-check}
if [[ "$mode" != check && "$mode" != update ]]; then
  echo "usage: $0 [check|update] [--fixture <name>]" >&2
  exit 2
fi

fixture_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$fixture_dir/../.." && pwd)
build="$root/unittest/build/compiler-fixtures"
x2c=${X2C:-"$root/builds/0/x2c"}
cc=${CC:-cc}
read -r -a build_cflags <<< "${BUILD_CFLAGS:-}"

mkdir -p "$build"

failures=0
artifact_count=0

has_phase() {
  local wanted=$1
  local phase
  for phase in "${phases[@]}"; do
    [[ "$phase" == "$wanted" ]] && return 0
  done
  return 1
}

record_failure() {
  echo "compiler fixture failure: $1" >&2
  failures=$((failures + 1))
}

check_artifact() {
  local phase=$1
  local actual=$2
  local expected="$fixture_dir/$name.$phase"
  artifact_count=$((artifact_count + 1))

  if [[ "$mode" == update ]]; then
    cp "$actual" "$expected"
    return
  fi
  if [[ ! -f "$expected" ]]; then
    record_failure "$name/$phase has no expected artifact"
    return
  fi
  if ! diff -u "$expected" "$actual"; then
    record_failure "$name/$phase differs"
  fi
}

run_dump() {
  local phase=$1
  local flag=$2
  local actual="$case_build/$phase.actual"
  local errors="$case_build/$phase.stderr"

  if ! (cd "$root" && "$x2c" translate "$flag" \
      "${extra_flags[@]}" "$source_rel") \
      >"$actual" 2>"$errors"; then
    cat "$errors" >&2
    record_failure "$name/$phase compiler invocation failed"
    return
  fi
  check_artifact "$phase" "$actual"
}

run_symbol_dump() {
  local raw="$case_build/symbols.raw"
  local actual="$case_build/symbols.actual"
  local errors="$case_build/symbols.stderr"
  local filter_file="$fixture_dir/$name.symbol-filter"
  if [[ ! -f "$filter_file" ]]; then
    record_failure "$name/symbols has no symbol-filter"
    return
  fi
  local filter
  filter=$(<"$filter_file")
  if [[ -z "$filter" ]]; then
    record_failure "$name/symbols has an empty symbol-filter"
    return
  fi
  if ! (cd "$root" && "$x2c" translate --dump-symbols \
      "${extra_flags[@]}" "$source_rel") \
      >"$raw" 2>"$errors"; then
    cat "$errors" >&2
    record_failure "$name/symbols compiler invocation failed"
    return
  fi
  awk -v filter="$filter" '
    function flush() {
      if (keep) print header " " value
      value = ""
    }
    /^\( source-node / {
      flush()
      keep = 0
      next
    }
    /^\(.*\) ==>[[:space:]]*$/ {
      flush()
      keep = index($0, filter) != 0
      header = $0
      next
    }
    keep {
      value = value (value ? " " : "") $0
    }
    END {
      flush()
    }
  ' "$raw" | LC_ALL=C sort >"$actual"
  check_artifact symbols "$actual"
}

# One fixture, start to finish. Fixtures share nothing but the checked-in
# expectations they each own, so this body is what the parent runs in
# parallel; it reports through files under its own $case_build rather than
# the terminal, whose interleaving would shred a multi-line diff.
run_fixture() {
  name=$1
  source="$fixture_dir/$name.x"
  source_rel=${source#"$root/"}
  case_build="$build/$name"

  rm -rf "$case_build"
  mkdir -p "$case_build"
  exec >"$case_build/log" 2>&1

  if [[ ! -f "$source" ]]; then
    record_failure "$name has no source file"
    return
  fi

  # Optional soft stack limit for fixtures that exercise compiler recursion.
  if [[ -f "$fixture_dir/$name.stack-kb" ]]; then
    ulimit -s "$(<"$fixture_dir/$name.stack-kb")"
  fi

  read -r -a phases <"$fixture_dir/$name.phases"
  # Optional flags appended to every translate invocation for this fixture.
  extra_flags=()
  if [[ -f "$fixture_dir/$name.flags" ]]; then
    read -r -a extra_flags <"$fixture_dir/$name.flags"
  fi

  if ((${#phases[@]} == 0)); then
    record_failure "$name.phases is empty; no artifacts would be checked"
    return
  fi

  for phase in "${phases[@]}"; do
    case "$phase" in
      tokens|ast|transform|emit|symbols|h|c|compile-status|diagnostics)
        ;;
      stdout|stderr|status)
        ;;
      *)
        record_failure "$name declares unknown phase '$phase'"
        ;;
    esac
  done

  if has_phase tokens; then
    raw="$case_build/tokens.raw"
    errors="$case_build/tokens.stderr"
    actual="$case_build/tokens.actual"
    if (cd "$root" && "$x2c" translate --no-cpp --dump-tokens \
        "${extra_flags[@]}" "$source_rel") \
        >"$raw" 2>"$errors"; then
      awk -F '\t' \
        '$2 !~ /^(space|comment|preproc)[[:space:]]/' "$raw" >"$actual"
      check_artifact tokens "$actual"
    else
      cat "$errors" >&2
      record_failure "$name/tokens compiler invocation failed"
    fi
  fi

  has_phase ast && run_dump ast --dump-ast
  has_phase transform && run_dump transform --dump-transforms
  has_phase emit && run_dump emit --dump-code
  has_phase symbols && run_symbol_dump

  need_compile=0
  for phase in h c compile-status diagnostics stdout stderr status; do
    has_phase "$phase" && need_compile=1
  done
  ((need_compile)) || return 0

  output="$case_build/output"
  compile_stdout="$case_build/compile.stdout"
  compile_stderr="$case_build/diagnostics.actual"
  rm -rf "$output"
  mkdir -p "$output"

  set +e
  (cd "$root" && "$x2c" translate --quiet \
    --out-dir "$output" "${extra_flags[@]}" "$source_rel") \
    >"$compile_stdout" 2>"$compile_stderr"
  compile_status=$?
  set -e
  printf '%d\n' "$compile_status" >"$case_build/compile-status.actual"

  has_phase compile-status && \
    check_artifact compile-status "$case_build/compile-status.actual"
  has_phase diagnostics && check_artifact diagnostics "$compile_stderr"

  if ((compile_status != 0)); then
    if ! has_phase compile-status; then
      cat "$compile_stderr" >&2
      record_failure "$name compiler invocation failed"
    fi
    for phase in h c stdout stderr status; do
      if has_phase "$phase"; then
        record_failure "$name/$phase unavailable after compiler failure"
      fi
    done
    return 0
  fi

  has_phase h && check_artifact h "$output/$name.h"
  has_phase c && check_artifact c "$output/$name.c"

  need_run=0
  for phase in stdout stderr status; do
    has_phase "$phase" && need_run=1
  done
  ((need_run)) || return 0

  program="$case_build/program"
  if ! "$cc" "${build_cflags[@]}" \
      -iquote "$root/include" -iquote "$fixture_dir" \
      "$output/$name.c" \
      -L"$root/builds/0" -lx2c -lm -o "$program" \
      >"$case_build/cc.stdout" 2>"$case_build/cc.stderr"; then
    cat "$case_build/cc.stderr" >&2
    record_failure "$name generated C did not compile"
    return 0
  fi

  stderr_raw="$case_build/stderr.raw"
  set +e
  ( "$program" >"$case_build/stdout.actual" 2>"$stderr_raw"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null
  run_status=$?
  set -e
  sed -E '
    /^[0-9]+:[0-9][0-9]\.[0-9][0-9][0-9] (trace|debug|info|warn|error|fatal)\// {
      s/^[0-9]+:[0-9][0-9]\.[0-9][0-9][0-9]/<elapsed>/
      s/start_time="[^"]*"/start_time="<wall-time>"/
    }
  ' "$stderr_raw" >"$case_build/stderr.actual"
  printf '%d\n' "$run_status" >"$case_build/status.actual"

  has_phase stdout && check_artifact stdout "$case_build/stdout.actual"
  has_phase stderr && check_artifact stderr "$case_build/stderr.actual"
  has_phase status && check_artifact status "$case_build/status.actual"
  if ((run_status != 0)) && ! has_phase status; then
    record_failure "$name program exited $run_status"
  fi
  return 0
}

if [[ ${2:-} == --fixture ]]; then
  run_fixture "$3"
  printf '%d %d\n' "$failures" "$artifact_count" >"$build/$3/tally"
  exit 0
fi

names=()
for manifest in "$fixture_dir"/*.phases; do
  [[ -e "$manifest" ]] || continue
  names+=("$(basename "$manifest" .phases)")
done
fixture_count=${#names[@]}

if ((fixture_count)); then
  printf '%s\n' "${names[@]}" | \
    xargs -P "${JOBS:-$(getconf _NPROCESSORS_ONLN)}" -n 1 \
      "$fixture_dir/run.sh" "$mode" --fixture || true
fi

for name in "${names[@]}"; do
  tally="$build/$name/tally"
  if [[ ! -f "$tally" ]]; then
    echo "compiler fixture failure: $name did not report a result" >&2
    failures=$((failures + 1))
    continue
  fi
  read -r fixture_failures fixture_artifacts <"$tally"
  artifact_count=$((artifact_count + fixture_artifacts))
  ((fixture_failures)) || continue
  failures=$((failures + fixture_failures))
  cat "$build/$name/log" >&2
done

if ((failures)); then
  printf 'Compiler fixtures: %d failure(s) across %d fixtures\n' \
    "$failures" "$fixture_count" >&2
  exit 1
fi

if [[ "$mode" == update ]]; then
  printf 'Compiler fixtures: updated %d artifacts across %d fixtures\n' \
    "$artifact_count" "$fixture_count"
else
  echo "Compiler fixtures: $fixture_count passed ($artifact_count artifacts)"
fi
