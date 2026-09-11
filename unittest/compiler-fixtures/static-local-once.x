#include "x2c.x"

static int calls;
static int next(void) { return ++calls; }
#define INITIAL() next()
struct Row { const int number; String text; };
static const struct Row *rows(void) {
  static const struct Row values[2] = {{INITIAL(), "one"}, {next(), "two"}};
  return &values[0];
}
static int failure(void) { raise %(bad-state); }
static int try_state(void) {
  int count = 0;
  try { static int value = (++count, failure()); }
  catch: { }
  return count;
}
static int attempts;
static int fail_once(void) {
  attempts++;
  if (attempts == 1) raise %(bad-state);
  return 42;
}
static int retry(void) { static const int value = fail_once(); return value; }
static int argument(int input) { static int value = input; return value; }
static int nested_switch(int input) {
  static int value = next();
  switch (input) { case 1: return value; default: return 0; }
}
static int native(void) {
#define NATIVE 7
  static const int value = NATIVE;
  return value;
}
int main(void) {
  const struct Row *a = rows(), *b = rows();
  int caught = 0;
  try { retry(); }
  catch: { caught = 1; }
  int retried = retry(), first = argument(17), second = argument(99);
  int nested = nested_switch(1);
  printf("%d %d %d %d %s %d %d %d %d %d %d %d %d\n", a == b,
    (int)(sizeof(*a) == sizeof(struct Row)), calls, a[1].number,
    (const char *)a[0].text, caught, retried, attempts, first, second,
    nested, native(), try_state());
  return 0;
}
