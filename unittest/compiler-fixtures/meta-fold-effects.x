#include "x2c.x"

meta int next_value(int ignored) {
  (void) ignored;
  static int value = 0;
  value += 1;
  return value;
}

int main(int argc, char **argv) {
  (void) argv;
  int compile_value = $next_value(0);
  int first = next_value(1);
  int second = next_value(argc);
  int third = next_value(argc);
  printf("explicit %d\n", compile_value);
  printf("runtime %d %d %d\n", first, second, third);
  return 0;
}
