#include <assert.h>

class Int int;
class Count size_t;
class IntPointer int *;
class VarPointer Var *;
typedef VarPointer ChainedPointer;
class ConstVarPointer const Var *;
class Values Array;
class Point { int x; int y; };
class RenamedPoint Point;
class HeapPoint struct { int x; int y; } *;
class Sample struct { int count; Var value; Array history; } *;

void Sample.init(Sample sample) {
  assert(sample.count == 0);
  sample.count++;
  sample.history = %[];
}

int main(void) {
  Int n = Int.new(4);
  assert(n == 4);
  assert(n.str() == %"4");
  Count count = Count.new(12);
  assert(count == 12);
  IntPointer ip = IntPointer.new(5);
  assert(*ip == 5);
  ip.free();
  VarPointer vp = VarPointer.new(6);
  assert((*vp).integer() == 6);
  vp.free();
  Array shared = %[1];
  VarPointer slot = VarPointer.new(shared);
  shared.push(2);
  Array shallow = *slot;
  assert((void *) shallow == (void *) shared);
  assert(shallow.len() == 2);
  slot.free();
  ChainedPointer chained = VarPointer.new(8);
  assert((*chained).integer() == 8);
  chained.free();
  ConstVarPointer immutable = ConstVarPointer.new(9);
  assert((*immutable).integer() == 9);
  immutable.free();
  Values values = Values.new();
  values.push(7);
  assert(values.len() == 1);
  values.free();

  RenamedPoint renamed = RenamedPoint.new(1, 2);
  assert(renamed.repr() == %"Point { x: 1, y: 2 }");
  Point p = Point.new(1, 2), q = Point.new(1, 2);
  Var a = p, b = q;
  assert(a == b);
  assert(a.hash() == b.hash());
  Map keys = %{};
  keys[a] = 19;
  assert(keys[b] == 19);
  p.x = 9;
  Point copy = a;
  assert(copy.x == 1);
  assert(q.repr() == %"Point { x: 1, y: 2 }");

  HeapPoint hp = HeapPoint.new(3, 4), other = HeapPoint.new(3, 4);
  assert(hp.var() != other.var());
  hp.free();
  other.free();
  HeapPoint absent = NULL;
  assert(absent.repr().contains("HeapPoint"));
  Sample sample = Sample.new();
  assert(sample.count == 1);
  assert(sample.history.len() == 0);
  Array retained = sample.history;
  sample.free();
  retained.push(1);
  assert(retained.len() == 1);
  puts("class behavior passed");
  return 0;
}
