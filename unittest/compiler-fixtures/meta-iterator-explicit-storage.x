#include "x2c.x"

meta int explicit_storage(int offset) {
  Map values = {"a": 1};
  struct Iter storage;
  return values.keys(&storage).count() + offset;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $explicit_storage(0), explicit_storage(argc - 1));
  return 0;
}
