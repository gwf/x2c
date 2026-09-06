#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$CPP_ARGS_LOG"
if [[ ${CPP_FAIL:-0} == 1 ]]; then
  echo "deterministic preprocessor failure" >&2
  exit 23
fi

last=${!#}
exec /bin/cat "$last"
