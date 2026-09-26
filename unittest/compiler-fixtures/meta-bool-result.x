#include "x2c.x"
#include <stdbool.h>

/* C's bool has no Var form, so the call names the function and the fix. */

meta static bool positive(int n) => n > 0;

int main(void) { return $positive(1); }
