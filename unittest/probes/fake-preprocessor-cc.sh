#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$CPP_ARGS_LOG"
if [[ ${CPP_FAIL:-0} == 1 ]]; then
  echo "deterministic preprocessor failure" >&2
  exit 23
fi

# The unit arrives as the `-include` file; the main input is empty stdin.
while (($#)) && [[ $1 != -include ]]; do shift; done
exec /bin/cat "$2"
