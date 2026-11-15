#!/usr/bin/env bash
# Exercise installer selection and replacement without building a compiler.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/x2c-update-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
PREFIX="$WORK/prefix's files"
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
INSTALL="$ROOT/site/public/install.sh"
export X2C_PREFIX="$PREFIX" X2C_RELEASES="file://$WORK/releases"
export X2C_VERSION_URL="file://$WORK/latest"
unset X2C_VERSION X2C_RELEASE_TAG
mkdir -p "$WORK/releases"
fixture() {
  local version=$1 asset="x2c-$1-$PLATFORM.tar.gz"
  mkdir -p "$WORK/tree/x2c/bin" "$WORK/tree/x2c/packages" "$WORK/releases/v$version"
  printf '#!/bin/sh\necho "x2c %s"\n' "$version" >"$WORK/tree/x2c/bin/x2c"
  chmod +x "$WORK/tree/x2c/bin/x2c"
  printf 'x2c-native-v1 fixture\n0 0 bin/x2c\n' >"$WORK/tree/x2c/.x2c-install-manifest"
  tar -czf "$WORK/releases/v$version/$asset" -C "$WORK/tree" x2c
  (cd "$WORK/releases/v$version" && shasum -a 256 "$asset" >"$asset.sha256")
  rm -rf "$WORK/tree"
}
reject() {
  if "$@" >"$WORK/out" 2>"$WORK/err"; then
    echo "unexpected success: $*" >&2; exit 1
  fi
}
fixture 1.2.3
fixture 1.10.0
printf '1.2.3\n' >"$WORK/latest"
sh "$INSTALL" >"$WORK/out"
grep -q '^kind=release$' "$PREFIX/.x2c-install-origin"
[ "$("$PREFIX/bin/x2c" --version)" = 'x2c 1.2.3' ]
# A current installation needs only the version pointer, not an archive.
mv "$WORK/releases/v1.2.3" "$WORK/releases/hidden"
sh "$INSTALL" --update --prefix "$PREFIX" >"$WORK/out"
grep -q 'already up to date' "$WORK/out"
mv "$WORK/releases/hidden" "$WORK/releases/v1.2.3"
# Check mode reads only the pointer, even if no archive exists.
printf '2.0.0\n' >"$WORK/latest"
sh "$INSTALL" --update --prefix "$PREFIX" --check >"$WORK/out"
grep -q '2.0.0 is available' "$WORK/out"
[ ! -e "$PREFIX.update-lock" ]
[ "$("$PREFIX/bin/x2c" --version)" = 'x2c 1.2.3' ]
# Updater ignores installer environment defaults and retains packages.
mkdir -p "$PREFIX/packages/local"
printf 'preserved\n' >"$PREFIX/packages/local/source.x"
printf '1.10.0\n' >"$WORK/latest"
X2C_VERSION=9.0.0 X2C_RELEASES=file:///wrong X2C_VERSION_URL=file:///wrong \
  sh "$INSTALL" --update --prefix "$PREFIX" >"$WORK/out"
[ "$("$PREFIX/bin/x2c" --version)" = 'x2c 1.10.0' ]
grep -q preserved "$PREFIX/packages/local/source.x"
# A normal update never downgrades; an explicit version can.
printf '1.2.3\n' >"$WORK/latest"
sh "$INSTALL" --update --prefix "$PREFIX" >"$WORK/out"
grep -q 'no downgrade' "$WORK/out"
sh "$INSTALL" --update --prefix "$PREFIX" --version 1.2.3 >"$WORK/out"
[ "$("$PREFIX/bin/x2c" --version)" = 'x2c 1.2.3' ]
# Extra files are preserved by refusing replacement.
printf 'mine\n' >"$PREFIX/private-file"
reject sh "$INSTALL" --update --prefix "$PREFIX" --version 1.10.0
grep -q 'unowned file' "$WORK/err"
grep -q mine "$PREFIX/private-file"
rm "$PREFIX/private-file"
# Binary package incompatibility is reported before replacing the compiler.
printf '{"x2c_version":"1.2.3"}\n' >"$PREFIX/packages/local/BUNDLE.json"
reject sh "$INSTALL" --update --prefix "$PREFIX" --version 1.10.0
grep -q 'native package local' "$WORK/err"
[ "$("$PREFIX/bin/x2c" --version)" = 'x2c 1.2.3' ]
printf '{"x2c_version":"1.2.3","x2c_version":"1.10.0"}\n' >"$PREFIX/packages/local/BUNDLE.json"
reject sh "$INSTALL" --update --prefix "$PREFIX" --version 1.10.0
grep -q 'native package local' "$WORK/err"
printf '{}\n' >"$PREFIX/packages/local/BUNDLE.json"
reject sh "$INSTALL" --update --prefix "$PREFIX" --version 1.10.0
grep -q 'x2c unknown' "$WORK/err"
rm "$PREFIX/packages/local/BUNDLE.json"
# Origin is explicit; source and legacy installations are never guessed.
printf 'kind=source\nsource=/a checkout/it\047s source\n' >"$PREFIX/.x2c-install-origin"
reject sh "$INSTALL" --update --prefix "$PREFIX"
grep -q 'make -C' "$WORK/err"
reject sh "$INSTALL" --version 1.10.0
grep -q 'replace-origin' "$WORK/err"
rm "$PREFIX/.x2c-install-origin"
reject sh "$INSTALL" --update --prefix "$PREFIX"
grep -q 'origin is unknown' "$WORK/err"
sh "$INSTALL" --replace-origin --version 1.10.0 >"$WORK/out"
# Wrapper-owned prefix and installation origin cannot be redirected.
reject sh "$INSTALL" --update --prefix "$PREFIX" --prefix "$WORK/other"
reject sh "$INSTALL" --update --prefix "$PREFIX" --replace-origin
# Unfinished updates block mutation and name their recovery instructions.
mkdir "$PREFIX.update-lock"
reject sh "$INSTALL" --update --prefix "$PREFIX"
grep -q 'recover.sh' "$WORK/err"
rmdir "$PREFIX.update-lock"
# Replacement failures and interruption restore the old compiler and packages.
mkdir "$WORK/mock-bin"
cat >"$WORK/mock-bin/mv" <<'EOF_MV'
#!/bin/sh
case "$UPDATE_FAILURE:$1" in
  fail:*/staged) exit 1 ;;
  signal:*/staged) kill -TERM "$PPID"; exit 1 ;;
esac
/bin/mv "$@"
case "$UPDATE_FAILURE:$1" in
  kill:*.previous/packages) kill -KILL "$PPID" ;;
esac
EOF_MV
chmod +x "$WORK/mock-bin/mv"
for failure in fail signal; do
  reject env PATH="$WORK/mock-bin:$PATH" UPDATE_FAILURE="$failure" \
    sh "$INSTALL" --update --prefix "$PREFIX" --version 1.2.3
  [ "$("$PREFIX/bin/x2c" --version)" = 'x2c 1.10.0' ]
  grep -q preserved "$PREFIX/packages/local/source.x"
  [ ! -e "$PREFIX.update-lock" ]
  [ ! -e "$PREFIX.previous" ]
done
reject env PATH="$WORK/mock-bin:$PATH" UPDATE_FAILURE=kill \
  sh "$INSTALL" --update --prefix "$PREFIX" --version 1.2.3
[ -f "$PREFIX.update-lock/recover.sh" ]
sh "$PREFIX.update-lock/recover.sh"
[ "$("$PREFIX/bin/x2c" --version)" = 'x2c 1.10.0' ]
grep -q preserved "$PREFIX/packages/local/source.x"
[ ! -e "$PREFIX.update-lock" ]
[ ! -e "$PREFIX.previous" ]
# Invalid remote version cannot become a URL or path component.
printf '../escape\n' >"$WORK/latest"
reject sh "$INSTALL" --update --prefix "$PREFIX"
grep -q 'invalid release version' "$WORK/err"
[ ! -e "$PREFIX.update-lock" ]
echo 'compiler update: passed'
