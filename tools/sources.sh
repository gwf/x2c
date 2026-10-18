#!/bin/sh
# List compiler or runtime entry units, excluding their module members.
set -eu

root=.
area=src
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root|--area)
      [ "$#" -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
      case "$1" in --root) root=$2 ;; --area) area=$2 ;; esac
      shift 2 ;;
    --help|-h)
      echo 'Usage: sources.sh [--root DIRECTORY] [--area src|lib]'
      exit 0 ;;
    *) echo "unknown source-list option: $1" >&2; exit 2 ;;
  esac
done
case "$area" in src|lib) ;; *) echo "unknown source area: $area" >&2; exit 2 ;; esac

directory=${root%/}/$area
directory=${directory#./}
entries=$(
  find -L "$directory" ! -path "$directory" -prune -type f -name '*.x' || exit
  if [ "$area" = src ] && [ -d "$directory/components" ]; then
    find -L "$directory/components" ! -path "$directory/components" \
      -prune -type f -name '*.x' || exit
  fi
  for module in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
    [ -d "$module" ] || continue
    entry=$module/${module##*/}.x
    if [ -f "$entry" ]; then printf '%s\n' "$entry"; fi
  done
)
# Sort path components, so ast/ast.x precedes ast.x.
if [ -n "$entries" ]; then printf '%s\n' "$entries"; fi |
  tr '/' '\001' | LC_ALL=C sort | tr '\001' '/'
