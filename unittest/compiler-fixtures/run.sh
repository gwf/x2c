#!/usr/bin/env bash
set -euo pipefail

mode=${1:-check}
if [[ "$mode" != check && "$mode" != update ]]; then
  echo "usage: $0 [check|update] [--fixture <name>]" >&2
  exit 2
fi

# Public runs supervise complete fixture workers.
if [[ "${2:-}" != --worker ]]; then
  exec python3 "$(dirname "$0")/supervise.py" "$@"
fi

# FIXTURE_DIR and FIXTURE_BUILD let a package run its own fixtures here.
script_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$script_dir/../.." && pwd)
fixture_dir=${FIXTURE_DIR:-$script_dir}
build=${FIXTURE_BUILD:-"$root/unittest/build/compiler-fixtures"}
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

# A raise or a protocol note inside `lib/` reports the runtime source line it
# came from. That line belongs to the runtime, not to the fixture, so editing
# any runtime module would otherwise rewrite these artifacts. Replace it as
# elapsed times are replaced below; the file and function still name the
# raising operation.
normalize_runtime_lines() {
  local file=$1
  sed -E \
    -e 's|(\(file "[^"]*lib/[A-Za-z0-9_/-]+\.x"\) \(line )[0-9]+|\1<line>|g' \
    -e 's|(lib/[A-Za-z0-9_/-]+\.x):[0-9]+:[0-9]+|\1:<line>:<column>|g' \
    "$file" >"$file.normalized"
  mv "$file.normalized" "$file"
}

# The C compiler's own warnings about the generated C. Keep the diagnostic
# text and drop the build path, the line and column, the echoed source, and
# the per-run summary. Preserve other text so an unfamiliar diagnostic cannot
# silently turn a warning-producing compile into a clean one.
normalize_cc_warnings() {
  local file=$1
  sed -E \
    -e '/^[[:space:]]*[0-9]*[[:space:]]*\|/d' \
    -e '/^[0-9]+ (warning|error)s?( and [0-9]+ (warning|error)s?)? generated\.$/d' \
    -e "/^[^:]+: (In function '[^']*'|At top level):$/d" \
    "$file" | perl -pe '
      s{^(.*?):[0-9]+(?::[0-9]+)?: }{
        my $file = $1;
        $file =~ s{.*/}{};
        "$file: ";
      }e;
    ' >"$file.normalized"
  mv "$file.normalized" "$file"
}

# `<name>.cc-stderr` records clang's wording. gcc words the same warnings
# differently, so a gcc run checks `<name>.cc-stderr.gcc` when the fixture
# has one, and an update writes it only when gcc's text differs.
cc_stderr_phase() {
  local actual=$1 base="$fixture_dir/$name.cc-stderr"
  if [[ "$("$cc" --version 2>/dev/null)" == *"Free Software Foundation"* ]] &&
      { [[ -f "$base.gcc" ]] ||
        { [[ "$mode" == update ]] && ! cmp -s "$base" "$actual"; }; }; then
    echo cc-stderr.gcc
  else
    echo cc-stderr
  fi
}

check_artifact() {
  local phase=$1
  local actual=$2
  local expected="$fixture_dir/$name.$phase"
  artifact_count=$((artifact_count + 1))

  if [[ "$mode" == update ]]; then
    mkdir -p "$case_build/updates"
    cp "$actual" "$case_build/updates/$phase"
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
      ${extra_flags[@]+"${extra_flags[@]}"} "$source_rel") \
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
      ${extra_flags[@]+"${extra_flags[@]}"} "$source_rel") \
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
      tokens|ast|expansions|transform|emit|symbols|definitions|h|c|\
      compile-status|diagnostics)
        ;;
      cc-stderr|stdout|stderr|status)
        ;;
      *)
        record_failure "$name declares unknown phase '$phase'"
        ;;
    esac
  done

  if has_phase tokens; then
    token_flags=(--no-cpp)
    for flag in "${extra_flags[@]}"; do
      if [[ "$flag" == --cpp ]]; then token_flags=(); fi
    done
    raw="$case_build/tokens.raw"
    errors="$case_build/tokens.stderr"
    actual="$case_build/tokens.actual"
    if (cd "$root" && "$x2c" translate ${token_flags[@]+"${token_flags[@]}"} --dump-tokens \
        ${extra_flags[@]+"${extra_flags[@]}"} "$source_rel") \
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
  has_phase expansions && run_dump expansions --dump-expansions
  has_phase transform && run_dump transform --dump-transforms
  has_phase emit && run_dump emit --dump-code
  has_phase symbols && run_symbol_dump
  has_phase definitions && run_dump definitions --dump-definitions

  need_compile=0
  for phase in h c compile-status diagnostics cc-stderr stdout stderr \
      status; do
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
    --out-dir "$output" ${extra_flags[@]+"${extra_flags[@]}"} "$source_rel") \
    >"$compile_stdout" 2>"$compile_stderr"
  compile_status=$?
  set -e
  printf '%d\n' "$compile_status" >"$case_build/compile-status.actual"

  has_phase compile-status && \
    check_artifact compile-status "$case_build/compile-status.actual"
  normalize_runtime_lines "$compile_stderr"
  # This fixture changes a real binding's spelling; its allocated ID is incidental.
  if [[ "$name" == macro-binding-spelling-mismatch ]]; then
    sed -E 's/(note: binding: \(binding )[0-9]+ /\1<id> /' \
      "$compile_stderr" >"$compile_stderr.normalized"
    mv "$compile_stderr.normalized" "$compile_stderr"
  fi
  has_phase diagnostics && check_artifact diagnostics "$compile_stderr"

  if ((compile_status != 0)); then
    if ! has_phase compile-status; then
      cat "$compile_stderr" >&2
      record_failure "$name compiler invocation failed"
    fi
    for phase in h c cc-stderr stdout stderr status; do
      if has_phase "$phase"; then
        record_failure "$name/$phase unavailable after compiler failure"
      fi
    done
    return 0
  fi

  has_phase h && check_artifact h "$output/$name.h"
  has_phase c && check_artifact c "$output/$name.c"

  need_run=0
  for phase in cc-stderr stdout stderr status; do
    has_phase "$phase" && need_run=1
  done
  ((need_run)) || return 0

  program="$case_build/program"
  generated_sources=("$output/$name.c")
  for generated in "$output"/*.c; do
    [[ "$generated" == "$output/$name.c" ]] || \
      generated_sources+=("$generated")
  done
  # The C locale keeps the compiler's quotes in its warnings ASCII.
  if ! LC_ALL=C "$cc" -fsigned-char ${build_cflags[@]+"${build_cflags[@]}"} \
      -iquote "$root/include/x2c" -iquote "$fixture_dir" \
      "${generated_sources[@]}" \
      -L"$root/builds/0" -lx2c -lm -o "$program" \
      >"$case_build/cc.stdout" 2>"$case_build/cc.stderr"; then
    cat "$case_build/cc.stderr" >&2
    record_failure "$name generated C did not compile"
    return 0
  fi

  # A fixture that declares cc-stderr owns the warnings its generated C
  # provokes; every other fixture is expected to compile silently.
  normalize_cc_warnings "$case_build/cc.stderr"
  if has_phase cc-stderr; then
    check_artifact "$(cc_stderr_phase "$case_build/cc.stderr")" \
      "$case_build/cc.stderr"
  elif [[ -s "$case_build/cc.stderr" ]]; then
    cat "$case_build/cc.stderr" >&2
    record_failure "$name generated C compiled with warnings"
  fi

  stderr_raw="$case_build/stderr.raw"
  set +e
  ( X2C_SCOPE_ACCOUNTING=1 "$program" \
      >"$case_build/stdout.actual" 2>"$stderr_raw"
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
  normalize_runtime_lines "$case_build/stderr.actual"
  printf '%d\n' "$run_status" >"$case_build/status.actual"

  has_phase stdout && check_artifact stdout "$case_build/stdout.actual"
  has_phase stderr && check_artifact stderr "$case_build/stderr.actual"
  has_phase status && check_artifact status "$case_build/status.actual"
  if ((run_status != 0)) && ! has_phase status; then
    record_failure "$name program exited $run_status"
  fi
  return 0
}

# The supervisor publishes staged updates only after successful completion.
run_fixture "$3"
printf '%d %d\n' "$failures" "$artifact_count" >"$build/$3/tally"
