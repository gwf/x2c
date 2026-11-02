#include "x2c.x"

/* A file-scope Func initialized from a lambda or a function, static or not,
   holds its handle before any initializer or call reads it. A lambda's body
   is not part of a static initializer, so it may read any file-scope name. */

static Var twice(Var x) => x * 2;

int scale = 3;
Func doubled = %!(x) => x * 2;
Func named = twice;
static Func private_doubled = %!(x) => x * 2;
static Func private_named = twice;
static Func scaled = %!(x) => x * scale;
Array handlers = [doubled, named];
static Array private_handlers = [private_doubled, private_named, scaled];

int main(void) {
  printf("%s %s\n", doubled(1).repr(), named(2).repr());
  printf("%s %s\n", private_doubled(3).repr(), private_named(4).repr());
  printf("%s\n", scaled(5).repr());
  printf("handlers:");
  foreach (Func handler in handlers) printf(" %s", handler(6).repr());
  foreach (Func handler in private_handlers) printf(" %s", handler(7).repr());
  printf("\n");
  return 0;
}
