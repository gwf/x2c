#include "x2c.x"

int main(void) {
  match (%("same" "same"))
    case %(?{String value} ?{void *value}): return 1;
  return 0;
}
