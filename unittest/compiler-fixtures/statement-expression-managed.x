#include "x2c.x"

int main(void) {
  int n = ({ Array items = $auto([1, 2]); items.len(); });
  return n;
}
