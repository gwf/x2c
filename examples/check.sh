#!/usr/bin/env bash
set -euo pipefail

mode=${1:-check}
if [[ "$mode" != check && "$mode" != update ]]; then
  echo "usage: $0 [check|update]" >&2
  exit 2
fi

example_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$example_dir/.." && pwd)
manifest="$example_dir/manifest.txt"
build="$example_dir/build"
x2c=${X2C:-"$root/builds/0/x2c"}
cc=${CC:-cc}
linker_flags=()
if [[ $(uname -s) == Linux ]]; then
  linker_flags+=(-rdynamic)
fi
read -r -a build_linker_flags <<<"${BUILD_LDFLAGS:-}"
linker_flags+=("${build_linker_flags[@]}")

mkdir -p "$build"

declare -A seen
failures=0
classified=0
checked=0
run_count=0
build_count=0
artifact_count=0

record_failure() {
  echo "example failure: $1" >&2
  failures=$((failures + 1))
}

check_stdout() {
  local name=$1
  local actual=$2
  local declared=$3

  if [[ "$declared" == - ]]; then
    if [[ -s "$actual" ]]; then
      cat "$actual" >&2
      record_failure "$name produced unexpected stdout"
    fi
    return
  fi

  local expected="$example_dir/$declared"
  artifact_count=$((artifact_count + 1))
  if [[ "$mode" == update ]]; then
    mkdir -p "$(dirname "$expected")"
    cp "$actual" "$expected"
    return
  fi
  if [[ ! -f "$expected" ]]; then
    record_failure "$name has no expected stdout at $declared"
    return
  fi
  if [[ "$name" == love/maps ]]; then
    # Map traversal order is unspecified; compare every emitted line.
    diff -u <(LC_ALL=C sort "$expected") <(LC_ALL=C sort "$actual") && return
  elif diff -u "$expected" "$actual"; then
    return
  fi
  record_failure "$name stdout differs"
}

# One example, built and run in its own directory. Examples share nothing but
# the package archives the parent builds first, so this is what runs in
# parallel; it reports through files under $case_build rather than the
# terminal, whose interleaving would shred a multi-line diff.
check_example() {
  local name=$1 row_name row_category action arguments stdout note
  IFS='|' read -r row_name row_category action arguments stdout note \
    < <(awk -F '|' -v want="$name" '$1 == want' "$manifest")

  case_build="$build/${name//\//-}"
  output="$case_build/output"
  rm -rf "$case_build"
  mkdir -p "$output"
  exec >"$case_build/log" 2>&1

  program="$case_build/${name##*/}"
  extra_flags=()
  [[ -f "$example_dir/$name.flags" ]] && \
    read -r -a extra_flags <"$example_dir/$name.flags"

  if ((${#extra_flags[@]})); then
    if ! (cd "$root" && "$x2c" build --output "$program" \
        --build-dir "$output" "${extra_flags[@]}" "examples/$name.x") \
        >"$case_build/x2c.stdout" 2>"$case_build/x2c.stderr"; then
      cat "$case_build/x2c.stderr" >&2
      record_failure "$name did not build"
      return 0
    fi
  else
    if ! (cd "$root" && \
        "$x2c" translate --out-dir "$output" "examples/$name.x") \
        >"$case_build/x2c.stdout" 2>"$case_build/x2c.stderr"; then
      cat "$case_build/x2c.stderr" >&2
      record_failure "$name did not translate"
      return 0
    fi
    if ! "$cc" "${linker_flags[@]}" -iquote "$root/include" \
        "$output/${name##*/}.c" -L"$root/builds/0" -lx2c -lm -o "$program" \
        >"$case_build/cc.stdout" 2>"$case_build/cc.stderr"; then
      cat "$case_build/cc.stderr" >&2
      record_failure "$name generated C did not compile"
      return 0
    fi
  fi

  if [[ "$action" == build ]]; then
    build_count=1
    return 0
  fi

  fixture_dir="$example_dir/data/${name//\//-}"
  if [[ -d "$fixture_dir" ]]; then
    cp -R "$fixture_dir/." "$case_build/"
  fi

  run_count=1
  run_args=()
  [[ -n "$arguments" ]] && read -r -a run_args <<<"$arguments"
  set +e
  (cd "$case_build" && "$program" "${run_args[@]}") \
    >"$case_build/stdout.actual" 2>"$case_build/stderr.actual"
  run_status=$?
  set -e

  if ((run_status != 0)); then
    cat "$case_build/stderr.actual" >&2
    record_failure "$name exited $run_status"
  fi
  if [[ -s "$case_build/stderr.actual" ]]; then
    cat "$case_build/stderr.actual" >&2
    record_failure "$name produced unexpected stderr"
  fi
  check_stdout "$name" "$case_build/stdout.actual" "$stdout"
  return 0
}

if [[ ${2:-} == --one ]]; then
  check_example "$3"
  printf '%d %d %d %d\n' "$failures" "$artifact_count" "$run_count" \
    "$build_count" >"$case_build/tally"
  exit 0
fi

python3 "$root/tools/check-gallery-examples.py"

# The Greet example links the teaching package. Third-party applications
# and shortcuts under packages/ belong to the optional package checks.
make -C "$example_dir/packages/greet" build >/dev/null

# The manifest is checked here rather than in a worker: the rules are string
# comparisons, and duplicate detection needs every row at once.
work=()
while IFS= read -r row || [[ -n "$row" ]]; do
  [[ -z "$row" || "$row" == \#* ]] && continue
  if [[ $(awk -F '|' '{ print NF }' <<<"$row") -ne 6 ]]; then
    record_failure "malformed manifest row: $row"
    continue
  fi

  IFS='|' read -r name category action arguments stdout note <<<"$row"
  classified=$((classified + 1))

  if [[ -n ${seen[$name]+present} ]]; then
    record_failure "$name appears more than once in the manifest"
    continue
  fi
  seen[$name]=1

  source="$example_dir/$name.x"
  [[ -f "$source" ]] || record_failure "$name has no .x source"

  case "$category" in
    showcase|optional|external-input|probe|legacy|known-failure) ;;
    *) record_failure "$name has unknown category '$category'" ;;
  esac
  case "$action" in
    run|build|none) ;;
    *) record_failure "$name has unknown check '$action'" ;;
  esac

  if [[ "$category" == showcase && "$action" != run ]]; then
    record_failure "$name is a showcase but is not run"
  fi
  if [[ "$category" == external-input && "$action" != build ]]; then
    record_failure "$name needs external input but is not build-checked"
  fi
  if [[ "$action" != run && -n "$arguments" ]]; then
    record_failure "$name declares arguments without a run check"
  fi
  if [[ "$action" != run && "$stdout" != - ]]; then
    record_failure "$name declares stdout without a run check"
  fi

  if [[ "$category" == optional ]]; then
    [[ "$action" == none ]] || record_failure "$name must use optional package checks"
  fi
  [[ "$action" == none ]] && continue
  checked=$((checked + 1))
  work+=("$name")
done <"$manifest"

if ((${#work[@]})); then
  printf '%s\n' "${work[@]}" | \
    xargs -P "${JOBS:-$(getconf _NPROCESSORS_ONLN)}" -n 1 \
      "$example_dir/check.sh" "$mode" --one || true
fi

for name in "${work[@]}"; do
  tally="$build/${name//\//-}/tally"
  if [[ ! -f "$tally" ]]; then
    record_failure "$name did not report a result"
    continue
  fi
  read -r name_failures name_artifacts name_run name_build <"$tally"
  artifact_count=$((artifact_count + name_artifacts))
  run_count=$((run_count + name_run))
  build_count=$((build_count + name_build))
  ((name_failures)) || continue
  failures=$((failures + name_failures))
  cat "$build/${name//\//-}/log" >&2
done

while IFS= read -r source; do
  name=${source#"$example_dir/"}
  name=${name%.x}
  if [[ -z ${seen[$name]+present} ]]; then
    record_failure "$name.x is not classified"
  fi
done < <({
  find "$example_dir" -maxdepth 1 -type f -name '*.x'
  find "$example_dir"/{love,power,magic,programs,tours} \
    -type f -name '*.x'
} | sort)

if ((failures)); then
  printf 'Examples: %d failure(s), %d classified, %d checked\n' \
    "$failures" "$classified" "$checked" >&2
  exit 1
fi

if [[ "$mode" == update ]]; then
  printf 'Examples: updated %d artifact(s); %d sources classified\n' \
    "$artifact_count" "$classified"
else
  printf 'Examples: %d passed (%d run, %d build-only); %d classified\n' \
    "$checked" "$run_count" "$build_count" "$classified"
fi
