#!/usr/bin/env bash
# Check a published release the way a user meets it: the site names the
# version, the site's installer installs that compiler, and the site's
# package index installs a bundle for this platform.
#
#   tools/check-release.sh <version> [package]
#
# <version> has no leading v; [package] defaults to pcre2. X2C_SITE selects
# another site (default https://x2c-lang.dev). Nothing outside a scratch
# prefix is touched, and the prefix is removed on exit.
set -euo pipefail

version=${1:?usage: tools/check-release.sh <version> [package]}
version=${version#v}
package=${2:-pcre2}
site=${X2C_SITE:-https://x2c-lang.dev}

fail() { echo "check-release: $*" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/x2c-release-check.XXXXXX")
trap 'rm -rf "$work"' EXIT

published=$(curl -fsSL "$site/x2c-version.txt")
[[ $published == "$version" ]] ||
  fail "the site names $published, not $version"

index=$(curl -fsSL "$site/packages/index.txt")
[[ $(head -1 <<<"$index") == "# x2c package index for x2c $version" ]] ||
  fail "the site's package index is not for x2c $version"

curl -fsSL "$site/install.sh" |
  X2C_PREFIX="$work/x2c" sh -s -- --version "$version" >"$work/install.log"
x2c="$work/x2c/bin/x2c"
[[ $("$x2c" --version) == "x2c $version" ]] ||
  fail "install.sh installed $("$x2c" --version), not x2c $version"

"$x2c" install -q "$package"
listed=$("$x2c" list)
grep -q "^$package .* bundle$" <<<"$listed" ||
  fail "x2c install $package did not install a bundle: $listed"

echo "release $version: site, installer, and $package bundle check out"
