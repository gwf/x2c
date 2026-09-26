#include "meta.x"
#include <assert.h>
// A macro implemented in x2c rather than in compile-time Lisp. `meta` marks
// a function the compiler runs during translation, and the `x2c_*` functions
// `meta.x` declares are the compiler surface those functions call.

typedef struct Response {
  int code;
  String label;
} Response;

$(import "meta-functions.xmacro")

int main(void) {
  Response found = { 200, "OK" };
  printf("fields  %s\n", $shape.names(found));

  Response copy = $shape.reads(found);
  printf("copy    %d %s\n", copy.code, copy.label);

  printf("tag     %s %s\n", $(tag "row" 4), tag("row", 4));

  assert(String.equal($shape.names(found), "code, label"));
  assert(copy.code == 200);
  return 0;
}
