#include "x2c.x"

int main(void) {
  match (%(value)) {
    default:
      return 0;
    case %(value):
      return 1;
  }
  return 2;
}
