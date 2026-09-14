#!/usr/bin/env bash
# x2c install, remove, and list against a scratch home: a local source
# directory, a tarball through file:// with a digest, an index, a bundle
# with a version mismatch, and the refusals that protect user data.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/package-install"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

fail() { echo "package install: $*" >&2; exit 1; }

rm -rf "$BUILD"
mkdir -p "$BUILD/home/include" "$BUILD/home/etc" "$BUILD/home/lib" \
  "$BUILD/home/packages" "$BUILD/home/bin" "$BUILD/src"
cp "$ROOT/etc/"*.xlisp "$ROOT/etc/"*.xmacro "$BUILD/home/etc/"
cp "$ROOT/lib/"*.x "$ROOT/lib/"*.xmacro "$ROOT/lib/"*.xlisp \
  "$ROOT/builds/0/lib/"*.h "$BUILD/home/include/"
cp "$ROOT/builds/0/libx2c.a" "$BUILD/home/lib/"
cp "$X2C" "$BUILD/home/bin/x2c"
x2c="$BUILD/home/bin/x2c"
[[ "$("$x2c" env home)" == "$BUILD/home" ]] || fail "home not resolved"

# A source package from a directory, then through file:// with a digest.
cp -R "$ROOT/examples/packages/greet" "$BUILD/src/greet"
rm -rf "$BUILD/src/greet/builds"
(cd "$BUILD/src" && tar -czf greet.tar.gz greet)
digest=$(shasum -a 256 "$BUILD/src/greet.tar.gz" | cut -d' ' -f1)
"$x2c" install -q "$BUILD/src/greet"
[[ "$("$x2c" list)" == "greet - source" ]] || fail "list after directory"
[[ -f "$BUILD/home/packages/greet/builds/libgreet.a" ]] || fail "no archive"
[[ ! -s "$BUILD/home/packages/greet/builds/greet.link" ]] || fail "link file"
"$x2c" run -q "$ROOT/examples/power/greet-client.x" >"$BUILD/client.stdout"
grep -q "ping ping ping" "$BUILD/client.stdout" || fail "client output"
"$x2c" remove -q greet
[[ -z "$("$x2c" list)" ]] || fail "list after remove"
"$x2c" install -q "file://$BUILD/src/greet.tar.gz" --sha256 "$digest"
grep -q '"sha256": "'"$digest"'"' "$BUILD/home/packages/greet/SOURCE.json" ||
  fail "SOURCE.json digest"

# Refusals: a URL without a digest, a wrong digest, a missing index entry,
# and a directory that is not an installed package.
set +e
"$x2c" install "file://$BUILD/src/greet.tar.gz" 2>"$BUILD/nosha.stderr"
[[ $? == 2 ]] || fail "URL without --sha256 accepted"
"$x2c" install "file://$BUILD/src/greet.tar.gz" --sha256 0 \
  2>"$BUILD/badsha.stderr"
[[ $? == 2 ]] || fail "bad digest accepted"
printf '# name version kind platform url sha256\n' >"$BUILD/index.txt"
printf 'greet 1.0 source - file://%s/src/greet.tar.gz %s\n' \
  "$BUILD" "$digest" >>"$BUILD/index.txt"
"$x2c" install nosuch --index "$BUILD/index.txt" 2>"$BUILD/nosuch.stderr"
[[ $? == 2 ]] || fail "unknown index name accepted"
mkdir -p "$BUILD/home/packages/mine"
"$x2c" remove mine 2>"$BUILD/mine.stderr"
[[ $? == 2 ]] || fail "unowned directory removed"
"$x2c" install "$BUILD/src/greet" 2>"$BUILD/keep.stderr"
status=$?
set -e
[[ -d "$BUILD/home/packages/mine" ]] || fail "unowned directory lost"
grep -q "needs --sha256" "$BUILD/nosha.stderr" || fail "nosha diagnostic"
grep -q "sha256 mismatch" "$BUILD/badsha.stderr" || fail "badsha diagnostic"
grep -q "no package 'nosuch'" "$BUILD/nosuch.stderr" || fail "nosuch diagnostic"
grep -q "not an installed package" "$BUILD/mine.stderr" || fail "mine diagnostic"
[[ $status == 0 ]] || fail "reinstall over an installed package failed"
[[ -z "$(ls -A "$BUILD/home/packages" | grep '^\.install')" ]] ||
  fail "staging directory left behind"

# The index resolves a name and records its version.
"$x2c" install -q greet --index "$BUILD/index.txt"
[[ "$("$x2c" list)" == "greet 1.0 source" ]] || fail "index version"

# A bundle is checked against this compiler's version.
mkdir -p "$BUILD/bundle/fake/builds" "$BUILD/bundle/fake/src"
printf 'int fake__one(void) { return 1; }\n' >"$BUILD/bundle/fake/src/fake.x"
: >"$BUILD/bundle/fake/builds/libfake.a"
printf '{\n  "package": "fake",\n  "x2c_version": "x2c 0.0.0"\n}\n' \
  >"$BUILD/bundle/fake/BUNDLE.json"
set +e
"$x2c" install "$BUILD/bundle/fake" 2>"$BUILD/fake.stderr"
[[ $? == 2 ]] || fail "mismatched bundle accepted"
set -e
grep -q "built for 'x2c 0.0.0'" "$BUILD/fake.stderr" || fail "fake diagnostic"
"$x2c" install -q --force "$BUILD/bundle/fake"
[[ "$("$x2c" list)" == $'fake - bundle\ngreet 1.0 source' ]] || fail "bundle list"
"$x2c" remove -q fake
"$x2c" remove -q greet
rm -rf "$BUILD/home/packages/mine"

echo "package install probes passed"
