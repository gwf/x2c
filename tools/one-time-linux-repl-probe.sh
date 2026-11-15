#!/usr/bin/env bash
set -eu
# Run from a Linux checkout; build-safe is required unless already completed.
mkdir -p debug
make build-safe >debug/repl-probe-bootstrap.log 2>&1
probe=$(mktemp -d /tmp/x2c-linux-repl.XXXXXX)
export X2C="$PWD/builds/0/x2c"
printf '%s\n' "$probe"
uname -a
cc --version | head -1
ld --version | head -1
python3 - "$probe" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
s=pathlib.Path('commands/repl/tests/program-api.x').read_text()
old='    unlink(removed);'
assert s.count(old)==1
s=s.replace(old, '''    String replacement = removed + ".replacement";
    if (rename(replacement, removed)) return 2;
    printf("dependency map: %s\\n", program.dependencies.repr());
    String changed = repl_program_changed(program);
    printf("changed: %s\\n", changed ? changed : "NOT DETECTED");''')
(p/'program-api.x').write_text(s)
PY
builds/0/x2c build --plain --build-dir "$probe/cc" --output "$probe/program-api" \
 --x-include-dir commands/repl --x-include-dir commands/repl/tests \
 --x-include-dir src --c-include-dir builds/0/src \
 -Xlinker -export-dynamic -Wl,--whole-archive,builds/0/libx2c.a,--no-whole-archive \
 "$probe/program-api.x" commands/repl/repl-program.x commands/repl/repl-types.x \
 commands/repl/tests/library/program-check.c builds/0/commands/identity.x builds/0/libx2c-dev.a
cc -shared -fPIC commands/repl/tests/library/playground.c -o "$probe/libplayground.so"
cp commands/repl/tests/library/playground.c "$probe/replacement.c"
printf '\nint changed_library_marker(void) { return 42; }\n' >>"$probe/replacement.c"
cc -shared -fPIC -I commands/repl/tests/library "$probe/replacement.c" -o "$probe/libplayground.so.replacement"
printf 'extern int playground_calls; int main(void) { return playground_calls; }\n' >"$probe/trace.c"
cc "$probe/trace.c" -L"$probe" -lplayground -Wl,-t -o "$probe/trace" >"$probe/link-trace.log" 2>&1
cat "$probe/link-trace.log"
LD_LIBRARY_PATH="$probe${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" REPL_PROGRAM_REMOVE_NATIVE="$probe/libplayground.so" \
 "$probe/program-api" "$PWD/commands/repl/tests/library/playground.h" -L"$probe" -lplayground \
 >"$probe/repl.log" 2>&1 || { cat "$probe/repl.log"; exit 1; }
cat "$probe/repl.log"
