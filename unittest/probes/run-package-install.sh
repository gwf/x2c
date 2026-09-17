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
mkdir -p "$BUILD/home/include/x2c" "$BUILD/home/etc" "$BUILD/home/lib" \
  "$BUILD/home/packages" "$BUILD/home/bin" "$BUILD/src"
cp "$ROOT/etc/"*.xlisp "$ROOT/etc/"*.xmacro "$BUILD/home/etc/"
cp "$ROOT/lib/"*.x "$ROOT/lib/"*.xmacro "$ROOT/lib/"*.xlisp \
  "$ROOT/builds/0/lib/"*.h "$BUILD/home/include/x2c/"
cp "$ROOT/lib/"*.x "$ROOT/lib/"*.xmacro "$ROOT/lib/"*.xlisp \
  "$ROOT/builds/0/libx2c.a" "$ROOT/builds/0/lib/"*.xi "$BUILD/home/lib/"
cp "$X2C" "$BUILD/home/bin/x2c"
x2c="$BUILD/home/bin/x2c"
[[ "$("$x2c" env home)" == "$BUILD/home" ]] || fail "home not resolved"

# A failed removal names its own command and takes no lock.
set +e
"$x2c" remove nosuch 2>"$BUILD/remove-nosuch.stderr"
[[ $? == 2 ]] || fail "removing an absent package succeeded"
set -e
grep -q "^x2c: error: remove: no installed package 'nosuch'" \
  "$BUILD/remove-nosuch.stderr" || fail "remove diagnostic"
[[ ! -e "$BUILD/home/packages/.lock" ]] || fail "failed removal took the lock"

# A source package from a directory, then through file:// with a digest.
cp -R "$ROOT/examples/packages/greet" "$BUILD/src/greet"
rm -rf "$BUILD/src/greet/builds"
(cd "$BUILD/src" && tar -czf greet.tar.gz greet)
digest=$(shasum -a 256 "$BUILD/src/greet.tar.gz" | cut -d' ' -f1)

# A host tool that exists but cannot run is a diagnostic, not an abort.
mkdir -p "$BUILD/broken-tools"
: >"$BUILD/broken-tools/tar"
set +e
PATH="$BUILD/broken-tools" "$x2c" install -q "$BUILD/src/greet.tar.gz" \
  2>"$BUILD/broken-tar.stderr"
broken_status=$?
set -e
[[ $broken_status == 2 ]] || fail "unrunnable tar exited $broken_status"
grep -q "extract failed (tar)" "$BUILD/broken-tar.stderr" ||
  fail "unrunnable tar diagnostic"
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

# Reinstalling leaves a user's <name>.previous alone.
mkdir -p "$BUILD/home/packages/greet.previous"
: >"$BUILD/home/packages/greet.previous/precious"
"$x2c" install -q "$BUILD/src/greet"
[[ -f "$BUILD/home/packages/greet.previous/precious" ]] ||
  fail "reinstall removed greet.previous"
rm -rf "$BUILD/home/packages/greet.previous"

# A removal waits while another process holds the home's packages lock.
trap 'touch "$BUILD/release"' EXIT
python3 - "$BUILD/home/packages/.lock" "$BUILD/release" <<'PY' &
import fcntl, os, sys, time
lock = open(sys.argv[1], "a")
fcntl.flock(lock, fcntl.LOCK_EX)
open(sys.argv[2] + ".held", "w").close()
while not os.path.exists(sys.argv[2]):
    time.sleep(0.05)
PY
holder=$!
while [[ ! -e "$BUILD/release.held" ]]; do sleep 0.05; done
"$x2c" remove greet >/dev/null 2>"$BUILD/wait.stderr" &
remover=$!
sleep 1
[[ -d "$BUILD/home/packages/greet" ]] || fail "removal ignored the lock"
grep -q "waiting for another install or removal" "$BUILD/wait.stderr" ||
  fail "waiting diagnostic"
touch "$BUILD/release"
wait "$holder"
wait "$remover" || fail "removal after the lock failed"
[[ ! -e "$BUILD/home/packages/greet" ]] || fail "greet not removed"

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

# A project manifest pins packages, and `x2c build` installs what the home
# does not already hold, then records the resolution in x2c.lock.
mkdir -p "$BUILD/project/src"
cp "$ROOT/examples/power/greet-client.x" "$BUILD/project/src/client.x"
cat >"$BUILD/project/x2c.toml" <<'MANIFEST'
[project]
name = "client"
default-target = "client"

[dependencies]
greet = "1.0"

[target.client]
kind = "executable"
sources = ["src/client.x"]
MANIFEST
cd "$BUILD/project"
"$x2c" build -q --index "$BUILD/index.txt" --output "$BUILD/project/client"
[[ "$("$x2c" list)" == "greet 1.0 source" ]] || fail "dependency not installed"
grep -q '^greet 1.0 source - ' x2c.lock || fail "lockfile row"
"$BUILD/project/client" >"$BUILD/project/client.stdout"
grep -q "ping ping ping" "$BUILD/project/client.stdout" || fail "client output"

# A satisfied lockfile reaches no index, so an unreachable one still builds.
rm -rf .x2c-build
"$x2c" build -q --index "file://$BUILD/absent/index.txt" \
  --output "$BUILD/project/client"

# A pin the index cannot satisfy stops the build and names both versions.
sed 's/greet = "1.0"/greet = "9.9"/' x2c.toml >x2c.toml.next
mv x2c.toml.next x2c.toml
rm -rf .x2c-build
set +e
"$x2c" build -q --index "$BUILD/index.txt" --output "$BUILD/project/client" \
  2>"$BUILD/project/pin.stderr"
[[ $? == 2 ]] || fail "unsatisfiable pin accepted"
set -e
grep -q "the index has greet 1.0, not the pinned 9.9" \
  "$BUILD/project/pin.stderr" || fail "pin diagnostic"

# A dry run and an invalid target resolve nothing: both leave the home and
# the lockfile as they were.
sed 's/greet = "9.9"/greet = "1.0"/' x2c.toml >x2c.toml.next
mv x2c.toml.next x2c.toml
"$x2c" remove -q greet
rm -f x2c.lock
"$x2c" build -### --index "$BUILD/index.txt" \
  --output "$BUILD/project/client" >/dev/null 2>&1
[[ -z "$("$x2c" list)" ]] || fail "a dry run installed a pinned package"
[[ ! -e x2c.lock ]] || fail "a dry run wrote a lockfile"
set +e
"$x2c" build -q --target bogus --index "$BUILD/index.txt" \
  2>"$BUILD/project/target.stderr"
[[ $? == 2 ]] || fail "unknown target accepted"
set -e
grep -q "unknown target 'bogus'" "$BUILD/project/target.stderr" ||
  fail "unknown target diagnostic"
[[ -z "$("$x2c" list)" ]] || fail "an unknown target installed a package"
[[ ! -e x2c.lock ]] || fail "an unknown target wrote a lockfile"

# Deleting the section leaves nothing to reproduce, so the lockfile goes.
rm -rf .x2c-build
"$x2c" build -q --index "$BUILD/index.txt" --output "$BUILD/project/client"
grep -q '^greet 1.0 source - ' x2c.lock || fail "lockfile row after rebuild"
sed '/^\[dependencies\]$/,/^greet = /d' x2c.toml >x2c.toml.next
mv x2c.toml.next x2c.toml
rm -rf .x2c-build
"$x2c" build -q --output "$BUILD/project/client"
[[ ! -e x2c.lock ]] || fail "a manifest with no pins kept its lockfile"
cd "$ROOT"
"$x2c" remove -q greet

# The home is one path however it is spelled: a link, a relative name, and
# the real path select the same stage, prelude, and runtime archive.
mkdir -p "$BUILD/home/builds/1"
cp "$BUILD/home/lib/libx2c.a" "$BUILD/home/builds/1/libx2c.a"
mkdir -p "$BUILD/home/builds/1/lib"
cp "$BUILD/home/lib/"*.xi "$BUILD/home/builds/1/lib/"
cp "$x2c" "$BUILD/home/builds/1/x2c"
real=$(cd "$BUILD/home" && pwd -P)
ln -sfn "$real" "$BUILD/home-link"
staged="$BUILD/home/builds/1/x2c"
for name in home runtime_lib prelude; do
  direct=$(X2C_HOME="$real" "$staged" env "$name")
  linked=$(X2C_HOME="$BUILD/home-link" "$BUILD/home-link/builds/1/x2c" \
    env "$name")
  relative=$(cd "$BUILD/home" && X2C_HOME=. ./builds/1/x2c env "$name")
  [[ "$direct" == "$linked" && "$direct" == "$relative" ]] ||
    fail "env $name differs by home spelling: $direct $linked $relative"
done
[[ "$(X2C_HOME="$real" "$staged" env runtime_lib)" == \
   "$real/builds/1/libx2c.a" ]] || fail "a staged compiler links its stage"

# A script under any of those spellings compiles only the script.
mkdir -p "$BUILD/script"
printf 'int main(void) { printf("cached\\n"); return 0; }\n' \
  >"$BUILD/script/one.x"
for home in "$real" "$BUILD/home-link"; do
  rm -rf "$BUILD/script/cache"
  units=$(X2C_HOME="$home" X2C_CACHE_DIR="$BUILD/script/cache" \
    "$home/builds/1/x2c" script -v "$BUILD/script/one.x" 2>&1 >/dev/null |
    grep -c '^x2c: translate ' || true)
  [[ $units == 1 ]] ||
    fail "a script under $home translated $units units, not 1"
done

echo "package install probes passed"
