#include "x2c.x"

typedef int (*IntFn)(int);

static int apply_twice(IntFn fn, int value) {
  return fn(fn(value));
}

static int apply_middle(int before, IntFn fn, int after) {
  return before + fn(after);
}

static int apply_last(int value, IntFn fn) {
  return fn(value);
}

static int apply_func(Func fn, int value) {
  return fn(value).int();
}

static int calls;

static int counted(int value) {
  calls++;
  return value;
}

macro Expression $callback() => (%!(int x) => x + 1)

int main(void) {
  int first = apply_twice(%!(int x) => x + 1, 5);
  int middle = apply_middle(10, %!(int x) => x + 1, 5);
  int last = apply_last(5, %!(int x) => x + 1);
  int grouped = apply_twice(((%!(int x) => x + 1)), 5);
  int block = apply_twice((%!(int x) => { return x + 1; }), 5);
  int comma = apply_twice(%!(int x) => (counted(x), x + 1), 5);
  int assignment = apply_twice(%!(int x) => x += 1, 5);
  int from_macro = apply_twice($callback(), 5);
  int offset = 3;
  int captured = apply_func(%!(int x) => x + offset, 5);
  int captured_grouped = apply_func((%!(int x) => x + offset), 5);
  printf("positions=%d,%d,%d grouped=%d block=%d comma=%d,%d ",
         first, middle, last, grouped, block, comma, calls);
  printf("assignment=%d macro=%d captured=%d,%d\n",
         assignment, from_macro, captured, captured_grouped);
  return first != 7 || middle != 16 || last != 6 || grouped != 7 ||
         block != 7 || comma != 7 || calls != 2 || assignment != 7 ||
         from_macro != 7 || captured != 8 || captured_grouped != 8;
}
