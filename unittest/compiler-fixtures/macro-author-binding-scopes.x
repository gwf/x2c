#include "x2c.x"
#include <stdio.h>

/* A template that lists `leaked` with `using` keeps the file-scope `leaked`
   under every enclosing local of that spelling: nested blocks, a loop, and a
   lifted lambda's captures, parameters, and locals. */
static int leaked = 100;

macro Expression $leaked() using leaked => leaked;

static int nested(void) {
  int leaked = 5;
  {
    int leaked = 6;
    { int leaked = 7; return $leaked() + leaked; }
  }
}

static int sibling(void) {
  int leaked = 1;
  { int leaked = 2; leaked += $leaked(); }
  return $leaked() + leaked;
}

static int looped(void) {
  int sum = 0;
  for (int leaked = 0; leaked < 2; leaked++) sum += $leaked() + leaked;
  return sum;
}

static int captured(void) {
  int leaked = 5;
  Func before = %!() => $leaked() + leaked;
  Func after = %!() => leaked + $leaked();
  return before().int() + after().int();
}

static int referenced(void) {
  int leaked = 5;
  Func f = %!() using &leaked => leaked += $leaked();
  f();
  return leaked;
}

static int parameter(void) {
  Func f = %!(int leaked) => $leaked() + leaked;
  return f(3).int();
}

static int lambda_local(void) {
  Func f = %!() => {
    int leaked = 4;
    { int leaked = 8; return $leaked() + leaked; }
  };
  return f().int();
}

static int inner_lambda(void) {
  int leaked = 5;
  {
    int leaked = 6;
    Func outer = %!() => {
      Func inner = %!() => $leaked() + leaked;
      return inner().int() + leaked;
    };
    return outer().int();
  }
}

int main(void) {
  printf("%d %d %d\n", nested(), sibling(), looped());
  printf("%d %d %d\n", captured(), referenced(), parameter());
  printf("%d %d\n", lambda_local(), inner_lambda());
  return 0;
}
