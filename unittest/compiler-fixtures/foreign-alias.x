#include "x2c.x"
#include <stdlib.h>

typedef int Alias;

$x2c.foreign.alias(abs)
inline int Alias.absolute(int value);

$x2c.foreign.alias(abs)
inline int alias_absolute(int value);

#pragma private

$x2c.foreign.alias(labs)
static long private_absolute(long value);

#pragma public

int main(void) {
  int same_receiver = Alias.absolute == abs;
  int same_free = alias_absolute == abs;
  int same_private = private_absolute == labs;
  printf("%d %d %d %d %ld\n",
         same_receiver, same_free, same_private,
         Alias.absolute(-42), private_absolute(-43));
  return 0;
}
