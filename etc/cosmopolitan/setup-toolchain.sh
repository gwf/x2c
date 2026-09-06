#!/bin/sh
set -eu

COSMO_VERSION=4.0.2
COSMO_SHA256=\
85b8c37a406d862e656ad4ec14be9f6ce474c1b436b9615e91a55208aced3f44
COSMO_URL=https://cosmo.zip/pub/cosmocc/cosmocc-4.0.2.zip
SDK_FORMAT=3

if test -n "${X2C_COSMO_CACHE:-}"; then
  CACHE_ROOT=$X2C_COSMO_CACHE
else
  if test -n "${XDG_CACHE_HOME:-}"; then
    CACHE_ROOT=$XDG_CACHE_HOME/x2c/cosmopolitan
  else
    CACHE_ROOT=${HOME:?set HOME or X2C_COSMO_CACHE}/.cache/x2c/cosmopolitan
  fi
fi
case "$CACHE_ROOT" in
  ""|/) printf '%s\n' "x2c: unsafe Cosmopolitan cache root" >&2; exit 2 ;;
esac

SDK_NAME="cosmocc-$COSMO_VERSION-v$SDK_FORMAT"
SDK_ROOT=$CACHE_ROOT/$SDK_NAME
READY=$SDK_ROOT/.x2c-cosmopolitan-sdk
DOWNLOADS=$CACHE_ROOT/downloads
COSMO_ARCHIVE=$DOWNLOADS/cosmocc-$COSMO_VERSION.zip
BUILD_LOG=$CACHE_ROOT/$SDK_NAME.build.log
MAKE_PROGRAM=${X2C_COSMO_MAKE:-make}
BUILD_ROOT=
DOWNLOAD_TEMP=
LOCK_OWNED=0
LOCK=$SDK_ROOT.lock

_message() {
  printf 'x2c: cosmopolitan: %s\n' "$*" >&2
}

_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
    return
  fi
  _message "need sha256sum or shasum"
  exit 2
}

_ready() {
  test -r "$READY" &&
  grep -Fqx "format=$SDK_FORMAT" "$READY" &&
  grep -Fqx "cosmocc=$COSMO_VERSION:$COSMO_SHA256" "$READY" &&
  test -x "$SDK_ROOT/cosmocc/bin/cosmocc" &&
  test -x "$SDK_ROOT/cosmocc/bin/cosmoar"
}

_cleanup() {
  if test -n "$BUILD_ROOT"; then
    case "$BUILD_ROOT" in
      "$CACHE_ROOT"/.sdk-build.*) rm -rf "$BUILD_ROOT" ;;
    esac
  fi
  if test -n "$DOWNLOAD_TEMP"; then
    case "$DOWNLOAD_TEMP" in
      "$DOWNLOADS"/*.part.*) rm -f "$DOWNLOAD_TEMP" ;;
    esac
  fi
  if test "$LOCK_OWNED" = 1; then
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null || true
  fi
}

_download() {
  url=$1
  expected=$2
  output=$3
  if test -r "$output" && test "$(_hash "$output")" = "$expected"; then
    _message "using cached $(basename "$output")"
    return
  fi
  if test -e "$output"; then
    rejected=$output.rejected.$$
    _message "preserving invalid download as $rejected"
    mv "$output" "$rejected"
  fi
  DOWNLOAD_TEMP=$output.part.$$
  _message "downloading $url"
  curl --fail --location --retry 3 --show-error "$url" \
    -o "$DOWNLOAD_TEMP"
  actual=$(_hash "$DOWNLOAD_TEMP")
  if test "$actual" != "$expected"; then
    _message "checksum mismatch for $(basename "$output")"
    _message "expected $expected"
    _message "actual   $actual"
    exit 2
  fi
  mv "$DOWNLOAD_TEMP" "$output"
  DOWNLOAD_TEMP=
}

_jobs() {
  if test -n "${X2C_COSMO_JOBS:-}"; then
    printf '%s\n' "$X2C_COSMO_JOBS"
    return
  fi
  count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  if test -z "$count"; then
    count=$(sysctl -n hw.ncpu 2>/dev/null || true)
  fi
  printf '%s\n' "${count:-2}"
}

for required in curl unzip tar "$MAKE_PROGRAM" awk grep; do
  command -v "$required" >/dev/null 2>&1 || {
    _message "missing required command: $required"
    exit 2
  }
done

if _ready; then
  _message "using $SDK_ROOT"
  printf '%s\n' "$SDK_ROOT"
  exit 0
fi

mkdir -p "$CACHE_ROOT" "$DOWNLOADS"
if ! mkdir "$LOCK" 2>/dev/null; then
  if _ready; then
    _message "using $SDK_ROOT"
    printf '%s\n' "$SDK_ROOT"
    exit 0
  fi
  lock_pid=$(sed -n '1p' "$LOCK/pid" 2>/dev/null || true)
  if test -n "$lock_pid" && kill -0 "$lock_pid" 2>/dev/null; then
    _message "another toolchain setup owns $LOCK"
    exit 2
  fi
  stale=$LOCK.stale.$$
  _message "preserving stale setup lock as $stale"
  mv "$LOCK" "$stale"
  mkdir "$LOCK"
fi
printf '%s\n' "$$" >"$LOCK/pid"
LOCK_OWNED=1
trap _cleanup EXIT HUP INT TERM

_download "$COSMO_URL" "$COSMO_SHA256" "$COSMO_ARCHIVE"

if test -e "$SDK_ROOT"; then
  incomplete=$SDK_ROOT.incomplete.$$
  _message "preserving incomplete SDK as $incomplete"
  mv "$SDK_ROOT" "$incomplete"
fi

BUILD_ROOT=$(mktemp -d "$CACHE_ROOT/.sdk-build.XXXXXX")
: >"$BUILD_LOG"
mkdir -p "$BUILD_ROOT/sdk/cosmocc"
_message "extracting cosmocc $COSMO_VERSION"
unzip -q "$COSMO_ARCHIVE" -d "$BUILD_ROOT/sdk/cosmocc"

{
  printf 'format=%s\n' "$SDK_FORMAT"
  printf 'cosmocc=%s:%s\n' "$COSMO_VERSION" "$COSMO_SHA256"
} >"$BUILD_ROOT/sdk/.x2c-cosmopolitan-sdk"

mv "$BUILD_ROOT/sdk" "$SDK_ROOT"
_message "prepared $SDK_ROOT"
printf '%s\n' "$SDK_ROOT"
