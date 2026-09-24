/* runtime.x -- prototypes in a lib/ unit, where the runtime exceptions
   make them review candidates. */
#include <stdio.h>

int helper(int value);
int other_unit(int value);
meta int compile_time(int value);

$x2c.foreign.alias(puts)
static int _say(const char *text);

int helper(int value) => value + other_unit(value);
