#include <assert.h>

class Node struct { Array children; } *;
void Node.init(Node node) { node.children = %[]; }
class Box { Var member; };
class Styled { int x; };
String Styled.repr(Styled value) { return %"styled"; }
class Bomb { int value; };
String Bomb.repr(Bomb bomb) {
  if (bomb.value < 0) raise %(render-err);
  return %"ok";
}

int main(void) {
  Node node = Node.new();
  node.children.push(node);
  String once = node.repr();
  assert(once.contains("Node"));
  assert(node.var().repr() == once);
  node.children.truncate(0);
  assert(node.repr() == %"Node { children: [  ] }");

  Box box = Box.new(0);
  Var boxed = box;
  Box *copy = (Box *) boxed.pointer();
  copy.member = boxed;
  assert(boxed.repr().contains("Box"));
  copy.member = 1;
  assert(boxed.repr() == %"Box { member: 1 }");

  Styled styled = Styled.new(1);
  Array repeated = %[$styled, $styled];
  assert(repeated.repr() == %"[ styled, styled ]");
  assert(styled.str() == %"styled");

  Var failure = Bomb.new(-1);
  node.children.push(failure);
  List wrapped = %($node);
  int caught = 0;
  for (int attempt = 0; attempt < 2; attempt++) {
    size_t before = Scope.stats().live_allocations;
    try wrapped.repr();
    catch %(render-err): caught++;
    assert(Scope.stats().live_allocations == before);
  }
  assert(caught == 2);
  Bomb *payload = (Bomb *) failure.pointer();
  payload.value = 1;
  assert(node.repr() == %"Node { children: [ ok ] }");
  puts("class cycles passed");
  return 0;
}
