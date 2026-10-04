# Runs independent checks or builds concurrently. Source this file, start
# each job with parallel_start, and finish with parallel_wait. Each job
# writes its own log; parallel_wait prints the logs in start order, repeats
# the failed jobs' names, and fails when any job failed.

parallel_logs=$(mktemp -d "${TMPDIR:-/tmp}/x2c-parallel.XXXXXX")
parallel_jobs=

# Stops unfinished jobs when the caller is interrupted.
parallel_stop() {
  for parallel_job in $parallel_jobs; do
    kill "${parallel_job%%:*}" 2>/dev/null || :
  done
  rm -rf "$parallel_logs"
}
trap 'parallel_stop; exit 1' HUP INT TERM

# parallel_start NAME COMMAND [ARG...] runs COMMAND in the background.
parallel_start() {
  parallel_name=$1
  shift
  "$@" >"$parallel_logs/$parallel_name.log" 2>&1 &
  parallel_jobs="$parallel_jobs $!:$parallel_name"
}

parallel_wait() {
  parallel_failed=
  for parallel_job in $parallel_jobs; do
    parallel_name=${parallel_job#*:}
    if wait "${parallel_job%%:*}"; then
      cat "$parallel_logs/$parallel_name.log"
    else
      parallel_failed="$parallel_failed $parallel_name"
      echo "--- $parallel_name failed:" >&2
      cat "$parallel_logs/$parallel_name.log" >&2
    fi
  done
  parallel_jobs=
  rm -rf "$parallel_logs"
  if [ -n "$parallel_failed" ]; then
    echo "failed:$parallel_failed" >&2
    return 1
  fi
}
