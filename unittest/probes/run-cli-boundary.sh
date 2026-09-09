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

retained="$BUILD/direct/retained-link"
mkdir -p "$retained/first" "$retained/second"
for value in 1 2 3; do
  printf 'int library_value(void) { return %s; }\n' "$value" \
    >"$retained/value.c"
  "$host_cc" -c "$retained/value.c" -o "$retained/value.o"
  library_dir="$retained/second"
  if [[ $value == 3 ]]; then library_dir="$retained/first"; fi
  "$host_ar" rcs "$library_dir/libvalue.a" "$retained/value.o"
  "$X2C" build -v --build-dir "$retained/build" \
    --output "$retained/app" "$BUILD/direct/consumer.c" \
    -L "$retained/first" -L "$retained/second" -lvalue \
    >"$retained/$value.stdout" 2>"$retained/$value.stderr"
  [[ $("$retained/app") == "$value" ]]
  if [[ $value != 1 ]]; then
    grep -Fq 'x2c: up-to-date compile ' "$retained/$value.stderr"
    grep -Fq 'x2c: link ' "$retained/$value.stderr"
  fi
done

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

cat >"$BUILD/direct/terminal.c" <<'EOF'
#include <stdio.h>
#include <unistd.h>
int main(void) {
  printf("ready tty=%d%d%d\n", isatty(0), isatty(1), isatty(2));
  fflush(stdout);
  return getchar() == 'x' ? 23 : 1;
}
EOF
python3 - "$X2C" "$BUILD/direct/terminal.c" <<'PY'
import os
import pty
import select
import signal
import subprocess
import sys
import time

master, slave = pty.openpty()
process = subprocess.Popen(
    [sys.argv[1], 'run', sys.argv[2]],
    stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
os.close(slave)
try:
    output = b''
    deadline = time.monotonic() + 20
    while b'ready tty=111' not in output:
        remaining = deadline - time.monotonic()
        assert remaining > 0, 'run withheld the terminal prompt: ' + repr(output)
        if select.select([master], [], [], remaining)[0]:
            output += os.read(master, 65536)
    os.write(master, b'x\n')
    assert process.wait(timeout=10) == 23
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    os.close(master)
PY

"$X2C" build -### --build-dir "$BUILD/direct/matched-dry" \
  "$BUILD/direct/source.c" >"$BUILD/direct/matched.stdout" \
  2>"$BUILD/direct/matched.stderr"
grep -Fq "$ROOT/builds/0/libx2c.a" "$BUILD/direct/matched.stderr"
[[ ! -e "$BUILD/direct/matched-dry" ]]

python3 - "$X2C" "$BUILD/scheduling" <<'PY_SCHEDULING'
import os
from pathlib import Path
import shutil
import subprocess
import sys

compiler, directory = sys.argv[1:]
root = Path(directory)
root.mkdir()
wrapper = root / 'cc-wrapper'
wrapper.write_text(r"""#!/usr/bin/env python3
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(os.environ['SCHEDULING_STATE'])
name = Path(sys.argv[sys.argv.index('-c') + 1]).stem

def event(kind):
    with (root / 'events').open('a') as output:
        fcntl.flock(output, fcntl.LOCK_EX)
        output.write(kind + ' ' + name + '\n')
        output.flush()

event('start')
print('stdout-' + name, flush=True)
print('stderr-' + name, file=sys.stderr, flush=True)
if name == 'third':
    (root / 'third-started').touch()
if name == 'first':
    marker = 'second-finished' if os.environ['SCHEDULING_FAIL'] else 'third-started'
    deadline = time.monotonic() + 5
    while not (root / marker).exists():
        if time.monotonic() >= deadline:
            event('timeout')
            sys.exit(98)
        time.sleep(0.005)
    if os.environ['SCHEDULING_FAIL']:
        time.sleep(0.1)
if name == 'second' and os.environ['SCHEDULING_FAIL']:
    event('finish')
    (root / 'second-finished').touch()
    sys.exit(23)
status = subprocess.call([os.environ['SCHEDULING_CC'], *sys.argv[1:]])
event('finish')
sys.exit(status)
""")
wrapper.chmod(0o755)
sources = []
for name in ('first', 'second', 'third'):
    source = root / (name + '.c')
    source.write_text('int ' + name + '(void) { return 0; }\n')
    sources.append(str(source))
for fail in (False, True):
    state = root / ('failure' if fail else 'success')
    state.mkdir()
    env = dict(os.environ, SCHEDULING_STATE=str(state),
               SCHEDULING_FAIL='1' if fail else '',
               SCHEDULING_CC=shutil.which('cc'))
    result = subprocess.run(
        [compiler, 'build', '-c', '-j2', '--cc', str(wrapper),
         '--build-dir', str(state / 'build'), *sources],
        env=env, text=True, capture_output=True, timeout=20)
    (state / 'stdout').write_text(result.stdout)
    (state / 'stderr').write_text(result.stderr)
    assert (result.returncode != 0) == fail, result.stderr
    active = set()
    started = set()
    for row in (state / 'events').read_text().splitlines():
        kind, name = row.split()
        if kind == 'start':
            assert name not in started
            started.add(name)
            active.add(name)
            assert len(active) <= 2
        else:
            assert kind == 'finish', row
            active.remove(name)
    assert not active, 'build returned before draining its children'
    assert started == ({'first', 'second'} if fail else
                       {'first', 'second', 'third'})
    for name in started:
        assert result.stderr.count('stdout-' + name) == 1
        assert result.stderr.count('stderr-' + name) == 1
    if fail:
        assert 'compile failed with status 23' in result.stderr
PY_SCHEDULING

python3 - "$X2C" "$BUILD/compile-commands" <<'PY_COMMANDS'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

compiler, directory = sys.argv[1:]
root = Path(directory).resolve()
root.mkdir()
source = root / 'native space.c'
source.write_text('int main(void) { return 0; }\n')
helper = root / 'helper.x'
helper.write_text('int helper(void) { return 7; }\n')
wrapper = root / 'compiler wrapper'
capture = root / 'actual.jsonl'
wrapper.write_text(r'''#!/usr/bin/env python3
import json
import os
import sys
if '-c' in sys.argv:
    with open(os.environ['DB_CAPTURE'], 'a') as output:
        output.write(json.dumps(sys.argv) + '\n')
os.execv(os.environ['DB_CC'], [os.environ['DB_CC'], *sys.argv[1:]])
''')
wrapper.chmod(0o755)
env = dict(os.environ, DB_CAPTURE=str(capture), DB_CC=shutil.which('cc'))
database = root / 'compile_commands.json'
command = [compiler, 'build', '-c', '--compile-commands', str(database),
           '--build-dir', 'build space', '--cc', str(wrapper),
           '-Xcc', '-DDB_TEXT="a\\\"b\\\\c"',
           '-Xcc', '-fdebug-prefix-map=a\tb\nc"\\=mapped',
           str(source), str(helper)]
def run(command, name, status=0):
    result = subprocess.run(command, cwd=root, env=env, text=True,
                            capture_output=True, timeout=30)
    (root / (name + '.stderr')).write_text(result.stderr)
    assert result.returncode == status, result.stderr
    return result
run(command, 'first')
first = database.read_bytes()
rows = json.loads(first)
actual = [json.loads(row) for row in capture.read_text().splitlines()]
assert len(rows) == len(actual) == 2
for row, argv in zip(rows, actual):
    assert row['directory'] == str(root)
    assert row['arguments'] == argv
    assert row['file'] == argv[argv.index('-c') + 1]
    assert row['output'] == argv[argv.index('-o') + 1]
    assert (root / row['file']).is_file()
    assert (root / row['output']).is_file()
objects = [str(root / row['output']) for row in rows]
run([compiler, 'build', '--kind', 'static-library',
     '--compile-commands', 'empty.json', '--output', 'libempty.a', *objects],
    'objects-only')
assert json.loads((root / 'empty.json').read_text()) == []
capture.unlink()
run(command, 'warm')
assert database.read_bytes() == first
assert not capture.exists(), 'warm build executed a native compilation'
run(command[:2] + ['-###'] + command[2:], 'dry')
assert database.read_bytes() == first
assert not capture.exists()
source.write_text('int broken( {\n')
run(command, 'failure', 1)
assert database.read_bytes() == first
assert not list(root.glob('compile_commands.json.tmp.*'))
run_source = root / 'run.x'
run_source.write_text('int main(void) { return 23; }\n')
run([compiler, 'run', '--compile-commands', 'run.json', str(run_source)],
    'run', 23)
run_rows = json.loads((root / 'run.json').read_text())
assert len(run_rows) == 1
assert (root / run_rows[0]['file']).is_file()
assert '.x2c-build' in run_rows[0]['file']
assert (root / run_rows[0]['output']).is_file()
blocked = root / 'db-directory'
blocked.mkdir()
run([compiler, 'build', '-c', '--compile-commands', str(blocked), str(helper)],
    'write-failure', 1)
assert blocked.is_dir()
assert not list(root.glob('db-directory.tmp.*'))
print('compilation database argv, cache, retention, failure, run: passed')
PY_COMMANDS

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

(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --compile-commands "$manifest/compile_commands.json") \
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

cp "$manifest/compile_commands.json" "$manifest/commands-first.json"
(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --compile-commands "$manifest/compile_commands.json") \
  >"$manifest/noop.stdout" 2>"$manifest/noop.stderr"
cmp "$manifest/commands-first.json" "$manifest/compile_commands.json"
python3 - "$manifest" <<'PY_MANIFEST_COMMANDS'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
rows = json.loads((root / 'compile_commands.json').read_text())
assert len(rows) == 4
assert {Path(row['file']).stem for row in rows} == {'core', 'leaf', 'main', 'native'}
for row in rows:
    assert row['directory'] == str(root / 'nested')
    assert Path(row['file']).is_file()
    assert Path(row['output']).is_file()
    argv = row['arguments']
    assert argv[argv.index('-c') + 1] == row['file']
    assert argv[argv.index('-o') + 1] == row['output']
PY_MANIFEST_COMMANDS
[[ $(grep -c '^x2c: up-to-date ' "$manifest/noop.stderr") == 8 ]]
[[ $(grep -c '^x2c: compile ' "$manifest/noop.stderr") == 0 ]]
grep -Fq 'x2c: up-to-date archive ' "$manifest/noop.stderr"
grep -Fq 'x2c: link ' "$manifest/noop.stderr"

printf '\n  # A presentation-only manifest edit.\n\n' >>"$manifest/x2c.toml"
(cd "$manifest/nested" && "$X2C" build -v --profile release) \
  >"$manifest/comment.stdout" 2>"$manifest/comment.stderr"
[[ $(grep -c '^x2c: up-to-date ' "$manifest/comment.stderr") == 8 ]]
[[ $(grep -c '^x2c: compile ' "$manifest/comment.stderr") == 0 ]]
[[ $("$manifest/out/app") == 10 ]]

printf 'defines = ["MANIFEST_PROBE=1"]\n' >>"$manifest/x2c.toml"
(cd "$manifest/nested" && "$X2C" build -v --profile release) \
  >"$manifest/setting.stdout" 2>"$manifest/setting.stderr"
[[ $(grep -c '^x2c: compile ' "$manifest/setting.stderr") == 2 ]]
grep '^x2c: compile ' "$manifest/setting.stderr" |
  grep -Fq -- '-DMANIFEST_PROBE=1'
grep -Fq 'x2c: up-to-date archive ' "$manifest/setting.stderr"
[[ $("$manifest/out/app") == 10 ]]

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

final_state=$(find "$manifest/out/.x2c/core/.x2c-state" \
  -name 'final-*' -type f)
printf 'corrupt private state\n' >"$final_state"
(cd "$manifest/nested" && "$X2C" build -v --profile release \
  --cc "$manifest/cc-wrapper") >"$manifest/corrupt.stdout" \
  2>"$manifest/corrupt.stderr"
[[ $(grep -c '^x2c: link ' "$manifest/corrupt.stderr") == 1 ]]
[[ $(grep -c '^x2c: archive ' "$manifest/corrupt.stderr") == 1 ]]

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

# Source mapping is independent of -g and belongs to translation reuse.
python3 - "$X2C" "$BUILD/source-map" <<'PY_SOURCE_MAP'
from pathlib import Path
import subprocess
import sys

compiler = sys.argv[1]
root = Path(sys.argv[2]).resolve()
source_dir = root / 'source "quote\\ and space'
source_dir.mkdir(parents=True)
source = source_dir / 'mapped.x'
helper = source_dir / 'included.x'
(source_dir / 'where.xmacro').write_text(
    'macro Expression $imported_where() => (__LINE__)\n')
source.write_text(r'''#include "x2c.x"
#include "included.x"
$(import "where.xmacro")
macro Expression $where() => (__LINE__)
int main(void) {
  printf("source=%s:%d\n", __FILE__, __LINE__);
  printf("multiline=%d\n",
    __LINE__);
  printf("macro=%d\n", $where());
  printf("imported=%d\n",
    $imported_where());
  defer printf("cleanup=%d\n", __LINE__);
  return included();
}
''')
helper.write_text(r'''#include "x2c.x"
int included(void) {
  printf("included=%s:%d\n", __FILE__, __LINE__);
  return 0;
}
''')


def run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


command = [compiler, 'build', '--quiet', '-g', '-O0', '--build-dir',
           str(root / 'build'), '--output', str(root / 'app'),
           str(source), str(helper)]
run(command)
generated = list((root / 'build').rglob('*.c'))
assert generated and all('#line ' not in p.read_text() for p in generated)
mapped = command[:2] + ['--source-map'] + command[2:]
run(mapped)
expected = (f'source={source}:6\nmultiline=8\nmacro=9\nimported=11\n'
            f'included={helper}:3\ncleanup=12\n')
assert run([str(root / 'app')]) == expected
assert all('#line ' in p.read_text() for p in generated)
artifacts = generated + list((root / 'build').rglob('*.h'))
stamps = [p.stat().st_mtime_ns for p in artifacts]
run(mapped)
assert stamps == [p.stat().st_mtime_ns for p in artifacts]
run(command)
assert all('#line ' not in p.read_text() for p in generated)
output = root / 'translated'
output.mkdir()
run([compiler, 'translate', '--quiet', '--source-map', '--out-dir',
     str(output), str(source)])
assert '#line ' in (output / 'mapped.c').read_text()
PY_SOURCE_MAP

echo "CLI, dependency, build, run, manifest, and state probes: 110 passed"
