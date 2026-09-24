#include "x2c.x"

static int calls;
static int counted(void) { calls++; return 7; }

const size_t file_width = sizeof(counted());

static size_t fixed_width(void) {
  static const size_t width = sizeof(counted());
  return width;
}

static size_t first_vla_width(int n) {
  static const size_t width = sizeof(int[n]);
  return width;
}

static Array array_once(void) {
  static Array value = [];
  return value;
}

static Map map_once(void) {
  static Map value = {};
  return value;
}

int main(void) {
  printf("%zu %zu %d %zu %u %zu %zu\n", file_width, fixed_width(),
    calls, array_once().len(), map_once().len(), first_vla_width(3),
    first_vla_width(5));
  return 0;
}
