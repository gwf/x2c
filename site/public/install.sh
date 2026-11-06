#!/bin/sh
# Install a released x2c into a dedicated prefix.
#
# The script downloads the compiler archive x2c-VERSION-PLATFORM.tar.gz and
# its .sha256 checksum file from the x2c release on GitHub
# (https://github.com/gwf/x2c/releases). Both files come from the same
# release, so the checksum detects a damaged download; it does not prove who
# published the archive. The archive unpacks into $HOME/.local/x2c, or the
# directory that --prefix names. Apart from temporary files, nothing outside
# that directory changes, and no shell profile is edited.
#
# To upgrade, run the script again; installed packages are kept. To
# uninstall, remove the prefix directory and the PATH line that names it.
usage() {
  cat <<'EOF_USAGE'
Install a released x2c into a dedicated prefix.

  curl -fsSL https://x2c-lang.dev/install.sh | sh
  curl -fsSL https://x2c-lang.dev/install.sh | sh -s -- --version X.Y.Z

Options:
  --version VERSION  install VERSION instead of the latest release
  --prefix DIR       install into DIR instead of $HOME/.local/x2c
  -h, --help         show this help

X2C_VERSION and X2C_PREFIX set the same defaults as the options. X2C_RELEASES
selects the download base; it defaults to the GitHub release assets.
X2C_RELEASE_TAG selects an independent candidate tag; it defaults to vVERSION.
X2C_VERSION_URL names the file holding the latest version; it defaults to
the one the site publishes. Re-running the script upgrades in place and keeps
installed packages.
EOF_USAGE
}
set -eu

prefix="${X2C_PREFIX:-$HOME/.local/x2c}"
releases="${X2C_RELEASES:-https://github.com/gwf/x2c/releases/download}"
version_url="${X2C_VERSION_URL:-https://x2c-lang.dev/x2c-version.txt}"
version="${X2C_VERSION:-latest}"

usage_error() {
  echo "x2c: $*" >&2
  echo "x2c: run with --help for usage" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version|--prefix)
      [ $# -ge 2 ] || usage_error "option '$1' requires a value"
      case "$1" in
        --version) version="$2" ;;
        --prefix) prefix="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage_error "unknown option '$1'" ;;
  esac
done

fail() { echo "x2c: $*" >&2; exit 1; }

case "$prefix" in
  /*) ;;
  *) fail "the prefix must be an absolute path: $prefix" ;;
esac
if [ -e "$prefix" ] && [ ! -f "$prefix/.x2c-install-manifest" ]; then
  fail "$prefix exists and is not an x2c installation"
fi

supported="darwin-arm64, darwin-x86_64, linux-aarch64, linux-x86_64"
platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
case "$platform" in
  darwin-arm64|darwin-x86_64|linux-aarch64|linux-x86_64) ;;
  mingw*|msys*|cygwin*)
    fail "Windows is not supported; install WSL2 and run this script in its" \
      "Linux shell (releases support $supported)" ;;
  *) fail "no x2c release for $platform; releases support $supported" ;;
esac

command -v curl >/dev/null || fail "curl is required"
command -v tar >/dev/null || fail "tar is required"
if ! command -v cc >/dev/null; then
  case "$(uname -s)" in
    Darwin) hint="run: xcode-select --install" ;;
    Linux) hint="install clang or gcc, for example: sudo apt-get install clang" ;;
    *) hint="install a C compiler that provides cc" ;;
  esac
  fail "no C compiler 'cc' on PATH; $hint"
fi
if command -v shasum >/dev/null; then
  sha="shasum -a 256"
elif command -v sha256sum >/dev/null; then
  sha="sha256sum"
else
  fail "shasum or sha256sum is required"
fi

case "$version" in
  latest)
    version="$(curl -fsSL "$version_url")" ||
      fail "cannot determine the latest release from $version_url"
    ;;
esac
version="${version#v}"
asset="x2c-$version-$platform.tar.gz"
release_tag="${X2C_RELEASE_TAG:-v$version}"
base="$releases/$release_tag"

work="$(mktemp -d "${TMPDIR:-/tmp}/x2c-install.XXXXXX")"
trap 'rm -rf "$work"' EXIT
echo "x2c: downloading $asset"
curl -fsSL -o "$work/$asset" "$base/$asset" ||
  fail "no release $version for $platform at $base/$asset"
curl -fsSL -o "$work/$asset.sha256" "$base/$asset.sha256" ||
  fail "no checksum for $asset"
expected="$(cut -d' ' -f1 "$work/$asset.sha256")"
actual="$(cd "$work" && $sha "$asset" | cut -d' ' -f1)"
[ "$expected" = "$actual" ] || fail "checksum mismatch for $asset"

mkdir -p "$work/tree"
tar -xzf "$work/$asset" -C "$work/tree"
extracted="$(find "$work/tree" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -f "$extracted/.x2c-install-manifest" ] ||
  fail "$asset is not an x2c installation"

mkdir -p "$(dirname "$prefix")"
# Stage beside the prefix so replacing it is a pair of renames. Nothing that
# holds installed packages is removed until they are in the new tree.
staged="$prefix.new.$$"
previous="$prefix.previous.$$"
trap 'rm -rf "$work" "$staged"' EXIT
mv "$extracted" "$staged"
if [ -d "$prefix" ]; then
  if [ -d "$prefix/packages" ]; then
    rm -rf "$staged/packages"
  fi
  mv "$prefix" "$previous"
  if ! { mv "$staged" "$prefix" &&
         { [ ! -d "$previous/packages" ] ||
           mv "$previous/packages" "$prefix/packages"; }; }; then
    [ ! -d "$prefix" ] || mv "$prefix" "$staged"
    mv "$previous" "$prefix"
    fail "cannot replace $prefix"
  fi
  rm -rf "$previous"
else
  mv "$staged" "$prefix"
fi

installed="$("$prefix/bin/x2c" --version 2>&1)" ||
  fail "unpacked into $prefix, but '$prefix/bin/x2c --version' failed:" \
    "$installed; this system may be older than the release supports"
echo "x2c: installed $installed at $prefix"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "x2c: add the compiler to PATH:"
     echo "  export PATH=\"$prefix/bin:\$PATH\""
     echo "x2c: add that line to your shell profile to keep it on PATH" ;;
esac
echo "x2c: to uninstall, remove $prefix and its PATH line"
