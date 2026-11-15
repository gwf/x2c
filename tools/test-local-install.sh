#!/bin/sh
# Optional focused check of source install defaults and provenance.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/x2c-local-install.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
work=$(cd "$work" && pwd -P)
make install DESTDIR="$work/staging" >"$work/install.log" 2>&1 || {
  cat "$work/install.log" >&2; exit 1;
}
prefix="$work/staging$HOME/.local/x2c"
test -x "$prefix/bin/x2c"
grep -Fx 'kind=source' "$prefix/.x2c-install-origin"
grep -Fx "source=$root" "$prefix/.x2c-install-origin"
cmp site/public/install.sh "$prefix/etc/install.sh"
test -x "$prefix/libexec/x2c/x2c-update"
status=0
"$prefix/bin/x2c" update --check >"$work/update.log" 2>&1 || status=$?
test "$status" = 1
grep -F "this compiler was installed from $root" "$work/update.log"
grep -F "PREFIX='$prefix'" "$work/update.log"
"$prefix/bin/x2c" help update >"$work/update-help.log"
grep -F 'Usage: x2c update' "$work/update-help.log"
printf 'personal file\n' >"$prefix/personal.txt"
mkdir -p "$prefix/packages/personal"
printf 'package\n' >"$prefix/packages/personal/keep.txt"
builds/0/x2c script etc/x2c-payload.x install --prefix "$prefix" \
  >"$work/reinstall.log" 2>&1 || { cat "$work/reinstall.log" >&2; exit 1; }
grep -Fx 'personal file' "$prefix/personal.txt"
grep -Fx 'package' "$prefix/packages/personal/keep.txt"
grep -Fx "source=$root" "$prefix/.x2c-install-origin"
builds/0/x2c script etc/x2c-payload.x install --prefix "$work/distribution" \
  --distribution >"$work/dist.log" 2>&1 || {
    cat "$work/dist.log" >&2; exit 1;
  }
test ! -e "$work/distribution/.x2c-install-origin"
cmp site/public/install.sh "$work/distribution/etc/install.sh"
builds/0/x2c script etc/x2c-payload.x uninstall --prefix "$prefix"
test ! -e "$prefix/.x2c-install-origin"
test ! -e "$prefix/bin/x2c"
test -f "$prefix/personal.txt"
test -f "$prefix/packages/personal/keep.txt"
printf 'local install: passed\n'
