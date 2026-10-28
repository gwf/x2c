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

# Explicit runs share the script cache machinery, with their own entries.
mkdir run-sources run-logs
export X2C_CACHE_DIR="$BUILD/run-cache"
cat > run-sources/main.x <<'SOURCE'
#include <stdio.h>
int main(int argc, char **argv) {
  printf("%s:%s\n", argv[0], argc > 1 ? argv[1] : "none");
  return 0;
}
SOURCE
"$X2C" run --plain run-sources/main.x -- first >run-logs/out 2>run-logs/cold
grep -q 'Built executable' run-logs/cold
[ "$(cat run-logs/out)" = "$BUILD/run-sources/main.x:first" ]
"$X2C" run --plain run-sources/main.x -- second >run-logs/out 2>run-logs/warm
[ ! -s run-logs/warm ]
[ "$(cat run-logs/out)" = "$BUILD/run-sources/main.x:second" ]
"$X2C" run -v run-sources/main.x >run-logs/out 2>run-logs/verbose
grep -q '^x2c: run ' run-logs/verbose
if grep -q 'Built executable' run-logs/verbose; then exit 1; fi
printf '\n' >> run-sources/main.x
"$X2C" run --plain run-sources/main.x >run-logs/out 2>run-logs/edited
grep -q 'Built executable' run-logs/edited
"$X2C" run --plain --rebuild run-sources/main.x >run-logs/out 2>run-logs/rebuilt
grep -q 'Built executable' run-logs/rebuilt
"$X2C" run --clean run-sources/main.x
[ "$(find "$X2C_CACHE_DIR/runs" -name source | wc -l | tr -d ' ')" = 0 ]
"$X2C" run -q -o explicit-run run-sources/main.x >run-logs/out
[ -x explicit-run ]
"$X2C" run -q --build-dir retained-run run-sources/main.x >run-logs/out
[ -x retained-run/run ]
[ "$(find "$X2C_CACHE_DIR/runs" -name source | wc -l | tr -d ' ')" = 0 ]

# A second input's included file participates in executable freshness.
printf 'int value(void); int main(void) { return value(); }\n' >run-sources/multi.x
printf 'enum { RESULT = 0 };\n' >run-sources/constants.h
printf '#include "constants.h"\nint value(void) { return RESULT; }\n' >run-sources/value.x
run_multi() { "$X2C" run -I "$BUILD/run-sources" "$@"; }
run_multi -q run-sources/multi.x run-sources/value.x
run_multi --plain run-sources/multi.x run-sources/value.x 2>run-logs/multi-warm
[ ! -s run-logs/multi-warm ]
printf 'enum { RESULT = 7 };\n' >run-sources/constants.h
status=0
run_multi --plain run-sources/multi.x run-sources/value.x 2>run-logs/header || status=$?
[ "$status" = 7 ]
grep -q 'Built executable' run-logs/header
printf 'int value(void) { return 0; }\n' >run-sources/other.x
run_multi -q run-sources/multi.x run-sources/other.x
[ "$(find "$X2C_CACHE_DIR/runs" -name source | wc -l | tr -d ' ')" = 2 ]
run_multi --clean run-sources/multi.x run-sources/value.x
run_multi --clean run-sources/multi.x run-sources/other.x
"$X2C" run '-###' run-sources/not-created.x >run-logs/dry 2>&1
[ ! -e run-sources/not-created.x ]
unset X2C_CACHE_DIR
# Run keeps one default build receipt, while verbose shows the build phases.
printf 'int main(void) { puts("program output"); return 0; }\n' > run-output.x
"$X2C" run --plain run-output.x >run-output.out 2>run-output.log
[ "$(cat run-output.out)" = "program output" ]
[ "$(wc -l < run-output.log | tr -d ' ')" = 1 ]
grep -q '^Built executable .* in ' run-output.log
"$X2C" run --plain -q run-output.x >quiet.out 2>quiet.log
[ ! -s quiet.log ]
"$X2C" run --plain --rebuild -v run-output.x >verbose.out 2>verbose.log
grep -q 'Translate 1 x2c file' verbose.log
grep -q 'Generated 1 C file' verbose.log
grep -q '^x2c: run ' verbose.log
"$X2C" run --plain -q -v run-output.x >quiet-verbose.out 2>quiet-verbose.log
if grep -q '^x2c: run ' quiet-verbose.log; then exit 1; fi

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

# Source-mapped project meta groups retain included provider selection.
printf '#pragma once\nmeta int twice(int n) => n * 2;\n' > meta-provider.x
printf '#include "meta-provider.x"\nmeta int plus(int n) => twice(n) + 1;\nint main(void) { return $plus(3) != 7; }\n' > meta-include.x
"$X2C" run -q meta-include.x meta-provider.x

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
