#!/usr/bin/env -S x2c script
/* A script that defines main is an ordinary program: its declarations,
   initialized ones included, stay at file scope and main runs. */

int calls = 0;
const char *label = "program";

static void count(void) {
  calls++;
}

int main(int argc, char **argv) {
  count();
  count();
  printf("%s calls=%d args=%d\n", label, calls, argc - 1);
  return calls == 2 ? 0 : 1;
}
