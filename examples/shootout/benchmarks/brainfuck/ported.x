/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/brainfuck-ported ported.x
 *   /tmp/brainfuck-ported 100000
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Program {
  unsigned char *commands;
  int *jumps;
  int len;
} *Program;

static Program Program.compile(const char *source) {
  size_t capacity = strlen(source);
  Program program = Scope.malloc(sizeof(struct Program));
  program.commands = Scope.malloc(capacity);
  program.jumps = Scope.calloc(capacity, sizeof(int));
  program.len = 0;
  int *stack = Scope.malloc(capacity * sizeof(int));
  int depth = 0;

  for (const char *cursor = source; *cursor; cursor++) {
    if (!strchr("+-<>[].", *cursor)) continue;
    int here = program.len++;
    program.commands[here] = (unsigned char) *cursor;
    if (*cursor == '[') stack[depth++] = here;
    if (*cursor == ']') {
      int open = stack[--depth];
      program.jumps[open] = here;
      program.jumps[here] = open;
    }
  }
  return program;
}

static uint64_t Program.run(Program program, int repetitions) {
  uint64_t checksum = 0;
  for (int run = 0; run < repetitions; run++) {
    unsigned char tape[64] = {0};
    size_t data = 0;
    for (int pc = 0; pc < program.len; pc++) {
      switch (program.commands[pc]) {
        case '+': tape[data]++; break;
        case '-': tape[data]--; break;
        case '>': data++; break;
        case '<': data--; break;
        case '[': if (!tape[data]) pc = program.jumps[pc]; break;
        case ']': if (tape[data]) pc = program.jumps[pc]; break;
        case '.': checksum = checksum * 33 + tape[data]; break;
      }
    }
  }
  return checksum;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  Program program = Program.compile(
    "noise ++++++++[>++++++++<-]>+.+.+.+. ignored");
  printf("%llu\n", (unsigned long long) program.run(atoi(argv[1])));
  return 0;
}
