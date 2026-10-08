/* A query that a project meta body asks and the compiler rejects reports
   at the call, as it would in the compiler's own meta code. */
#include "x2c.x"
#include "meta.x"
#include <stdio.h>

typedef int Code;

meta static int count(void) => x2c_type_fields(%("Code")).len();

int main(void) {
  printf("%d\n", $count());
  return 0;
}
