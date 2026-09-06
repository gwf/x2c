/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/brainfuck-idiomatic main.x
 *   /tmp/brainfuck-idiomatic 100000
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "typed-array.x"
#include "typed-list.x"

typedef struct Program {
  String code;
  ArrayInt jumps;
} Program;

static Program _compile(String source) {
  Program program = {source.keep("+-<>[]."), ArrayInt.new()};
  int len = program.code.len();
  for (int i = 0; i < len; i++) program.jumps.push(0);
  ListInt stack = %();
  for (int pc = 0; pc < len; pc++) {
    if (program.code[pc] == '[') stack = ListInt.cons(pc, stack);
    if (program.code[pc] == ']') {
      int open = stack.car();
      stack = stack.cdr();
      program.jumps[open] = pc;
      program.jumps[pc] = open;
    }
  }
  return program;
}

static uint64_t _run(Program program, int repetitions) {
  const char *code = program.code;
  int len = program.code.len();
  uint64_t checksum = 0;
  for (int run = 0; run < repetitions; run++) {
    unsigned char tape[64] = {0};
    int data = 0;
    for (int pc = 0; pc < len; pc++) {
      switch (code[pc]) {
        case '+': tape[data]++; break;
        case '-': tape[data]--; break;
        case '>': data++; break;
        case '<': data--; break;
        case '[': if (!tape[data]) pc = program.jumps[pc];
          break;
        case ']': if (tape[data]) pc = program.jumps[pc];
          break;
        case '.': checksum = checksum * 33 + tape[data]; break;
      }
    }
  }
  return checksum;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  Program program = _compile(%"noise ++++++++[>++++++++<-]>+.+.+.+. ignored");
  printf("%llu\n", (unsigned long long) _run(program, atoi(argv[1])));
  return 0;
}
