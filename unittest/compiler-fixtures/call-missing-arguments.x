/* call-missing-arguments.x -- a call omits required arguments of a function
   whose definition follows the call. */
#include "x2c.x"

typedef struct Survey { int count; } *Survey;

int main(void) {
  Var value = 3;
  return Survey.signature(value);
}

int Survey.signature(Var value, List &?names, List &?types) =>
  names ? 1 : 0;
