#!/bin/sh
# usage: tools/run-make-steps.sh <log-dir> <make-option>... -- <target>...
# Run independent Make targets at the same time. Each target writes its whole
# output to <log-dir>/<target>.log. The summary reports each target's status
# and time and shows the end of each failed log; any failure fails the run.
set -u

logs=$1
shift
options=
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
  options="$options $1"
  shift
done
shift

rm -rf "$logs"
mkdir -p "$logs"
for target; do
  (
    start=$(date +%s)
    # The options are Make flags written by the caller, so split them.
    # shellcheck disable=SC2086
    ${MAKE:-make} $options "$target" >"$logs/$target.log" 2>&1
    status=$?
    echo "$status $(($(date +%s) - start))" >"$logs/$target.status"
  ) &
done
wait

failed=
for target; do
  status=unknown seconds=?
  read -r status seconds <"$logs/$target.status" 2>/dev/null
  if [ "$status" = 0 ]; then
    echo "[$target] passed in ${seconds}s"
  else
    echo "[$target] FAILED with status $status in ${seconds}s;" \
      "log: $logs/$target.log"
    tail -n 40 "$logs/$target.log" | sed "s/^/[$target] /"
    failed="$failed $target"
  fi
done
if [ -n "$failed" ]; then
  echo "failed:$failed" >&2
  exit 1
fi
