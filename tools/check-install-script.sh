#!/usr/bin/env bash
# Run site/public/install.sh against a local release layout built from the
# current tree, then prove the installed compiler builds a program and
# installs a package. Usage: tools/check-install-script.sh [work-dir]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${1:-"$ROOT/unittest/build/install-script"}
rm -rf "$WORK"
mkdir -p "$WORK/releases/latest"

version=$("$ROOT/builds/0/x2c" --version | cut -d' ' -f2)
platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
asset="x2c-$version-$platform.tar.gz"

make -C "$ROOT" dist PREFIX=/opt/x2c >"$WORK/dist.log" 2>&1
mkdir -p "$WORK/releases/v$version"
cp "$ROOT/dist/$asset" "$ROOT/dist/$asset.sha256" "$WORK/releases/v$version/"
printf '%s\n' "$version" >"$WORK/releases/latest/x2c-version.txt"

export X2C_PREFIX="$WORK/prefix" X2C_RELEASES="file://$WORK/releases"
sh "$ROOT/site/public/install.sh" >"$WORK/install.stdout"
grep -q "installed x2c $version" "$WORK/install.stdout"
[[ -x "$WORK/prefix/bin/x2c" ]]
[[ ! -d "$WORK/prefix/src" ]]

# The installed compiler stands alone: no checkout on PATH.
export PATH="$WORK/prefix/bin:/usr/bin:/bin"
[[ "$(x2c env home)" == "$WORK/prefix" ]]
x2c run -q "$WORK/prefix/examples/foreach.x" >"$WORK/foreach.stdout"
grep -q "v = 3" "$WORK/foreach.stdout"

# A package survives a re-run of the installer.
x2c install -q "$ROOT/examples/packages/greet"
sh "$ROOT/site/public/install.sh" --version "$version" >/dev/null
[[ "$(x2c list)" == "greet - source" ]]
x2c run -q "$ROOT/examples/power/greet-client.x" >"$WORK/greet.stdout"
grep -q "ping ping ping" "$WORK/greet.stdout"

# A bad checksum is refused before anything is replaced.
printf 'bad\n' >"$WORK/releases/v$version/$asset.sha256"
if sh "$ROOT/site/public/install.sh" --version "$version" \
    >/dev/null 2>"$WORK/bad.stderr"; then
  echo "install.sh accepted a bad checksum" >&2
  exit 1
fi
grep -q "checksum mismatch" "$WORK/bad.stderr"
[[ "$(x2c list)" == "greet - source" ]]

echo "install script: passed"
