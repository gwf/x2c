#include "x2c.x"
meta int next(void) {
  static int value;
  value += 1;
  return value;
}
meta int wrapper(void) => next();
meta int conditional(int n) {
  if (!n) return 0;
  static int value = n;
  value += 1;
  return value;
}
meta int loop(int n) {
  int result = 0;
  for (int i = 0; i < n; i++) {
    static int value = 0;
    value += 1;
    result += value;
  }
  return result;
}
meta int recursive(int n) {
  static int value = 0;
  value += 1;
  if (n) return recursive(n - 1);
  return value;
}
meta int same(int n) {
  if (n) { static int value = 10; value += 1; return value; }
  else { static int value = 20; value += 1; return value; }
}
meta int *address(void) {
  static int value = 4;
  return &value;
}
meta int stable(void) {
  int *a = address();
  *a += 2;
  return a == address() ? *address() : -1;
}
meta void increment(int &value) { value += 1; }
meta int references(void) {
  static int value = 7;
  Func change = increment;
  (void) change(value);
  increment(value);
  return value;
}
meta int arrays(void) {
  static int values[3] = {1, 2, 3};
  values[1] += 1;
  return values[0] + values[1] + values[2];
}
struct Pair { int a; int b; };
meta int record(int n) {
  static struct Pair value = {n, 2};
  value.a += 1;
  return value.a + value.b;
}
int main(void) {
  printf("explicit %d %d %d\n", $next(), $wrapper(), $next());
  int a = next(), b = wrapper(), c = next();
  printf("native %d %d %d\n", a, b, c);
  printf("mixed %d %d\n", $wrapper(), wrapper());
  printf("conditional %d %d %d\n",
         $conditional(0), $conditional(10), $conditional(30));
  printf("loop %d %d\n", $loop(3), $loop(2));
  printf("recursion %d %d\n", $recursive(2), $recursive(1));
  printf("shadow %d %d %d %d\n", $same(1), $same(0), $same(1), $same(0));
  printf("address %d %d\n", $stable(), $stable());
  printf("references %d %d\n", $references(), $references());
  printf("array %d %d\n", $arrays(), $arrays());
  printf("record %d %d\n", $record(10), $record(40));
  return 0;
}
