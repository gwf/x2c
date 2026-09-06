#include "x2c.x"

int main(void) {
  List values = %(1 2);
  foreach (Var item, values)
    (void) item.integer();
  return item.integer();
}
