static class Node { int value; };
static int counter = 10;

static int sum(Node node) => node.value;

int second_total(void) {
  counter += sum(Node.new(5));
  return counter;
}

String second_repr(void) {
  Var boxed = Node.new(7);
  return boxed.repr();
}
