#include "x2c.x"

typedef List method_inherit_Base;
typedef method_inherit_Base method_inherit_Mid;
typedef method_inherit_Mid method_inherit_Leaf;
typedef method_inherit_Leaf method_inherit_Override;

typedef struct method_self_Record {
  int value;
} method_self_Record;
typedef method_self_Record method_self_RecordLeaf;

macro Decorator $self_identity(Function $function) => {
  $(x2c.function.body $function)...
}

Self method_inherit_Base.rest(Self value) {
  return value.cdr();
}

Self method_inherit_Base.merge(Self left, Self right) {
  return left.append(right);
}

$self_identity()
Self method_inherit_Base.decorated(Self value) {
  return value.cdr();
}

const Self *method_self_Record.choose(const Self *value, const Self *other) {
  return value->value >= other->value ? value : other;
}

String method_inherit_Base.root(method_inherit_Base value) {
  return value ? "base-root" : "bad";
}

String method_inherit_Base.shadow(method_inherit_Base value) {
  return value ? "base-shadow" : "bad";
}

String typedef_shadow(method_inherit_Leaf value) {
  return value ? "typedef-shadow" : "bad";
}

String method_inherit_Mid.level(method_inherit_Mid value) {
  return value ? "mid-level" : "bad";
}

String method_inherit_Leaf.own(method_inherit_Leaf value) {
  return value ? "leaf-own" : "bad";
}

String method_inherit_Override.level(method_inherit_Override value) {
  return value ? "override-level" : "bad";
}

method_inherit_Mid method_inherit_Override.rest(
  method_inherit_Override value) {
  return value.cdr();
}

static Var _mapped_string(Var value) {
  (void) value;
  return %"mapped";
}

int main(void) {
  method_inherit_Leaf leaf = %(one two);
  method_inherit_Override override = %(three four);
  method_inherit_Leaf tail = leaf.rest();
  method_inherit_Leaf merged = leaf.merge(tail);
  method_inherit_Leaf decorated = leaf.decorated();
  method_inherit_Base direct = method_inherit_Base_rest(leaf);
  List mapped = leaf.map(_mapped_string);
  method_self_RecordLeaf low = { 2 }, high = { 7 };
  const method_self_RecordLeaf *chosen = low.choose(&high);
  printf("%s\n", leaf.own());
  printf("%s\n", leaf.level());
  printf("%s\n", leaf.root());
  printf("%s\n", leaf.shadow());
  printf("%s\n", override.level());
  printf("%s\n", leaf.repr());
  printf("%s\n", leaf.cdr().repr());
  printf("%s\n", leaf.car().repr());
  printf("%s %s %s\n", tail.own(), merged.repr(), direct.repr());
  printf("%s\n", decorated.own());
  printf("%s\n", mapped.repr());
  printf("%s\n", override.rest().repr());
  printf("%d\n", chosen->value);
  return 0;
}
