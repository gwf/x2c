/* A native meta prototype may name a target's parameter and result through
   another alias of the same native type. */

#include "x2c.x"

typedef unsigned long Size;
typedef double Real;

meta Real sqrt(Real value);
meta void Array.resize(Array arr, Size size);

meta static Size resized(Size size) {
  Array values = [];
  values.resize(size);
  return values.len();
}

int main(void) {
  printf("%.1f %d\n", $(sqrt 9.0), (int) $(resized 3));
  return 0;
}
