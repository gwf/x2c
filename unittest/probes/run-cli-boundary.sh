#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/cli-boundary"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
FIXTURES="$ROOT/unittest/compiler-fixtures"

rm -rf "$BUILD"
mkdir -p "$BUILD/out" "$BUILD/a" "$BUILD/b" \
  "$BUILD/space dir" "$BUILD/includes/first" "$BUILD/includes/second"

"$X2C" --help >"$BUILD/top.help"
"$X2C" translate --help >"$BUILD/translate.help"
"$X2C" build --help >"$BUILD/build.help"
"$X2C" run --help >"$BUILD/run.help"
"$X2C" bootstrap --help >"$BUILD/bootstrap.help"
"$X2C" help --help >"$BUILD/help.help"
"$X2C" help help >"$BUILD/help-command.help"
"$X2C" -h >"$BUILD/top-short.help"
"$X2C" translate -h >"$BUILD/translate-short.help"
"$X2C" build -h >"$BUILD/build-short.help"
"$X2C" run -h >"$BUILD/run-short.help"
"$X2C" bootstrap -h >"$BUILD/bootstrap-short.help"
"$X2C" help -h >"$BUILD/help-short.help"
diff -u "$FIXTURES/cli-top.help" "$BUILD/top.help"
diff -u "$FIXTURES/cli-translate.help" "$BUILD/translate.help"
diff -u "$FIXTURES/cli-build.help" "$BUILD/build.help"
diff -u "$FIXTURES/cli-run.help" "$BUILD/run.help"
diff -u "$FIXTURES/cli-bootstrap.help" "$BUILD/bootstrap.help"
diff -u "$FIXTURES/cli-help.help" "$BUILD/help.help"
cmp "$BUILD/help.help" "$BUILD/help-command.help"
cmp "$BUILD/top.help" "$BUILD/top-short.help"
cmp "$BUILD/translate.help" "$BUILD/translate-short.help"
cmp "$BUILD/build.help" "$BUILD/build-short.help"
cmp "$BUILD/run.help" "$BUILD/run-short.help"
cmp "$BUILD/bootstrap.help" "$BUILD/bootstrap-short.help"
cmp "$BUILD/help.help" "$BUILD/help-short.help"
[[ $("$X2C" --version) == "x2c 0.12.0" ]]
[[ $("$X2C" -V) == "x2c 0.12.0" ]]
"$X2C" build -q --help >"$BUILD/build-short-quiet.help"
"$X2C" build --compile-only --help >"$BUILD/build-long-compile.help"
"$X2C" build -j 1 --help >"$BUILD/build-short-jobs.help"
"$X2C" build --jobs 1 --help >"$BUILD/build-long-jobs.help"
cmp "$BUILD/build.help" "$BUILD/build-short-quiet.help"
cmp "$BUILD/build.help" "$BUILD/build-long-compile.help"
cmp "$BUILD/build.help" "$BUILD/build-short-jobs.help"
cmp "$BUILD/build.help" "$BUILD/build-long-jobs.help"

set +e
"$X2C" bootstrap --prefix "$BUILD/not-an-ape" \
  >"$BUILD/bootstrap.stdout" 2>"$BUILD/bootstrap.stderr"
bootstrap_status=$?
set -e
[[ $bootstrap_status == 2 ]]
grep -Fq "has no embedded source payload" "$BUILD/bootstrap.stderr"

printf '#include "x2c.x"\nint quoted(void) { return 7; }\n' \
  >"$BUILD/space dir/quoted.x"
printf 'translate\n--out-dir\n%s\n"%s"\n' \
  "$BUILD/out" "$BUILD/space dir/quoted.x" >"$BUILD/inner.rsp"
printf '# first non-whitespace comment\n@%s\n' "$BUILD/inner.rsp" \
  >"$BUILD/outer.rsp"
"$X2C" @"$BUILD/outer.rsp"
[[ -f "$BUILD/out/quoted.c" && -f "$BUILD/out/quoted.h" ]]

# An omitted output directory writes beside the invocation, not the source.
(cd "$BUILD" && "$X2C" translate "$BUILD/space dir/quoted.x")
cmp "$BUILD/quoted.c" "$BUILD/out/quoted.c"
cmp "$BUILD/quoted.h" "$BUILD/out/quoted.h"
[[ -f "$BUILD/quoted.d" ]]
[[ ! -e "$BUILD/space dir/quoted.c" ]]


printf '#include "x2c.x"\n' >"$BUILD/space dir/hash#name.x"
printf "translate --out-dir %s '%s/space dir/hash#name.x'\n" \
  "$BUILD/out" "$BUILD" >"$BUILD/single-quote.rsp"
"$X2C" @"$BUILD/single-quote.rsp"
printf 'translate --out-dir %s %s/space\\ dir/quoted.x\n' \
  "$BUILD/out" "$BUILD" >"$BUILD/backslash.rsp"
"$X2C" @"$BUILD/backslash.rsp"

printf '#include "x2c.x"\n' >"$BUILD/@literal.x"
printf 'translate --out-dir out @@literal.x\n' >"$BUILD/literal.rsp"
(cd "$BUILD" && "$X2C" @literal.rsp)
[[ -f "$BUILD/out/@literal.c" ]]

printf '@%s\n' "$BUILD/cycle-b.rsp" >"$BUILD/cycle-a.rsp"
printf '@%s\n' "$BUILD/cycle-a.rsp" >"$BUILD/cycle-b.rsp"
set +e
"$X2C" @"$BUILD/cycle-a.rsp" >"$BUILD/cycle.stdout" \
  2>"$BUILD/cycle.stderr"
cycle_status=$?
printf 'translate "unterminated\n' >"$BUILD/malformed.rsp"
"$X2C" @"$BUILD/malformed.rsp" >"$BUILD/malformed.stdout" \
  2>"$BUILD/malformed.stderr"
malformed_status=$?
printf '\377' >"$BUILD/invalid-utf8.rsp"
"$X2C" @"$BUILD/invalid-utf8.rsp" >"$BUILD/utf8.stdout" \
  2>"$BUILD/utf8.stderr"
utf8_status=$?
set -e
[[ $cycle_status == 2 && $malformed_status == 2 && $utf8_status == 2 ]]
grep -Fq "recursive response-file inclusion" "$BUILD/cycle.stderr"
grep -Fq "unterminated quote" "$BUILD/malformed.stderr"
grep -Fq "input is not valid UTF-8" "$BUILD/utf8.stderr"

printf '#include "x2c.x"\n' >"$BUILD/a/item.x"
printf '#include "x2c.x"\n' >"$BUILD/b/item.x"

"$X2C" translate --dump-cpp "$BUILD/a/item.x" \
  >"$BUILD/dump-cpp.stdout" 2>"$BUILD/dump-cpp.stderr"
"$X2C" translate --dump-cpp-text "$BUILD/a/item.x" \
  >"$BUILD/dump-cpp-text.stdout" 2>"$BUILD/dump-cpp-text.stderr"
cmp "$BUILD/dump-cpp.stdout" "$BUILD/dump-cpp-text.stdout"
cmp "$BUILD/dump-cpp.stderr" "$BUILD/dump-cpp-text.stderr"

"$X2C" translate --color=auto --out-dir "$BUILD/out" \
  "$BUILD/a/item.x" >"$BUILD/receipt.stdout" \
  2>"$BUILD/receipt.stderr"
[[ ! -s "$BUILD/receipt.stdout" ]]
grep -Fq "Translated 1 x2c file to $BUILD/out" "$BUILD/receipt.stderr"
grep -Fq "Generated 1 C file and 1 header" "$BUILD/receipt.stderr"
if LC_ALL=C grep -q $'\033' "$BUILD/receipt.stderr" ||
   LC_ALL=C grep -q $'\r' "$BUILD/receipt.stderr"; then
  echo "redirected receipt contains terminal control bytes" >&2
  exit 1
fi

"$X2C" translate --quiet --out-dir "$BUILD/out" "$BUILD/a/item.x" \
  >"$BUILD/quiet.stdout" 2>"$BUILD/quiet.stderr"
[[ ! -s "$BUILD/quiet.stdout" && ! -s "$BUILD/quiet.stderr" ]]

"$X2C" translate --color=always --out-dir "$BUILD/out" \
  "$BUILD/a/item.x" >"$BUILD/color.stdout" 2>"$BUILD/color.stderr"
LC_ALL=C grep -q $'\033' "$BUILD/color.stderr"
"$X2C" translate --plain --color=always --out-dir "$BUILD/out" \
  "$BUILD/a/item.x" >"$BUILD/plain.stdout" 2>"$BUILD/plain.stderr"
if LC_ALL=C grep -q $'\033' "$BUILD/plain.stderr" ||
   LC_ALL=C grep -q $'\r' "$BUILD/plain.stderr"; then
  echo "plain receipt contains terminal control bytes" >&2
  exit 1
fi

"$X2C" translate --verbose --out-dir "$BUILD/out" "$BUILD/a/item.x" \
  >"$BUILD/verbose.stdout" 2>"$BUILD/verbose.stderr"
grep -Fq "x2c: translate --out-dir" "$BUILD/verbose.stderr"
if grep -Fq "Translated 1 x2c file" "$BUILD/verbose.stderr"; then
  echo "verbose transcript contains a completion receipt" >&2
  exit 1
fi

set +e
"$X2C" translate --color=invalid --out-dir "$BUILD/out" \
  "$BUILD/a/item.x" >"$BUILD/color-invalid.stdout" \
  2>"$BUILD/color-invalid.stderr"
color_status=$?
"$X2C" translate --color= --out-dir "$BUILD/out" \
  "$BUILD/a/item.x" >"$BUILD/color-empty.stdout" \
  2>"$BUILD/color-empty.stderr"
color_empty_status=$?
set -e
[[ $color_status == 2 && $color_empty_status == 2 ]]
grep -Fq "invalid color mode 'invalid'" "$BUILD/color-invalid.stderr"
grep -Fq "color requires auto, always, or never" \
  "$BUILD/color-empty.stderr"

rm -f "$BUILD/out/item.c" "$BUILD/out/item.h"
set +e
"$X2C" translate --out-dir "$BUILD/out" "$BUILD/a/item.x" \
  "$BUILD/missing.x" >"$BUILD/preflight.stdout" 2>"$BUILD/preflight.stderr"
preflight_status=$?
"$X2C" translate --out-dir "$BUILD/out" "$BUILD/a/item.x" \
  "$BUILD/b/item.x" >"$BUILD/collision.stdout" 2>"$BUILD/collision.stderr"
collision_status=$?
"$X2C" translate --out-dir "$BUILD/absent" "$BUILD/a/item.x" \
  >"$BUILD/out-dir.stdout" 2>"$BUILD/out-dir.stderr"
out_dir_status=$?
"$X2C" translate --out-dir "$BUILD/out" "$BUILD/a" \
  >"$BUILD/directory.stdout" 2>"$BUILD/directory.stderr"
directory_status=$?
set -e
[[ $preflight_status == 2 && $collision_status == 2 ]]
[[ $out_dir_status == 2 && $directory_status == 2 ]]
[[ ! -e "$BUILD/out/item.c" && ! -e "$BUILD/out/item.h" ]]
grep -Fq "$BUILD/missing.x" "$BUILD/preflight.stderr"
grep -Fq "$BUILD/a" "$BUILD/directory.stderr"
grep -Fq "inputs produce the same output stem 'item'" \
  "$BUILD/collision.stderr"

"$X2C" translate -### --out-dir "$BUILD/out" "$BUILD/a/item.x" \
  >"$BUILD/dry-run.stdout" 2>"$BUILD/dry-run.stderr"
[[ ! -e "$BUILD/out/item.c" && ! -e "$BUILD/out/item.h" ]]
grep -Fq "x2c: translate --out-dir" "$BUILD/dry-run.stderr"

set +e
"$X2C" "$BUILD/a/item.x" >"$BUILD/no-command.stdout" \
  2>"$BUILD/no-command.stderr"
no_command_status=$?
"$X2C" -o "$BUILD/out" "$BUILD/a/item.x" >"$BUILD/old-o.stdout" \
  2>"$BUILD/old-o.stderr"
old_o_status=$?
"$X2C" -dump-ast "$BUILD/a/item.x" >"$BUILD/one-dash.stdout" \
  2>"$BUILD/one-dash.stderr"
one_dash_status=$?
set -e
[[ $no_command_status == 2 && $old_o_status == 2 ]]
[[ $one_dash_status == 2 ]]
grep -Fq "expected a command before" "$BUILD/no-command.stderr"
grep -Fq "option '-o' was removed" "$BUILD/old-o.stderr"
grep -Fq "one-dash long option '-dump-ast' was removed" \
  "$BUILD/one-dash.stderr"

printf 'typedef struct Pick { int first; } Pick;\n' \
  >"$BUILD/includes/first/choice.x"
printf 'typedef struct Pick { int second; } Pick;\n' \
  >"$BUILD/includes/second/choice.x"
printf '#include "choice.x"\nint read(Pick p) { return p.first; }\n' \
  >"$BUILD/includes/source.x"
"$X2C" translate --dump-symbols -I "$BUILD/includes/first" \
  -I "$BUILD/includes/second" "$BUILD/includes/source.x" \
  >"$BUILD/includes/first.symbols"
"$X2C" translate --dump-symbols -I "$BUILD/includes/second" \
  -I "$BUILD/includes/first" "$BUILD/includes/source.x" \
  >"$BUILD/includes/second.symbols"
"$X2C" translate --dump-symbols \
  --x-include-dir "$BUILD/includes/first" "$BUILD/includes/source.x" \
  >"$BUILD/includes/x-only.symbols"
grep -Fq "( struct Pick first ) ==>" "$BUILD/includes/first.symbols"
grep -Fq "( struct Pick second ) ==>" "$BUILD/includes/second.symbols"
grep -Fq "( struct Pick first ) ==>" "$BUILD/includes/x-only.symbols"

mkdir -p "$BUILD/batch" "$BUILD/solo"
"$X2C" translate --out-dir "$BUILD/batch" \
  "$BUILD/a/item.x" "$BUILD/space dir/quoted.x"
"$X2C" translate --out-dir "$BUILD/solo" "$BUILD/a/item.x"
"$X2C" translate --out-dir "$BUILD/solo" "$BUILD/space dir/quoted.x"
cmp "$BUILD/batch/item.c" "$BUILD/solo/item.c"
cmp "$BUILD/batch/item.h" "$BUILD/solo/item.h"
cmp "$BUILD/batch/quoted.c" "$BUILD/solo/quoted.c"
cmp "$BUILD/batch/quoted.h" "$BUILD/solo/quoted.h"
grep -Fq "space\\ dir/quoted.x" "$BUILD/batch/quoted.d"
grep -Fq "hash\\#name.x" "$BUILD/out/hash#name.d"

mkdir -p "$BUILD/deps/src" "$BUILD/deps/bad-src" "$BUILD/deps/out"
mkdir -p "$BUILD/deps/live-out" "$BUILD/deps/repo-out"
printf 'typedef struct Leaf { int value; } Leaf;\n' \
  >"$BUILD/deps/src/leaf.x"
printf '#include "leaf.x"\n' >"$BUILD/deps/src/middle.x"
printf '#include "x2c.x"\n#include "middle.x"\n' \
  >"$BUILD/deps/src/root.x"
printf '#include "x2c.x"\nint other(void) { return 1; }\n' \
  >"$BUILD/deps/src/other.x"
"$X2C" translate --out-dir "$BUILD/deps/out" -I "$BUILD/deps/src" \
  "$BUILD/deps/src/root.x" "$BUILD/deps/src/other.x"
grep -Fq "$BUILD/deps/src/root.x" "$BUILD/deps/out/root.d"
grep -Fq "$BUILD/deps/src/middle.x" "$BUILD/deps/out/root.d"
grep -Fq "$BUILD/deps/src/leaf.x" "$BUILD/deps/out/root.d"
grep -Fq "$ROOT/etc/symbols.xlisp" "$BUILD/deps/out/root.d"
grep -Fq "$BUILD/deps/src/leaf.x:" "$BUILD/deps/out/root.d"
"$X2C" translate --live-symbols --out-dir "$BUILD/deps/live-out" \
  -I "$BUILD/deps/src" "$BUILD/deps/src/root.x"
grep -Fq "$BUILD/deps/src/leaf.x" "$BUILD/deps/live-out/root.d"
"$X2C" translate --out-dir "$BUILD/deps/repo-out" "$ROOT/src/main.x"
grep -Fq "$ROOT/etc/header-symbols.xlisp" \
  "$BUILD/deps/repo-out/main.d"
cp "$BUILD/deps/out/root.d" "$BUILD/deps/root.d.saved"
printf 'int broken( {\n' >"$BUILD/deps/bad-src/root.x"
set +e
"$X2C" translate --out-dir "$BUILD/deps/out" -I "$BUILD/deps/src" \
  "$BUILD/deps/bad-src/root.x" >"$BUILD/deps/stale.stdout" \
  2>"$BUILD/deps/stale.stderr"
stale_dep_status=$?
set -e
[[ $stale_dep_status == 1 ]]
cmp "$BUILD/deps/root.d.saved" "$BUILD/deps/out/root.d"

rm -f "$BUILD/deps/out/root.d"
"$X2C" translate --no-deps --out-dir "$BUILD/deps/out" \
  -I "$BUILD/deps/src" "$BUILD/deps/src/root.x"
[[ ! -e "$BUILD/deps/out/root.d" ]]

"$X2C" translate --no-phony-deps \
  --dep-file "$BUILD/deps/custom.d" --dep-target "custom target" \
  --out-dir "$BUILD/deps/out" -I "$BUILD/deps/src" \
  "$BUILD/deps/src/root.x"
grep -Fq "custom\\ target:" "$BUILD/deps/custom.d"
[[ $(wc -l <"$BUILD/deps/custom.d" | tr -d ' ') == 1 ]]

set +e
"$X2C" translate --dep-file "$BUILD/deps/ambiguous.d" \
  --out-dir "$BUILD/deps/out" "$BUILD/deps/src/root.x" \
  "$BUILD/deps/src/other.x" >"$BUILD/deps/multi.stdout" \
  2>"$BUILD/deps/multi.stderr"
multi_dep_status=$?
set -e
[[ $multi_dep_status == 2 ]]
grep -Fq "require exactly one input" "$BUILD/deps/multi.stderr"

printf 'int broken( {\n' >"$BUILD/deps/bad-src/bad.x"
set +e
"$X2C" translate --out-dir "$BUILD/deps/out" -I "$BUILD/deps/src" \
  "$BUILD/deps/bad-src/bad.x" >"$BUILD/deps/bad.stdout" \
  2>"$BUILD/deps/bad.stderr"
bad_dep_status=$?
set -e
[[ $bad_dep_status == 1 ]]
[[ ! -e "$BUILD/deps/out/bad.d" ]]

mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}
{
  printf 'SOURCE := build/cli-boundary/deps/src\n'
  printf 'BUILD := build/cli-boundary/deps/make-out\n'
  printf 'X2CFLAGS += -I $(SOURCE)\n'
  printf 'include ../etc/x2c.mk\n'
  printf 'default: $(C_FILES)\n'
} >"$BUILD/deps/Makefile"
make -C "$ROOT/unittest" -f build/cli-boundary/deps/Makefile \
  default >/dev/null
root_before=$(mtime "$BUILD/deps/make-out/root.c")
other_before=$(mtime "$BUILD/deps/make-out/other.c")
sleep 1
touch "$BUILD/deps/src/leaf.x"
make -C "$ROOT/unittest" -f build/cli-boundary/deps/Makefile \
  default >/dev/null
root_after=$(mtime "$BUILD/deps/make-out/root.c")
other_after=$(mtime "$BUILD/deps/make-out/other.c")
[[ $root_after -gt $root_before ]]
[[ $other_after == "$other_before" ]]

mkdir -p "$BUILD/direct/a" "$BUILD/direct/b"
printf '#include "x2c.x"\nint main(void) { puts("one"); return 0; }\n' \
  >"$BUILD/direct/one.x"
"$X2C" build --output "$BUILD/direct/one" "$BUILD/direct/one.x"
[[ $("$BUILD/direct/one") == one ]]

(
  cd "$BUILD/direct"
  "$X2C" build --save-temps --output keep-default one.x
)
[[ $(find "$BUILD/direct/.x2c-build/gen" -name one.c | wc -l |
      tr -d ' ') == 1 ]]
"$X2C" build --save-temps="$BUILD/direct/saved" \
  --output "$BUILD/direct/keep-assigned" "$BUILD/direct/one.x"
[[ $(find "$BUILD/direct/saved/gen" -name one.c | wc -l |
      tr -d ' ') == 1 ]]

printf '#include "x2c.x"\nint helper(void) { return 4; }\n' \
  >"$BUILD/direct/helper.x"
printf '%s\n' '#include "x2c.x"' 'int helper(void);' 'int main(void) {' \
  '  printf("%d\n", helper()); return helper() == 4 ? 0 : 1;' '}' \
  >"$BUILD/direct/many-main.x"
"$X2C" build --output "$BUILD/direct/many" \
  "$BUILD/direct/many-main.x" "$BUILD/direct/helper.x"
[[ $("$BUILD/direct/many") == 4 ]]

printf 'int c_source(void) { return 2; }\n' >"$BUILD/direct/source.c"
"$X2C" build -### -j2 -I"$BUILD/includes/first" -DCLI_ATTACHED=1 \
  -Oarbitrary --output "$BUILD/direct/dry-run" "$BUILD/direct/source.c" \
  >"$BUILD/direct/dry-run.stdout" 2>"$BUILD/direct/dry-run.stderr"
grep -Fq -- '-Oarbitrary' "$BUILD/direct/dry-run.stderr"
grep -Fq -- '-DCLI_ATTACHED=1' "$BUILD/direct/dry-run.stderr"
printf 'int object_value(void) { return 3; }\n' >"$BUILD/direct/object.c"
printf 'int archive_value(void) { return 4; }\n' >"$BUILD/direct/archive.c"
host_cc=${CC:-cc}
host_ar=${AR:-ar}
"$host_cc" -c "$BUILD/direct/object.c" -o "$BUILD/direct/object.o"
"$host_cc" -c "$BUILD/direct/archive.c" -o "$BUILD/direct/archive.o"
"$host_ar" rcs "$BUILD/direct/libarchive.a" "$BUILD/direct/archive.o"
printf '%s\n' '#include "x2c.x"' \
  'int c_source(void); int object_value(void);' \
  'int archive_value(void);' 'int main(void) {' \
  '  int value = c_source() + object_value() + archive_value();' \
  '  printf("%d\n", value); return value == 9 ? 0 : 1;' '}' \
  >"$BUILD/direct/mixed.x"
"$X2C" build --output "$BUILD/direct/mixed" \
  "$BUILD/direct/mixed.x" "$BUILD/direct/source.c" \
  "$BUILD/direct/object.o" "$BUILD/direct/libarchive.a"
[[ $("$BUILD/direct/mixed") == 9 ]]

printf '#include "x2c.x"\nint library_value(void) { return 9; }\n' \
  >"$BUILD/direct/library.x"
"$X2C" build --kind static-library \
  --output "$BUILD/direct/libdirect.a" "$BUILD/direct/library.x"
"$host_ar" -t "$BUILD/direct/libdirect.a" >"$BUILD/direct/archive.list"
[[ $(grep -c '\.o$' "$BUILD/direct/archive.list") == 1 ]]

# A static-library build does not link x2c and must not require a matching
# runtime beside the invoking compiler. This is the APE bootstrap seam.
mkdir -p "$BUILD/standalone/bin"
cp "$X2C" "$BUILD/standalone/bin/x2c"
(
  cd "$BUILD/standalone"
  ./bin/x2c build --kind static-library \
    --output libstandalone.a ../direct/source.c
)
[[ -f "$BUILD/standalone/libstandalone.a" ]]

printf '%s\n' '#include <stdio.h>' 'int library_value(void);' \
  'int main(void) {' \
  '  printf("%d\n", library_value()); return 0;' '}' \
  >"$BUILD/direct/consumer.c"
"$host_cc" "$BUILD/direct/consumer.c" "$BUILD/direct/libdirect.a" \
  "$ROOT/builds/0/libx2c.a" -lm -o "$BUILD/direct/consumer"
[[ $("$BUILD/direct/consumer") == 9 ]]

printf '#include "x2c.x"\nint first_item(void) { return 5; }\n' \
  >"$BUILD/direct/a/item.x"
printf '#include "x2c.x"\nint second_item(void) { return 6; }\n' \
  >"$BUILD/direct/b/item.x"
printf '%s\n' 'int first_item(void); int second_item(void);' \
  'int main(void) {' \
  '  return first_item() + second_item() == 11 ? 0 : 1;' '}' \
  >"$BUILD/direct/collision-main.c"
"$X2C" build --build-dir "$BUILD/direct/collision-build" \
  --output "$BUILD/direct/collision" "$BUILD/direct/a/item.x" \
  "$BUILD/direct/b/item.x" "$BUILD/direct/collision-main.c"
"$BUILD/direct/collision"
[[ $(find "$BUILD/direct/collision-build/gen" -name item.c | wc -l |
      tr -d ' ') == 2 ]]

"$X2C" build -c --output "$BUILD/direct/single.o" \
  "$BUILD/direct/source.c"
[[ -f "$BUILD/direct/single.o" ]]
"$X2C" build -c --build-dir "$BUILD/direct/multiple-objects" \
  "$BUILD/direct/helper.x" "$BUILD/direct/source.c"
[[ $(find "$BUILD/direct/multiple-objects/obj" -name '*.o' | wc -l |
      tr -d ' ') == 2 ]]

set +e
"$X2C" build -c --output "$BUILD/direct/ambiguous.o" \
  "$BUILD/direct/source.c" "$BUILD/direct/object.c" \
  >"$BUILD/direct/compile-only.stdout" \
  2>"$BUILD/direct/compile-only.stderr"
compile_only_status=$?
"$X2C" run "$BUILD/direct/one.x" \
  >"$BUILD/direct/run.stdout" 2>"$BUILD/direct/run.stderr"
run_status=$?
set -e
[[ $compile_only_status == 2 && $run_status == 0 ]]
[[ $(cat "$BUILD/direct/run.stdout") == one ]]

"$X2C" build -### --build-dir "$BUILD/direct/matched-dry" \
  "$BUILD/direct/source.c" >"$BUILD/direct/matched.stdout" \
  2>"$BUILD/direct/matched.stderr"
grep -Fq "$ROOT/builds/0/libx2c.a" "$BUILD/direct/matched.stderr"
[[ ! -e "$BUILD/direct/matched-dry" ]]

manifest="$BUILD/manifest"
mkdir -p "$manifest/src" "$manifest/nested" "$manifest/include"
printf 'int leaf_value(void) { return 8; }\n' >"$manifest/src/leaf.x"
printf '%s\n' '#include "x2c.x"' '#include "leaf.x"' \
  'int core_value(void) { return leaf_value(); }' \
  >"$manifest/src/core.x"
printf '#define NATIVE_VALUE 2\n' >"$manifest/include/native.h"
printf '%s\n' '#include "native.h"' 'int native_value(void) {' \
  '  return NATIVE_VALUE;' '}' >"$manifest/src/native.c"
printf '%s\n' '#include "x2c.x"' \
  'int core_value(void); int native_value(void);' 'int main(void) {' \
  '  int value = core_value() + native_value();' \
  '  printf("%d\n", value); return 0;' '}' >"$manifest/src/main.x"
printf 'int main(void) { return 99; }\n' >"$manifest/src/excluded.x"
{
  printf '[project]\n'
  printf 'name = "manifest-probe"\n'
  printf 'default-target = "app"\n'
  printf 'build-dir = "out"\n\n'
  printf '[target.core]\n'
  printf 'kind = "static-library"\n'
  printf 'sources = ["src/**/core.x", "src/leaf.x"]\n\n'
  printf '[target.app]\n'
  printf 'sources = ["src/*.x", "src/native.c"]\n'
  printf 'exclude = ["src/core.x", "src/leaf.x", "src/excluded.x"]\n'
  printf 'dependencies = ["core"]\n'
  printf 'include-dirs = ["include"]\n\n'
  printf '[target.app.profile.release]\n'
  printf 'optimization = "O2"\n'
  printf 'debug = true\n'
} >"$manifest/x2c.toml"

(cd "$manifest/nested" && "$X2C" build -v --profile release) \
  >"$manifest/first.stdout" 2>"$manifest/first.stderr"
[[ $("$manifest/out/app") == 10 ]]
grep -Fq "excluded $manifest/src/excluded.x from target app" \
  "$manifest/first.stderr"
archive_line=$(grep -n '^x2c: archive ' "$manifest/first.stderr" |
  cut -d: -f1)
link_line=$(grep -n '^x2c: link ' "$manifest/first.stderr" |
  cut -d: -f1)
[[ $archive_line -lt $link_line ]]
grep -Fq -- '-O2 -g' "$manifest/first.stderr"

(cd "$manifest/nested" && "$X2C" build -v --profile release) \
  >"$manifest/noop.stdout" 2>"$manifest/noop.stderr"
[[ $(grep -c '^x2c: up-to-date ' "$manifest/noop.stderr") == 9 ]]
[[ $(grep -c '^x2c: compile ' "$manifest/noop.stderr") == 0 ]]

printf '%s\n' '#include "x2c.x"' \
  'int core_value(void); int native_value(void);' 'int main(void) {' \
  '  int value = core_value() + native_value();' \
  '  printf("%d\n", value); return value < 0;' '}' \
  >"$manifest/src/main.x"
(cd "$manifest/nested" && "$X2C" build -v --profile release) \
  >"$manifest/source.stdout" 2>"$manifest/source.stderr"
[[ $(grep -c '^x2c: translate ' "$manifest/source.stderr") == 1 ]]
[[ $(grep -c '^x2c: compile ' "$manifest/source.stderr") == 1 ]]

printf 'int leaf_value(void) { return 10; }\n' >"$manifest/src/leaf.x"
(cd "$manifest/nested" && "$X2C" build -v --profile release) \
  >"$manifest/xdep.stdout" 2>"$manifest/xdep.stderr"
grep -Fq "x2c: translate --out-dir" "$manifest/xdep.stderr"
grep -Fq "$manifest/src/core.x" "$manifest/xdep.stderr"
grep -Fq "x2c: archive " "$manifest/xdep.stderr"
[[ $("$manifest/out/app") == 12 ]]

printf '#define NATIVE_VALUE 3\n' >"$manifest/include/native.h"
(cd "$manifest/nested" && "$X2C" build -v --profile release) \
  >"$manifest/cdep.stdout" 2>"$manifest/cdep.stderr"
[[ $(grep -c '^x2c: compile ' "$manifest/cdep.stderr") == 1 ]]
grep -Fq "$manifest/src/native.c" "$manifest/cdep.stderr"
[[ $("$manifest/out/app") == 13 ]]

(cd "$manifest/nested" && "$X2C" build -v --profile release -O0) \
  >"$manifest/override.stdout" 2>"$manifest/override.stderr"
grep '^x2c: compile ' "$manifest/override.stderr" |
  grep -Fq -- '-O0'
! grep '^x2c: compile ' "$manifest/override.stderr" |
  grep -Fq -- '-O2'

(cd "$manifest/nested" && "$X2C" build -v) \
  >"$manifest/profile-change.stdout" \
  2>"$manifest/profile-change.stderr"
[[ $(grep -c '^x2c: compile ' "$manifest/profile-change.stderr") -ge 1 ]]

real_cc=$(command -v cc)
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$real_cc" \
  >"$manifest/cc-wrapper"
chmod +x "$manifest/cc-wrapper"
(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --cc "$manifest/cc-wrapper") >"$manifest/tool-first.stdout" \
  2>"$manifest/tool-first.stderr"
(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --cc "$manifest/cc-wrapper") >"$manifest/tool-noop.stdout" \
  2>"$manifest/tool-noop.stderr"
[[ $(grep -c '^x2c: compile ' "$manifest/tool-noop.stderr") == 0 ]]
printf '#!/usr/bin/env bash\n# changed identity\nexec "%s" "$@"\n' "$real_cc" \
  >"$manifest/cc-wrapper"
(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --cc "$manifest/cc-wrapper") >"$manifest/tool-change.stdout" \
  2>"$manifest/tool-change.stderr"
[[ $(grep -c '^x2c: compile ' "$manifest/tool-change.stderr") -ge 1 ]]

rm "$manifest/out/app"
(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --cc "$manifest/cc-wrapper") >"$manifest/removed.stdout" \
  2>"$manifest/removed.stderr"
[[ $(grep -c '^x2c: link ' "$manifest/removed.stderr") == 1 ]]

final_state=$(find "$manifest/out/.x2c/app/.x2c-state" \
  -name 'final-*' -type f)
printf 'corrupt private state\n' >"$final_state"
(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --cc "$manifest/cc-wrapper") >"$manifest/corrupt.stdout" \
  2>"$manifest/corrupt.stderr"
[[ $(grep -c '^x2c: link ' "$manifest/corrupt.stderr") == 1 ]]

"$X2C" run --manifest-path "$manifest/x2c.toml" \
  --profile release -- -leading program.x \
  >"$manifest/run.stdout" 2>"$manifest/run.stderr"
[[ $(cat "$manifest/run.stdout") == 13 ]]

mkdir -p "$manifest/direct-nearby"
printf '[broken\n' >"$manifest/direct-nearby/x2c.toml"
printf 'int main(void) { return 0; }\n' \
  >"$manifest/direct-nearby/main.c"
(cd "$manifest/direct-nearby" && "$X2C" build \
  --output explicit main.c)
[[ -x "$manifest/direct-nearby/explicit" ]]

{
  printf '[target.a]\n'
  printf 'sources = ["src/native.c"]\n'
  printf 'dependencies = ["b"]\n'
  printf '[target.b]\n'
  printf 'kind = "static-library"\n'
  printf 'sources = ["src/native.c"]\n'
  printf 'dependencies = ["a"]\n'
} >"$manifest/cycle.toml"
{
  printf '[target.missing]\n'
  printf 'sources = ["src/no-match-*.x"]\n'
} >"$manifest/unmatched.toml"
set +e
"$X2C" build --manifest-path "$manifest/cycle.toml" --target a \
  >"$manifest/cycle.stdout" 2>"$manifest/cycle.stderr"
cycle_manifest_status=$?
"$X2C" build --manifest-path "$manifest/unmatched.toml" \
  >"$manifest/unmatched.stdout" 2>"$manifest/unmatched.stderr"
unmatched_status=$?
set -e
[[ $cycle_manifest_status == 2 && $unmatched_status == 2 ]]
grep -Fq 'target dependency cycle' "$manifest/cycle.stderr"
grep -Fq 'unmatched source pattern' "$manifest/unmatched.stderr"

equivalent="$BUILD/equivalent"
mkdir -p "$equivalent"
printf 'int main(void) { return 0; }\n' >"$equivalent/main.c"
{
  printf '[project]\n'
  printf 'default-target = "app"\n'
  printf '[target.app]\n'
  printf 'sources = ["main.c"]\n'
} >"$equivalent/x2c.toml"
"$X2C" build -### --manifest-path "$equivalent/x2c.toml" \
  --build-dir "$equivalent/build" --output "$equivalent/app" \
  >"$equivalent/manifest.stdout" 2>"$equivalent/manifest.stderr"
"$X2C" build -### --build-dir "$equivalent/build/.x2c/app" \
  --output "$equivalent/app" "$equivalent/main.c" \
  >"$equivalent/direct.stdout" 2>"$equivalent/direct.stderr"
cmp "$equivalent/manifest.stderr" "$equivalent/direct.stderr"

echo "CLI, dependency, build, run, manifest, and state probes: 93 passed"
