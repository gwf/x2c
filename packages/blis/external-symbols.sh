#!/bin/sh
# Print the symbols a BLIS archive leaves undefined, one per line.
#
#   ./external-symbols.sh <libblis.a>
#
# verify-archive.sh compares this list with a profile, and
# tools/record-blis-profile.sh records it. Sorting uses LC_ALL=C: other
# collations ignore leading underscores and reorder the list. macOS prefixes
# each C symbol with an underscore, which the list omits.
set -eu

strip=0
[ "$(uname -s)" != Darwin ] || strip=1
nm -g --format=posix "${1:?usage: external-symbols.sh <archive>}" |
  awk -v strip="$strip" '
    { name = strip ? substr($1, 2) : $1 }
    $2 == "U" { undefined[name] = 1; next }
    NF >= 2 { defined[name] = 1 }
    END { for (name in undefined) if (!(name in defined)) print name }' |
  LC_ALL=C sort
