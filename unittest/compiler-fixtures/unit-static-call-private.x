// The same rule applies below the private boundary, where the row is
// dropped from what the file publishes.
#include "unit-static-call/source.x"

int main(void) {
  return shared_value(1) + below_boundary(2);
}
