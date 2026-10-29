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
  int *calls = program.addresses["playground_calls"].pointer();
  if (*calls < 1) return 1;
  *calls = 23;
  if (*(int *) program.addresses["playground_calls"].pointer() != 23) return 1;
  return 0;
}

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  if (argc < 2) return 2;
  CliRequest request = CliRequest.new(<build>);
  Array roots = [];
  for (int i = 1; i < argc; i++) roots.push(String.new(argv[i]));
  Frontend frontend = Frontend.new(request);
  String failure = NULL;
  ReplProgram program = repl_program_build(frontend, roots, failure);
  if (!program) { fprintf(stderr, "%s\n", failure); return 1; }
  if (_check(program)) return 1;

  Map function = program.descriptions["playground_new"];
  if (!("int x" in function["declaration"].str()) ||
      !("int y" in function["declaration"].str())) return 1;
  if (!program.symbols.contains(%(struct "PlaygroundPoint" "field-order")))
    return 1;
  if (!program.macros.contains("PLAYGROUND_SCALE") ||
      !program.symbols.contains(%("PLAYGROUND_Y")) ||
      !program.symbols.contains(%(enum "PlaygroundAxis" "enumerators")))
    return 1;
  String header = Path.read_text(program.header);
  if ("#include" in header) return 1;
  Buffer encoded = auto Buffer.new(0);
  if (!encoded.write_datum(repl_program_snapshot(program), 1)) return 1;
  unsigned cursor = 0;
  Var decoded = void;
  if (!encoded.str().read_datum(cursor, decoded)) return 1;
  ReplProgram restored = repl_program_restore(decoded, failure);
  if (!restored || _check(restored)) {
    fprintf(stderr, "restore: %s\n", failure ? failure : "wrong native value");
    return 1;
  }
  printf("native program C ABI and snapshot checks passed\n");
  return 0;
}
