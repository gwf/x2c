#!/usr/bin/env bash
# Install a package bundle into a scratch x2c prefix and prove a program that
# imports it builds and runs there, loading every native library the bundle
# carries from the installed bundle.
#
#   packages/tools/check-bundle.sh <bundle.tar.gz> <program.x>
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
bundle=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
program=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
work=$(mktemp -d "${TMPDIR:-/tmp}/x2c-bundle-check.XXXXXX")
trap 'rm -rf "$work"' EXIT

make -C "$ROOT" install PREFIX="$work/x2c" >"$work/install.log"
x2c="$work/x2c/bin/x2c"
"$x2c" install -q "$bundle"

# A shared library must not name a path on the machine that built it.
if [[ $(uname -s) == Darwin ]]; then
  for library in "$work"/x2c/packages/*/native/lib/*.dylib; do
    [[ -e $library ]] || continue
    if otool -L "$library" | tail -n +2 | grep -q /opt/homebrew; then
      echo "check-bundle: $library names a Homebrew path" >&2
      exit 1
    fi
  done
fi

mkdir "$work/app"
cp "$program" "$work/app/"
cd "$work/app"
"$x2c" build -q --output program "$(basename "$program")"
./program
