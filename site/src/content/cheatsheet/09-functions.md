---
title: Functions, lambdas, and arguments
group: Flow
---

```x2c
#include <assert.h>

int twice(int x) => x * 2;                       // expression body
String greet(String who, Map @opts) =>           // keyword arguments
  %"$(opts.getdefault(<hi>, "Hello")), $who";
int count(List @items) => items.len();           // rest arguments
void bump(int &n) => n++;                        // reference parameter

int main(void) {
  Func f = twice;                                // first-class function
  Func add = %!(a, b) => a + b;                  // lambda; results are Var
  int k = 1;
  Func inc = %!(void) using &k => { k++; };      // capture by reference
  inc(); inc();
  assert(f(21) == 42 && add(1, 2) == 3 && k == 3);
  assert(greet("Ada", hi: "Hey") == "Hey, Ada" && count(1, 2, 3) == 3);
  int n = 1; bump(n); assert(n == 2);            // call with n, not &n
  return 0;
}
```

- A lambda captures by value unless `using &name`. Typed parameters are
  optional.
- `T &?p` is an optional reference; test it before use.
- Functions may be defined after their first call in the same unit.
