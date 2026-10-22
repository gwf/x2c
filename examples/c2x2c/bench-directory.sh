#!/bin/bash
# Manual benchmark driver; keep file discovery outside the C implementations.
set -eo pipefail
if [ "$#" -ne 3 ]; then
  printf 'Usage: %s per-file|aggregate PROGRAM DIRECTORY\n' "$0" >&2
  exit 1
fi
mode=$1
program=$2
root=$3
if [ ! -d "$root" ]; then
  printf 'Not a directory: %s\n' "$root" >&2
  exit 1
fi
find_files() {
  # Follow file symlinks, but not child directory symlinks, like Path.walk/is_file.
  find -H "$root" \( -type f -o \( -type l -exec test -f {} \; \) \) -print0
}
case "$mode" in
  per-file) find_files | xargs -0 -n 1 "$program" ;;
  aggregate)
    files=()
    while IFS= read -r -d '' file_path; do files+=("$file_path"); done < <(find_files)
    exec "$program" "${files[@]}"
    ;;
  *) printf 'Unknown mode: %s\n' "$mode" >&2; exit 1 ;;
esac
