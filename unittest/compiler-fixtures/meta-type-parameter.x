/* A `meta` parameter declared `TypeInfo` receives the description of its
   argument's type, which the compiler computes at the `$` call: its name,
   kind, canonical type, and the named fields of a struct or union. */

#include "x2c.x"
#include "meta.x"

typedef struct Response { int code; String label; } Response;
static int Response.len(Response response) => response.code;
struct Pair { int a; double b; };
union Number { int i; float f; };
enum Color { RED, GREEN };

#include "meta-type-parameter-defs.x"

int main(void) {
  struct Response response = { 1, "x" };
  struct Pair pair = { 1, 2 };
  union Number number = { 1 };
  enum Color color = RED;
  unsigned long count = 3;
  String text = "a";
  int *address = NULL;
  printf("%s\n", $type.describe(response));
  printf("%s\n", $type.describe(pair));
  printf("%s\n", $type.describe(number));
  printf("%s\n", $type.describe(color));
  printf("%s\n", $type.describe(count));
  printf("%s\n", $type.describe(text));
  printf("%s\n", $type.describe(address));
  (void) response, (void) pair, (void) number, (void) color, (void) count;
  (void) text, (void) address;
  return 0;
}
