#include <assert.h>
class VeryLongQualifiedClassNameOne { int value; };
class VeryLongQualifiedClassNameTwo { int value; };
int main(void) {
  VeryLongQualifiedClassNameOne one = VeryLongQualifiedClassNameOne.new(1);
  VeryLongQualifiedClassNameTwo two = VeryLongQualifiedClassNameTwo.new(1);
  Var a = one, b = two;
  assert(a.tag() != b.tag());
  assert(a.tag().str().symbol() == a.tag());
  assert(b.tag().str().symbol() == b.tag());
  assert(one.repr() == %"VeryLongQualifiedClassNameOne { value: 1 }");
  assert(two.repr() == %"VeryLongQualifiedClassNameTwo { value: 1 }");
  puts("class tags passed");
  return 0;
}
