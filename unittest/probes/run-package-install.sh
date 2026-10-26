#!/usr/bin/env bash
# x2c install, remove, and list against a scratch home: a local source
# directory, a tarball through file:// with a digest, an index, a bundle
# with a version mismatch, and the refusals that protect user data.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/x2c-package-install.XXXXXX")
BUILD=$(cd "$BUILD" && pwd -P)
trap 'rm -rf "$BUILD"' EXIT
X2C=${X2C:-"$ROOT/builds/0/x2c"}

fail() { echo "package install: $*" >&2; exit 1; }

copy_runtime_sources() {
  local destination=$1 source
  cp "$ROOT"/lib/*.x "$destination"
  for source in "$ROOT"/lib/*; do
    [[ -d "$source" ]] && cp -R "$source" "$destination"
  done
  for source in "$ROOT"/lib/*.xlisp; do
    [[ -e "$source" ]] && cp "$source" "$destination"
  done
  return 0
}

mkdir -p "$BUILD/home/include/x2c" "$BUILD/home/etc" "$BUILD/home/lib" \
  "$BUILD/home/packages" "$BUILD/home/bin" "$BUILD/src"
cp "$ROOT/etc/"*.xlisp "$ROOT/etc/"*.x "$BUILD/home/etc/"
copy_runtime_sources "$BUILD/home/include/x2c/"
cp "$ROOT/builds/0/lib/"*.h "$BUILD/home/include/x2c/"
for header in "$ROOT/builds/0/lib"/*/*.h; do
  directory=$(basename "$(dirname "$header")")
  mkdir -p "$BUILD/home/include/x2c/$directory"
  cp -L "$header" "$BUILD/home/include/x2c/$directory/"
done
copy_runtime_sources "$BUILD/home/lib/"
mkdir -p "$BUILD/home/src"
mkdir -p "$BUILD/home/src/components"
cp "$ROOT"/src/components/*.x "$BUILD/home/src/components"/
cp "$ROOT"/src/grammar.x "$BUILD/home/src/"
cp "$ROOT/builds/0/libx2c.a" "$ROOT/builds/0/lib/"*.xi "$BUILD/home/lib/"
cp "$X2C" "$BUILD/home/bin/x2c"
mkdir -p "$BUILD/home/libexec/x2c"
cp "$ROOT/builds/0/libexec/"x2c-{build,editor,new,package} "$BUILD/home/libexec/x2c/"
x2c="$BUILD/home/bin/x2c"
[[ "$("$x2c" env home)" == "$BUILD/home" ]] || fail "home not resolved"

# The command is shipped once, and both forms reach it. Legacy help does
# not need the executable; package state does.
package="$BUILD/home/libexec/x2c/x2c-package"
"$x2c" package --help >"$BUILD/package.help"
grep -q 'install|remove|list' "$BUILD/package.help" || fail "package help"
[[ "$("$x2c" package list)" == "$("$x2c" list)" ]] || fail "list dispatch"
set +e
X2C_IDENTITY=wrong "$package" list >"$BUILD/mismatch.out" 2>"$BUILD/mismatch.err"
[[ $? == 2 ]] || fail "mismatched package command accepted"
set -e
grep -q 'identity' "$BUILD/mismatch.err" || fail "identity diagnostic"
mv "$package" "$package.saved"
"$x2c" install --help >"$BUILD/install.help"
"$x2c" remove --help >"$BUILD/remove.help"
"$x2c" list --help >"$BUILD/list.help"
set +e
"$x2c" list >"$BUILD/missing.out" 2>"$BUILD/missing.err"
[[ $? == 2 ]] || fail "missing package command accepted"
set -e
grep -q 'missing x2c-package command' "$BUILD/missing.err" || fail "missing diagnostic"
"$x2c" new -q "$BUILD/empty-project"
(cd "$BUILD/empty-project" && "$x2c" build -q)
mv "$package.saved" "$package"

# Legacy vectors expand once; the direct package dialect stays literal.
python3 - "$x2c" "$BUILD" <<'PYTHON'
import pathlib, subprocess, sys
compiler, scratch = sys.argv[1], pathlib.Path(sys.argv[2])
def run(args):
    return subprocess.run([compiler, *args], cwd=scratch, capture_output=True)
for legacy, direct, name in [
    (["remove", "@@absent"], ["package", "remove", "@absent"], "@absent"),
    (["remove", "--", "--help"], ["package", "remove", "--", "--help"], "--help"),
]:
    left, right = run(legacy), run(direct)
    assert left.returncode == right.returncode == 2, (left, right)
    assert left.stderr == right.stderr and name.encode() in left.stderr, (left, right)
(scratch / "remove.rsp").write_text("remove @@absent")
assert run(["@remove.rsp"]).stderr == run(["remove", "@@absent"]).stderr
for operation in ["install", "remove", "list"]:
    assert run([operation, "--help"]).returncode == 0
    assert run(["help", operation]).returncode == 0
result = run(["install", "--index", "--help"])
assert result.returncode == 2 and b"requires exactly one operand" in result.stderr
PYTHON

# Command startup checks identity before parsing forwarded legacy help.
mv "$package" "$package.saved"
printf '#!/bin/sh\nexport X2C_IDENTITY=wrong\nexec "%s" "$@"\n' \
  "$package.saved" >"$package"
chmod +x "$package"
set +e
"$x2c" install --help >"$BUILD/legacy-mismatch.out" 2>"$BUILD/legacy-mismatch.err"
[[ $? == 2 ]] || fail "legacy help bypassed command identity"
set -e
grep -q 'identity' "$BUILD/legacy-mismatch.err" || fail "legacy identity diagnostic"
[[ ! -s "$BUILD/legacy-mismatch.out" ]] || fail "mismatch printed help"
mv "$package.saved" "$package"

# New's missing-command fallback retains legacy help and operand errors.
new="$BUILD/home/libexec/x2c/x2c-new"
mv "$new" "$new.saved"
"$x2c" new --help >"$BUILD/new.help"
set +e
"$x2c" new >"$BUILD/new-missing.out" 2>"$BUILD/new-missing.err"
[[ $? == 2 ]] || fail "missing new operand accepted"
set -e
grep -q 'requires exactly one operand' "$BUILD/new-missing.err" || fail "new parse fallback"
mv "$new.saved" "$new"

# A failed removal names its own command and takes no lock.
set +e
"$x2c" remove nosuch 2>"$BUILD/remove-nosuch.stderr"
[[ $? == 2 ]] || fail "removing an absent package succeeded"
set -e
grep -q "^x2c: error: remove: no installed package 'nosuch'" \
  "$BUILD/remove-nosuch.stderr" || fail "remove diagnostic"
[[ ! -e "$BUILD/home/packages/.lock" ]] || fail "failed removal took the lock"

# An installed indentation entry imports like an ordinary source entry.
mkdir -p "$BUILD/src/xppkg/src"
printf 'int answer(void):\n  return 7\n' >"$BUILD/src/xppkg/src/xppkg.xp"
cat >"$BUILD/xp-client.x" <<'SOURCE'
import "xppkg" as xp;
int main(void) { return xp.answer() == 7 ? 0 : 1; }
SOURCE
printf 'install -q "%s"\n' "$BUILD/src/xppkg" >"$BUILD/install.rsp"
"$x2c" @"$BUILD/install.rsp" >"$BUILD/quiet.out" 2>"$BUILD/quiet.err"
[[ ! -s "$BUILD/quiet.out" && ! -s "$BUILD/quiet.err" ]] || fail "quiet install"
"$x2c" run -q "$BUILD/xp-client.x" || fail "installed .xp entry import"
"$x2c" package remove -q xppkg

# Directory operands derive the same package name after normalization.
for directory in . "$BUILD/src/xppkg/."; do
  (cd "$BUILD/src/xppkg" && "$x2c" install -q "$directory")
  [[ "$("$x2c" list)" == "xppkg - source" ]] || fail "normalized package name"
  "$x2c" run -q "$BUILD/xp-client.x" || fail "normalized package import"
  "$x2c" remove -q xppkg
done

# The existing .x entry still wins when both source spellings exist.
printf 'int answer(void) { return 11; }\n' >"$BUILD/src/xppkg/src/xppkg.x"
printf 'int alternate(void):\n  return 7\n' >"$BUILD/src/xppkg/src/xppkg.xp"
sed 's/== 7/== 11/' "$BUILD/xp-client.x" >"$BUILD/x-entry-client.x"
mkdir -p "$BUILD/x-precedence"
"$x2c" translate --out-dir "$BUILD/x-precedence" --package-dir "$BUILD/src" \
  "$BUILD/x-entry-client.x" >/dev/null || fail ".x entry precedence"
mv "$BUILD/src/xppkg/src/xppkg.x" "$BUILD/src/xppkg/xppkg.x"
"$x2c" translate --out-dir "$BUILD/x-precedence" --package-dir "$BUILD/src" \
  "$BUILD/x-entry-client.x" >/dev/null || fail "root .x precedes nested .xp"

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
# A receipt is action output, so it goes to standard error.
"$x2c" install "$BUILD/src/greet" >"$BUILD/receipt.stdout" \
  2>"$BUILD/receipt.stderr"
[[ ! -s "$BUILD/receipt.stdout" ]] || fail "install receipt on stdout"
grep -q "^x2c: installed .*/packages/greet$" "$BUILD/receipt.stderr" ||
  fail "install receipt on stderr"
[[ "$("$x2c" list)" == "greet - source" ]] || fail "list after directory"
[[ -f "$BUILD/home/packages/greet/builds/libgreet.a" ]] || fail "no archive"
[[ -f "$BUILD/home/packages/greet/builds/greet.native.rsp" ]] ||
  fail "no native response file"
[[ ! -s "$BUILD/home/packages/greet/builds/greet.native.rsp" ]] ||
  fail "a source package recorded native arguments"
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

# A failed install removes its own staging directory, download and all,
# instead of leaving it for the next install to collect.
set +e
"$x2c" install "file://$BUILD/src/greet.tar.gz" --sha256 0 \
  2>"$BUILD/badsha2.stderr"
[[ $? == 2 ]] || fail "bad digest accepted"
set -e
[[ -z "$(ls -A "$BUILD/home/packages" | grep '^\.install')" ]] ||
  fail "a failed install left its staging directory"

# A damaged package or marker is a refusal, not an abort, and one damaged
# marker leaves list and the lock check working.
mkdir -p "$BUILD/broken/nosrc" "$BUILD/broken/badbundle/builds"
printf 'not json\n' >"$BUILD/broken/badbundle/BUNDLE.json"
: >"$BUILD/broken/badbundle/builds/libbadbundle.a"
set +e
"$x2c" install "$BUILD/broken/nosrc" 2>"$BUILD/nosrc.stderr"
[[ $? == 2 ]] || fail "a package without src/ did not refuse with 2"
"$x2c" install --force "$BUILD/broken/badbundle" 2>"$BUILD/badbundle.stderr"
[[ $? == 2 ]] || fail "an unreadable BUNDLE.json did not refuse with 2"
set -e
grep -q "has no src/nosrc.x or src/nosrc.xp entry unit" "$BUILD/nosrc.stderr" ||
  fail "missing src diagnostic"
grep -q "no readable BUNDLE.json" "$BUILD/badbundle.stderr" ||
  fail "unreadable bundle diagnostic"
mkdir -p "$BUILD/home/packages/damaged"
printf '[1, 2]\n' >"$BUILD/home/packages/damaged/SOURCE.json"
[[ "$("$x2c" list)" == $'damaged - source\ngreet - source' ]] ||
  fail "a damaged marker broke list"
printf 'not json\n' >"$BUILD/home/packages/damaged/SOURCE.json"
[[ "$("$x2c" list)" == $'damaged - source\ngreet - source' ]] ||
  fail "an unreadable marker broke list"
rm -rf "$BUILD/home/packages/damaged"

# Only what this compiler builds is archived: a builds directory the source
# tree carried is not installed with it.
mkdir -p "$BUILD/src/greet/builds"
printf 'int greet__stale(void) { return 7; }\n' \
  >"$BUILD/src/greet/builds/stale.c"
"$x2c" install -q "$BUILD/src/greet"
rm -rf "$BUILD/src/greet/builds"
[[ ! -e "$BUILD/home/packages/greet/builds/stale.c" ]] ||
  fail "a stale generated file was installed"
if nm "$BUILD/home/packages/greet/builds/libgreet.a" 2>/dev/null |
   grep -q "greet__stale"; then
  fail "a stale symbol reached the archive"
fi

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
(cd "$BUILD" && cp index.txt @index.txt &&
  "$x2c" install -q greet --index @@index.txt)
[[ "$("$x2c" list)" == "greet 1.0 source" ]] || fail "index version"

# A reinstall from a local path keeps the version the package it replaces
# recorded, and the marker records an absolute source and nothing empty.
(cd "$BUILD/src" && "$x2c" install -q ./greet)
[[ "$("$x2c" list)" == "greet 1.0 source" ]] ||
  fail "a reinstall from a path lost the version"
grep -q '"source": "/' "$BUILD/home/packages/greet/SOURCE.json" ||
  fail "SOURCE.json recorded a relative source"
if grep -q '": ""' "$BUILD/home/packages/greet/SOURCE.json"; then
  fail "SOURCE.json recorded an empty field"
fi

# Two removals of one package cannot both report success.
set +e
"$x2c" remove greet >"$BUILD/remove-1.out" 2>&1 &
first=$!
"$x2c" remove greet >"$BUILD/remove-2.out" 2>&1 &
second=$!
wait $first; one=$?
wait $second; two=$?
set -e
[[ $((one + two)) == 2 ]] ||
  fail "concurrent removals returned $one and $two"
"$x2c" package install -q greet --index "$BUILD/index.txt"

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

# Packages without dependency manifests use the shared build and bundle path.
for name in pure mixed; do
  directory="$BUILD/src/$name"
  mkdir -p "$directory/src"
  printf 'PACKAGE := %s\nROOT := %s\nX2C := %s\nPACKAGE_C_FLAGS := --c-include-dir src\ninclude %s/packages/package.mk\n' \
    "$name" "$ROOT" "$X2C" "$ROOT" >"$directory/Makefile"
  if [[ "$name" == pure ]]; then
    printf 'int answer(void) { return 42; }\n' >"$directory/src/$name.x"
  else
    printf '#include "answer.h"\nint answer(void) { return native_answer(); }\n' \
      >"$directory/src/$name.x"
    printf 'int native_answer(void);\n' >"$directory/src/answer.h"
    printf 'int native_answer(void) { return 42; }\n' >"$directory/src/answer.c"
  fi
  make -C "$directory" bundle >"$BUILD/$name-bundle.log" 2>&1 ||
    fail "$name bundle; see $BUILD/$name-bundle.log"
  [[ ! -e "$directory/builds/$name.link" ]] || fail "legacy link file required"
  bundle="$directory/builds/bundle/$name"
  python3 - "$bundle/BUNDLE.json" <<'PYTHON'
import json, sys
identity = json.load(open(sys.argv[1]))
assert all(not key.startswith('dependency_') for key in identity), identity
for key in ('package', 'platform', 'machine', 'x2c_version', 'x2c_sha256',
            'runtime_sha256', 'archive_sha256'):
    assert identity[key], (key, identity)
PYTHON
  "$x2c" install -q "$bundle"
  printf 'import "%s" as sample;\nint main(void) { return sample.answer() != 42; }\n' \
    "$name" >"$BUILD/$name-client.x"
  "$x2c" run -q "$BUILD/$name-client.x" || fail "$name bundle consumer"
  "$x2c" remove -q "$name"
done

# A nonempty native response still requires explicit distribution data.
printf '%s\n' '-lm' >"$directory/builds/mixed.native.rsp"
if make -C "$directory" bundle >"$BUILD/native-without-manifest.log" 2>&1; then
  fail "native inputs bundled without distribution data"
fi
grep -q 'native link inputs require distribution data' \
  "$BUILD/native-without-manifest.log" || fail "native distribution diagnostic"
cat >"$BUILD/dependency.json" <<'MANIFEST'
{"schema":1,"name":"inert","sources":[{}],"version":"1.0",
 "profile":"test","distribution":{"native_args":["-lm"]}}
MANIFEST
make -C "$directory" bundle DEPENDENCY_MANIFEST="$BUILD/dependency.json" \
  >"$BUILD/manifest-bundle.log" 2>&1 || fail "manifest-backed bundle"
python3 - "$bundle/BUNDLE.json" <<'PYTHON'
import json, sys
identity = json.load(open(sys.argv[1]))
assert identity['dependency_version'] == '1.0', identity
assert identity['dependency_profile'] == 'test', identity
PYTHON
"$x2c" install -q "$bundle"
"$x2c" run -q "$BUILD/mixed-client.x" || fail "manifest-backed bundle consumer"
"$x2c" remove -q mixed

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

# The lockfile's own url and digest are what a later build installs, so a
# second index offering another archive for the same version changes neither
# the installed package nor the lockfile.
mkdir -p "$BUILD/other"
cp -R "$ROOT/examples/packages/greet" "$BUILD/other/greet"
rm -rf "$BUILD/other/greet/builds"
sed 's/hello, /other build, /' "$BUILD/other/greet/src/greet.x" \
  >"$BUILD/other/greet/src/greet.next"
mv "$BUILD/other/greet/src/greet.next" "$BUILD/other/greet/src/greet.x"
(cd "$BUILD/other" && tar -czf "$BUILD/greet-other.tar.gz" greet)
other=$(shasum -a 256 "$BUILD/greet-other.tar.gz" | cut -d' ' -f1)
printf '# name version kind platform url sha256\n' >"$BUILD/index-other.txt"
printf 'greet 1.0 source - file://%s/greet-other.tar.gz %s\n' \
  "$BUILD" "$other" >>"$BUILD/index-other.txt"
cp x2c.lock "$BUILD/lock.before"
"$x2c" remove -q greet
rm -rf .x2c-build
"$x2c" build -q --index "$BUILD/index-other.txt" --output "$BUILD/project/client"
cmp -s x2c.lock "$BUILD/lock.before" ||
  fail "a second index rewrote the lockfile"
"$BUILD/project/client" >"$BUILD/project/pinned.stdout"
if grep -q "other build" "$BUILD/project/pinned.stdout"; then
  fail "a second index replaced the pinned package"
fi
grep -q "hello, x2c" "$BUILD/project/pinned.stdout" || fail "pinned output"

# `run` releases the packages lock before the program starts, so an install
# does not wait for the program to finish.
cat >"$BUILD/project/src/client.x" <<EOF
import "greet" as g;

#include <unistd.h>

int main(void) {
  g.Greeting greeting = g.Greeting.new("x2c");
  printf("%s", %"\$(greeting.line())\n");
  fflush(stdout);
  for (int i = 0; i < 400 && access("$BUILD/release-run", F_OK); i++)
    usleep(50000);
  return 0;
}
EOF
rm -f "$BUILD/release-run"
rm -rf .x2c-build
"$x2c" remove -q greet
"$x2c" run -q --index "$BUILD/index.txt" >"$BUILD/run.stdout" \
  2>"$BUILD/run.stderr" &
runner=$!
for _ in $(seq 1 600); do
  [[ -s "$BUILD/run.stdout" ]] && break
  sleep 0.1
done
[[ -s "$BUILD/run.stdout" ]] || fail "the run never started its program"
"$x2c" install -q "$BUILD/src/greet"
kill -0 "$runner" 2>/dev/null ||
  fail "the install waited for the running program"
touch "$BUILD/release-run"
wait "$runner" || fail "run failed"
cp "$ROOT/examples/power/greet-client.x" "$BUILD/project/src/client.x"
"$x2c" remove -q greet
rm -rf .x2c-build
"$x2c" build -q --index "$BUILD/index.txt" --output "$BUILD/project/client"

# An absent package manager stops a real build before its output is made,
# but editor requests and dry runs never invoke it.
mv "$package" "$package.saved"
"$x2c" build -### --output "$BUILD/missing-client" >"$BUILD/dry.out" 2>&1
"$x2c" editor "$BUILD/editor.json" "$BUILD/project/src/client.x" hover 0 0 -- build
[[ -s "$BUILD/editor.json" ]] || fail "editor without package command"
set +e
"$x2c" build -q --output "$BUILD/missing-client" 2>"$BUILD/build-missing.err"
[[ $? == 2 ]] || fail "build accepted missing package command"
set -e
[[ ! -e "$BUILD/missing-client" ]] || fail "build continued after package failure"
grep -q 'missing x2c-package command' "$BUILD/build-missing.err" || fail "build missing diagnostic"
mv "$package.saved" "$package"

# A satisfied lockfile reaches no index, so an unreachable one still builds.
rm -rf .x2c-build
cp x2c.lock "$BUILD/offline.lock"
"$x2c" build -q --index "file://$BUILD/absent/index.txt" \
  --output "$BUILD/project/client"
cmp x2c.lock "$BUILD/offline.lock" || fail "offline build rewrote lock"

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
mkdir -p "$BUILD/home/builds/1/libexec"
cp "$BUILD/home/lib/libx2c.a" "$BUILD/home/builds/1/libx2c.a"
mkdir -p "$BUILD/home/builds/1/lib"
cp "$BUILD/home/lib/"*.xi "$BUILD/home/builds/1/lib/"
cp "$x2c" "$BUILD/home/builds/1/x2c"
cp "$BUILD/home/libexec/x2c/x2c-build" "$BUILD/home/builds/1/libexec/"
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
