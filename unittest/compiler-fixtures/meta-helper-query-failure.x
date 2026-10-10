/* A query that a project meta body asks and the compiler rejects reports
   at the call, as it would in the compiler's own meta code. */
#include "x2c.x"
#include "meta.x"
#include <stdio.h>

typedef int Nonrecord;

meta static int count(void) => Type.fields(%("Nonrecord")).len();

int main(void) {
  printf("%d\n", $count());
  return 0;
}
