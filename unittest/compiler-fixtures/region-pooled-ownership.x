#include "x2c.x"

static List make_list(int value) => cons(value, NULL);

String pooled_string(char *bytes) {
  Pool.open();
  defer Pool.close();
  return String.new(bytes);
}

String pooled_buffer(int size) {
  Pool.open();
  defer Pool.close();
  return String.malloc(size);
}

List pooled_helper(int value) {
  Pool.open();
  defer Pool.close();
  return make_list(value);
}

void same_pool(int value) {
  Pool.open();
  defer Pool.close();
  List first = cons(value, NULL);
  List second = cons(first, NULL);
  (void) second;
}

void outer_list(int value) {
  Pool.open();
  List inner = cons(value, NULL);
  Pool.close();
  List outer = cons(inner, NULL);
  (void) outer;
}
