#include "x2c.x"

static int calls;
static int next(void) { return ++calls; }
static const char *source = "first";
static const char *pointer(void) {
  static const char *value = source;
  return value;
}
static int qualified(void) {
  typedef volatile int LocalValue;
  static LocalValue value = next();
  static volatile int values[] = {next(), next()};
  return value + values[0] + values[1];
}
int main(void) {
  const char *first = pointer();
  source = "second";
  const char *second = pointer();
  int a = qualified(), b = qualified();
  printf("%s %s %d %d %d\n", first, second, a, b, calls);
  return 0;
}
