---
title: Methods and classes
group: Types
---

```x2c
#include <assert.h>

typedef struct Vec { double x, y; } Vec;
double Vec.len2(Vec v) => v.x * v.x + v.y * v.y;   // T.method: a dotted call
void Vec.scale(Vec &v, double k) { v.x *= k; v.y *= k; }

class Point { int x; int y; };                     // value class: new, ==, hash, repr
class Node { int value; } *;                       // pointer class, Scope-allocated
String Node.repr(Node n) => %"Node($(n.value))";   // your method replaces the default

int main(void) {
  Vec v = { 3, 4 }; v.scale(2);
  assert(v.len2() == 100);
  Point p = Point.new(1, 2);
  Map m = {}; m[p] = "here";
  assert(m[Point.new(1, 2)] == "here" && p.repr() == "Point { x: 1, y: 2 }");
  Node n = auto Node.new(7);
  assert(n.repr() == "Node(7)" && n.value == 7);
  return 0;
}
```

- `T.f(T self, ...)` is called as `value.f(...)`; the receiver's static
  type selects it. Generated C names it `T_f`.
- `class` chooses a representation: `class Count int;`, a value record,
  or a pointer record. Define `init`, `drop`, `equal`, `hash`, `repr` to
  override.
- `delegate T field;` forwards unknown dotted calls through a field.
