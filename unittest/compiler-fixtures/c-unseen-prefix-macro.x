#include <stdio.h>
#include "c-unseen-prefix-macro-values.h"

int unit = 7;

int scale(int value) { return value * unit; }

Point origin(void) { return (Point){ 4 }; }

Point *nearest(Point *from) { return from; }

bool positive(int value) { return value > 0; }

int main(void) {
  printf("%d\n", scale(3));
  Point start = origin();
  printf("%d %d\n", nearest(&start)->x, positive(start.x));
  return 0;
}
