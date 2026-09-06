#include "x2c.x"

int main(void) {
  List value = %(one);
  int hit = 0;
  match (value)
    case %(one):
      hit = 1;
  return hit == 1 ? 0 : 1;
}
