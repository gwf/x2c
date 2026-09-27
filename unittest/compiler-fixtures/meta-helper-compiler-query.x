/* A project meta body that asks a symbol-table query fails at the call
   rather than computing on a placeholder. */
#include "x2c.x"
#include "meta.x"
#include <stdio.h>

typedef enum { RED, GREEN } Color;

meta static int members(void) => x2c_type_members(%("Color")).len();

int main(void) {
  printf("%d\n", $members());
  return 0;
}
