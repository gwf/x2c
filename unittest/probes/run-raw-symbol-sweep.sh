#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/raw-symbol-sweep"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

# The translate flags a source carries in both symbol modes. The parent needs
# them to classify a live-symbol fixture; the worker needs them to run.
source_flags() {
  local src=$1
  flags=()
  case "$src" in
    "$ROOT"/unittest/probes/*) flags=(-I "$ROOT/unittest/probes") ;;
  esac
  if [[ -f "${src%.x}.flags" ]]; then
    local extra
    read -r -a extra <"${src%.x}.flags"
    flags+=("${extra[@]}")
  fi
}

# One source, translated both ways into its own scratch pair so the sweep can
# run as wide as the machine allows.
if [[ ${1:-} == --one ]]; then
  src=$2
  base=$(basename "$src" .x)
  key=${src#"$ROOT/"}
  key=${key//\//_}
  work="$BUILD/work/$key"
  fail() {
    : >"$BUILD/failed/$key"
    exit 1
  }
  rm -rf "$work"
  mkdir -p "$work/cpp" "$work/raw"
  source_flags "$src"
  set +e
  "$X2C" translate --cpp-symbols "${flags[@]+"${flags[@]}"}" \
    --out-dir "$work/cpp" "$src" >/dev/null 2>&1
  cpp_status=$?
  "$X2C" translate "${flags[@]+"${flags[@]}"}" \
    --out-dir "$work/raw" "$src" >/dev/null 2>&1
  raw_status=$?
  set -e
  if [ "$cpp_status" -ne 0 ] || [ "$raw_status" -ne 0 ]; then
    echo "required translation failed (CPP=$cpp_status raw=$raw_status):" \
      "$src" >&2
    fail
  fi
  if ! diff -q "$work/cpp/$base.c" "$work/raw/$base.c" >/dev/null ||
     ! diff -q "$work/cpp/$base.h" "$work/raw/$base.h" >/dev/null; then
    echo "output mismatch: $src" >&2
    fail
  fi
  exit 0
fi

rm -rf "$BUILD"
mkdir -p "$BUILD/failed"

total=0
required=0
excluded=0
failures=0
declare -A exclusions

while IFS='|' read -r name category action arguments stdout note; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  if [[ "$action" == none ]]; then
    exclusions["$ROOT/examples/$name.x"]="$category: $note"
  fi
done <"$ROOT/examples/manifest.txt"

for expected in "$ROOT"/unittest/compiler-fixtures/*.compile-status; do
  [[ -e "$expected" ]] || continue
  if [[ $(<"$expected") != 0 ]]; then
    name=$(basename "$expected" .compile-status)
    exclusions["$ROOT/unittest/compiler-fixtures/$name.x"]=$(
      printf '%s' "negative compiler fixture: expected translation failure"
    )
  fi
done
for phases in "$ROOT"/unittest/compiler-fixtures/*.phases; do
  [[ -e "$phases" ]] || continue
  if [[ $(tr -d '[:space:]' <"$phases") == tokens ]]; then
    name=$(basename "$phases" .phases)
    exclusions["$ROOT/unittest/compiler-fixtures/$name.x"]=$(
      printf '%s' "token-only fixture: full translation is outside its contract"
    )
  fi
done

sources=()
for src in "$ROOT"/src/*.x "$ROOT"/lib/*.x "$ROOT"/examples/*.x \
    "$ROOT"/unittest/*.x "$ROOT"/unittest/compiler-fixtures/*.x \
    "$ROOT"/unittest/probes/*.x "$ROOT"/unittest/benchmarks/*.x; do
  total=$((total + 1))
  relative=${src#"$ROOT/"}
  if [[ -n ${exclusions[$src]+classified} ]]; then
    echo "raw symbol exclusion: $relative -- ${exclusions[$src]}"
    excluded=$((excluded + 1))
    continue
  fi
  source_flags "$src"
  if [[ " ${flags[*]} " == *" --live-symbols "* ]]; then
    echo "raw symbol exclusion: $relative -- live-symbol fixture: " \
      "raw and CPP symbol modes conflict with its required flag"
    excluded=$((excluded + 1))
    continue
  fi
  required=$((required + 1))
  sources+=("$src")
done

# A failing worker reports one line and leaves a marker, so the output stays
# readable without buffering and the tally does not depend on xargs status.
if ((required)); then
  printf '%s\n' "${sources[@]}" | \
    xargs -P "${JOBS:-$(getconf _NPROCESSORS_ONLN)}" -n 1 \
      "$ROOT/unittest/probes/run-raw-symbol-sweep.sh" --one || true
  failures=$(find "$BUILD/failed" -type f | grep -c '' || true)
fi

echo "raw symbol sweep: $required required, $excluded classified exclusions," \
  "$failures failures ($total total)"
[ "$failures" -eq 0 ]
