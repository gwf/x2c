/*  usingorder.x -- toy package whose macros keep package functions with
    `using`, one declared before its macro and one defined after it, and
    native names that no x2c declaration supplies, in an expression and in
    a declared array size.
*/
#pragma once
#include "x2c.x"

#define USINGORDER_MAX(a, b) ((a) > (b) ? (a) : (b))
#define USINGORDER_SIZE 4

int thrice(int n);

macro Expression $tripled(Expr $value) using thrice => thrice($value);
macro Expression $doubled(Expr $value) using twice => twice($value);
macro Expression $larger(Expr $a, Expr $b) using USINGORDER_MAX =>
  USINGORDER_MAX($a, $b);
macro Stmt $sized(Name $count) {
  using USINGORDER_SIZE;
  int scratch[USINGORDER_SIZE];
  int $count = (int) (sizeof scratch / sizeof scratch[0]);
}


int thrice(int n) => 3 * n;
int twice(int n) => 2 * n;
