#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
X2C="$ROOT/builds/0/x2c"
COMMAND="$ROOT/builds/0/libexec/x2c-build"
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/x2c-build-command.XXXXXX")
BUILD=$(cd "$BUILD" && pwd -P)
trap 'status=$?; if [ "$status" != 0 ]; then cat "$BUILD/"*.log >&2 2>/dev/null || :; fi; rm -rf "$BUILD"; exit "$status"' EXIT HUP INT TERM
"$COMMAND" --help | grep -q '<build|run|script>'
"$COMMAND" build --help >"$BUILD/direct-help"
"$X2C" build --help >"$BUILD/driver-help"
cmp "$BUILD/direct-help" "$BUILD/driver-help"
status=0
"$COMMAND" translate >"$BUILD/rejected" 2>&1 || status=$?
[ "$status" = 2 ]

# The private argument vector is already expanded, including escaped @ words.
cd "$BUILD"
printf 'int main(void) { return 0; }\n' > @input.x
printf 'build -q --output app @@input.x\n' > build.rsp
"$X2C" @build.rsp
./app
"$COMMAND" build -q --output direct @@input.x
./direct
"$COMMAND" run -q @@input.x
# Run keeps one default build receipt, while verbose shows the build phases.
printf 'int main(void) { puts("program output"); return 0; }\n' > run-output.x
"$X2C" run --plain run-output.x >run-output.out 2>run-output.log
[ "$(cat run-output.out)" = "program output" ]
[ "$(wc -l < run-output.log | tr -d ' ')" = 1 ]
grep -q '^Built executable .* in ' run-output.log
"$X2C" run --plain -q run-output.x >quiet.out 2>quiet.log
[ ! -s quiet.log ]
"$X2C" run --plain -v run-output.x >verbose.out 2>verbose.log
grep -q 'Translate 1 x2c file' verbose.log
grep -q 'Generated 1 C file' verbose.log
grep -q '^Running ' verbose.log
"$X2C" run --plain -q -v run-output.x >quiet-verbose.out 2>quiet-verbose.log
if grep -q '^Running ' quiet-verbose.log; then exit 1; fi

# Native warnings use the x2c source unless generated-C locations are asked for.
printf 'int main(void) { char *raw = "hello"; return raw == "hello"; }\n' > warning.x
"$X2C" build -q -Xcc -Waddress -o warning warning.x 2>warning.log
grep -q 'warning.x:1:' warning.log
"$X2C" build -q --no-source-map -Xcc -Waddress -o warning warning.x 2>generated.log
grep -q 'warning.c:' generated.log

# A native include failure retains the location of the source include.
mkdir support
printf 'int helper(void) { return 0; }\n' > support/helpers.x
printf '#include "support/helpers.x"\nint main(void) { return 0; }\n' > missing-include.x
status=0
"$X2C" build -q missing-include.x >missing-include.log 2>&1 || status=$?
[ "$status" = 1 ]
grep -q 'missing-include.x:1:10:.*support/helpers.h.*file not found' missing-include.log

printf 'int main(void) { int n = ; }\n' > bad.x
status=0
"$X2C" build -c --diagnostics-file diagnostics.json bad.x >bad.log 2>&1 || status=$?
[ "$status" = 1 ]
grep -q '"code":"parse"' diagnostics.json

# A matching synthetic stage must use its own runtime and command directory.
mkdir -p home/builds/7/libexec
cp -R "$ROOT/lib" "$ROOT/etc" "$ROOT/src" home/
mkdir -p home/include/x2c
cp "$ROOT/builds/0/lib/"*.h "$ROOT/lib/"*.x home/include/x2c/
for header in "$ROOT/builds/0/lib"/*/*.h; do
  directory=$(basename "$(dirname "$header")")
  mkdir -p "home/include/x2c/$directory"
  cp -L "$header" "home/include/x2c/$directory/"
done
cp "$X2C" home/builds/7/x2c
cp "$COMMAND" home/builds/7/libexec/x2c-build
cp "$ROOT/builds/0/libx2c.a" home/builds/7/libx2c.a
export X2C_HOME="$BUILD/home"
stage="$BUILD/home/builds/7/x2c"
[ "$("$stage" env runtime_lib)" = "$BUILD/home/builds/7/libx2c.a" ]
printf 'int main(void) { return 0; }\n' > relative.c
X2C=home/builds/7/x2c home/builds/7/libexec/x2c-build build -q \
  --output relative relative.c
./relative
"$stage" build -q -v --build-dir bd --output staged @\@input.x 2>cold.log
"$stage" build -q -v --build-dir bd --output staged @\@input.x 2>warm.log
grep -q 'up-to-date translate' warm.log
# Only the command changes. Both build and script reuse must be invalidated.
mkdir scripts
printf '#!/usr/bin/env -S x2c script\nputs("ok");\n' > scripts/hello.x
export X2C_CACHE_DIR="$BUILD/cache"
[ "$(home/builds/7/libexec/x2c-build script scripts/hello.x)" = ok ]
[ "$("$stage" script scripts/hello.x)" = ok ]
"$stage" script -v scripts/hello.x >script.out 2>script-warm.log
if grep -q '^x2c: link ' script-warm.log; then exit 1; fi
printf '\n' >> home/builds/7/libexec/x2c-build
"$stage" build -q -v --build-dir bd --output staged @\@input.x 2>changed.log
if grep -q 'up-to-date translate' changed.log; then exit 1; fi
"$stage" script -v scripts/hello.x >script.out 2>script-changed.log
grep -q '^x2c: link ' script-changed.log

# Manifest preparation must find commands beside the matching stage driver.
mkdir project
cat > project/x2c.toml <<'MANIFEST'
[dependencies]
marker = "1"
[target.app]
kind = "executable"
sources = ["main.c"]
MANIFEST
printf 'int main(void) { return 0; }\n' > project/main.c
cat > home/builds/7/libexec/x2c-package <<'PACKAGE'
#!/bin/sh
[ "$1" = ensure ] || exit 1
printf '%s' "$X2C" > "$X2C_STAGE_MARKER"
PACKAGE
chmod +x home/builds/7/libexec/x2c-package
(cd project && X2C_STAGE_MARKER="$BUILD/nested-driver" "$stage" build -q)
[ "$(cat nested-driver)" = "$stage" ]

# Missing and mismatched commands fail at the driver/command boundary.
mv home/builds/7/libexec/x2c-build saved-command
status=0
"$stage" build --help >missing.log 2>&1 || status=$?
[ "$status" = 2 ]
grep -q 'missing x2c-build command' missing.log
mv saved-command home/builds/7/libexec/x2c-build
status=0
X2C_IDENTITY=wrong home/builds/7/libexec/x2c-build build --help >mismatch.log 2>&1 || status=$?
[ "$status" = 2 ]
grep -q 'compiler identity mismatch' mismatch.log
# A C-only prefix needs no language support or runtime for an archive.
unset X2C_HOME X2C_CACHE_DIR
mkdir -p bare/bin bare/libexec/x2c bare/lib
cp "$X2C" bare/bin/x2c
cp "$COMMAND" bare/libexec/x2c/
printf 'int value(void) { return 3; }\n' > plain.c
bare/bin/x2c build -q --kind static-library --output bare/libplain.a plain.c
[ -f bare/libplain.a ]
cp "$ROOT/builds/0/libx2c.a" bare/lib/
printf 'int main(void) { return 0; }\n' > plain.c
bare/bin/x2c build -q --output bare/app plain.c
bare/app
printf '%s\n' 'external build command probes passed'
