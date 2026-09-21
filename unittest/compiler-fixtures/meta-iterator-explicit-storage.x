#include "x2c.x"

meta int explicit_storage(void) {
  Map values = {"a": 1};
  struct Iter storage;
  return values.keys(&storage).count();
}

int main(void) { return $(explicit_storage); }
