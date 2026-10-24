#include "x2c.x"

int main(void) {
  const int limit = 1;
  with (limit = 2) {
    return limit;
  }
}
