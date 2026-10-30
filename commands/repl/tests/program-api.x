/*  program-api.x -- native program addresses and retained ABI declarations

    Copyright (c) 2026 Gary William Flake.
*/
#include "repl-program.x"
#include "datum.x"
#include <stdio.h>

typedef struct PlaygroundPoint { int x; int y; } PlaygroundPoint;
typedef struct PlaygroundHandle PlaygroundHandle;
int repl_test_packet(void *address);

String x2c_embedded_identity(void);

static int _combine(int x, int y) { return x * 10 + y; }

static int _check(ReplProgram program) {
  PlaygroundPoint *(*create)(int, int) =
    (PlaygroundPoint *(*)(int, int)) program.addresses["playground_new"].pointer();
  void (*move)(PlaygroundPoint *, int) =
    (void (*)(PlaygroundPoint *, int)) program.addresses["playground_move"].pointer();
  void (*release)(PlaygroundPoint *) =
    (void (*)(PlaygroundPoint *)) program.addresses["playground_free"].pointer();
  PlaygroundPoint (*value)(int, int) =
    (PlaygroundPoint (*)(int, int)) program.addresses["playground_value"].pointer();
  int (*apply)(PlaygroundPoint *, int (*)(int, int)) =
    (int (*)(PlaygroundPoint *, int (*)(int, int)))
      program.addresses["playground_apply"].pointer();
  PlaygroundHandle *(*open)(int) =
    (PlaygroundHandle *(*)(int)) program.addresses["playground_open"].pointer();
  int (*read)(PlaygroundHandle *) =
    (int (*)(PlaygroundHandle *)) program.addresses["playground_read"].pointer();
  void (*close)(PlaygroundHandle *) =
    (void (*)(PlaygroundHandle *)) program.addresses["playground_close"].pointer();

  PlaygroundPoint *point = create(1, 2);
  PlaygroundPoint *alias = point;
  move(point, 5);
  if (alias->x != 6 || point->y != 2 || apply(point, _combine) != 62) return 1;
  release(point);
  PlaygroundPoint copy = value(8, 9);
  if (copy.x != 8 || copy.y != 9 ||
      repl_test_packet(program.addresses["playground_packet"].pointer())) return 1;
  PlaygroundHandle *handle = open(42);
  if (read(handle) != 42) return 1;
  close(handle);
  if ("playground_inline" in program.addresses) {
    int (*increment)(int) =
      (int (*)(int)) program.addresses["playground_inline"].pointer();
    if (increment(31) != 32) return 1;
  }
  int *calls = program.addresses["playground_calls"].pointer();
  if (*calls < 1) return 1;
  *calls = 23;
  if (*(int *) program.addresses["playground_calls"].pointer() != 23) return 1;
  return 0;
}

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  if (argc < 2) return 2;
  Array options = ["build"];
  for (int i = 1; i < argc; i++) options.push(String.new(argv[i]));
  CliRequest request = CliRequest.parse_arguments(options);
  List roots = request.inputs;
  Frontend frontend = Frontend.new(request);
  String failure = NULL;
  ReplProgram program = repl_program_build(frontend, roots, failure);
  if (!program) { fprintf(stderr, "%s\n", failure); return 1; }
  String missing = Env.get("REPL_PROGRAM_MISSING");
  if (missing) {
    Map description = program.descriptions[missing];
    if (missing in program.addresses || !description ||
        !description["unavailable"].integer()) return 1;
    puts("missing header provider remains inspectable and unavailable");
    return 0;
  }
  if ("sqlite3_open" in program.addresses) {
    int (*open)(const char *, void **) =
      (int (*)(const char *, void **)) program.addresses["sqlite3_open"].pointer();
    int (*exec)(void *, const char *, void *, void *, char **) =
      (int (*)(void *, const char *, void *, void *, char **))
        program.addresses["sqlite3_exec"].pointer();
    int (*close)(void *) = (int (*)(void *)) program.addresses["sqlite3_close"].pointer();
    void *db = NULL;
    if (open(":memory:", &db) || !db ||
        exec(db, "CREATE TABLE sample(value); INSERT INTO sample VALUES(42)",
             NULL, NULL, NULL) || close(db)) return 1;
    Buffer encoded = auto Buffer.new(0);
    if (!encoded.write_datum(repl_program_snapshot(program), 1)) return 1;
    printf("SQLite snapshot: %zu bytes\n", encoded.len());
    puts("native SQLite wrapper header create/call/close passed");
    return 0;
  }
  if (!("playground_new" in program.addresses)) {
    if (!("main" in program.addresses)) return 1;
    List parameters = NULL;
    ((Type) program.symbols[%("main")]).function_parts(parameters, NULL);
    int result;
    if (parameters) {
      int (*entry)(Array) = (int (*)(Array)) program.addresses["main"].pointer();
      result = entry(["demo", "abc"]);
    }
    else {
      int (*entry)(void) = (int (*)(void)) program.addresses["main"].pointer();
      result = entry();
    }
    if (result != (parameters ? 23 : 11)) return 1;
    String replacement = Env.get("REPL_PROGRAM_REPLACE");
    if (replacement) {
      ReplProgram selected = repl_program_build_selected(frontend,
        roots.append($(replacement)), $(replacement), failure);
      if (!selected || selected.roots.len() != 1 ||
          selected.roots.car() != replacement) return 1;
      int (*entry)(void) = (int (*)(void)) selected.addresses["main"].pointer();
      if (entry() != 11) return 1;
      puts("native main root replacement passed");
    }
    puts("native main adapter passed");
    return 0;
  }
  if (_check(program)) return 1;
  if ("manifest_value" in program.addresses) {
    int (*value)(void) =
      (int (*)(void)) program.addresses["manifest_value"].pointer();
    if (value() != 17) return 1;
  }

  Map function = program.descriptions["playground_new"];
  if (function && (!("int x" in function["declaration"].str()) ||
      !("int y" in function["declaration"].str()))) return 1;
  if (!program.symbols.contains(%(struct "PlaygroundPoint" "field-order")))
    return 1;
  Map macro = program.descriptions["PLAYGROUND_SCALE"];
  if (!macro || macro["kind"] != <macro> ||
      !("#define PLAYGROUND_SCALE 3" in macro["declaration"].str())) return 1;
  if (function && roots && roots.car().str().endswith(".h")) {
    if (!("requested coordinates" in function["documentation"].str()) ||
        !program.descriptions.contains("struct playground_value") ||
        !program.descriptions.contains("playground_value")) return 1;
  }
  if (!program.macros.contains("PLAYGROUND_SCALE") ||
      !program.symbols.contains(%("PLAYGROUND_Y")) ||
      !program.symbols.contains(%(enum "PlaygroundAxis" "enumerators")))
    return 1;
  String header = Path.read_text(program.header);
  if ("#include" in header) return 1;
  Buffer encoded = auto Buffer.new(0);
  if (!encoded.write_datum(repl_program_snapshot(program), 1)) return 1;
  printf("library snapshot: %zu bytes\n", encoded.len());
  unsigned cursor = 0;
  Var decoded = void;
  if (!encoded.str().read_datum(cursor, decoded)) return 1;
  ReplProgram restored = repl_program_restore(decoded, failure);
  if (!restored || _check(restored)) {
    fprintf(stderr, "restore: %s\n", failure ? failure : "wrong native value");
    return 1;
  }
  String removed = Env.get("REPL_PROGRAM_REMOVE_NATIVE");
  if (removed) {
    unlink(removed);
    if (!repl_program_changed(program) ||
        repl_program_restore(decoded, failure) || !failure) return 1;
    puts("changed external native dependency refuses restore");
  }
  printf("native program C ABI and snapshot checks passed\n");
  return 0;
}
