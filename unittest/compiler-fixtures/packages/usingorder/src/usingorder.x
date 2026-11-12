/*  usingorder.x -- toy package whose macros keep package functions with
    `using`, one declared before its macro and one defined after it, and a
    native name that no x2c declaration supplies.
*/
#pragma once
#include "x2c.x"

#define USINGORDER_MAX(a, b) ((a) > (b) ? (a) : (b))

int thrice(int n);

macro Expression $tripled(Expr $value) using thrice => thrice($value);
macro Expression $doubled(Expr $value) using twice => twice($value);
macro Expression $larger(Expr $a, Expr $b) using USINGORDER_MAX =>
  USINGORDER_MAX($a, $b);


int thrice(int n) => 3 * n;
int twice(int n) => 2 * n;
