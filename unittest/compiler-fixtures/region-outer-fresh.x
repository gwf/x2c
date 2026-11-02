#include "x2c.x"

void assigned_fresh(int base) {
  Array literal, constructed;
  Map map;
  Func closure;
  String pooled;
  auto { literal = [1, 2]; }
  auto { constructed = Array.new(); }
  auto { map = {"key": 1}; }
  auto { closure = %!() => base; }
  {
    Pool.open();
    pooled = String.printf("%d", base);
    Pool.close();
  }
  (void) literal;
  (void) constructed;
  (void) map;
  (void) closure;
  (void) pooled;
}

void canonical_outlives_scope(int value) {
  String text;
  auto { text = String.printf("%d", value); }
  puts(text);
}
