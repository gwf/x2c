#!/usr/bin/env bash
set -euo pipefail

tool=$(basename "$0")
phase=link
if [[ $tool == *ar* ]]; then
  phase=archive
else
  for argument in "$@"; do
    if [[ $argument == -c ]]; then
      phase=compile
      break
    fi
  done
fi

{
  printf 'BEGIN %s\n' "$phase"
  printf '%s\n' "$@"
} >>"$TOOL_ARGS_LOG"

if [[ -n ${TOOL_DELAY_PHASE:-} && $TOOL_DELAY_PHASE == "$phase" ]]; then
  sleep "${TOOL_DELAY_SECONDS:-1}"
fi

printf 'END %s\n' "$phase" >>"$TOOL_ARGS_LOG"

if [[ ${TOOL_FAIL_PHASE:-} == "$phase" ]]; then
  printf 'deterministic %s failure\n' "$phase" >&2
  exit "${TOOL_FAIL_STATUS:-23}"
fi

output=
if [[ $phase == archive ]]; then
  output=${2:?archive output missing}
else
  previous=
  for argument in "$@"; do
    if [[ $previous == -o ]]; then
      output=$argument
      break
    fi
    previous=$argument
  done
fi

if [[ -n $output ]]; then
  if [[ $phase == link && -n ${TOOL_PROGRAM_LOG:-} ]]; then
    {
      printf '#!/usr/bin/env bash\n'
      printf 'printf "%%s\\\\n" "$@" >"$TOOL_PROGRAM_LOG"\n'
      printf 'exit "${TOOL_PROGRAM_STATUS:-0}"\n'
    } >"$output"
    chmod +x "$output"
  else
    : >"$output"
  fi
fi
