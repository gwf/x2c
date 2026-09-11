#include <assert.h>

class ConstValue { const int x; int y; };
class ConstHeap struct { const int x; int y; } *;
class VolatileValue { volatile int x; int y; };
class Bits { unsigned low : 3; unsigned : 2; unsigned high : 4; };
class Choice { union { int x; float y; }; int tag; };
typedef struct Cell { int value; } Cell;
class Nested { Cell cell; int tag; };
class Fixed { int items[2]; };
class ConstNested struct { const int values[2]; } *;
class Custom { Array values; };

static int initialized;

void Choice.init(Choice *value) {
  assert(value->x == 0 && value->tag == 0);
  value->x = 5;
  value->tag = 1;
  initialized++;
}
int Choice.equal(Choice a, Choice b) {
  return a.tag == b.tag && a.x == b.x;
}
unsigned Choice.hash(Choice value) { return value.tag * 31 + value.x; }

void Nested.init(Nested *value) {
  assert(value->cell.value == 0 && value->tag == 0);
  value->cell.value = 5;
  value->tag = 1;
  initialized++;
}
int Nested.equal(Nested a, Nested b) {
  return a.tag == b.tag && a.cell.value == b.cell.value;
}
unsigned Nested.hash(Nested value) {
  return value.tag * 31 + value.cell.value;
}

void Fixed.init(Fixed *value) {
  assert(value->items[0] == 0 && value->items[1] == 0);
  value->items[0] = 5;
  value->items[1] = 9;
  initialized++;
}
int Fixed.equal(Fixed a, Fixed b) {
  return a.items[0] == b.items[0] && a.items[1] == b.items[1];
}
unsigned Fixed.hash(Fixed value) {
  return value.items[0] * 31 + value.items[1];
}

ConstNested ConstNested.new(int x, int y) {
  const struct ConstNested initial = { { x, y } };
  return Scope.memdup(&initial, sizeof(initial));
}

Custom Custom.new(int value) {
  Custom result = { %[] };
  result.values.push(value);
  return result;
}
int Custom.equal(Custom a, Custom b) {
  return (void *) a.values == (void *) b.values;
}
unsigned Custom.hash(Custom value) {
  return (unsigned) ((unsigned long) value.values >> 3);
}

int main(void) {
  ConstValue value = ConstValue.new(3, 4);
  Var boxed = value;
  ConstValue copy = boxed;
  assert(copy.x == 3 && copy.y == 4);
  ConstHeap heap = ConstHeap.new(3, 4);
  assert(heap.x == 3 && heap.y == 4);
  heap.free();

  VolatileValue observed = VolatileValue.new(3, 4);
  Var first = observed, second = observed;
  assert(first == second && first.hash() == second.hash());
  Bits bits = Bits.new(5, 9);
  first = bits;
  second = bits;
  assert(bits.low == 5 && bits.high == 9 && first == second);
  assert(bits.repr() == %"Bits { low: 5, high: 9 }");

  Choice choice = Choice.new();
  Nested nested = Nested.new();
  Fixed fixed = Fixed.new();
  assert(choice.x == 5 && choice.tag == 1);
  assert(nested.cell.value == 5 && nested.tag == 1);
  assert(fixed.items[0] == 5 && fixed.items[1] == 9);
  assert(initialized == 3);
  assert(nested.repr().contains("cell: <opaque:"));
  assert(fixed.repr().contains("items: <opaque:"));
  ConstNested immutable = ConstNested.new(5, 9);
  assert(immutable.values[0] == 5 && immutable.values[1] == 9);
  assert(immutable.repr().contains("values: <opaque:"));
  immutable.free();
  Custom custom = Custom.new(7);
  assert(custom.values[0] == 7);
  custom.values.free();
  puts("class layouts passed");
  return 0;
}
