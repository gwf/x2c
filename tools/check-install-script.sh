#!/usr/bin/env bash
# Run site/public/install.sh against a local release layout built from the
# current tree, then prove the installed compiler builds a program and
# installs a package. Usage: tools/check-install-script.sh [work-dir]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${1:-"$ROOT/unittest/build/install-script"}
rm -rf "$WORK"
mkdir -p "$WORK/releases"

version=$("$ROOT/builds/0/x2c" --version | cut -d' ' -f2)
platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
asset="x2c-$version-$platform.tar.gz"

make -C "$ROOT" dist PREFIX=/opt/x2c >"$WORK/dist.log" 2>&1
mkdir -p "$WORK/releases/v$version"
cp "$ROOT/dist/$asset" "$ROOT/dist/$asset.sha256" "$WORK/releases/v$version/"
printf '%s\n' "$version" >"$WORK/releases/x2c-version.txt"

unset X2C_RELEASE_TAG X2C_VERSION
export X2C_PREFIX="$WORK/prefix" X2C_RELEASES="file://$WORK/releases"
export X2C_VERSION_URL="file://$WORK/releases/x2c-version.txt"
sh "$ROOT/site/public/install.sh" >"$WORK/install.stdout"
grep -q "installed x2c $version" "$WORK/install.stdout"
[[ -x "$WORK/prefix/bin/x2c" ]] || exit 1
# The home carries prelude component sources, not the compiler.
[[ ! -e "$WORK/prefix/src/main.x" ]] || exit 1

# The installed compiler stands alone: no checkout on PATH.
export PATH="$WORK/prefix/bin:/usr/bin:/bin"
[[ "$(x2c env home)" == "$WORK/prefix" ]] || exit 1
x2c run -q "$WORK/prefix/examples/foreach.x" >"$WORK/foreach.stdout"
grep -q "v = 3" "$WORK/foreach.stdout"

# A package survives a re-run of the installer.
x2c install -q "$ROOT/examples/packages/greet"
sh "$ROOT/site/public/install.sh" --version "$version" >/dev/null
[[ "$(x2c list)" == "greet - source" ]] || exit 1
x2c run -q "$ROOT/examples/power/greet-client.x" >"$WORK/greet.stdout"
grep -q "ping ping ping" "$WORK/greet.stdout"

# The installed command uses its own prefix and recorded feed, not overrides.
X2C_HOME="$ROOT" X2C_VERSION=9.9.9 X2C_RELEASES=file:///wrong \
  X2C_VERSION_URL=file:///wrong x2c update --check >"$WORK/update-check.stdout"
grep -q 'already up to date' "$WORK/update-check.stdout"
x2c update --version "$version" >"$WORK/update.stdout"
[[ "$(x2c list)" == "greet - source" ]] || exit 1
grep -q '^kind=release$' "$WORK/prefix/.x2c-install-origin"

# Candidates sharing a version select distinct bytes, never the vVERSION path.
for candidate in candidate-one candidate-two; do
  mkdir -p "$WORK/candidate-tree" "$WORK/releases/$candidate"
  tar -xzf "$ROOT/dist/$asset" -C "$WORK/candidate-tree"
  tree=$(find "$WORK/candidate-tree" -mindepth 1 -maxdepth 1 -type d)
  printf '%s\n' "$candidate" >"$tree/candidate-test.txt"
  printf '0 0 candidate-test.txt\n' >>"$tree/.x2c-install-manifest"
  tar -czf "$WORK/releases/$candidate/$asset" \
    -C "$WORK/candidate-tree" "$(basename "$tree")"
  (cd "$WORK/releases/$candidate" && shasum -a 256 "$asset" >"$asset.sha256")
  X2C_RELEASE_TAG="$candidate" sh "$ROOT/site/public/install.sh" >/dev/null
  [[ "$(cat "$WORK/prefix/candidate-test.txt")" == "$candidate" ]] || exit 1
  [[ "$(x2c list)" == "greet - source" ]] || exit 1
  rm -rf "$WORK/candidate-tree"
done
# Selecting the earlier candidate still installs its original bytes.
X2C_RELEASE_TAG=candidate-one sh "$ROOT/site/public/install.sh" \
  --version "$version" >/dev/null
[[ "$(cat "$WORK/prefix/candidate-test.txt")" == candidate-one ]] || exit 1

# A checksum-valid but unusable compiler must leave the installation intact.
mkdir -p "$WORK/unusable-tree/x2c/bin" "$WORK/releases/unusable"
printf 'unusable\n' >"$WORK/unusable-tree/x2c/.x2c-install-manifest"
printf '#!/bin/sh\necho unsupported-host >&2\nexit 1\n' \
  >"$WORK/unusable-tree/x2c/bin/x2c"
chmod +x "$WORK/unusable-tree/x2c/bin/x2c"
tar -czf "$WORK/releases/unusable/$asset" -C "$WORK/unusable-tree" x2c
(cd "$WORK/releases/unusable" && shasum -a 256 "$asset" >"$asset.sha256")
if X2C_RELEASE_TAG=unusable sh "$ROOT/site/public/install.sh" \
    --version "$version" >/dev/null 2>"$WORK/unusable.stderr"; then
  echo "install.sh accepted an unusable compiler" >&2
  exit 1
fi
grep -q "unsupported-host" "$WORK/unusable.stderr"
[[ "$(x2c --version)" == "x2c $version" ]] || exit 1
[[ "$(cat "$WORK/prefix/candidate-test.txt")" == candidate-one ]] || exit 1
[[ "$(x2c list)" == "greet - source" ]] || exit 1
x2c run -q "$ROOT/examples/power/greet-client.x" >"$WORK/preserved-greet.stdout"
grep -q "ping ping ping" "$WORK/preserved-greet.stdout"
# A failed fresh install must not leave an unusable installation behind.
if X2C_RELEASE_TAG=unusable sh "$ROOT/site/public/install.sh" \
    --version "$version" --prefix "$WORK/fresh" >/dev/null 2>&1; then
  echo "install.sh accepted an unusable compiler for a fresh install" >&2
  exit 1
fi
[[ ! -e "$WORK/fresh" ]] || exit 1

# A bad checksum is refused before anything is replaced.
printf 'bad\n' >"$WORK/releases/v$version/$asset.sha256"
if sh "$ROOT/site/public/install.sh" --version "$version" \
    >/dev/null 2>"$WORK/bad.stderr"; then
  echo "install.sh accepted a bad checksum" >&2
  exit 1
fi
grep -q "checksum mismatch" "$WORK/bad.stderr"
[[ "$(x2c list)" == "greet - source" ]] || exit 1

echo "install script: passed"
