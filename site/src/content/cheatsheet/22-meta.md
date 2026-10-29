---
title: Meta functions and quotations
group: Compile time
---

```x2c
#include <assert.h>
#include "meta.x"

meta int poly(int n) => n * n + 1;                  // runs in the compiler too
meta static List table(int n) {                     // returns code
  Array cells = [];
  for (int i = 0; i < n; i++) cells.push(i * i);
  List items = cells.list_free();
  return $!( { @items } );                          // a quotation with a splice
}
meta static List count_fields(TypeInfo t) =>        // ask about a type
  $!int{ $(((List) t.assoc(<fields>)).len()) };
macro Expression $fields(Expr $v) => $count_fields($v);

typedef struct P { int x, y, z; } P;
static const int squares[] = $table(4);

int main(void) {
  P p = { 1, 2, 3 };
  assert($poly(3) == 10 && poly(3) == 10 && squares[3] == 9);
  assert($fields(p) == 3);
  return 0;
}
```

- `$f(args)` calls a meta function during translation and inserts its
  result as code; `f(args)` is the ordinary runtime call.
- `$!( ... )`, `$!Stmt{ ... }`, `$!int{ ... }` quote code; `$x` inserts
  one value and `@xs` splices a List.
- A `TypeInfo` parameter receives `(name kind type fields methods)` for
  the argument's type.
