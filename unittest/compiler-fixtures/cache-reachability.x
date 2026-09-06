#include "x2c.x"

String direct_cache(void) {
  return %"direct";
}

String transitive_cache(void) {
  return direct_cache();
}

String cycle_b(int value);

String cycle_a(int value) {
  return value ? cycle_b(value - 1) : %"cycle";
}

String cycle_b(int value) {
  return value ? cycle_a(value - 1) : NULL;
}

int disconnected(void) {
  return 7;
}

int main(void) {
  printf("%s\n", transitive_cache());
  printf("%s\n", cycle_a(0));
  return 0;
}
