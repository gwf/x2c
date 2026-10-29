---
title: Macros, decorators, and keywords
group: Compile time
---

```x2c
#include <assert.h>

macro Expression $minutes(Expr $n) => $n * 60;         // typed template
macro Stmt $swap(Expr $a, Expr $b) {                    // hygienic temporary
  $Code.type($a) t = $a; $a = $b; $b = t;
}
macro Decorator $twice(Function $f) {                   // wraps a function
  @Code.body($f)
  @Code.body($f)
}
macro Decorator $control.repeat(Stmt $body, Expr $n) {
  for (int i = 0; i < $n; i++) $body
}
keyword repeat $control.repeat;                         // now it is syntax

static int calls;
$twice()
static void hit(void) { calls++; }

int main(void) {
  int a = 1, b = 2; $swap(a, b);
  hit();
  repeat (3) calls++;
  assert($minutes(2) == 120 && a == 2 && calls == 5);
  return 0;
}
```

- Hole kinds: `Expr`, `Stmt`, `Block`, `Function`, `Literal`, `Type`,
  `Name`. Result kinds: `Expression`, `Stmt`, `Decorator`, `Unit`.
- Names a template declares are private to each expansion. `using name`
  keeps a file-scope name instead.
- `Code.type`, `Code.name`, `Code.body` ask the compiler about captured
  code.
