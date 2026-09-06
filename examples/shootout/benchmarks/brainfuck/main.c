#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Program {
  unsigned char *commands;
  int *jumps;
  size_t len;
} Program;

static Program compile_program(const char *source) {
  size_t capacity = strlen(source);
  Program program = {
    malloc(capacity),
    malloc(capacity * sizeof(int)),
    0
  };
  int *stack = malloc(capacity * sizeof(int));
  size_t stack_len = 0;
  if (!program.commands || !program.jumps || !stack) abort();

  for (const char *cursor = source; *cursor; cursor++) {
    if (!strchr("+-<>[].", *cursor)) continue;
    size_t at = program.len++;
    program.commands[at] = (unsigned char) *cursor;
    program.jumps[at] = 0;
    if (*cursor == '[') stack[stack_len++] = (int) at;
    if (*cursor == ']') {
      int open = stack[--stack_len];
      program.jumps[open] = (int) at;
      program.jumps[at] = open;
    }
  }
  free(stack);
  return program;
}

static uint64_t run_program(const Program *program, int repetitions) {
  uint64_t checksum = 0;
  for (int run = 0; run < repetitions; run++) {
    unsigned char tape[64] = {0};
    size_t data = 0;
    for (size_t pc = 0; pc < program->len; pc++) {
      switch (program->commands[pc]) {
        case '+': tape[data]++; break;
        case '-': tape[data]--; break;
        case '>': data++; break;
        case '<': data--; break;
        case '[':
          if (!tape[data]) pc = (size_t) program->jumps[pc];
          break;
        case ']':
          if (tape[data]) pc = (size_t) program->jumps[pc];
          break;
        case '.': checksum = checksum * 33 + tape[data]; break;
      }
    }
  }
  return checksum;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  Program program = compile_program(
    "noise ++++++++[>++++++++<-]>+.+.+.+. ignored");
  uint64_t checksum = run_program(&program, atoi(argv[1]));
  free(program.commands);
  free(program.jumps);
  printf("%llu\n", (unsigned long long) checksum);
  return 0;
}
