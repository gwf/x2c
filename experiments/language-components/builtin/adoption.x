#include "x2c.x"

typedef Array Values;
static inline Var Values.var(Values value) { return Var.new(<array>, value); }
static inline Values Var.values(Var value) { return value.array(); }
static int stores, updates, posts;
Var Values.setindex(Values values, int key, Var value) {
  stores++;
  return Array_setindex(values, key, value);
}
Var Values.updateindex(Values values, int key, Symbol op, Var value) {
  updates++;
  return Array_updateindex(values, key, op, value);
}
Var Values.postfixindex(Values values, int key, Symbol op) {
  posts++;
  return Array_postfixindex(values, key, op);
}
protocol Var(Values) as Array;
int main(void) {
  Values values = [1];
  values[0] = 10;
  values[0] += 2;
  values[0]++;
  ++values[0];
  printf("%d %d %d %ld\n", stores, updates, posts, values[0].integer());
  return 0;
}
