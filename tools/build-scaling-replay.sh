#!/usr/bin/env bash
# Replay the build cost score over past commits.
#
#   tools/build-scaling-replay.sh                # 10 commits across dev
#   tools/build-scaling-replay.sh C1 C2 ...      # the named commits
#
# Each commit builds its own stage 0 in a fresh copy under /tmp, then counts
# the CPU cycles of three stage builds as tools/build-scaling.py does. The
# CSV lists commits oldest first; score is cycles per source line with the
# newest commit at 100. Cycle counts need macOS /usr/bin/time -l. Commits
# build two at a time; ten take about half an hour.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/x2c-build-replay.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

if [[ $# -eq 0 ]]; then
  history=($(git -C "$ROOT" log --first-parent --format=%h origin/dev))
  count=${#history[@]}
  set --
  for i in 0 1 2 3 4 5 6 7 8 9; do
    set -- "$@" "${history[$((i * (count - 1) / 9))]}"
  done
fi

score() {
  local commit=$1 tree=$WORK/$1 cycles=()
  mkdir -p "$tree"
  git -C "$ROOT" archive "$commit" | tar -x -C "$tree"
  cd "$tree"
  env -u MAKEFLAGS -u MAKELEVEL make build-safe >build.log 2>&1
  mkdir -p builds/8
  cp builds/0/x2c builds/8/x2c
  printf '%s\n' '#!/bin/sh' \
    'exec /usr/bin/time -l "$@" 2>"$(mktemp "$COUNT_DIR/count.XXXXXX")"' \
    >counted
  chmod +x counted
  for sample in 1 2 3; do
    mkdir -p "builds/9$sample" "counts$sample"
    COUNT_DIR=$tree/counts$sample env -u MAKEFLAGS -u MAKELEVEL -u X2C_HOME \
      make -s -j1 -f ../stage.mk -C "builds/9$sample" \
      "X2C_COMPILER=$tree/counted ../8/x2c" "CC=$tree/counted cc" \
      >"stage$sample.log" 2>&1
    cycles+=("$(cat "counts$sample"/* |
      awk '/cycles elapsed/ { s += $1 } END { printf "%.0f", s }')")
  done
  local median lines
  median=$(printf '%s\n' "${cycles[@]}" | sort -n | sed -n 2p)
  lines=$(find src lib -maxdepth 1 -type f \
    \( -name '*.x' -o -name '*.xmacro' -o -name '*.xlisp' \) \
    ! -name x2c.x -exec cat {} + | wc -l)
  echo "$(git -C "$ROOT" log -1 --format='%ct %h %cs' "$commit") $lines" \
    "$median"
}
export -f score
export ROOT WORK

printf '%s\n' "$@" | xargs -P 2 -I{} bash -c 'score {}' >"$WORK/rows"
sort -n "$WORK/rows" | awk '
  { commit[NR] = $2; date[NR] = $3; lines[NR] = $4; per[NR] = $5 / $4 }
  END {
    print "commit,date,lines,cycles_per_line,score"
    for (i = 1; i <= NR; i++)
      printf "%s,%s,%d,%.0f,%.0f\n", commit[i], date[i], lines[i], per[i],
        100 * per[i] / per[NR]
  }'
