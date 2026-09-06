#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: audit-source.sh path/to/file.x" >&2
  exit 2
fi

target_path=$1
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ ! -f "$target_path" ]]; then
  echo "not a file: $target_path" >&2
  exit 2
fi
if [[ "$target_path" != *.x ]]; then
  echo "not an x2c source file: $target_path" >&2
  exit 2
fi

narration_pattern='//[[:space:]]*'
narration_pattern+='(function to|convert|check if|return|get|set|create|'
narration_pattern+='handle|skip|remove|extract|add|initialize|free|parse|'
narration_pattern+='write|copy|find|determine|update|open|close)\b'
prose_pattern='load[ -]bearing|it is important to note|note that|keep in mind|'
prose_pattern+='in order to|serves to|\b(leverage|utilize|robust|powerful|'
prose_pattern+='seamless|comprehensive|elegant|clearly|simply|obviously|'
prose_pattern+='just)\b|'
prose_pattern+='this ensures|as mentioned above|we can see|not only.*but also'
legacy_is_not_pattern='!\([^;]*[[:space:]]is[[:space:]]'

compact_control_candidates() {
  awk '
    function leading_width(line, text) {
      text = line
      sub(/[^ ].*$/, "", text)
      return length(text)
    }
    function trim(line) {
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      return line
    }
    { source[NR] = $0 }
    END {
      for (line = 1; line < NR; line++) {
        head = source[line]
        body = source[line + 1]
        if (head !~ /^[ ]*(if|for|while) \(.*\)[ ]*$/) continue
        if (body !~ /^[ ]+[^ #\/].*;[ ]*$/) continue
        if (leading_width(body) <= leading_width(head)) continue
        joined = trim(head) " " trim(body)
        if (leading_width(head) + length(joined) <= 79)
          print line ":" joined
      }
    }
  ' "$1"
}

line_count=$(wc -l <"$target_path" | tr -d ' ')
byte_count=$(wc -c <"$target_path" | tr -d ' ')
include_count=$(rg -c '^#include' "$target_path" || true)
doc_count=$(rg -c '^/\*\*' "$target_path" || true)
block_count=$(rg -c '^/\*([^*]|$)' "$target_path" || true)
line_comment_count=$(rg -c '//' "$target_path" || true)
over_width_count=$(
  awk 'length($0) > 79 { count++ } END { print count + 0 }' "$target_path"
)
max_width=$(
  awk 'length($0) > width { width = length($0) } END { print width + 0 }' \
    "$target_path"
)
non_ascii_count=$(LC_ALL=C rg -c '[^\x00-\x7F]' "$target_path" || true)
narration_count=$(
  rg -i -c "$narration_pattern" "$target_path" || true
)
ruler_count=$(
  rg -c '(^|//|/\*)[[:space:]]*[-=]{8,}' "$target_path" || true
)
prose_count=$(
  rg -i -c "$prose_pattern" "$target_path" || true
)
legacy_is_not_count=$(
  rg -c "$legacy_is_not_pattern" "$target_path" || true
)
compact_control_output=$(compact_control_candidates "$target_path")
if [[ -n "$compact_control_output" ]]; then
  compact_control_count=$(printf '%s\n' "$compact_control_output" | wc -l)
  compact_control_count=${compact_control_count//[[:space:]]/}
else
  compact_control_count=0
fi

printf 'file: %s\n' "$target_path"
printf 'lines: %s\n' "$line_count"
printf 'bytes: %s\n' "$byte_count"
printf 'includes: %s\n' "${include_count:-0}"
printf 'doc_comment_starts: %s\n' "${doc_count:-0}"
printf 'plain_block_starts: %s\n' "${block_count:-0}"
printf 'line_comment_lines: %s\n' "${line_comment_count:-0}"
printf 'over_79_columns: %s\n' "$over_width_count"
printf 'maximum_width: %s\n' "$max_width"
printf 'non_ascii_lines: %s\n' "${non_ascii_count:-0}"
printf 'narration_candidates: %s\n' "${narration_count:-0}"
printf 'decorated_ruler_candidates: %s\n' "${ruler_count:-0}"
printf 'prohibited_prose_candidates: %s\n' "${prose_count:-0}"
printf 'legacy_negated_is_candidates: %s\n' "${legacy_is_not_count:-0}"
printf 'short_control_flow_wrap_candidates: %s\n' "$compact_control_count"

echo
echo "compact source-style findings:"
python3 "$script_dir/source_style.py" "$target_path"

if ((over_width_count)); then
  echo
  echo "raw lines over 79 columns (see classified findings above):"
  awk 'length($0) > 79 { printf "%d:%d:%s\n", NR, length($0), $0 }' \
    "$target_path"
fi

if [[ -n "${narration_count:-}" && "$narration_count" != 0 ]]; then
  echo
  echo "narration candidates:"
  rg -n -i "$narration_pattern" "$target_path"
fi

if [[ -n "${prose_count:-}" && "$prose_count" != 0 ]]; then
  echo
  echo "prohibited prose candidates:"
  rg -n -i "$prose_pattern" "$target_path"
fi

if [[ -n "${legacy_is_not_count:-}" && "$legacy_is_not_count" != 0 ]]; then
  echo
  echo "legacy negated is candidates:"
  rg -n "$legacy_is_not_pattern" "$target_path"
fi

if ((compact_control_count)); then
  echo
  echo "short control-flow wrap candidates:"
  printf '%s\n' "$compact_control_output"
fi
