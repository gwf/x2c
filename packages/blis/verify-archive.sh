#!/bin/sh
# Check the built BLIS archive against this platform's recorded profile.
#
#   ./verify-archive.sh PROFILE-<system>-<machine>.json <blis prefix>
#
# The Makefile calls this rather than spelling the comparisons out in a
# recipe: a long continued recipe line is where Apple's make 3.81 on x86_64
# loses bytes. tools/record-blis-profile.sh writes a profile.
set -eu

profile=${1:?usage: verify-archive.sh <profile> <prefix>}
prefix=${2:?missing blis prefix}
archive="$prefix/lib/libblis.a"
header="$prefix/include/blis/blis.h"

fail() { echo "blis profile: $*" >&2; exit 1; }

expected=$(jq -r '.header_sha256' "$profile")
actual=$(shasum -a 256 "$header" | cut -d' ' -f1)
[ "$actual" = "$expected" ] || fail "blis.h is $actual, not $expected"

expected=$(jq -r '.archive.members' "$profile")
actual=$(ar -t "$archive" | wc -l | tr -d ' ')
[ "$actual" = "$expected" ] || fail "$actual members, not $expected"

# Both sides sort under LC_ALL=C. Without it the collation follows the
# caller's locale: en_US.UTF-8 ignores the leading underscores, so
# _DefaultRuneLocale moves and the comparison fails on a machine whose
# LC_COLLATE is not C.
work=$(mktemp -d "${TMPDIR:-/tmp}/x2c-blis-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT
export LC_ALL=C

if [ "$(uname -s)" = Darwin ]; then
  symbol='substr($1, 2)'
else
  symbol='$1'
fi
nm -g --format=posix "$archive" |
  awk "\$2 == \"U\" {print $symbol}" | sort -u >"$work/undefined"
nm -g --format=posix "$archive" |
  awk "\$2 != \"U\" && NF >= 2 {print $symbol}" | sort -u >"$work/defined"
comm -23 "$work/undefined" "$work/defined" >"$work/external"
jq -r '.archive.external_undefined_symbols[]' "$profile" |
  sort -u >"$work/expected"
diff -u "$work/expected" "$work/external"
