/*  relative-adoption.x -- An adoption in a relative source path.

    The probe translates this file as `src/main.x` from a directory other
    than the x2c root, where the root has its own `src/main.x`.
*/
#pragma once
#include <stdio.h>

typedef struct Point {
  int x;
} *Point;

Var Point.var(Point point) => (Var) { .p64 = point };
Point Var.point(Var value) => value.p64;

protocol Var(Point);
#pragma private

int main(void) {
  struct Point storage = { 7 };
  Point point = &storage;
  Var boxed = point;
  printf("%d\n", boxed.point().x);
  return 0;
}
