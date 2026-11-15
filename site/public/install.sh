#!/bin/sh
# Install a released x2c into a dedicated prefix.
#
# The script downloads the compiler archive x2c-VERSION-PLATFORM.tar.gz and
# its .sha256 checksum file from the x2c release on GitHub
# (https://github.com/gwf/x2c/releases). Both files come from the same
# release, so the checksum detects a damaged download; it does not prove who
# published the archive. The archive unpacks into $HOME/.local/x2c, or the
# directory that --prefix names. Updates use a sibling lock and backup;
# no shell profile is edited.
#
# To upgrade, run the script again; installed packages are kept. To
# uninstall, remove the prefix directory and the PATH line that names it.
usage() {
  if [ "${update:-0}" = 1 ]; then
    cat <<'EOF_UPDATE'
Usage: x2c update [--check] [--version VERSION]

Update this official installation from its recorded release source.
--check reports the selected version without changing files (status 0).
--version explicitly selects a release, including an older release.
Source installations must be updated with make install in their checkout.
Errors return status 1; invalid options return status 2.
EOF_UPDATE
    return
  fi
  cat <<'EOF_USAGE'
Install a released x2c into a dedicated prefix.

  curl -fsSL https://x2c-lang.dev/install.sh | sh
  curl -fsSL https://x2c-lang.dev/install.sh | sh -s -- --version X.Y.Z

Options:
  --version VERSION  install VERSION instead of the latest release
  --prefix DIR       install into DIR instead of $HOME/.local/x2c
  --check            report available version without installing
  --replace-origin   deliberately replace a source or unknown installation
  -h, --help         show this help

X2C_VERSION and X2C_PREFIX set the same defaults as the options. X2C_RELEASES
selects the download base; it defaults to the GitHub release assets.
X2C_RELEASE_TAG selects the release tag to download (default vVERSION).
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
release_tag="${X2C_RELEASE_TAG:-}"
update=0 check=0 replace_origin=0 explicit_version=0 cli_version=0 prefix_seen=0
[ "$version" = latest ] || explicit_version=1

usage_error() {
  echo "x2c: $*" >&2
  echo "x2c: run with --help for usage" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --update) update=1; shift ;;
    --check) check=1; shift ;;
    --replace-origin) replace_origin=1; shift ;;
    --version|--prefix)
      [ $# -ge 2 ] || usage_error "option '$1' requires a value"
      case "$1" in
        --version) version="$2"; explicit_version=1; cli_version=1 ;;
        --prefix)
          [ "$prefix_seen" = 0 ] || usage_error "--prefix was supplied twice"
          prefix="$2"; prefix_seen=1 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage_error "unknown option '$1'" ;;
  esac
done

fail() { echo "x2c: $*" >&2; exit 1; }

# Read installation data as text, never as shell code.
origin_value() { sed -n "s/^$1=//p" "$prefix/.x2c-install-origin"; }
quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
valid_version() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }
compare_versions() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".");
    for (i = 1; i <= 3; i++) {
      if (x[i]+0 < y[i]+0) { print -1; exit }
      if (x[i]+0 > y[i]+0) { print 1; exit }
    }
    print 0
  }'
}

case "$prefix" in
  /*) ;;
  *) fail "the prefix must be an absolute path: $prefix" ;;
esac
# A trailing slash must not change the meaning of the sibling stage and lock.
while [ "${prefix%/}" != "$prefix" ]; do prefix="${prefix%/}"; done
[ -n "$prefix" ] || fail "the filesystem root cannot be an x2c prefix"
[ ! -L "$prefix" ] || fail "the installation prefix is a symlink: $prefix"
if [ -e "$prefix" ] && [ ! -f "$prefix/.x2c-install-manifest" ]; then
  fail "$prefix exists and is not an x2c installation"
fi
kind=unknown
if [ -f "$prefix/.x2c-install-origin" ]; then kind="$(origin_value kind)"; fi
if [ "$update" = 1 ]; then
  [ "$replace_origin" = 0 ] || usage_error "update cannot change installation origin"
  explicit_version="$cli_version"
  case "$kind" in
    source)
      echo "x2c: this compiler was installed from $(origin_value source)" >&2
      echo "x2c: update it with:" >&2
      printf '  make -C %s install PREFIX=%s\n' \
        "$(quote "$(origin_value source)")" "$(quote "$prefix")" >&2
      exit 1 ;;
    release)
      releases="$(origin_value releases)"
      version_url="$(origin_value version_url)"
      # Environment defaults never redirect an installed compiler's updates.
      [ "$explicit_version" = 1 ] || version=latest
      release_tag=
      installed_tag="$(origin_value release_tag)"
      if [ "$installed_tag" != "v$(origin_value version)" ]; then
        fail "this installation is pinned to $installed_tag; use its release installer to select another candidate"
      fi ;;
    *) fail "installation origin is unknown; run make install from its source checkout, or rerun the official installer with --replace-origin" ;;
  esac
elif [ -e "$prefix" ] && [ "$kind" != release ] && [ "$replace_origin" != 1 ]; then
  fail "installation origin is $kind; use --replace-origin to deliberately install an official release here"
fi
lock="$prefix.update-lock"
previous="$prefix.previous"
if [ -e "$lock" ] || [ -e "$previous" ]; then
  echo "x2c: another update is running, or an update was interrupted at $prefix" >&2
  echo "x2c: after confirming no updater is running, follow $lock/recover.sh" >&2
  exit 1
fi
work= staged= locked=0
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ ! -f "$lock/committed" ] && [ -d "$previous" ]; then
    if [ -d "$prefix/packages" ] && [ ! -d "$previous/packages" ]; then
      mv "$prefix/packages" "$previous/packages" || exit "$status"
    fi
    if [ -e "$prefix" ]; then
      mv "$prefix" "$lock/failed" || exit "$status"
    fi
    mv "$previous" "$prefix" || exit "$status"
  fi
  [ -z "$work" ] || rm -rf "$work"
  if [ "$locked" = 1 ] && [ ! -e "$previous" ]; then rm -rf "$lock"; fi
  exit "$status"
}
if [ "$check" = 0 ]; then
  mkdir -p "$(dirname "$prefix")"
  mkdir "$lock" || fail "another update is running at $prefix"
  locked=1
  trap cleanup EXIT
  trap 'exit 130' HUP INT TERM
  # Leave a readable recovery recipe if SIGKILL or power loss bypasses traps.
  cat >"$lock/recover.sh" <<EOF_RECOVERY
#!/bin/sh
set -eu
# Run only after confirming that no installer is running.
prefix=$(quote "$prefix")
previous=$(quote "$previous")
lock=$(quote "$lock")
if [ ! -f "\$lock/committed" ] && [ -d "\$previous" ]; then
  if [ -d "\$prefix/packages" ] && [ ! -d "\$previous/packages" ]; then
    mv "\$prefix/packages" "\$previous/packages"
  fi
  [ ! -e "\$prefix" ] || mv "\$prefix" "\$lock/failed"
  mv "\$previous" "\$prefix"
fi
rm -rf "\$previous" "\$lock"
EOF_RECOVERY
fi
current=
if [ -x "$prefix/bin/x2c" ]; then
  current="$("$prefix/bin/x2c" --version | sed -n 's/^x2c //p')"
  valid_version "$current" || fail "cannot read installed compiler version at $prefix"
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

case "$version" in
  latest)
    version="$(curl -fsSL "$version_url")" ||
      fail "cannot determine the latest release from $version_url"
    ;;
esac
version="${version#v}"
asset="x2c-$version-$platform.tar.gz"
valid_version "$version" || fail "invalid release version: $version"
release_tag="${release_tag:-v$version}"
if [ -n "$current" ]; then
  comparison="$(compare_versions "$version" "$current")"
  echo "x2c: installed $current at $prefix; selected $version"
  if [ "$comparison" = -1 ] && [ "$explicit_version" != 1 ]; then
    echo "x2c: installed compiler is newer; no downgrade performed"
    exit 0
  fi
  if [ "$comparison" = 0 ] && [ "$explicit_version" != 1 ] &&
     [ "$kind" = release ] && [ "$release_tag" = "$(origin_value release_tag)" ] &&
     [ "$releases" = "$(origin_value releases)" ]; then
    echo "x2c: already up to date"
    exit 0
  fi
fi
if [ "$check" = 1 ]; then
  echo "x2c: release $version is available; no files changed"
  exit 0
fi
if [ -n "$current" ] && [ "$comparison" = -1 ]; then
  echo "x2c: explicitly downgrading $current to $version"
fi
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

base="$releases/$release_tag"

work="$(mktemp -d "${TMPDIR:-/tmp}/x2c-install.XXXXXX")"
# Unknown files are not ours to replace. Packages have a separate owner.
if [ -d "$prefix" ]; then
  (cd "$prefix" && find . -path ./packages -prune -o \
    \( -type f -o -type l \) -print | sed 's|^./||' | sort) >"$work/files"
  { sed '1d; s/^[^ ]* [^ ]* //' "$prefix/.x2c-install-manifest"
    printf '%s\n' .x2c-install-manifest .x2c-install-origin
  } | sort >"$work/owned"
  unowned="$(comm -23 "$work/files" "$work/owned" | head -n 1)"
  [ -z "$unowned" ] || fail "unowned file $prefix/$unowned; move it outside the installation before updating"
fi
for bundle in "$prefix"/packages/*/BUNDLE.json; do
  [ -f "$bundle" ] || continue
  built="$(grep -o '"x2c_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$bundle" |
    sed 's/^[^:]*:[[:space:]]*"//; s/"$//')"
  [ "$built" = "x2c $version" ] || fail "native package $(basename "$(dirname "$bundle")") was built for ${built:-an unknown compiler}; remove it with x2c remove, update, then reinstall or rebuild it for $version"
done

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

staged="$lock/staged"
mv "$extracted" "$staged"
installed="$("$staged/bin/x2c" --version 2>&1)" ||
  fail "'$staged/bin/x2c --version' failed:" \
    "$installed; this system may be older than the release supports"
[ "$installed" = "x2c $version" ] || fail "archive compiler reports '$installed', expected x2c $version"
printf 'kind=release\nversion=%s\nreleases=%s\nversion_url=%s\nrelease_tag=%s\n' \
  "$version" "$releases" "$version_url" "$release_tag" >"$staged/.x2c-install-origin"
if [ -d "$prefix" ]; then
  if [ -d "$prefix/packages" ]; then rm -rf "$staged/packages"; fi
  mv "$prefix" "$previous"
  mv "$staged" "$prefix"
  if [ -d "$previous/packages" ]; then mv "$previous/packages" "$prefix/packages"; fi
else
  mv "$staged" "$prefix"
fi
touch "$lock/committed"
rm -rf "$previous"

echo "x2c: installed $installed at $prefix"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "x2c: add the compiler to PATH:"
     echo "  export PATH=\"$prefix/bin:\$PATH\""
     echo "x2c: add that line to your shell profile to keep it on PATH" ;;
esac
echo "x2c: to uninstall, remove $prefix and its PATH line"
