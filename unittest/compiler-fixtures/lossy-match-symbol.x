#include "x2c.x"

int main(void) {
  List value = %(item);
  match (value) {
    case %(<lossy_match> *tail): return 1;
  }
  return 0;
}
