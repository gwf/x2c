#include "x2c.x"

/* In quoted data, `${` opens an evaluated Map; an old insertion is not
   guessed from its contents. */
int main(void) {
  int n = 42;
  List xs = %(head ${n} foot);
  return xs.len();
}
