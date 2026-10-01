// A template's destructuring targets are template locals: literal uses bind
// to each expansion's private declaration, and same-spelled call-site names
// stay distinct.
#include <stdio.h>
#include "x2c.x"

macro Statement $probe(Expr $root, Name $n) {
  List items = $root;
  Map m = {"a": 1, "b": 2};
  foreach (Var (key, val), {"a": 1, "b": 2}) $n += (int) val;
}

macro Statement $pairs(Name $n) {
  foreach (Var (key, val), {"a": 1, "b": 2}) $n += (int) val;
}

macro Statement $assign(Name $n) {
  Var (left, right) = %(4 5);
  $n += (int) left + (int) right;
}

int main(void) {
  int n = 0;
  $probe(%(a b c), n);
  printf("%d\n", n);
  int val = 0, left = 0;
  $pairs(val);
  $assign(left);
  printf("%d %d\n", val, left);
  return 0;
}
