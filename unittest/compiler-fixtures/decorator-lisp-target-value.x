#include "x2c.x"

/* A decorator's produced items are searched for the target by value. An
   operator inside the target that is spelled like a pattern binder, such
   as `*=`, must not be read as one. */

$(defun keep (fn) (list fn))

macro Decorator $keep.target(Unit $fn) { $(keep $fn)... }

$keep.target()
int scaled(int x) {
  x *= 3;
  x += 1;
  return x > 0 ? x : -x;
}

int main(void) {
  printf("%d\n", scaled(4));
  return 0;
}
