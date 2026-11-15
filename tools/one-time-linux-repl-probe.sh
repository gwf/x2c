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
cat >"$probe/program-api.x" <<'X'
#include "repl-program.x"
#include <stdio.h>
String x2c_embedded_identity(void);
int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  Array options = ["build"];
  for (int i = 1; i < argc; i++) options.push(String.new(argv[i]));
  CliRequest request = CliRequest.parse_arguments(options);
  Frontend frontend = Frontend.new(request);
  String failure = NULL;
  ReplProgram program = repl_program_build_selected(
    frontend, Path.temp_dir(), request.inputs, NULL, failure);
  if (!program) { fprintf(stderr, "BUILD: %s\n", failure); return 10; }
  String missing = Env.get("REPL_PROGRAM_MISSING");
  if (missing) {
    Map description = program.descriptions[missing];
    if (missing in program.addresses || !description ||
        !description["unavailable"].integer()) return 18;
    puts("missing provider remains inspectable and unavailable");
    return 0;
  }
  printf("dependency map: %s\n", program.dependencies.repr());
  fflush(stdout);
  if (!("dependency_value" in program.addresses)) {
    fprintf(stderr, "dependency_value missing from addresses\n"); return 11;
  }
  int (*value)(void) = (int (*)(void)) program.addresses["dependency_value"].pointer();
  int result = value();
  printf("loaded shared library value: %d\n", result);
  if (result != 17) return 12;
  List snapshot = repl_program_snapshot(program);
  if (repl_program_changed(program)) return 13;
  ReplProgram before = repl_program_restore(snapshot, failure);
  if (!before) { fprintf(stderr, "PRE-CHANGE RESTORE: %s\n", failure); return 14; }
  String library = Env.get("REPL_PROGRAM_REMOVE_NATIVE");
  String replacement = library + ".replacement";
  if (rename(replacement, library)) { perror("rename"); return 15; }
  String changed = repl_program_changed(program);
  printf("changed: %s\n", changed ? changed : "NOT DETECTED");
  failure = NULL;
  ReplProgram after = repl_program_restore(snapshot, failure);
  printf("restore after replacement: %s; %s\n", after ? "ACCEPTED" : "REFUSED",
    failure ? failure : "no failure");
  if (!changed || after || !failure) return 16;
  puts("changed shared library detected and stale restore refused");
  return 0;
}
X
builds/0/x2c build --plain --build-dir "$probe/cc" --output "$probe/program-api" \
 --x-include-dir commands/repl --x-include-dir commands/repl/tests \
 --x-include-dir src --c-include-dir builds/0/src \
 -Xlinker -export-dynamic -Wl,--whole-archive,builds/0/libx2c.a,--no-whole-archive \
 "$probe/program-api.x" commands/repl/repl-program.x commands/repl/repl-types.x \
 builds/0/commands/identity.x builds/0/libx2c-dev.a
printf 'int dependency_value(void);\n' >"$probe/library.h"
printf 'int dependency_value(void) { return 17; }\n' >"$probe/library.c"
printf 'int dependency_value(void) { return 29; }\n' >"$probe/replacement.c"
cc -shared -fPIC "$probe/library.c" -o "$probe/libplayground.so"
cc -shared -fPIC "$probe/replacement.c" -o "$probe/libplayground.so.replacement"
printf 'extern int dependency_value(void); int main(void) { return dependency_value(); }\n' >"$probe/trace.c"
cc "$probe/trace.c" -L"$probe" -lplayground -Wl,-t -o "$probe/trace" >"$probe/link-trace.log" 2>&1
cat "$probe/link-trace.log"
LD_LIBRARY_PATH="$probe${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" REPL_PROGRAM_REMOVE_NATIVE="$probe/libplayground.so" \
 "$probe/program-api" "$probe/library.h" -L"$probe" -lplayground \
 >"$probe/repl.log" 2>&1 || { cat "$probe/repl.log"; exit 1; }
cat "$probe/repl.log"
printf 'int unavailable_example(int value);\n' >"$probe/missing.h"
REPL_PROGRAM_MISSING=unavailable_example "$probe/program-api" "$probe/missing.h" \
 >>"$probe/repl.log" 2>&1 || { cat "$probe/repl.log"; exit 1; }
tail -1 "$probe/repl.log"
make commands >debug/repl-command-build.log 2>&1
sh commands/repl/tests/program.sh >debug/repl-program-tests.log 2>&1 || { cat debug/repl-program-tests.log; exit 1; }
cat debug/repl-program-tests.log
