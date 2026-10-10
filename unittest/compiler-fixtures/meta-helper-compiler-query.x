/* A project meta body asks the compiler's symbol-table queries, which the
   compiler answers in the state of the call site. */
#include "x2c.x"
#include "meta.x"
#include <stdio.h>

typedef enum { RED, GREEN } Color;
typedef String Name;
typedef struct { int x; double y; } Point;

meta static int members(void) => Type.members(%("Color")).len();

meta static String resolved(String name) =>
  Type.resolve(%($name)).repr();

meta static String fields(void) => Type.fields(%("Point")).repr();

int main(void) {
  printf("%d %s %s\n", $members(), $resolved("Name"), $fields());
  return 0;
}
