#include "x2c.x"

typedef struct Vec {
  int value;
} *Vec;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

Vec Var.vec(Var value) {
  return (Vec) value.pointer();
}

Vec Vec.new(int value) {
  Vec result = Scope.malloc(sizeof(struct Vec));
  result.value = value;
  return result;
}

String Vec.str(Vec value) {
  return %"Vec(${value.value})";
}

int Vec.truth(Vec value) {
  return value.value != 0;
}

int Vec.contains(Vec value, Var needle) {
  return value.value == needle.integer();
}

Vec Vec.add(Vec lhs, Vec rhs) {
  return Vec.new(lhs.value + rhs.value);
}

Vec Vec.neg(Vec value) {
  return Vec.new(-value.value);
}

protocol Var(Vec);

int main(void) {
  Vec two = Vec.new(2);
  Vec five = Vec.new(5);
  Vec static_sum = two.add(five);
  Vec static_neg = two.neg();
  Var boxed_two = two;
  Var boxed_five = five;
  Var boxed_sum = boxed_two.add(boxed_five);
  Var boxed_neg = boxed_two.neg();
  printf(
    "%s %s %d %d %d %d\n",
    static_sum.str(), boxed_sum.str(),
    static_neg.value, boxed_neg.vec().value,
    two.contains(2), boxed_two.contains(2)
  );
  return 0;
}
